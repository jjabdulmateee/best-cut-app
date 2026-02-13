import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/slot.dart';
import '../services/booking_engine_service.dart';
import 'booking_details_screen.dart';
import 'reroute_options_sheet.dart';

// ============================================================================
// BOOKING HISTORY SCREEN — Phase 1 Booking Engine
// ============================================================================
//
// Displays customer bookings from Firestore (real-time stream).
// Bookings are split into Upcoming and Past tabs.
// Tapping a booking opens BookingDetailsScreen with engine actions.
// ============================================================================

class BookingHistoryScreen extends StatefulWidget {
  const BookingHistoryScreen({super.key});

  @override
  State<BookingHistoryScreen> createState() => _BookingHistoryScreenState();
}

class _BookingHistoryScreenState extends State<BookingHistoryScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final BookingEngineService _engine = BookingEngineService();
  final String? _userId = FirebaseAuth.instance.currentUser?.uid;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_userId == null) {
      return const Scaffold(
        body: Center(child: Text('Please sign in to view bookings')),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'My Bookings',
          style: TextStyle(
            color: Color(0xFF1A1A1A),
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
        centerTitle: true,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: const Color(0xFFF5F5F5),
              borderRadius: BorderRadius.circular(10),
            ),
            child: TabBar(
              controller: _tabController,
              indicator: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(8),
              ),
              labelColor: Colors.white,
              unselectedLabelColor: Colors.grey[600],
              labelStyle: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
              unselectedLabelStyle: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
              dividerColor: Colors.transparent,
              indicatorSize: TabBarIndicatorSize.tab,
              padding: const EdgeInsets.all(4),
              tabs: const [
                Tab(text: 'Upcoming'),
                Tab(text: 'Past'),
              ],
            ),
          ),
        ),
      ),
      body: StreamBuilder<List<Booking>>(
        stream: _engine.streamCustomerBookings(_userId!),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(40),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.error_outline, size: 48, color: Colors.grey[400]),
                    const SizedBox(height: 16),
                    Text(
                      'Could not load bookings',
                      style: TextStyle(color: Colors.grey[600], fontSize: 16),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${snapshot.error}',
                      style: TextStyle(color: Colors.grey[400], fontSize: 12),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            );
          }

          final allBookings = snapshot.data ?? [];
          final now = DateTime.now();

          final upcoming = allBookings
              .where((b) =>
                  b.status.isActive &&
                  b.bookingDateTime.isAfter(now))
              .toList();

          final past = allBookings
              .where((b) =>
                  b.status.isTerminal ||
                  (b.status.isActive && b.bookingDateTime.isBefore(now)))
              .toList();

          return TabBarView(
            controller: _tabController,
            children: [
              _buildBookingsList(upcoming, isUpcoming: true),
              _buildBookingsList(past, isUpcoming: false),
            ],
          );
        },
      ),
    );
  }

  Widget _buildBookingsList(List<Booking> bookings, {required bool isUpcoming}) {
    if (bookings.isEmpty) {
      return _buildEmptyState(isUpcoming);
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: bookings.length,
      itemBuilder: (context, index) {
        return _buildBookingCard(bookings[index]);
      },
    );
  }

  Widget _buildBookingCard(Booking booking) {
    final cancellationPolicy = _engine.getCancellationPolicy(booking);
    final reschedulePolicy = _engine.getReschedulePolicy(booking);
    final isActive = booking.status.isActive;

    return GestureDetector(
      onTap: () => _navigateToDetails(booking),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  // Barber avatar
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      color: Colors.grey[200],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Image.network(
                        booking.barberImageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) {
                          return Icon(Icons.person,
                              color: Colors.grey[400], size: 30);
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  // Booking info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          booking.barberName,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1A1A1A),
                          ),
                        ),
                        if (booking.shopName != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            booking.shopName!,
                            style: TextStyle(
                                fontSize: 13, color: Colors.grey[600]),
                          ),
                        ],
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Icon(Icons.calendar_today_outlined,
                                size: 14, color: Colors.grey[500]),
                            const SizedBox(width: 4),
                            Text(
                              booking.shortDate,
                              style: TextStyle(
                                  fontSize: 12, color: Colors.grey[600]),
                            ),
                            const SizedBox(width: 12),
                            Icon(Icons.access_time,
                                size: 14, color: Colors.grey[500]),
                            const SizedBox(width: 4),
                            Text(
                              booking.timeSlot,
                              style: TextStyle(
                                  fontSize: 12, color: Colors.grey[600]),
                            ),
                          ],
                        ),
                        // Services count
                        if (booking.selectedServices.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            '${booking.selectedServices.length} service(s)',
                            style: TextStyle(
                                fontSize: 11, color: Colors.grey[500]),
                          ),
                        ],
                      ],
                    ),
                  ),
                  // Price & status
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        booking.formattedPrice,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1A1A1A),
                        ),
                      ),
                      const SizedBox(height: 6),
                      _buildStatusBadge(booking.status),
                      // Reschedule/switch badges
                      if (booking.rescheduleCount > 0) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Rescheduled ${booking.rescheduleCount}x',
                          style: TextStyle(
                              fontSize: 10, color: Colors.blue[600]),
                        ),
                      ],
                      if (booking.barberSwitched) ...[
                        const SizedBox(height: 2),
                        Text(
                          'Barber switched',
                          style: TextStyle(
                              fontSize: 10, color: Colors.orange[600]),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            // Phase 4: Expired assignment alert on card
            if (booking.needsRerouteDecision) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.08),
                  border: Border(
                    top: BorderSide(color: Colors.orange.withValues(alpha: 0.2)),
                  ),
                ),
                child: GestureDetector(
                  onTap: () => showRerouteOptionsSheet(context, booking),
                  child: const Row(
                    children: [
                      Icon(Icons.timer_off, color: Colors.orange, size: 16),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Barber didn\'t respond — Tap to choose next step',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.orange,
                          ),
                        ),
                      ),
                      Icon(Icons.arrow_forward_ios, color: Colors.orange, size: 12),
                    ],
                  ),
                ),
              ),
            ],
            // Quick action bar
            if (isActive && booking.bookingDateTime.isAfter(DateTime.now()) && !booking.needsRerouteDecision) ...[
              Container(height: 1, color: const Color(0xFFF0F0F0)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  children: [
                    // Cancel
                    if (cancellationPolicy.allowed)
                      Expanded(
                        child: TextButton.icon(
                          onPressed: () => _navigateToDetails(booking),
                          icon: const Icon(Icons.cancel_outlined, size: 16),
                          label: const Text('Cancel', style: TextStyle(fontSize: 13)),
                          style: TextButton.styleFrom(
                              foregroundColor: const Color(0xFFFF4444)),
                        ),
                      ),
                    // Reschedule
                    if (reschedulePolicy.allowed)
                      Expanded(
                        child: TextButton.icon(
                          onPressed: () => _navigateToDetails(booking),
                          icon: const Icon(Icons.replay, size: 16),
                          label: const Text('Reschedule', style: TextStyle(fontSize: 13)),
                          style: TextButton.styleFrom(
                              foregroundColor: const Color(0xFF276EF1)),
                        ),
                      ),
                    // View Details
                    Expanded(
                      child: TextButton.icon(
                        onPressed: () => _navigateToDetails(booking),
                        icon: const Icon(Icons.visibility_outlined, size: 16),
                        label: const Text('Details', style: TextStyle(fontSize: 13)),
                        style: TextButton.styleFrom(
                            foregroundColor: const Color(0xFF1A1A1A)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBadge(BookingStatus status) {
    Color bgColor;
    Color textColor;

    switch (status) {
      case BookingStatus.pending:
        bgColor = Colors.orange.withValues(alpha: 0.1);
        textColor = Colors.orange;
        break;
      case BookingStatus.confirmed:
        bgColor = const Color(0xFF00AA5B).withValues(alpha: 0.1);
        textColor = const Color(0xFF00AA5B);
        break;
      case BookingStatus.inProgress:
        bgColor = const Color(0xFF2196F3).withValues(alpha: 0.1);
        textColor = const Color(0xFF2196F3);
        break;
      case BookingStatus.completed:
        bgColor = const Color(0xFF276EF1).withValues(alpha: 0.1);
        textColor = const Color(0xFF276EF1);
        break;
      case BookingStatus.rejected:
        bgColor = const Color(0xFFFF4444).withValues(alpha: 0.1);
        textColor = const Color(0xFFFF4444);
        break;
      case BookingStatus.cancelledByCustomer:
      case BookingStatus.cancelledByBarber:
        bgColor = const Color(0xFFFF4444).withValues(alpha: 0.1);
        textColor = const Color(0xFFFF4444);
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        status.displayName,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: textColor,
        ),
      ),
    );
  }

  Widget _buildEmptyState(bool isUpcoming) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: const BoxDecoration(
                color: Color(0xFFF5F5F5),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isUpcoming ? Icons.calendar_today_outlined : Icons.history,
                color: Colors.grey[400],
                size: 44,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              isUpcoming ? 'No upcoming bookings' : 'No past bookings',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1A1A1A),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              isUpcoming
                  ? 'Book a haircut and it will appear here'
                  : 'Your booking history will appear here',
              style: TextStyle(fontSize: 14, color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
            if (isUpcoming) ...[
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () {
                  // Navigate to home tab (pop to first for now)
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1A1A1A),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                child: const Text(
                  'Find a Barber',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _navigateToDetails(Booking booking) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => BookingDetailsScreen(booking: booking),
      ),
    );
  }
}
