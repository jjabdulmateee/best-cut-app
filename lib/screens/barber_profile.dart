import 'package:flutter/material.dart';
import '../models/barber.dart';
import '../services/map_service.dart';
import '../services/location_service.dart';
import 'booking_screen.dart';

class BarberProfileScreen extends StatelessWidget {
  final Barber barber;

  const BarberProfileScreen({super.key, required this.barber});

  @override
  Widget build(BuildContext context) {
    // Simulated Distance & Travel Time (In real app, we fetch user location again)
    const mockUserLoc = GeoPoint(31.5204, 74.3587); // Center Lahore
    final barberLoc = GeoPoint(barber.latitude, barber.longitude);
    final distance = GeoUtils.calculateDistance(mockUserLoc, barberLoc);
    final travelTime = GeoUtils.estimateTravelTime(distance);

    return Scaffold(
      backgroundColor: Colors.white,
      body: CustomScrollView(
        slivers: [
          // 1. UBER-STYLE HEADER (Profile & Shop Info)
          SliverAppBar(
            expandedHeight: 300,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  // Main Profile Image or Shop Image
                  Image.network(
                    barber.imageUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => Container(color: Colors.grey[200]),
                  ),
                  // Gradient Overlay
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withOpacity(0.7),
                        ],
                      ),
                    ),
                  ),
                  // Profile Info
                  Positioned(
                    bottom: 20,
                    left: 20,
                    right: 20,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          barber.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (barber.shopName != null)
                          Text(
                            barber.shopName!,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.9),
                              fontSize: 16,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 2. QUICK STATS BAR
          SliverToBoxAdapter(
            child: _buildQuickStats(distance, travelTime),
          ),

          // 3. ABOUT SECTION
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'About',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    barber.bio ?? 'Professional barber dedicated to providing the best haircuts in town.',
                    style: TextStyle(color: Colors.grey[700], height: 1.5),
                  ),
                ],
              ),
            ),
          ),

          // 4. GALLERY (Uber Style Grid)
          if (barber.galleryUrls.isNotEmpty)
            SliverToBoxAdapter(
              child: _buildGallery(),
            ),

          // 5. SCHEDULE & LOCATION
          SliverToBoxAdapter(
            child: _buildScheduleSection(),
          ),

          // Padding for bottom button
          const SliverToBoxAdapter(child: SizedBox(height: 100)),
        ],
      ),
      bottomSheet: _buildBookingAction(context),
    );
  }

  Widget _buildQuickStats(double dist, int time) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 10),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.grey[100]!)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _statItem(Icons.star, barber.rating.toString(), 'Rating'),
          _statItem(Icons.access_time, '$time min', 'Travel time'),
          _statItem(Icons.location_on_outlined, GeoUtils.formatDistance(dist), 'Distance'),
        ],
      ),
    );
  }

  Widget _statItem(IconData icon, String value, String label) {
    return Column(
      children: [
        Icon(icon, color: Colors.black, size: 24),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        Text(
          label,
          style: TextStyle(color: Colors.grey[500], fontSize: 12),
        ),
      ],
    );
  }

  Widget _buildGallery() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          child: Text(
            'Gallery',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ),
        SizedBox(
          height: 120,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: barber.galleryUrls.length,
            itemBuilder: (context, index) {
              return Container(
                width: 120,
                margin: const EdgeInsets.only(right: 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  image: DecorationImage(
                    image: NetworkImage(barber.galleryUrls[index]),
                    fit: BoxFit.cover,
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildScheduleSection() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Working Hours',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.calendar_today_outlined, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Daily: ${barber.workStartHour} - ${barber.workEndHour}',
                    style: const TextStyle(fontSize: 15),
                  ),
                ),
                if (!barber.isWithinWorkingHours)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.red[50],
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'Closed',
                      style: TextStyle(color: Colors.red, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBookingAction(BuildContext context) {
    final isBookable = barber.isBookable;
    final status = barber.availabilityStatus;
    
    String buttonText;
    Color buttonColor;
    
    if (isBookable) {
      buttonText = 'Book Now • ${barber.formattedPrice}';
      buttonColor = const Color(0xFF1A1A1A);
    } else {
      switch (status) {
        case BarberAvailabilityStatus.offline:
          buttonText = 'Offline - Schedule for Later';
          buttonColor = Colors.grey[700]!;
          break;
        case BarberAvailabilityStatus.closed:
          buttonText = 'Closed - Schedule for Later';
          buttonColor = Colors.grey[700]!;
          break;
        case BarberAvailabilityStatus.dayOff:
          buttonText = 'Day Off - Schedule for Later';
          buttonColor = Colors.grey[700]!;
          break;
        default:
          buttonText = 'View Available Slots';
          buttonColor = Colors.grey[700]!;
      }
    }
    
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Status indicator
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: barber.statusColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: barber.statusColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    barber.statusText,
                    style: TextStyle(
                      color: barber.statusColor,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '•',
                    style: TextStyle(color: barber.statusColor),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    barber.formattedWorkingHours,
                    style: TextStyle(
                      color: barber.statusColor,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => BookingScreen(barber: barber),
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: buttonColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  buttonText,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
