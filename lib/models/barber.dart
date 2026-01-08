import 'package:flutter/material.dart';

class Barber {
  final String id;
  final String name;
  final String email;
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
  
  // Schedule Properties
  final String workStartHour; // e.g., "09:00"
  final String workEndHour;   // e.g., "22:00"
  final List<int> daysOff;     // 1 = Monday, 7 = Sunday
  
  final String? bio;
  final String? address;

  Barber({
    required this.id,
    required this.name,
    required this.email,
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
    this.workStartHour = "09:00",
    this.workEndHour = "22:00",
    this.daysOff = const [],
    this.bio,
    this.address,
  });

  bool get isAvailable => isOnline && status == 'approved' && isWithinWorkingHours;

  bool get isProfileComplete => 
    name.isNotEmpty && 
    imageUrl.isNotEmpty && 
    imageUrl.startsWith('http');

  bool get isWithinWorkingHours {
    final now = DateTime.now();
    
    // Check if today is a day off
    if (daysOff.contains(now.weekday)) return false;

    // Parse working hours
    final startParts = workStartHour.split(':');
    final endParts = workEndHour.split(':');
    
    final startTime = TimeOfDay(
      hour: int.parse(startParts[0]), 
      minute: int.parse(startParts[1])
    );
    final endTime = TimeOfDay(
      hour: int.parse(endParts[0]), 
      minute: int.parse(endParts[1])
    );

    final currentTime = TimeOfDay.fromDateTime(now);
    
    // Simple comparison
    double nowDouble = currentTime.hour + currentTime.minute / 60.0;
    double startDouble = startTime.hour + startTime.minute / 60.0;
    double endDouble = endTime.hour + endTime.minute / 60.0;

    return nowDouble >= startDouble && nowDouble <= endDouble;
  }

  factory Barber.fromMap(Map<String, dynamic> map) {
    return Barber(
      id: map['id'] ?? '',
      name: map['name'] ?? '',
      email: map['email'] ?? '',
      shopName: map['shopName'],
      imageUrl: map['imageUrl'] ?? '',
      galleryUrls: List<String>.from(map['galleryUrls'] ?? []),
      rating: (map['rating'] ?? 0.0).toDouble(),
      reviewsCount: map['reviewsCount'] ?? 0,
      latitude: (map['latitude'] ?? 0.0).toDouble(),
      longitude: (map['longitude'] ?? 0.0).toDouble(),
      isOnline: map['isOnline'] ?? false,
      priceStartingPKR: (map['priceStartingPKR'] ?? 0.0).toDouble(),
      status: map['status'] ?? 'pending',
      workStartHour: map['workStartHour'] ?? "09:00",
      workEndHour: map['workEndHour'] ?? "22:00",
      daysOff: List<int>.from(map['daysOff'] ?? []),
      bio: map['bio'],
      address: map['address'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'email': email,
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
      'workStartHour': workStartHour,
      'workEndHour': workEndHour,
      'daysOff': daysOff,
      'bio': bio,
      'address': address,
    };
  }

  Barber copyWith({
    String? name,
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
  }) {
    return Barber(
      id: id,
      name: name ?? this.name,
      email: email,
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
      workStartHour: workStartHour ?? this.workStartHour,
      workEndHour: workEndHour ?? this.workEndHour,
      daysOff: daysOff ?? this.daysOff,
      bio: bio ?? this.bio,
      address: address ?? this.address,
    );
  }
}
