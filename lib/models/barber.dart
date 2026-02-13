import 'package:flutter/material.dart';

/// Barber Availability Status for UI display
enum BarberAvailabilityStatus {
  online,      // Online and bookable
  offline,     // Offline (not bookable, but shop visible)
  closed,      // Outside working hours (not bookable, shop visible)
  dayOff,      // Day off (not bookable, shop visible)
}

class Barber {
  final String id;
  final String name;
  final String email;
  final String? phone;
  final String? shopName;
  final String imageUrl;
  final List<String> galleryUrls;
  final double rating;
  final int reviewsCount;
  final double latitude;
  final double longitude;
  final bool isOnline;
  final double priceStartingPKR;
  final String status; // 'pending', 'approved', 'rejected'
  final int avgDurationMinutes;
  
  // Schedule Properties
  final String workStartHour; // e.g., "09:00"
  final String workEndHour;   // e.g., "22:00"
  final List<int> daysOff;     // 1 = Monday, 7 = Sunday
  
  final String? bio;
  final String? address;
  final double? calculatedDistance;
  
  // Services offered
  final List<String> services;

  // Phase 3: Barber type (shop_only | doorstep_only | both)
  final String barberType;

  Barber({
    required this.id,
    required this.name,
    required this.email,
    this.phone,
    this.shopName,
    required this.imageUrl,
    this.galleryUrls = const [],
    this.rating = 0.0,
    this.reviewsCount = 0,
    required this.latitude,
    required this.longitude,
    this.isOnline = false,
    required this.priceStartingPKR,
    this.status = 'pending',
    this.avgDurationMinutes = 30,
    this.workStartHour = '09:00',
    this.workEndHour = '22:00',
    this.daysOff = const [],
    this.bio,
    this.address,
    this.calculatedDistance,
    this.services = const [],
    this.barberType = 'shop_only',
  });

  String get formattedPrice => 'Rs. ${priceStartingPKR.toInt()}';

  String get formattedDistance {
    if (calculatedDistance == null) return '0.0 km';
    if (calculatedDistance! < 1) {
      return '${(calculatedDistance! * 1000).toInt()} m';
    }
    return '${calculatedDistance!.toStringAsFixed(1)} km';
  }

  /// Whether barber is available for booking (online + within hours + approved)
  bool get isAvailable => isOnline && status == 'approved' && isWithinWorkingHours;

  /// Whether barber is bookable right now
  bool get isBookable => isOnline && status == 'approved' && isWithinWorkingHours;

  bool get isProfileComplete => 
    name.isNotEmpty && 
    imageUrl.isNotEmpty && 
    imageUrl.startsWith('http');

  /// Get the current availability status for display
  BarberAvailabilityStatus get availabilityStatus {
    if (status != 'approved') return BarberAvailabilityStatus.offline;
    
    final now = DateTime.now();
    if (daysOff.contains(now.weekday)) return BarberAvailabilityStatus.dayOff;
    if (!isWithinWorkingHours) return BarberAvailabilityStatus.closed;
    if (!isOnline) return BarberAvailabilityStatus.offline;
    
    return BarberAvailabilityStatus.online;
  }

  /// Human readable status text
  String get statusText {
    switch (availabilityStatus) {
      case BarberAvailabilityStatus.online:
        return 'Open Now';
      case BarberAvailabilityStatus.offline:
        return 'Offline';
      case BarberAvailabilityStatus.closed:
        return 'Closed';
      case BarberAvailabilityStatus.dayOff:
        return 'Day Off';
    }
  }

  /// Status color for UI
  Color get statusColor {
    switch (availabilityStatus) {
      case BarberAvailabilityStatus.online:
        return const Color(0xFF00C853);
      case BarberAvailabilityStatus.offline:
        return Colors.grey;
      case BarberAvailabilityStatus.closed:
        return Colors.red;
      case BarberAvailabilityStatus.dayOff:
        return Colors.orange;
    }
  }

  bool get isWithinWorkingHours {
    final now = DateTime.now();
    
    // Check if today is a day off
    if (daysOff.contains(now.weekday)) return false;

    // Parse working hours
    final startParts = workStartHour.split(':');
    final endParts = workEndHour.split(':');
    
    if (startParts.length != 2 || endParts.length != 2) return false;
    
    final startTime = TimeOfDay(
      hour: int.tryParse(startParts[0]) ?? 9, 
      minute: int.tryParse(startParts[1]) ?? 0
    );
    final endTime = TimeOfDay(
      hour: int.tryParse(endParts[0]) ?? 22, 
      minute: int.tryParse(endParts[1]) ?? 0
    );

    final currentTime = TimeOfDay.fromDateTime(now);
    
    // Simple comparison
    double nowDouble = currentTime.hour + currentTime.minute / 60.0;
    double startDouble = startTime.hour + startTime.minute / 60.0;
    double endDouble = endTime.hour + endTime.minute / 60.0;

    return nowDouble >= startDouble && nowDouble <= endDouble;
  }

  /// Check if a specific time is within working hours
  bool isTimeWithinWorkingHours(DateTime dateTime) {
    // Check if that day is a day off
    if (daysOff.contains(dateTime.weekday)) return false;

    // Parse working hours
    final startParts = workStartHour.split(':');
    final endParts = workEndHour.split(':');
    
    if (startParts.length != 2 || endParts.length != 2) return false;
    
    final startHour = int.tryParse(startParts[0]) ?? 9;
    final startMin = int.tryParse(startParts[1]) ?? 0;
    final endHour = int.tryParse(endParts[0]) ?? 22;
    final endMin = int.tryParse(endParts[1]) ?? 0;

    final time = TimeOfDay.fromDateTime(dateTime);
    double timeDouble = time.hour + time.minute / 60.0;
    double startDouble = startHour + startMin / 60.0;
    double endDouble = endHour + endMin / 60.0;

    return timeDouble >= startDouble && timeDouble <= endDouble;
  }

  /// Get formatted working hours string
  String get formattedWorkingHours {
    return '$workStartHour - $workEndHour';
  }

  /// Get list of days off as strings
  List<String> get daysOffNames {
    const dayNames = ['', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return daysOff.map((d) => dayNames[d]).toList();
  }

  factory Barber.fromMap(Map<String, dynamic> map) {
    // Defensive parsing: Firestore may store workStartHour/workEndHour as int
    // (e.g. 9 instead of '09:00'). Convert gracefully to avoid type errors.
    String _parseHour(dynamic value, String fallback) {
      if (value == null) return fallback;
      if (value is String) return value;
      if (value is int) return '${value.toString().padLeft(2, '0')}:00';
      return value.toString();
    }

    return Barber(
      id: (map['id'] ?? '').toString(),
      name: (map['name'] ?? '').toString(),
      email: (map['email'] ?? '').toString(),
      phone: map['phone']?.toString(),
      shopName: map['shopName']?.toString(),
      imageUrl: (map['imageUrl'] ?? '').toString(),
      galleryUrls: List<String>.from(map['galleryUrls'] ?? []),
      rating: (map['rating'] ?? 0.0).toDouble(),
      reviewsCount: (map['reviewsCount'] is int) ? map['reviewsCount'] : int.tryParse(map['reviewsCount']?.toString() ?? '0') ?? 0,
      latitude: (map['latitude'] ?? 0.0).toDouble(),
      longitude: (map['longitude'] ?? 0.0).toDouble(),
      isOnline: map['isOnline'] ?? false,
      priceStartingPKR: (map['priceStartingPKR'] ?? 0).toDouble(),
      status: (map['status'] ?? 'pending').toString(),
      avgDurationMinutes: (map['avgDurationMinutes'] is int) ? map['avgDurationMinutes'] : int.tryParse(map['avgDurationMinutes']?.toString() ?? '30') ?? 30,
      workStartHour: _parseHour(map['workStartHour'], '09:00'),
      workEndHour: _parseHour(map['workEndHour'], '22:00'),
      daysOff: List<int>.from(map['daysOff'] ?? []),
      bio: map['bio']?.toString(),
      address: map['address']?.toString(),
      services: List<String>.from(map['services'] ?? []),
      barberType: (map['barberType'] ?? 'shop_only').toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'email': email,
      'phone': phone,
      'shopName': shopName,
      'imageUrl': imageUrl,
      'galleryUrls': galleryUrls,
      'rating': rating,
      'reviewsCount': reviewsCount,
      'latitude': latitude,
      'longitude': longitude,
      'isOnline': isOnline,
      'priceStartingPKR': priceStartingPKR,
      'status': status,
      'avgDurationMinutes': avgDurationMinutes,
      'workStartHour': workStartHour,
      'workEndHour': workEndHour,
      'daysOff': daysOff,
      'bio': bio,
      'address': address,
      'services': services,
      'barberType': barberType,
    };
  }

  Barber copyWith({
    String? name,
    String? phone,
    String? shopName,
    String? imageUrl,
    List<String>? galleryUrls,
    bool? isOnline,
    String? workStartHour,
    String? workEndHour,
    List<int>? daysOff,
    String? bio,
    String? address,
    double? priceStartingPKR,
    int? avgDurationMinutes,
    double? calculatedDistance,
    List<String>? services,
    String? barberType,
  }) {
    return Barber(
      id: id,
      name: name ?? this.name,
      email: email,
      phone: phone ?? this.phone,
      shopName: shopName ?? this.shopName,
      imageUrl: imageUrl ?? this.imageUrl,
      galleryUrls: galleryUrls ?? this.galleryUrls,
      rating: rating,
      reviewsCount: reviewsCount,
      latitude: latitude,
      longitude: longitude,
      isOnline: isOnline ?? this.isOnline,
      priceStartingPKR: priceStartingPKR ?? this.priceStartingPKR,
      status: status,
      avgDurationMinutes: avgDurationMinutes ?? this.avgDurationMinutes,
      workStartHour: workStartHour ?? this.workStartHour,
      workEndHour: workEndHour ?? this.workEndHour,
      daysOff: daysOff ?? this.daysOff,
      bio: bio ?? this.bio,
      address: address ?? this.address,
      calculatedDistance: calculatedDistance ?? this.calculatedDistance,
      services: services ?? this.services,
      barberType: barberType ?? this.barberType,
    );
  }
}
