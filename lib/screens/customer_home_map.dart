import 'package:flutter/material.dart';
import '../models/barber.dart';
import '../services/firestore_service.dart';
import '../services/map_service.dart';
import '../services/location_service.dart';
import '../services/smart_agent_service.dart';
import '../widgets/barber_card.dart';
import 'barber_profile.dart';
import 'booking_screen.dart';

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
  int _selectedFilter = 0; // 0: All, 1: Online Only

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
          // 1. THE MAP LAYER - Shows ALL approved barber shops
          StreamBuilder<List<Barber>>(
            stream: _firestoreService.streamApprovedBarbers(),
            builder: (context, snapshot) {
              final barbers = snapshot.data ?? [];
              
              // Create markers for ALL shops (online, offline, closed)
              final markers = barbers.map((b) => BarberMarker(
                id: b.id,
                position: GeoPoint(b.latitude, b.longitude),
                title: b.shopName ?? b.name,
                isOnline: b.isBookable,
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
            color: Colors.black.withValues(alpha: 0.1),
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

              final allBarbers = snapshot.data ?? [];
              
              // Use Smart Agent to find best nearby barbers
              var nearbyBarbers = _agent.findBestBarbers(
                allBarbers: allBarbers,
                userLocation: userLoc,
              );

              // Apply filter
              if (_selectedFilter == 1) {
                nearbyBarbers = nearbyBarbers.where((b) => b.isBookable).toList();
              }

              return ListView.builder(
                controller: scrollController,
                padding: const EdgeInsets.all(16),
                itemCount: nearbyBarbers.length + 2, // +2 for header and filter
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return _buildSheetHeader(nearbyBarbers.length, allBarbers.length);
                  }
                  if (index == 1) {
                    return _buildFilterChips(allBarbers);
                  }
                  
                  if (nearbyBarbers.isEmpty) {
                    return _buildNoBarbersState();
                  }
                  
                  final barber = nearbyBarbers[index - 2];
                  double dist = GeoUtils.calculateDistance(
                    userLoc, 
                    GeoPoint(barber.latitude, barber.longitude)
                  );

                  return BarberCard(
                    barber: barber,
                    distance: GeoUtils.formatDistance(dist),
                    showBookButton: true,
                    onBook: barber.isBookable ? () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => BookingScreen(barber: barber),
                        ),
                      );
                    } : null,
                  );
                },
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildSheetHeader(int count, int totalCount) {
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
              'Barber Shops Near You',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            Text(
              '$count of $totalCount',
              style: TextStyle(color: Colors.grey[600], fontSize: 14),
            ),
          ],
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildFilterChips(List<Barber> allBarbers) {
    final onlineCount = allBarbers.where((b) => b.isBookable).length;
    
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _buildFilterChip('All Shops', 0, null),
            const SizedBox(width: 8),
            _buildFilterChip('Open Now', 1, onlineCount),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label, int index, int? count) {
    final isSelected = _selectedFilter == index;
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedFilter = index;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF1A1A1A) : Colors.grey[100],
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (index == 1)
              Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.only(right: 6),
                decoration: const BoxDecoration(
                  color: Color(0xFF00C853),
                  shape: BoxShape.circle,
                ),
              ),
            Text(
              count != null ? '$label ($count)' : label,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.black,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoBarbersState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            _selectedFilter == 1 ? Icons.schedule : Icons.location_off, 
            size: 60, 
            color: Colors.grey[300]
          ),
          const SizedBox(height: 16),
          Text(
            _selectedFilter == 1 
                ? 'No barbers available right now'
                : 'No barber shops in your area',
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
          ),
          const SizedBox(height: 8),
          Text(
            _selectedFilter == 1
                ? 'Try viewing all shops to schedule for later'
                : 'Try adjusting your search or filters',
            style: TextStyle(color: Colors.grey[600]),
            textAlign: TextAlign.center,
          ),
          if (_selectedFilter == 1) ...[
            const SizedBox(height: 16),
            TextButton(
              onPressed: () {
                setState(() {
                  _selectedFilter = 0;
                });
              },
              child: const Text('View All Shops'),
            ),
          ],
        ],
      ),
    );
  }
}
