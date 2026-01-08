import 'package:cloud_firestore/cloud_firestore.dart';
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
      status == BookingStatus.confirmed && 
      bookingDateTime.isAfter(DateTime.now());

  bool get canCancel => 
      status == BookingStatus.confirmed && 
      bookingDateTime.isAfter(DateTime.now());

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

    // Parse status
    final statusStr = map['status'] as String? ?? 'pending';
    final status = BookingStatus.values.firstWhere(
      (s) => s.name == statusStr,
      orElse: () => BookingStatus.pending,
    );

    // Parse payment method
    PaymentMethod? paymentMethod;
    final paymentMethodStr = map['paymentMethod'] as String?;
    if (paymentMethodStr != null) {
      paymentMethod = PaymentMethod.values.firstWhere(
        (p) => p.name == paymentMethodStr,
        orElse: () => PaymentMethod.wallet,
      );
    }

    return Booking(
      id: map['id'] as String? ?? '',
      barberId: map['barberId'] as String? ?? '',
      barberName: map['barberName'] as String? ?? '',
      shopName: map['shopName'] as String?,
      barberImageUrl: map['barberImageUrl'] as String? ?? '',
      barberAddress: map['barberAddress'] as String?,
      bookingDateTime: bookingDateTime,
      timeSlot: map['timeSlot'] as String? ?? '',
      pricePKR: map['pricePKR'] as int? ?? 0,
      status: status,
      createdAt: createdAt,
      paymentMethod: paymentMethod,
      cancellationReason: map['cancellationReason'] as String?,
      cancelledBy: map['cancelledBy'] as String?,
      rating: map['rating'] as int?,
      customerId: map['customerId'] as String?,
      customerName: map['customerName'] as String?,
      customerImageUrl: map['customerImageUrl'] as String?,
      customerRatingScore: (map['customerRatingScore'] as num?)?.toDouble(),
      customerRating: map['customerRating'] as int?,
      customerRatingComment: map['customerRatingComment'] as String?,
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
    };
  }

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
    );
  }
}

enum BookingStatus {
  pending,
  confirmed,
  completed,
  cancelledByCustomer,
  cancelledByBarber,
}

extension BookingStatusExtension on BookingStatus {
  String get displayName {
    switch (this) {
      case BookingStatus.pending:
        return 'Pending';
      case BookingStatus.confirmed:
        return 'Confirmed';
      case BookingStatus.completed:
        return 'Completed';
      case BookingStatus.cancelledByCustomer:
        return 'Cancelled';
      case BookingStatus.cancelledByBarber:
        return 'Cancelled by Barber';
    }
  }

  String get description {
    switch (this) {
      case BookingStatus.pending:
        return 'Waiting for confirmation';
      case BookingStatus.confirmed:
        return 'Your booking is confirmed';
      case BookingStatus.completed:
        return 'Haircut completed';
      case BookingStatus.cancelledByCustomer:
        return 'You cancelled this booking';
      case BookingStatus.cancelledByBarber:
        return 'Barber cancelled this booking';
    }
  }

  bool get isCancelled => 
      this == BookingStatus.cancelledByCustomer || 
      this == BookingStatus.cancelledByBarber;
}
