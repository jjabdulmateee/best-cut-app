import 'package:geolocator/geolocator.dart';
import 'map_service.dart';
import 'package:flutter/material.dart';

class LocationService {
  static final LocationService _instance = LocationService._internal();
  factory LocationService() => _instance;
  LocationService._internal();

  /// Get current device location
  Future<GeoPoint?> getCurrentLocation() async {
    bool serviceEnabled;
    LocationPermission permission;

    // Test if location services are enabled.
    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return null;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return null;
      }
    }
    
    if (permission == LocationPermission.deniedForever) {
      return null;
    } 

    try {
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high
      );
      return GeoPoint(position.latitude, position.longitude);
    } catch (e) {
      // Fallback for web or errors: Lahore center
      return const GeoPoint(31.5204, 74.3587);
    }
  }
}

/// Mock Map Provider - The "Uber-style" grid placeholder
class MockMapProvider implements MapService {
  @override
  Widget buildMap({
    required GeoPoint userLocation,
    required List<BarberMarker> markers,
    required Function(String barberId) onMarkerTap,
  }) {
    return Container(
      color: const Color(0xFFF0F0F0),
      child: Stack(
        children: [
          // Simulated Map Grid Lines
          CustomPaint(
            size: Size.infinite,
            painter: MapGridPainter(),
          ),
          
          // User Location Pin (Center)
          const Center(
            child: Icon(
              Icons.my_location,
              color: Colors.blue,
              size: 30,
            ),
          ),
          
          // Barber Markers (Simulated scattered around user)
          ...markers.map((m) => _buildMarker(m, userLocation, onMarkerTap)),
        ],
      ),
    );
  }

  Widget _buildMarker(BarberMarker marker, GeoPoint userLoc, Function(String) onTap) {
    // Math to position markers relative to center in the mock UI
    // In a real map, the provider handles this automatically
    double latDiff = (marker.position.latitude - userLoc.latitude) * 5000;
    double lngDiff = (marker.position.longitude - userLoc.longitude) * 5000;

    return Positioned(
      left: 200 + lngDiff, // Simple offset logic for visual mock
      top: 300 - latDiff,
      child: GestureDetector(
        onTap: () => onTap(marker.id),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(4),
                boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4)],
              ),
              child: Text(
                marker.title,
                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
              ),
            ),
            const Icon(Icons.location_on, color: Color(0xFF1A1A1A), size: 30),
          ],
        ),
      ),
    );
  }
}

class MapGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.grey.withOpacity(0.2)
      ..strokeWidth = 1.0;

    for (double i = 0; i < size.width; i += 40) {
      canvas.drawLine(Offset(i, 0), Offset(i, size.height), paint);
    }
    for (double i = 0; i < size.height; i += 40) {
      canvas.drawLine(Offset(0, i), Offset(size.width, i), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

