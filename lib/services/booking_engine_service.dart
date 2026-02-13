import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/slot.dart';
import '../models/barber.dart';

// ============================================================================
// BOOKING ENGINE SERVICE — Phase 1 + Phase 3
// ============================================================================
//
// Phase 1: Booking creation, cancellation, rescheduling, barber switching
// Phase 3: Accept/Reject, Start/Complete job lifecycle, earnings tracking
//
// Lifecycle state machine:
//   pending → accepted(confirmed) → inProgress → completed
//   pending → rejected (full refund)
//   pending/confirmed → cancelledByCustomer / cancelledByBarber
//
// All data stored in Firestore `bookings` collection.
// ============================================================================

/// Result of a cancellation policy check
class CancellationPolicy {
  final bool allowed;
  final int refundPercent;
  final int refundAmount;
  final int barberAmount;
  final int platformAmount;
  final String message;
  final String tier; // 'full', 'partial', 'blocked'

  const CancellationPolicy({
    required this.allowed,
    required this.refundPercent,
    required this.refundAmount,
    required this.barberAmount,
    required this.platformAmount,
    required this.message,
    required this.tier,
  });
}

/// Result of a reschedule eligibility check
class ReschedulePolicy {
  final bool allowed;
  final String message;
  final int remainingReschedules;

  const ReschedulePolicy({
    required this.allowed,
    required this.message,
    required this.remainingReschedules,
  });
}

/// Result of a booking engine operation
class BookingEngineResult {
  final bool success;
  final String message;
  final String? bookingId;

  const BookingEngineResult({
    required this.success,
    required this.message,
    this.bookingId,
  });

  factory BookingEngineResult.ok(String message, {String? bookingId}) =>
      BookingEngineResult(success: true, message: message, bookingId: bookingId);

  factory BookingEngineResult.fail(String message) =>
      BookingEngineResult(success: false, message: message);
}

class BookingEngineService {
  static final BookingEngineService _instance = BookingEngineService._internal();
  factory BookingEngineService() => _instance;
  BookingEngineService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // ─────────────────────── Constants ───────────────────────
  static const int maxReschedules = 2;
  static const int maxForwardDays = 30;
  static const double fullRefundHours = 5.0;
  static const double partialRefundHours = 2.0;
  // Partial cancellation: 80% customer, 10% barber, 10% platform
  static const double partialRefundRate = 0.80;
  static const double partialBarberRate = 0.10;
  static const double partialPlatformRate = 0.10;

  // Phase 3: Earnings split on completion (85% barber, 15% platform)
  static const double barberEarningsRate = 0.85;
  static const double platformFeeRate = 0.15;

  // Phase 4: Rerouting limits
  static const int maxReroutes = 3;
  static const int assignmentTimeoutMinutes = 30;

  // ─────────────────────── Streams ───────────────────────

  /// Stream customer's bookings (real-time)
  Stream<List<Booking>> streamCustomerBookings(String customerId) {
    return _firestore
        .collection('bookings')
        .where('customerId', isEqualTo: customerId)
        .orderBy('bookingDateTime', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map((doc) {
              final data = doc.data();
              data['id'] = doc.id;
              return Booking.fromMap(data);
            }).toList());
  }

  /// Get a single booking by ID
  Future<Booking?> getBooking(String bookingId) async {
    final doc = await _firestore.collection('bookings').doc(bookingId).get();
    if (!doc.exists) return null;
    final data = doc.data()!;
    data['id'] = doc.id;
    return Booking.fromMap(data);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 1. BOOKING CREATION
  // ═══════════════════════════════════════════════════════════════════════════

  /// Create a new booking with selected services
  ///
  /// Validates: user auth, slot availability, service existence.
  /// Stores in Firestore under `bookings/{auto-id}`.
  Future<BookingEngineResult> createBooking({
    required String barberId,
    required List<String> serviceIds,
    required DateTime appointmentTime,
    required String timeSlot,
    required int totalPrice,
    required String barberName,
    String? shopName,
    String? barberImageUrl,
    String? barberAddress,
    String? paymentMethod,
    bool isBookingForOther = false,
    String? bookedForName,
    String? bookedForNotes,
    List<String> selectedServiceNames = const [],
    String serviceMode = 'shop',
  }) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        return BookingEngineResult.fail('You must be logged in to book.');
      }

      // Validate appointment is in the future
      if (appointmentTime.isBefore(DateTime.now())) {
        return BookingEngineResult.fail('Cannot book a time in the past.');
      }

      // Validate appointment is within 30 days
      final daysAhead = appointmentTime.difference(DateTime.now()).inDays;
      if (daysAhead > maxForwardDays) {
        return BookingEngineResult.fail(
            'Cannot book more than $maxForwardDays days ahead.');
      }

      // Validate at least one service selected
      if (serviceIds.isEmpty) {
        return BookingEngineResult.fail('Please select at least one service.');
      }

      // Fetch customer data for the booking
      final userDoc = await _firestore.collection('users').doc(user.uid).get();
      final userData = userDoc.data() ?? {};

      // Create the booking document
      final bookingRef = _firestore.collection('bookings').doc();
      final bookingData = {
        'id': bookingRef.id,
        'barberId': barberId,
        'barberName': barberName,
        'shopName': shopName,
        'barberImageUrl': barberImageUrl ?? '',
        'barberAddress': barberAddress,
        'bookingDateTime': Timestamp.fromDate(appointmentTime),
        'timeSlot': timeSlot,
        'pricePKR': totalPrice,
        'status': BookingStatus.pending.name, // Phase 3: starts as "requested"
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'paymentMethod': paymentMethod ?? 'wallet',
        'customerId': user.uid,
        'customerName': userData['name'] as String? ?? 'Customer',
        'customerImageUrl': userData['imageUrl'] as String? ?? '',
        'isBookingForOther': isBookingForOther,
        'bookedForName': bookedForName,
        'bookedForNotes': bookedForNotes,
        'selectedServices': selectedServiceNames,
        // Booking engine fields
        'serviceIds': serviceIds,
        'rescheduleCount': 0,
        'barberSwitched': false,
        'originalBarberId': null,
        'originalPrice': null,
        'refundAmount': null,
        // Phase 3 fields
        'serviceMode': serviceMode,
        'rejectedAt': null,
        'completedAt': null,
        'barberEarnings': null,
        'platformFee': null,
        // Phase 4: Assignment tracking (server-authoritative)
        'assignedAt': FieldValue.serverTimestamp(),
        'assignmentExpiresAt': Timestamp.fromDate(
          DateTime.now().add(const Duration(minutes: assignmentTimeoutMinutes)),
        ),
        'assignmentExpired': false,
        'rerouteCount': 0,
        'lastAssignmentBarberId': null,
      };

      await bookingRef.set(bookingData);

      print('✅ BookingEngine: Booking created ${bookingRef.id}');
      return BookingEngineResult.ok(
        'Booking confirmed!',
        bookingId: bookingRef.id,
      );
    } catch (e) {
      print('❌ BookingEngine.createBooking: $e');
      return BookingEngineResult.fail('Failed to create booking: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 2. CANCELLATION — Time-based rules
  // ═══════════════════════════════════════════════════════════════════════════

  /// Check cancellation policy for a booking (does NOT cancel)
  ///
  /// Rules:
  ///   >5 hours before  → Full refund (100% to customer)
  ///   2–5 hours before → 80% customer / 10% barber / 10% platform
  ///   ≤2 hours before  → Cancellation blocked
  CancellationPolicy getCancellationPolicy(Booking booking) {
    final now = DateTime.now();
    final hoursUntil =
        booking.bookingDateTime.difference(now).inMinutes / 60.0;

    // Already past or not cancellable status
    if (booking.status != BookingStatus.confirmed &&
        booking.status != BookingStatus.pending) {
      return const CancellationPolicy(
        allowed: false,
        refundPercent: 0,
        refundAmount: 0,
        barberAmount: 0,
        platformAmount: 0,
        message: 'This booking cannot be cancelled.',
        tier: 'blocked',
      );
    }

    if (hoursUntil <= partialRefundHours) {
      // ≤2 hours: BLOCKED
      return CancellationPolicy(
        allowed: false,
        refundPercent: 0,
        refundAmount: 0,
        barberAmount: 0,
        platformAmount: 0,
        message:
            'Cancellation is not allowed within 2 hours of your appointment. '
            'Please contact support if you have an emergency.',
        tier: 'blocked',
      );
    } else if (hoursUntil <= fullRefundHours) {
      // 2–5 hours: 80/10/10 split
      final refund = (booking.pricePKR * partialRefundRate).round();
      final barberCut = (booking.pricePKR * partialBarberRate).round();
      final platformCut = (booking.pricePKR * partialPlatformRate).round();

      return CancellationPolicy(
        allowed: true,
        refundPercent: 80,
        refundAmount: refund,
        barberAmount: barberCut,
        platformAmount: platformCut,
        message:
            'Cancelling 2–5 hours before appointment.\n'
            'You will receive 80% refund (PKR $refund).\n'
            'Barber receives PKR $barberCut, platform fee PKR $platformCut.',
        tier: 'partial',
      );
    } else {
      // >5 hours: FULL REFUND
      return CancellationPolicy(
        allowed: true,
        refundPercent: 100,
        refundAmount: booking.pricePKR,
        barberAmount: 0,
        platformAmount: 0,
        message: 'Full refund of PKR ${booking.pricePKR} will be credited.',
        tier: 'full',
      );
    }
  }

  /// Execute cancellation with time-based refund rules
  Future<BookingEngineResult> cancelBooking(
    String bookingId, {
    String? reason,
  }) async {
    try {
      final booking = await getBooking(bookingId);
      if (booking == null) {
        return BookingEngineResult.fail('Booking not found.');
      }

      final policy = getCancellationPolicy(booking);
      if (!policy.allowed) {
        return BookingEngineResult.fail(policy.message);
      }

      // Update booking in Firestore
      await _firestore.collection('bookings').doc(bookingId).update({
        'status': BookingStatus.cancelledByCustomer.name,
        'cancellationReason': reason ?? 'Cancelled by customer',
        'cancelledBy': 'customer',
        'refundAmount': policy.refundAmount,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      print('✅ BookingEngine: Booking $bookingId cancelled '
          '(refund: ${policy.refundPercent}%, PKR ${policy.refundAmount})');

      return BookingEngineResult.ok(
        policy.tier == 'full'
            ? 'Booking cancelled. Full refund of PKR ${policy.refundAmount} will be credited.'
            : 'Booking cancelled. PKR ${policy.refundAmount} (80%) refunded. '
                'PKR ${policy.barberAmount} to barber, PKR ${policy.platformAmount} platform fee.',
      );
    } catch (e) {
      print('❌ BookingEngine.cancelBooking: $e');
      return BookingEngineResult.fail('Cancellation failed: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 3. RESCHEDULING — Max 2, max 30 days, no within 2h
  // ═══════════════════════════════════════════════════════════════════════════

  /// Check if a booking can be rescheduled
  ReschedulePolicy getReschedulePolicy(Booking booking) {
    // Can't reschedule non-active bookings
    if (booking.status != BookingStatus.confirmed &&
        booking.status != BookingStatus.pending) {
      return const ReschedulePolicy(
        allowed: false,
        message: 'Only active bookings can be rescheduled.',
        remainingReschedules: 0,
      );
    }

    // Barber switch locks rescheduling
    if (booking.barberSwitched) {
      return const ReschedulePolicy(
        allowed: false,
        message:
            'Rescheduling is locked after switching barber. '
            'Please cancel and create a new booking instead.',
        remainingReschedules: 0,
      );
    }

    // Max 2 reschedules
    if (booking.rescheduleCount >= maxReschedules) {
      return const ReschedulePolicy(
        allowed: false,
        message:
            'Maximum $maxReschedules reschedules reached. '
            'Please cancel and create a new booking.',
        remainingReschedules: 0,
      );
    }

    // No reschedule within 2 hours
    final hoursUntil =
        booking.bookingDateTime.difference(DateTime.now()).inMinutes / 60.0;
    if (hoursUntil <= 2.0) {
      return ReschedulePolicy(
        allowed: false,
        message: 'Cannot reschedule within 2 hours of your appointment.',
        remainingReschedules: maxReschedules - booking.rescheduleCount,
      );
    }

    return ReschedulePolicy(
      allowed: true,
      message:
          '${maxReschedules - booking.rescheduleCount} reschedule(s) remaining.',
      remainingReschedules: maxReschedules - booking.rescheduleCount,
    );
  }

  /// Execute reschedule to a new date/time
  Future<BookingEngineResult> rescheduleBooking(
    String bookingId, {
    required DateTime newDateTime,
    required String newTimeSlot,
  }) async {
    try {
      final booking = await getBooking(bookingId);
      if (booking == null) {
        return BookingEngineResult.fail('Booking not found.');
      }

      final policy = getReschedulePolicy(booking);
      if (!policy.allowed) {
        return BookingEngineResult.fail(policy.message);
      }

      // Validate new time is in the future
      if (newDateTime.isBefore(DateTime.now())) {
        return BookingEngineResult.fail('Cannot reschedule to a past time.');
      }

      // Validate within 30 days
      final daysAhead = newDateTime.difference(DateTime.now()).inDays;
      if (daysAhead > maxForwardDays) {
        return BookingEngineResult.fail(
            'Cannot reschedule more than $maxForwardDays days ahead.');
      }

      // Update booking
      await _firestore.collection('bookings').doc(bookingId).update({
        'bookingDateTime': Timestamp.fromDate(newDateTime),
        'timeSlot': newTimeSlot,
        'rescheduleCount': booking.rescheduleCount + 1,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      final remaining = maxReschedules - booking.rescheduleCount - 1;
      print('✅ BookingEngine: Booking $bookingId rescheduled '
          '(count: ${booking.rescheduleCount + 1}, remaining: $remaining)');

      return BookingEngineResult.ok(
        'Booking rescheduled to $newTimeSlot. '
        '$remaining reschedule(s) remaining.',
      );
    } catch (e) {
      print('❌ BookingEngine.rescheduleBooking: $e');
      return BookingEngineResult.fail('Reschedule failed: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 4. BARBER SWITCHING — Price diff handled, locks rescheduling
  // ═══════════════════════════════════════════════════════════════════════════

  /// Switch to a different barber for the same time slot
  ///
  /// Price difference is calculated:
  ///   - New barber cheaper → customer is credited the difference
  ///   - New barber more expensive → customer pays the difference
  /// After switch, rescheduling is LOCKED for this booking.
  Future<BookingEngineResult> switchBarber(
    String bookingId, {
    required Barber newBarber,
    required int newPrice,
  }) async {
    try {
      final booking = await getBooking(bookingId);
      if (booking == null) {
        return BookingEngineResult.fail('Booking not found.');
      }

      // Only active bookings can be switched
      if (booking.status != BookingStatus.confirmed &&
          booking.status != BookingStatus.pending) {
        return BookingEngineResult.fail(
            'Only active bookings can switch barber.');
      }

      // Can't switch to the same barber
      if (booking.barberId == newBarber.id) {
        return BookingEngineResult.fail(
            'This is already your current barber.');
      }

      final priceDifference = newPrice - booking.pricePKR;
      final originalBarberId =
          booking.originalBarberId ?? booking.barberId;
      final originalPrice = booking.originalPrice ?? booking.pricePKR;

      // Update booking with new barber
      await _firestore.collection('bookings').doc(bookingId).update({
        'barberId': newBarber.id,
        'barberName': newBarber.name,
        'shopName': newBarber.shopName,
        'barberImageUrl': newBarber.imageUrl,
        'barberAddress': newBarber.address,
        'pricePKR': newPrice,
        'barberSwitched': true,
        'originalBarberId': originalBarberId,
        'originalPrice': originalPrice,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      String msg;
      if (priceDifference > 0) {
        msg = 'Switched to ${newBarber.name}. '
            'Additional PKR $priceDifference will be charged. '
            'Note: Rescheduling is now locked.';
      } else if (priceDifference < 0) {
        msg = 'Switched to ${newBarber.name}. '
            'PKR ${priceDifference.abs()} will be refunded. '
            'Note: Rescheduling is now locked.';
      } else {
        msg = 'Switched to ${newBarber.name}. '
            'No price change. Rescheduling is now locked.';
      }

      print('✅ BookingEngine: Barber switched for $bookingId '
          '(new: ${newBarber.id}, priceDiff: $priceDifference)');

      return BookingEngineResult.ok(msg);
    } catch (e) {
      print('❌ BookingEngine.switchBarber: $e');
      return BookingEngineResult.fail('Barber switch failed: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 5. PHASE 3 — BOOKING LIFECYCLE (Accept → Start → Complete)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Barber ACCEPTS a booking request.
  /// Transition: pending → confirmed (accepted)
  Future<BookingEngineResult> acceptBooking(String bookingId) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return BookingEngineResult.fail('Not authenticated.');

      final booking = await getBooking(bookingId);
      if (booking == null) return BookingEngineResult.fail('Booking not found.');

      // Only the assigned barber can accept
      if (booking.barberId != user.uid) {
        return BookingEngineResult.fail('Only the assigned barber can accept this booking.');
      }

      // Must be in pending status
      if (booking.status != BookingStatus.pending) {
        return BookingEngineResult.fail(
            'Cannot accept — booking is ${booking.status.displayName}.');
      }

      await _firestore.collection('bookings').doc(bookingId).update({
        'status': BookingStatus.confirmed.name,
        'acceptedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        // Phase 4: Clear assignment expiry — barber responded
        'assignmentExpired': false,
      });

      print('✅ BookingEngine: Booking $bookingId accepted');
      return BookingEngineResult.ok('Booking accepted! Customer has been notified.');
    } catch (e) {
      print('❌ BookingEngine.acceptBooking: $e');
      return BookingEngineResult.fail('Failed to accept booking: $e');
    }
  }

  /// Barber REJECTS a booking request.
  /// Transition: pending → rejected (triggers full refund)
  Future<BookingEngineResult> rejectBooking(
    String bookingId, {
    String reason = 'Barber unavailable',
  }) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return BookingEngineResult.fail('Not authenticated.');

      final booking = await getBooking(bookingId);
      if (booking == null) return BookingEngineResult.fail('Booking not found.');

      if (booking.barberId != user.uid) {
        return BookingEngineResult.fail('Only the assigned barber can reject this booking.');
      }

      if (booking.status != BookingStatus.pending) {
        return BookingEngineResult.fail(
            'Cannot reject — booking is ${booking.status.displayName}.');
      }

      // Reject with full refund
      await _firestore.collection('bookings').doc(bookingId).update({
        'status': BookingStatus.rejected.name,
        'cancellationReason': reason,
        'cancelledBy': 'barber',
        'refundAmount': booking.pricePKR, // Full refund on rejection
        'rejectedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      print('✅ BookingEngine: Booking $bookingId rejected (full refund: ${booking.pricePKR})');
      return BookingEngineResult.ok(
        'Booking rejected. Full refund of PKR ${booking.pricePKR} will be issued.',
      );
    } catch (e) {
      print('❌ BookingEngine.rejectBooking: $e');
      return BookingEngineResult.fail('Failed to reject booking: $e');
    }
  }

  /// Barber STARTS the job.
  /// Transition: confirmed → inProgress
  Future<BookingEngineResult> startJob(String bookingId) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return BookingEngineResult.fail('Not authenticated.');

      final booking = await getBooking(bookingId);
      if (booking == null) return BookingEngineResult.fail('Booking not found.');

      if (booking.barberId != user.uid) {
        return BookingEngineResult.fail('Only the assigned barber can start this job.');
      }

      if (booking.status != BookingStatus.confirmed) {
        return BookingEngineResult.fail(
            'Cannot start — booking must be accepted first (current: ${booking.status.displayName}).');
      }

      await _firestore.collection('bookings').doc(bookingId).update({
        'status': BookingStatus.inProgress.name,
        'startedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      print('✅ BookingEngine: Job $bookingId started');
      return BookingEngineResult.ok('Job started! The customer has been notified.');
    } catch (e) {
      print('❌ BookingEngine.startJob: $e');
      return BookingEngineResult.fail('Failed to start job: $e');
    }
  }

  /// Barber COMPLETES the job.
  /// Transition: inProgress → completed
  /// Calculates and stores earnings (85% barber / 15% platform).
  Future<BookingEngineResult> completeJob(
    String bookingId, {
    int? customerRating,
    String? ratingComment,
  }) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return BookingEngineResult.fail('Not authenticated.');

      final booking = await getBooking(bookingId);
      if (booking == null) return BookingEngineResult.fail('Booking not found.');

      if (booking.barberId != user.uid) {
        return BookingEngineResult.fail('Only the assigned barber can complete this job.');
      }

      if (booking.status != BookingStatus.inProgress) {
        return BookingEngineResult.fail(
            'Cannot complete — job must be in progress first (current: ${booking.status.displayName}).');
      }

      // Calculate earnings split
      final barberShare = (booking.pricePKR * barberEarningsRate).round();
      final platformShare = booking.pricePKR - barberShare;

      // Update booking to completed with earnings
      final updates = <String, dynamic>{
        'status': BookingStatus.completed.name,
        'completedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'barberEarnings': barberShare,
        'platformFee': platformShare,
      };

      if (customerRating != null) {
        updates['customerRating'] = customerRating;
      }
      if (ratingComment != null) {
        updates['customerRatingComment'] = ratingComment;
      }

      await _firestore.collection('bookings').doc(bookingId).update(updates);

      // Record earnings in barber_earnings collection
      await _firestore.collection('barber_earnings').add({
        'bookingId': bookingId,
        'barberId': booking.barberId,
        'customerId': booking.customerId,
        'amount': booking.pricePKR,
        'barberShare': barberShare,
        'platformShare': platformShare,
        'serviceMode': booking.serviceMode,
        'timestamp': FieldValue.serverTimestamp(),
      });

      print('✅ BookingEngine: Job $bookingId completed '
          '(barber: PKR $barberShare, platform: PKR $platformShare)');
      return BookingEngineResult.ok(
        'Job completed! You earned PKR $barberShare.',
      );
    } catch (e) {
      print('❌ BookingEngine.completeJob: $e');
      return BookingEngineResult.fail('Failed to complete job: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 6. PHASE 4 — SMART REROUTING
  // ═══════════════════════════════════════════════════════════════════════════

  /// Reroute a booking to a new barber.
  ///
  /// Rules:
  ///   - Only the customer can reroute
  ///   - Booking must be pending + assignmentExpired
  ///   - Max 3 reroutes per booking
  ///   - Same booking document, new barber assignment
  ///   - Escrow untouched
  Future<BookingEngineResult> rerouteBooking(
    String bookingId, {
    required Barber newBarber,
  }) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return BookingEngineResult.fail('Not authenticated.');

      final booking = await getBooking(bookingId);
      if (booking == null) return BookingEngineResult.fail('Booking not found.');

      // Only the customer can reroute
      if (booking.customerId != user.uid) {
        return BookingEngineResult.fail('Only the booking customer can reroute.');
      }

      // Must be pending + expired
      if (booking.status != BookingStatus.pending) {
        return BookingEngineResult.fail(
            'Cannot reroute — booking is ${booking.status.displayName}.');
      }

      if (!booking.assignmentExpired) {
        return BookingEngineResult.fail(
            'Cannot reroute — the current barber still has time to respond.');
      }

      // Max 3 reroutes
      if (booking.rerouteCount >= maxReroutes) {
        return BookingEngineResult.fail(
            'Maximum reroute limit ($maxReroutes) reached. '
            'You can cancel for a refund.');
      }

      // Cannot reroute to the same barber
      if (booking.barberId == newBarber.id) {
        return BookingEngineResult.fail('Cannot reroute to the same barber.');
      }

      // Calculate new expiry
      final expiresAt = DateTime.now().add(
        const Duration(minutes: assignmentTimeoutMinutes),
      );

      // Update the SAME booking document — one booking, one escrow, one lifecycle
      await _firestore.collection('bookings').doc(bookingId).update({
        // New barber
        'barberId': newBarber.id,
        'barberName': newBarber.name,
        'shopName': newBarber.shopName,
        'barberImageUrl': newBarber.imageUrl,
        'barberAddress': newBarber.address,
        // Assignment tracking
        'assignedAt': FieldValue.serverTimestamp(),
        'assignmentExpiresAt': Timestamp.fromDate(expiresAt),
        'assignmentExpired': false,
        'rerouteCount': booking.rerouteCount + 1,
        'lastAssignmentBarberId': booking.barberId,
        // Keep pending — new barber must accept
        'status': BookingStatus.pending.name,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      print('✅ BookingEngine: Booking $bookingId rerouted to ${newBarber.id} '
          '(count: ${booking.rerouteCount + 1}/$maxReroutes)');

      return BookingEngineResult.ok(
        'Booking sent to ${newBarber.name}. They have $assignmentTimeoutMinutes minutes to respond.',
      );
    } catch (e) {
      print('❌ BookingEngine.rerouteBooking: $e');
      return BookingEngineResult.fail('Rerouting failed: $e');
    }
  }

  /// Stream a single booking in real-time (for customer tracking)
  Stream<Booking?> streamBooking(String bookingId) {
    return _firestore
        .collection('bookings')
        .doc(bookingId)
        .snapshots()
        .map((snap) {
          if (!snap.exists) return null;
          final data = snap.data()!;
          data['id'] = snap.id;
          return Booking.fromMap(data);
        });
  }

  /// Get eligible barbers for rerouting (approved, with matching service mode)
  Future<List<Barber>> getEligibleBarbersForReroute({
    required String currentBarberId,
    String serviceMode = 'shop',
  }) async {
    final snap = await _firestore
        .collection('users')
        .where('role', isEqualTo: 'barber')
        .where('status', isEqualTo: 'approved')
        .get();

    final barbers = <Barber>[];
    for (final doc in snap.docs) {
      if (doc.id == currentBarberId) continue; // Exclude current barber
      final data = doc.data();
      data['id'] = doc.id;
      try {
        final barber = Barber.fromMap(data);
        // Check service mode compatibility
        if (isServiceModeValid(barber.barberType, serviceMode)) {
          barbers.add(barber);
        }
      } catch (_) {
        // Skip barbers with invalid data
      }
    }

    // Sort by rating (highest first)
    barbers.sort((a, b) => b.rating.compareTo(a.rating));
    return barbers;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 7. PHASE 3 — BARBER STREAMS & QUERIES
  // ═══════════════════════════════════════════════════════════════════════════

  /// Stream barber's bookings (real-time) — used in barber dashboard
  Stream<List<Booking>> streamBarberBookings(String barberId) {
    return _firestore
        .collection('bookings')
        .where('barberId', isEqualTo: barberId)
        .orderBy('bookingDateTime', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map((doc) {
              final data = doc.data();
              data['id'] = doc.id;
              return Booking.fromMap(data);
            }).toList());
  }

  /// Stream barber's earnings (real-time)
  Stream<List<Map<String, dynamic>>> streamBarberEarnings(String barberId) {
    return _firestore
        .collection('barber_earnings')
        .where('barberId', isEqualTo: barberId)
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map((doc) {
              final data = doc.data();
              data['id'] = doc.id;
              return data;
            }).toList());
  }

  /// Get today's earnings for a barber
  Future<int> getTodayEarnings(String barberId) async {
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);

    final snap = await _firestore
        .collection('barber_earnings')
        .where('barberId', isEqualTo: barberId)
        .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
        .get();

    return snap.docs.fold<int>(
      0,
      (sum, doc) => sum + ((doc.data()['barberShare'] as num?)?.toInt() ?? 0),
    );
  }

  // ─────────────────────── Helpers ───────────────────────

  /// Get hours until appointment (for display)
  double getHoursUntilAppointment(Booking booking) {
    return booking.bookingDateTime.difference(DateTime.now()).inMinutes / 60.0;
  }

  /// Check if a time slot is available for a barber
  Future<bool> isSlotAvailable(
      String barberId, DateTime dateTime, String timeSlot) async {
    final startOfDay =
        DateTime(dateTime.year, dateTime.month, dateTime.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    final snap = await _firestore
        .collection('bookings')
        .where('barberId', isEqualTo: barberId)
        .where('bookingDateTime',
            isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
        .where('bookingDateTime',
            isLessThan: Timestamp.fromDate(endOfDay))
        .where('status', whereIn: ['pending', 'confirmed', 'inProgress'])
        .get();

    final bookedSlots =
        snap.docs.map((d) => d.data()['timeSlot'] as String).toSet();
    return !bookedSlots.contains(timeSlot);
  }

  /// Check if service mode is valid for the barber type
  bool isServiceModeValid(String barberType, String serviceMode) {
    switch (barberType) {
      case 'shop_only':
        return serviceMode == 'shop';
      case 'doorstep_only':
        return serviceMode == 'doorstep';
      case 'both':
        return serviceMode == 'shop' || serviceMode == 'doorstep';
      default:
        return serviceMode == 'shop';
    }
  }
}
