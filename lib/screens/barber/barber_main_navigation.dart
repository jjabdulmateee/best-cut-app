import 'package:flutter/material.dart';
import 'barber_dashboard_screen.dart';
import 'barber_bookings_screen.dart';
import 'barber_earnings_screen.dart';
import 'barber_profile_screen.dart';
import 'service_management_screen.dart';

class BarberMainNavigation extends StatefulWidget {
  const BarberMainNavigation({super.key});

  @override
  State<BarberMainNavigation> createState() => _BarberMainNavigationState();
}

class _BarberMainNavigationState extends State<BarberMainNavigation> {
  int _currentIndex = 0;

  final List<Widget> _screens = [
    const BarberDashboardScreen(),
    const ServiceManagementScreen(),
    const BarberBookingsScreen(),
    const BarberEarningsScreen(),
    const BarberProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildNavItem(0, Icons.dashboard_outlined, Icons.dashboard, 'Home'),
                _buildNavItem(1, Icons.content_cut_outlined, Icons.content_cut, 'Services'),
                _buildNavItem(2, Icons.calendar_today_outlined, Icons.calendar_today, 'Bookings'),
                _buildNavItem(3, Icons.account_balance_wallet_outlined, Icons.account_balance_wallet, 'Earnings'),
                _buildNavItem(4, Icons.person_outline, Icons.person, 'Profile'),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, IconData activeIcon, String label) {
    final isSelected = _currentIndex == index;
    return GestureDetector(
      onTap: () {
        setState(() {
          _currentIndex = index;
        });
      },
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF1A1A1A).withOpacity(0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isSelected ? activeIcon : icon,
              color: isSelected ? const Color(0xFF1A1A1A) : Colors.grey[600],
              size: 24,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                color: isSelected ? const Color(0xFF1A1A1A) : Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

