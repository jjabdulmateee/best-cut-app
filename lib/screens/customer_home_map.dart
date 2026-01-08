import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/barber.dart';
import '../services/firestore_service.dart';
import '../services/map_service.dart';
import '../services/location_service.dart';
import '../services/smart_agent_service.dart';
import '../widgets/barber_card.dart';
import 'barber_profile.dart';

class CustomerHomeMapScreen extends StatefulWidget {
  const CustomerHomeMapScreen({super.key});

  @override
  State<CustomerHomeMapScreen> createState() => _CustomerHomeMapScreenState();
}

class _CustomerHomeMapScreenState extends State<CustomerHomeMapScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  final SmartAgentService _agent = SmartAgentService();
  final MapService _mapProvider = MockMapProvider(); // Swap with GoogleMapProvider later
  
  GeoPoint? _userLocation;
  bool _isLoadingLocation = true;

  @override
  void initState() {
    super.initState();
    _initLocation();
  }

  Future<void> _initLocation() async {
    final loc = await LocationService().getCurrentLocation();
    if (mounted) {
      setState(() {
        _userLocation = loc;
        _isLoadingLocation = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingLocation) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // Default to Lahore if location fails
    final currentLoc = _userLocation ?? const GeoPoint(31.5204, 74.3587);

    return Scaffold(
      body: Stack(
        children: [
          // 1. THE MAP LAYER (Plug & Play Architecture)
          StreamBuilder<List<Barber>>(
            stream: _firestoreService.streamApprovedBarbers(),
            builder: (context, snapshot) {
              final barbers = snapshot.data ?? [];
              final markers = barbers.map((b) => BarberMarker(
                id: b.id,
                position: GeoPoint(b.latitude, b.longitude),
                title: b.name,
              )).toList();

              return _mapProvider.buildMap(
                userLocation: currentLoc,
                markers: markers,
                onMarkerTap: (id) {
                  final barber = barbers.firstWhere((b) => b.id == id);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => BarberProfileScreen(barber: barber)),
                  );
                },
              );
            },
          ),

          // 2. SEARCH BAR OVERLAY (Uber Style)
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  _buildSearchBar(),
                ],
              ),
            ),
          ),

          // 3. DRAGGABLE BOTTOM SHEET (The "Uber Experience")
          _buildDraggableSheet(currentLoc),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.search, color: Colors.black),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Search barbers or salons',
              style: TextStyle(color: Colors.grey, fontSize: 16),
            ),
          ),
          Container(
            height: 24,
            width: 1,
            color: Colors.grey[300],
            margin: const EdgeInsets.symmetric(horizontal: 12),
          ),
          const Icon(Icons.tune, color: Colors.black),
        ],
      ),
    );
  }

  Widget _buildDraggableSheet(GeoPoint userLoc) {
    return DraggableScrollableSheet(
      initialChildSize: 0.35,
      minChildSize: 0.15,
      maxChildSize: 0.9,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
            ),
            boxShadow: [
              BoxShadow(color: Colors.black12, blurRadius: 10, spreadRadius: 5),
            ],
          ),
          child: StreamBuilder<List<Barber>>(
            stream: _firestoreService.streamApprovedBarbers(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              // Use Smart Agent to find best nearby barbers
              final nearbyBarbers = _agent.findBestBarbers(
                allBarbers: snapshot.data ?? [],
                userLocation: userLoc,
              );

              if (nearbyBarbers.isEmpty) {
                return _buildNoBarbersState();
              }

              return ListView.builder(
                controller: scrollController,
                padding: const EdgeInsets.all(16),
                itemCount: nearbyBarbers.length + 1,
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return _buildSheetHeader(nearbyBarbers.length);
                  }
                  
                  final barber = nearbyBarbers[index - 1];
                  double dist = GeoUtils.calculateDistance(
                    userLoc, 
                    GeoPoint(barber.latitude, barber.longitude)
                  );

                  return BarberCard(
                    barber: barber,
                    distance: GeoUtils.formatDistance(dist),
                  );
                },
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildSheetHeader(int count) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Best Barbers Near You',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            Text(
              '$count found',
              style: TextStyle(color: Colors.grey[600], fontSize: 14),
            ),
          ],
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildNoBarbersState() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.location_off, size: 60, color: Colors.grey[300]),
        const SizedBox(height: 16),
        const Text(
          'No online barbers in your area',
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
        ),
        const SizedBox(height: 8),
        Text(
          'Try adjusting your search or filters',
          style: TextStyle(color: Colors.grey[600]),
        ),
      ],
    );
  }
}
