import '../models/barber.dart';
import 'map_service.dart';
import 'firestore_service.dart';

class SmartAgentService {
  static final SmartAgentService _instance = SmartAgentService._internal();
  factory SmartAgentService() => _instance;
  SmartAgentService._internal();

  final FirestoreService _firestore = FirestoreService();

  /// Finds and sorts approved, online, and AVAILABLE barbers
  List<Barber> findBestBarbers({
    required List<Barber> allBarbers,
    required GeoPoint userLocation,
    double maxDistanceKm = 15.0, // Increased default search radius
  }) {
    return allBarbers.where((barber) {
      // 1. Core availability checks (Online, Approved, Complete Profile)
      if (!barber.isOnline || barber.status != 'approved' || !barber.isProfileComplete) {
        return false;
      }
      
      // 2. Schedule Check (Working hours + Days off)
      if (!barber.isWithinWorkingHours) {
        return false;
      }
      
      // 3. Distance calculation
      double distance = GeoUtils.calculateDistance(
        userLocation, 
        GeoPoint(barber.latitude, barber.longitude)
      );
      
      return distance <= maxDistanceKm;
    }).toList()
      ..sort((a, b) {
        // Smart Scoring: (Rating * 2) - (Distance_Penalty * 0.5)
        double distA = GeoUtils.calculateDistance(userLocation, GeoPoint(a.latitude, a.longitude));
        double distB = GeoUtils.calculateDistance(userLocation, GeoPoint(b.latitude, b.longitude));
        
        // Priority to online and highly rated nearby
        double scoreA = (a.rating * 2) - (distA * 0.5);
        double scoreB = (b.rating * 2) - (distB * 0.5);
        
        return scoreB.compareTo(scoreA); // Higher score first
      });
  }

  /// Suggests the absolute best match for the user
  Barber? getTopRecommendation(List<Barber> nearbyBarbers) {
    if (nearbyBarbers.isEmpty) return null;
    return nearbyBarbers.first;
  }
}
