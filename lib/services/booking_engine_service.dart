import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/slot.dart';
import '../models/barber.dart';

// ============================================================================
// BOOKING ENGINE SERVICE — Phase 1
// ============================================================================
//
// Handles all booking lifecycle operations with business rules:
//   1. Booking creation (barberId, serviceIds, appointmentTime, totalPrice)
//   2. Time-based cancellation (>5h full refund, 2-5h 80/10/10, ≤2h blocked)
//   3. Rescheduling (max 2, max 30 days forward, no within 2h)
//   4. Barber switching (price diff handled, locks rescheduling)
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
        'status': BookingStatus.confirmed.name,
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
        .where('status', whereIn: ['pending', 'confirmed'])
        .get();

    final bookedSlots =
        snap.docs.map((d) => d.data()['timeSlot'] as String).toSet();
    return !bookedSlots.contains(timeSlot);
  }
}
