import 'dart:math' show cos, sqrt, asin;
import 'package:flutter/material.dart';

/// Represents a geographic point
class GeoPoint {
  final double latitude;
  final double longitude;

  const GeoPoint(this.latitude, this.longitude);

  Map<String, dynamic> toMap() => {
    'latitude': latitude,
    'longitude': longitude,
  };

  factory GeoPoint.fromMap(Map<String, dynamic> map) {
    return GeoPoint(
      (map['latitude'] as num).toDouble(),
      (map['longitude'] as num).toDouble(),
    );
  }
}

/// Utility for real geographic calculations (Haversine Formula)
class GeoUtils {
  /// Calculates distance between two points in kilometers
  static double calculateDistance(GeoPoint p1, GeoPoint p2) {
    var p = 0.017453292519943295; // Math.PI / 180
    var c = cos;
    var a = 0.5 - c((p2.latitude - p1.latitude) * p) / 2 +
        c(p1.latitude * p) * c(p2.latitude * p) *
            (1 - c((p2.longitude - p1.longitude) * p)) / 2;
    return 12742 * asin(sqrt(a)); // 2 * R; R = 6371 km
  }

  /// Formats distance for display
  static String formatDistance(double km) {
    if (km < 1) {
      return '${(km * 1000).round()}m';
    }
    return '${km.toStringAsFixed(1)}km';
  }

  /// Estimates travel time in minutes based on distance
  /// Simple Uber-like estimation: ~2-3 mins per km in city
  static int estimateTravelTime(double km) {
    if (km < 0.5) return 5; // Minimum time
    return (km * 3 + 5).round(); // 3 mins per km + 5 mins base
  }
}

/// Abstract Map Service - PLUG AND PLAY ARCHITECTURE
/// Any map provider (Google, Apple, Mapbox) must implement this.
abstract class MapService {
  Widget buildMap({
    required GeoPoint userLocation,
    required List<BarberMarker> markers,
    required Function(String barberId) onMarkerTap,
  });
}

/// Represents a marker on the map
class BarberMarker {
  final String id;
  final GeoPoint position;
  final String title;
  final bool isOnline; // For showing different marker colors

  const BarberMarker({
    required this.id,
    required this.position,
    required this.title,
    this.isOnline = false,
  });
}

