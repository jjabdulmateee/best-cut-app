/// Customer model for the barber to view and rate
class Customer {
  final String id;
  final String name;
  final String phoneNumber;
  final String imageUrl;
  final double rating;
  final int totalBookings;
  final int cancelledBookings;

  const Customer({
    required this.id,
    required this.name,
    required this.phoneNumber,
    required this.imageUrl,
    required this.rating,
    required this.totalBookings,
    required this.cancelledBookings,
  });

  String get formattedRating => rating.toStringAsFixed(1);
  
  double get trustScore {
    if (totalBookings == 0) return 5.0;
    final cancelRate = cancelledBookings / totalBookings;
    return (rating * (1 - cancelRate * 0.5)).clamp(1.0, 5.0);
  }
  
  String get trustLevel {
    if (trustScore >= 4.5) return 'Excellent';
    if (trustScore >= 4.0) return 'Good';
    if (trustScore >= 3.0) return 'Fair';
    return 'Low';
  }
  
  bool get isLowTrust => trustScore < 3.0;
}

