import 'package:flutter/material.dart';
import '../../models/slot.dart';
import '../../data/user_data_provider.dart';

enum BookingListType { pending, upcoming, completed, cancelled }

class BarberBookingsScreen extends StatefulWidget {
  const BarberBookingsScreen({super.key});

  @override
  State<BarberBookingsScreen> createState() => _BarberBookingsScreenState();
}

class _BarberBookingsScreenState extends State<BarberBookingsScreen> with TickerProviderStateMixin {
  late TabController _tabController;
  final UserDataProvider _userDataProvider = UserDataProvider();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _userDataProvider.addListener(_onDataChanged);
  }

  void _onDataChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _userDataProvider.removeListener(_onDataChanged);
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Bookings'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Pending'),
            Tab(text: 'Upcoming'),
            Tab(text: 'Completed'),
            Tab(text: 'Cancelled'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildBookingList(_userDataProvider.pendingBookingRequests, BookingListType.pending),
          _buildBookingList(_userDataProvider.upcomingBookings, BookingListType.upcoming),
          _buildBookingList(_userDataProvider.completedBookings, BookingListType.completed),
          _buildBookingList(_userDataProvider.cancelledBookings, BookingListType.cancelled),
        ],
      ),
    );
  }

  Widget _buildBookingList(List<Booking> bookings, BookingListType type) {
    if (bookings.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              type == BookingListType.pending ? Icons.pending : Icons.calendar_today,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              'No ${type.name} bookings',
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: bookings.length,
      itemBuilder: (context, index) {
        return _buildBookingCard(bookings[index], type);
      },
    );
  }

  Widget _buildBookingCard(Booking booking, BookingListType type) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: type == BookingListType.pending
            ? Border.all(color: Colors.orange.withValues(alpha: 0.5), width: 2)
            : null,
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
          // Header with customer info
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text('${booking.customerName ?? 'Customer'} - ${booking.shortDate}'),
          ),

          // Footer with price and actions
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text('PKR ${booking.pricePKR}'),
          ),
        ],
      ),
    );
  }

  Color _getRatingColor(double rating) {
    if (rating >= 4.5) return Colors.green;
    if (rating >= 4.0) return Colors.lightGreen;
    if (rating >= 3.5) return Colors.yellow;
    if (rating >= 3.0) return Colors.orange;
    return Colors.red;
  }

  Widget _buildStatusBadge(BookingStatus status) {
    Color color;
    String text;

    switch (status) {
      case BookingStatus.pending:
        color = Colors.orange;
        text = 'Requested';
        break;
      case BookingStatus.confirmed:
        color = Colors.blue;
        text = 'Accepted';
        break;
      case BookingStatus.inProgress:
        color = const Color(0xFF00C853);
        text = 'In Progress';
        break;
      case BookingStatus.completed:
        color = Colors.green;
        text = 'Completed';
        break;
      case BookingStatus.rejected:
        color = Colors.red;
        text = 'Rejected';
        break;
      case BookingStatus.cancelledByCustomer:
        color = Colors.red;
        text = 'Cancelled by Customer';
        break;
      case BookingStatus.cancelledByBarber:
        color = Colors.red;
        text = 'Cancelled by Barber';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}