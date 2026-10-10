import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../data/app_data.dart';

class TimeSlot {
  final String id;
  final String time;
  final bool isAvailable;
  final DateTime dateTime;

  const TimeSlot({
    required this.id,
    required this.time,
    required this.isAvailable,
    required this.dateTime,
  });

  TimeSlot copyWith({
    String? id,
    String? time,
    bool? isAvailable,
    DateTime? dateTime,
  }) {
    return TimeSlot(
      id: id ?? this.id,
      time: time ?? this.time,
      isAvailable: isAvailable ?? this.isAvailable,
      dateTime: dateTime ?? this.dateTime,
    );
  }
}

class BookingDate {
  final DateTime date;
  final String dayName;
  final String dayNumber;
  final String monthName;
  final bool isToday;
  final List<TimeSlot> slots;

  const BookingDate({
    required this.date,
    required this.dayName,
    required this.dayNumber,
    required this.monthName,
    required this.isToday,
    required this.slots,
  });
}

// Generate dummy slots for the next 7 days
List<BookingDate> generateDummyBookingDates() {
  final now = DateTime.now();
  final List<BookingDate> dates = [];

  final dayNames = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
  final monthNames = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];

  // Slots that are "booked" for demo purposes (random indices)
  final bookedSlotsByDay = [
    [2, 5, 8],      // Today
    [1, 4, 7, 10],  // Tomorrow
    [3, 6],         // Day 3
    [0, 5, 9],      // Day 4
    [2, 4, 8, 11],  // Day 5
    [1, 6, 10],     // Day 6
    [3, 7],         // Day 7
  ];

  for (int dayOffset = 0; dayOffset < 7; dayOffset++) {
    final date = now.add(Duration(days: dayOffset));
    final slots = _generateSlotsForDay(date, bookedSlotsByDay[dayOffset]);

    dates.add(BookingDate(
      date: date,
      dayName: dayNames[date.weekday % 7],
      dayNumber: date.day.toString(),
      monthName: monthNames[date.month - 1],
      isToday: dayOffset == 0,
      slots: slots,
    ));
  }

  return dates;
}

List<TimeSlot> _generateSlotsForDay(DateTime date, List<int> bookedIndices) {
  final List<TimeSlot> slots = [];
  final times = [
    '9:00 AM',
    '9:30 AM',
    '10:00 AM',
    '10:30 AM',
    '11:00 AM',
    '11:30 AM',
    '12:00 PM',
    '12:30 PM',
    '1:00 PM',
    '1:30 PM',
    '2:00 PM',
    '2:30 PM',
    '3:00 PM',
    '3:30 PM',
    '4:00 PM',
    '4:30 PM',
    '5:00 PM',
    '5:30 PM',
  ];

  for (int i = 0; i < times.length; i++) {
    // Parse time to create proper DateTime
    final timeParts = times[i].split(' ');
    final hourMinute = timeParts[0].split(':');
    int hour = int.parse(hourMinute[0]);
    final minute = int.parse(hourMinute[1]);
    final isPM = timeParts[1] == 'PM';

    if (isPM && hour != 12) hour += 12;
    if (!isPM && hour == 12) hour = 0;

    final slotDateTime = DateTime(
      date.year,
      date.month,
      date.day,
      hour,
      minute,
    );

    // Check if slot is in the past (for today)
    final now = DateTime.now();
    final isPast = slotDateTime.isBefore(now);

    slots.add(TimeSlot(
      id: '${date.toIso8601String()}_$i',
      time: times[i],
      isAvailable: !bookedIndices.contains(i) && !isPast,
      dateTime: slotDateTime,
    ));
  }

  return slots;
}

// Booking model for confirmation and status
class Booking {
  final String id;
  final String barberId;
  final String barberName;
  final String? shopName;
  final String barberImageUrl;
  final String? barberAddress;
  final DateTime bookingDateTime;
  final String timeSlot;
  final int pricePKR;
  final BookingStatus status;
  final DateTime createdAt;
  final DateTime? acceptedAt; // When barber accepted the booking
  final DateTime? startedAt;  // When barber started the job
  final DateTime? updatedAt;  // Last time booking was updated
  final PaymentMethod? paymentMethod;
  final String? cancellationReason;
  final String? cancelledBy; // 'customer' or 'barber'
  final int? rating;
  // Customer info (for barber view)
  final String? customerId;
  final String? customerName;
  final String? customerImageUrl;
  final double? customerRatingScore; // Customer's trust score
  final int? customerRating; // Rating given by barber after completion
  final String? customerRatingComment;
  
  // Booking for family/friend (Uber-like)
  final bool isBookingForOther;
  final String? bookedForName;  // Name of person this booking is for
  final String? bookedForNotes; // Special notes for the booking
  
  // Services selected
  final List<String> selectedServices;

  // Escrow and Dispute Status
  final EscrowStatus? escrowStatus;
  final String? disputeId;
  final DisputeStatus? disputeStatus;

  // ── Booking Engine Fields ──────────────────────────────────────────────────
  // Phase 1 booking engine: service selection, reschedule tracking, barber switching
  
  /// IDs of selected BarberService documents (from barberServices collection)
  final List<String> serviceIds;
  
  /// How many times this booking has been rescheduled (max 2)
  final int rescheduleCount;
  
  /// Whether the barber has been switched (locks rescheduling)
  final bool barberSwitched;
  
  /// Original barber ID before switch (null if never switched)
  final String? originalBarberId;
  
  /// Original price before barber switch (null if never switched)
  final int? originalPrice;
  
  /// Refund amount (set on cancellation)
  final int? refundAmount;

  // ── Phase 3: Lifecycle + Barber Type ──────────────────────────────────────

  /// Service mode: 'shop' or 'doorstep'
  final String serviceMode;

  /// When the barber rejected the booking
  final DateTime? rejectedAt;

  /// When the job was completed
  final DateTime? completedAt;

  /// Barber's share of the earnings (set on completion)
  final int? barberEarnings;

  /// Platform's share (set on completion)
  final int? platformFee;

  // ── Phase 4: Smart Rerouting ──────────────────────────────────────────────

  /// When the current barber was assigned (set on creation and reroute)
  final DateTime? assignedAt;

  /// When the current assignment expires (server-set: assignedAt + 30 min)
  final DateTime? assignmentExpiresAt;

  /// Whether the assignment has expired (set by Cloud Function)
  final bool assignmentExpired;

  /// How many times this booking has been rerouted (max 3)
  final int rerouteCount;

  /// The barber who last held the assignment before reroute
  final String? lastAssignmentBarberId;

  const Booking({
    required this.id,
    required this.barberId,
    required this.barberName,
    this.shopName,
    required this.barberImageUrl,
    this.barberAddress,
    required this.bookingDateTime,
    required this.timeSlot,
    required this.pricePKR,
    required this.status,
    required this.createdAt,
    this.acceptedAt,
    this.startedAt,
    this.updatedAt,
    this.paymentMethod,
    this.cancellationReason,
    this.cancelledBy,
    this.rating,
    this.customerId,
    this.customerName,
    this.customerImageUrl,
    this.customerRatingScore,
    this.customerRating,
    this.customerRatingComment,
    this.isBookingForOther = false,
    this.bookedForName,
    this.bookedForNotes,
    this.selectedServices = const [],
    this.escrowStatus,
    this.disputeId,
    this.disputeStatus,
    // Booking engine fields
    this.serviceIds = const [],
    this.rescheduleCount = 0,
    this.barberSwitched = false,
    this.originalBarberId,
    this.originalPrice,
    this.refundAmount,
    // Phase 3 fields
    this.serviceMode = 'shop',
    this.rejectedAt,
    this.completedAt,
    this.barberEarnings,
    this.platformFee,
    // Phase 4 rerouting fields
    this.assignedAt,
    this.assignmentExpiresAt,
    this.assignmentExpired = false,
    this.rerouteCount = 0,
    this.lastAssignmentBarberId,
  });

  String get formattedDate {
    final dayNames = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
    final monthNames = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    return '${dayNames[bookingDateTime.weekday % 7]}, ${monthNames[bookingDateTime.month - 1]} ${bookingDateTime.day}';
  }

  String get shortDate {
    final monthNames = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${monthNames[bookingDateTime.month - 1]} ${bookingDateTime.day}, ${bookingDateTime.year}';
  }

  String get formattedPrice => 'PKR $pricePKR';

  bool get isUpcoming => 
      (status == BookingStatus.confirmed || status == BookingStatus.pending) && 
      bookingDateTime.isAfter(DateTime.now());

  /// Whether the customer can still cancel this booking.
  /// Cannot cancel once job is in_progress (Phase 3 rule).
  bool get canCancel =>
      (status == BookingStatus.pending || status == BookingStatus.confirmed) &&
      bookingDateTime.isAfter(DateTime.now()) &&
      status != BookingStatus.inProgress &&
      disputeStatus == null; // Cannot cancel if dispute is open

  /// Whether the booking is currently a live job
  bool get isLiveJob =>
      status == BookingStatus.confirmed || status == BookingStatus.inProgress;

  /// Whether this booking needs customer action due to expired assignment
  bool get needsRerouteDecision =>
      status == BookingStatus.pending && assignmentExpired;

  /// Whether rerouting is still allowed (max 3)
  bool get canReroute => rerouteCount < 3;

  /// Whether the assignment timer has expired (read from server flag only)
  bool get isAssignmentExpired => assignmentExpired;

  // Escrow and Dispute Getters
  String get escrowStatusText {
    switch (escrowStatus) {
      case EscrowStatus.held:
        return 'Held in Escrow';
      case EscrowStatus.released:
        return 'Payment Released';
      case EscrowStatus.refunded:
        return 'Payment Refunded';
      case EscrowStatus.disputed:
        return 'Payment Disputed';
      default:
        return 'Processing';
    }
  }

  Color get escrowStatusColor {
    switch (escrowStatus) {
      case EscrowStatus.held:
        return const Color(0xFFFF9800); // Orange
      case EscrowStatus.released:
        return const Color(0xFF4CAF50); // Green
      case EscrowStatus.refunded:
        return const Color(0xFF2196F3); // Blue
      case EscrowStatus.disputed:
        return const Color(0xFFF44336); // Red
      default:
        return const Color(0xFF9E9E9E); // Grey
    }
  }

  String get disputeStatusText {
    switch (disputeStatus) {
      case DisputeStatus.open:
        return 'Dispute Filed';
      case DisputeStatus.investigating:
        return 'Under Investigation';
      case DisputeStatus.resolved:
        return 'Dispute Resolved';
      case DisputeStatus.closed:
        return 'Dispute Closed';
      default:
        return '';
    }
  }

  Color get disputeStatusColor {
    switch (disputeStatus) {
      case DisputeStatus.open:
        return const Color(0xFFFF9800); // Orange
      case DisputeStatus.investigating:
        return const Color(0xFF2196F3); // Blue
      case DisputeStatus.resolved:
        return const Color(0xFF4CAF50); // Green
      case DisputeStatus.closed:
        return const Color(0xFF9E9E9E); // Grey
      default:
        return const Color(0xFF9E9E9E);
    }
  }

  bool get hasActiveDispute => disputeId != null && disputeStatus != DisputeStatus.closed;

  bool get isLockedByDispute => hasActiveDispute;

  /// Create Booking from Firestore document data
  factory Booking.fromMap(Map<String, dynamic> map) {
    // Parse bookingDateTime from Firestore Timestamp
    DateTime bookingDateTime;
    final bookingDateTimeField = map['bookingDateTime'];
    if (bookingDateTimeField is Timestamp) {
      bookingDateTime = bookingDateTimeField.toDate();
    } else if (bookingDateTimeField is DateTime) {
      bookingDateTime = bookingDateTimeField;
    } else {
      bookingDateTime = DateTime.now();
    }

    // Parse createdAt from Firestore Timestamp
    DateTime createdAt;
    final createdAtField = map['createdAt'];
    if (createdAtField is Timestamp) {
      createdAt = createdAtField.toDate();
    } else if (createdAtField is DateTime) {
      createdAt = createdAtField;
    } else {
      createdAt = DateTime.now();
    }

    // Parse acceptedAt from Firestore Timestamp
    DateTime? acceptedAt;
    final acceptedAtField = map['acceptedAt'];
    if (acceptedAtField is Timestamp) {
      acceptedAt = acceptedAtField.toDate();
    } else if (acceptedAtField is DateTime) {
      acceptedAt = acceptedAtField;
    }

    // Parse startedAt from Firestore Timestamp
    DateTime? startedAt;
    final startedAtField = map['startedAt'];
    if (startedAtField is Timestamp) {
      startedAt = startedAtField.toDate();
    } else if (startedAtField is DateTime) {
      startedAt = startedAtField;
    }

    // Parse updatedAt from Firestore Timestamp
    DateTime? updatedAt;
    final updatedAtField = map['updatedAt'];
    if (updatedAtField is Timestamp) {
      updatedAt = updatedAtField.toDate();
    } else if (updatedAtField is DateTime) {
      updatedAt = updatedAtField;
    }

    // Parse status (Phase 3: backward-compatible parser)
    final status = parseBookingStatus(map['status']?.toString());

    // Parse rejectedAt from Firestore Timestamp
    DateTime? rejectedAt;
    final rejectedAtField = map['rejectedAt'];
    if (rejectedAtField is Timestamp) {
      rejectedAt = rejectedAtField.toDate();
    } else if (rejectedAtField is DateTime) {
      rejectedAt = rejectedAtField;
    }

    // Parse completedAt from Firestore Timestamp
    DateTime? completedAt;
    final completedAtField = map['completedAt'];
    if (completedAtField is Timestamp) {
      completedAt = completedAtField.toDate();
    } else if (completedAtField is DateTime) {
      completedAt = completedAtField;
    }

    // Parse assignedAt from Firestore Timestamp
    DateTime? assignedAt;
    final assignedAtField = map['assignedAt'];
    if (assignedAtField is Timestamp) {
      assignedAt = assignedAtField.toDate();
    } else if (assignedAtField is DateTime) {
      assignedAt = assignedAtField;
    }

    // Parse assignmentExpiresAt from Firestore Timestamp
    DateTime? assignmentExpiresAt;
    final assignmentExpiresAtField = map['assignmentExpiresAt'];
    if (assignmentExpiresAtField is Timestamp) {
      assignmentExpiresAt = assignmentExpiresAtField.toDate();
    } else if (assignmentExpiresAtField is DateTime) {
      assignmentExpiresAt = assignmentExpiresAtField;
    }

    // Parse payment method
    PaymentMethod? paymentMethod;
    final paymentMethodStr = map['paymentMethod'] as String?;
    if (paymentMethodStr != null) {
      paymentMethod = PaymentMethod.values.firstWhere(
        (p) => p.name == paymentMethodStr,
        orElse: () => PaymentMethod.wallet,
      );
    }

    // Defensive helper: safely convert to int (handles int, double, String)
    int? safeInt(dynamic value) {
      if (value == null) return null;
      if (value is int) return value;
      if (value is double) return value.toInt();
      return int.tryParse(value.toString());
    }

    return Booking(
      id: (map['id'] ?? '').toString(),
      barberId: (map['barberId'] ?? '').toString(),
      barberName: (map['barberName'] ?? '').toString(),
      shopName: map['shopName']?.toString(),
      barberImageUrl: (map['barberImageUrl'] ?? '').toString(),
      barberAddress: map['barberAddress']?.toString(),
      bookingDateTime: bookingDateTime,
      timeSlot: (map['timeSlot'] ?? '').toString(),
      pricePKR: safeInt(map['pricePKR']) ?? 0,
      status: status,
      createdAt: createdAt,
      acceptedAt: acceptedAt,
      startedAt: startedAt,
      updatedAt: updatedAt,
      paymentMethod: paymentMethod,
      cancellationReason: map['cancellationReason']?.toString(),
      cancelledBy: map['cancelledBy']?.toString(),
      rating: safeInt(map['rating']),
      customerId: map['customerId']?.toString(),
      customerName: map['customerName']?.toString(),
      customerImageUrl: map['customerImageUrl']?.toString(),
      customerRatingScore: (map['customerRatingScore'] as num?)?.toDouble(),
      customerRating: safeInt(map['customerRating']),
      customerRatingComment: map['customerRatingComment']?.toString(),
      isBookingForOther: map['isBookingForOther'] as bool? ?? false,
      bookedForName: map['bookedForName']?.toString(),
      bookedForNotes: map['bookedForNotes']?.toString(),
      selectedServices: List<String>.from(map['selectedServices'] ?? []),
      escrowStatus: map['escrowStatus'] != null
          ? EscrowStatus.values.firstWhere(
              (s) => s.name == map['escrowStatus'].toString(),
              orElse: () => EscrowStatus.held,
            )
          : null,
      disputeId: map['disputeId']?.toString(),
      disputeStatus: map['disputeStatus'] != null
          ? DisputeStatus.values.firstWhere(
              (s) => s.name == map['disputeStatus'].toString(),
              orElse: () => DisputeStatus.open,
            )
          : null,
      // Booking engine fields
      serviceIds: List<String>.from(map['serviceIds'] ?? []),
      rescheduleCount: safeInt(map['rescheduleCount']) ?? 0,
      barberSwitched: map['barberSwitched'] as bool? ?? false,
      originalBarberId: map['originalBarberId']?.toString(),
      originalPrice: safeInt(map['originalPrice']),
      refundAmount: safeInt(map['refundAmount']),
      // Phase 3 fields
      serviceMode: (map['serviceMode'] ?? 'shop').toString(),
      rejectedAt: rejectedAt,
      completedAt: completedAt,
      barberEarnings: safeInt(map['barberEarnings']),
      platformFee: safeInt(map['platformFee']),
      // Phase 4 rerouting fields
      assignedAt: assignedAt,
      assignmentExpiresAt: assignmentExpiresAt,
      assignmentExpired: map['assignmentExpired'] as bool? ?? false,
      rerouteCount: safeInt(map['rerouteCount']) ?? 0,
      lastAssignmentBarberId: map['lastAssignmentBarberId']?.toString(),
    );
  }

  /// Convert Booking to Map for Firestore
  Map<String, dynamic> toMap() {
    return {
      'barberId': barberId,
      'barberName': barberName,
      'shopName': shopName,
      'barberImageUrl': barberImageUrl,
      'barberAddress': barberAddress,
      'bookingDateTime': Timestamp.fromDate(bookingDateTime),
      'timeSlot': timeSlot,
      'pricePKR': pricePKR,
      'status': status.name,
      'createdAt': Timestamp.fromDate(createdAt),
      'acceptedAt': acceptedAt != null ? Timestamp.fromDate(acceptedAt!) : null,
      'startedAt': startedAt != null ? Timestamp.fromDate(startedAt!) : null,
      'updatedAt': updatedAt != null ? Timestamp.fromDate(updatedAt!) : null,
      'paymentMethod': paymentMethod?.name,
      'cancellationReason': cancellationReason,
      'cancelledBy': cancelledBy,
      'rating': rating,
      'customerId': customerId,
      'customerName': customerName,
      'customerImageUrl': customerImageUrl,
      'customerRatingScore': customerRatingScore,
      'customerRating': customerRating,
      'customerRatingComment': customerRatingComment,
      'isBookingForOther': isBookingForOther,
      'bookedForName': bookedForName,
      'bookedForNotes': bookedForNotes,
      'selectedServices': selectedServices,
      'escrowStatus': escrowStatus?.name,
      'disputeId': disputeId,
      'disputeStatus': disputeStatus?.name,
      // Booking engine fields
      'serviceIds': serviceIds,
      'rescheduleCount': rescheduleCount,
      'barberSwitched': barberSwitched,
      'originalBarberId': originalBarberId,
      'originalPrice': originalPrice,
      'refundAmount': refundAmount,
      // Phase 3 fields
      'serviceMode': serviceMode,
      'rejectedAt': rejectedAt != null ? Timestamp.fromDate(rejectedAt!) : null,
      'completedAt': completedAt != null ? Timestamp.fromDate(completedAt!) : null,
      'barberEarnings': barberEarnings,
      'platformFee': platformFee,
      // Phase 4 rerouting fields
      'assignedAt': assignedAt != null ? Timestamp.fromDate(assignedAt!) : null,
      'assignmentExpiresAt': assignmentExpiresAt != null ? Timestamp.fromDate(assignmentExpiresAt!) : null,
      'assignmentExpired': assignmentExpired,
      'rerouteCount': rerouteCount,
      'lastAssignmentBarberId': lastAssignmentBarberId,
    };
  }

  /// Get the name to display for this booking
  String get displayName => isBookingForOther && bookedForName != null 
      ? bookedForName! 
      : customerName ?? 'Customer';

  /// Create a copy with updated fields
  Booking copyWith({
    String? id,
    String? barberId,
    String? barberName,
    String? shopName,
    String? barberImageUrl,
    String? barberAddress,
    DateTime? bookingDateTime,
    String? timeSlot,
    int? pricePKR,
    BookingStatus? status,
    DateTime? createdAt,
    DateTime? acceptedAt,
    DateTime? startedAt,
    DateTime? updatedAt,
    PaymentMethod? paymentMethod,
    String? cancellationReason,
    String? cancelledBy,
    int? rating,
    String? customerId,
    String? customerName,
    String? customerImageUrl,
    double? customerRatingScore,
    int? customerRating,
    String? customerRatingComment,
    bool? isBookingForOther,
    String? bookedForName,
    String? bookedForNotes,
    List<String>? selectedServices,
    EscrowStatus? escrowStatus,
    String? disputeId,
    DisputeStatus? disputeStatus,
    List<String>? serviceIds,
    int? rescheduleCount,
    bool? barberSwitched,
    String? originalBarberId,
    int? originalPrice,
    int? refundAmount,
    String? serviceMode,
    DateTime? rejectedAt,
    DateTime? completedAt,
    int? barberEarnings,
    int? platformFee,
    DateTime? assignedAt,
    DateTime? assignmentExpiresAt,
    bool? assignmentExpired,
    int? rerouteCount,
    String? lastAssignmentBarberId,
  }) {
    return Booking(
      id: id ?? this.id,
      barberId: barberId ?? this.barberId,
      barberName: barberName ?? this.barberName,
      shopName: shopName ?? this.shopName,
      barberImageUrl: barberImageUrl ?? this.barberImageUrl,
      barberAddress: barberAddress ?? this.barberAddress,
      bookingDateTime: bookingDateTime ?? this.bookingDateTime,
      timeSlot: timeSlot ?? this.timeSlot,
      pricePKR: pricePKR ?? this.pricePKR,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      acceptedAt: acceptedAt ?? this.acceptedAt,
      startedAt: startedAt ?? this.startedAt,
      updatedAt: updatedAt ?? this.updatedAt,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      cancellationReason: cancellationReason ?? this.cancellationReason,
      cancelledBy: cancelledBy ?? this.cancelledBy,
      rating: rating ?? this.rating,
      customerId: customerId ?? this.customerId,
      customerName: customerName ?? this.customerName,
      customerImageUrl: customerImageUrl ?? this.customerImageUrl,
      customerRatingScore: customerRatingScore ?? this.customerRatingScore,
      customerRating: customerRating ?? this.customerRating,
      customerRatingComment: customerRatingComment ?? this.customerRatingComment,
      isBookingForOther: isBookingForOther ?? this.isBookingForOther,
      bookedForName: bookedForName ?? this.bookedForName,
      bookedForNotes: bookedForNotes ?? this.bookedForNotes,
      selectedServices: selectedServices ?? this.selectedServices,
      escrowStatus: escrowStatus ?? this.escrowStatus,
      disputeId: disputeId ?? this.disputeId,
      disputeStatus: disputeStatus ?? this.disputeStatus,
      serviceIds: serviceIds ?? this.serviceIds,
      rescheduleCount: rescheduleCount ?? this.rescheduleCount,
      barberSwitched: barberSwitched ?? this.barberSwitched,
      originalBarberId: originalBarberId ?? this.originalBarberId,
      originalPrice: originalPrice ?? this.originalPrice,
      refundAmount: refundAmount ?? this.refundAmount,
      serviceMode: serviceMode ?? this.serviceMode,
      rejectedAt: rejectedAt ?? this.rejectedAt,
      completedAt: completedAt ?? this.completedAt,
      barberEarnings: barberEarnings ?? this.barberEarnings,
      platformFee: platformFee ?? this.platformFee,
      assignedAt: assignedAt ?? this.assignedAt,
      assignmentExpiresAt: assignmentExpiresAt ?? this.assignmentExpiresAt,
      assignmentExpired: assignmentExpired ?? this.assignmentExpired,
      rerouteCount: rerouteCount ?? this.rerouteCount,
      lastAssignmentBarberId: lastAssignmentBarberId ?? this.lastAssignmentBarberId,
    );
  }
}

enum BookingStatus {
  // ── Phase 3 Lifecycle ────────────────────────────────────────────────────
  // requested → accepted → inProgress → completed
  // rejected / cancelled handled separately
  pending,              // Customer created booking (= "Requested")
  rerouting,            // Barber didn't respond in time — finding another barber
  confirmed,            // Barber accepted (= "Accepted")
  inProgress,           // Barber started the job
  completed,            // Job finished
  rejected,             // Barber rejected the request
  cancelledByCustomer,
  cancelledByBarber,
}

extension BookingStatusExtension on BookingStatus {
  String get displayName {
    switch (this) {
      case BookingStatus.pending:
        return 'Requested';
      case BookingStatus.rerouting:
        return 'Finding Barber';
      case BookingStatus.confirmed:
        return 'Accepted';
      case BookingStatus.inProgress:
        return 'In Progress';
      case BookingStatus.completed:
        return 'Completed';
      case BookingStatus.rejected:
        return 'Rejected';
      case BookingStatus.cancelledByCustomer:
        return 'Cancelled';
      case BookingStatus.cancelledByBarber:
        return 'Cancelled by Barber';
    }
  }

  String get description {
    switch (this) {
      case BookingStatus.pending:
        return 'Waiting for barber to accept';
      case BookingStatus.rerouting:
        return 'Barber didn\'t respond — routing to the next nearest barber';
      case BookingStatus.confirmed:
        return 'Barber accepted — awaiting appointment';
      case BookingStatus.inProgress:
        return 'Your haircut is in progress';
      case BookingStatus.completed:
        return 'Haircut completed';
      case BookingStatus.rejected:
        return 'Barber declined this request';
      case BookingStatus.cancelledByCustomer:
        return 'You cancelled this booking';
      case BookingStatus.cancelledByBarber:
        return 'Barber cancelled this booking';
    }
  }

  bool get isCancelled => 
      this == BookingStatus.cancelledByCustomer || 
      this == BookingStatus.cancelledByBarber;

  /// Whether this status represents an active/live booking
  bool get isActive =>
      this == BookingStatus.pending ||
      this == BookingStatus.rerouting ||
      this == BookingStatus.confirmed ||
      this == BookingStatus.inProgress;

  /// Whether the booking is terminal (no further transitions)
  bool get isTerminal =>
      this == BookingStatus.completed ||
      this == BookingStatus.rejected ||
      isCancelled;

  /// Color for status badges
  Color get color {
    switch (this) {
      case BookingStatus.pending:
        return const Color(0xFFFF9800); // Orange
      case BookingStatus.rerouting:
        return const Color(0xFF9C27B0); // Purple
      case BookingStatus.confirmed:
        return const Color(0xFF2196F3); // Blue
      case BookingStatus.inProgress:
        return const Color(0xFF00C853); // Green
      case BookingStatus.completed:
        return const Color(0xFF4CAF50); // Green
      case BookingStatus.rejected:
        return const Color(0xFFF44336); // Red
      case BookingStatus.cancelledByCustomer:
      case BookingStatus.cancelledByBarber:
        return const Color(0xFFF44336); // Red
    }
  }

  /// Icon for this status
  IconData get icon {
    switch (this) {
      case BookingStatus.pending:
        return Icons.schedule;
      case BookingStatus.rerouting:
        return Icons.alt_route;
      case BookingStatus.confirmed:
        return Icons.check_circle;
      case BookingStatus.inProgress:
        return Icons.play_circle_filled;
      case BookingStatus.completed:
        return Icons.verified;
      case BookingStatus.rejected:
        return Icons.cancel;
      case BookingStatus.cancelledByCustomer:
      case BookingStatus.cancelledByBarber:
        return Icons.cancel_outlined;
    }
  }
}

/// Null-safe "HH:mm" time-slot parser.
///
/// Returns `null` for anything malformed (null, empty, non-numeric, out of
/// range) instead of throwing, so bad slot data from Firestore can never take
/// down a view. `"9:30"`, `"09:30"` and `"09"` are all accepted.
({int hour, int minute})? parseTimeSlot(String? slot) {
  if (slot == null) return null;
  final value = slot.trim();
  if (value.isEmpty) return null;

  final parts = value.split(':');
  final hour = int.tryParse(parts[0].trim());
  if (hour == null || hour < 0 || hour > 23) return null;

  final minute = parts.length > 1 ? int.tryParse(parts[1].trim()) : 0;
  if (minute == null || minute < 0 || minute > 59) return null;

  return (hour: hour, minute: minute);
}

/// Parse BookingStatus from Firestore string with backward compatibility.
/// Handles both old names (pending/confirmed) and Phase 3 names (requested/accepted/in_progress).
BookingStatus parseBookingStatus(String? statusStr) {
  switch (statusStr) {
    case 'pending':
    case 'requested':
      return BookingStatus.pending;
    case 'rerouting':
      return BookingStatus.rerouting;
    case 'confirmed':
    case 'accepted':
      return BookingStatus.confirmed;
    case 'inProgress':
    case 'in_progress':
      return BookingStatus.inProgress;
    case 'completed':
      return BookingStatus.completed;
    case 'rejected':
      return BookingStatus.rejected;
    case 'cancelledByCustomer':
      return BookingStatus.cancelledByCustomer;
    case 'cancelledByBarber':
      return BookingStatus.cancelledByBarber;
    default:
      return BookingStatus.pending;
  }
}
