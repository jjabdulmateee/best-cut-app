import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/user_data_provider.dart';
import '../../services/firestore_service.dart';
import '../../models/barber.dart';
import '../../services/auth_service.dart';

class BarberDashboardScreen extends StatefulWidget {
  const BarberDashboardScreen({super.key});

  @override
  State<BarberDashboardScreen> createState() => _BarberDashboardScreenState();
}

class _BarberDashboardScreenState extends State<BarberDashboardScreen> {
  final FirestoreService _firestore = FirestoreService();

  void _toggleOnline(bool value, Barber barber) async {
    // 1. Enforce Profile Completeness
    if (value && !barber.isProfileComplete) {
      _showIncompleteProfileDialog();
      return;
    }

    // 2. Toggle Status
    await _firestore.updateBarberAvailability(barber.id, value);
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(value ? 'You are now Online' : 'You are now Offline'),
          backgroundColor: value ? Colors.green : Colors.grey[800],
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _showIncompleteProfileDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Profile Incomplete'),
        content: const Text(
          'Please upload a profile picture and complete your details before going online.'
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              // TODO: Navigate to Edit Profile
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.black),
            child: const Text('Complete Now', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final userDataProvider = Provider.of<UserDataProvider>(context);
    final barber = userDataProvider.barberData;

    if (barber == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Dashboard',
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
        actions: [
          Row(
            children: [
              Text(
                barber.isOnline ? 'Online' : 'Offline',
                style: TextStyle(
                  color: barber.isOnline ? Colors.green : Colors.grey,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Switch(
                value: barber.isOnline,
                onChanged: (val) => _toggleOnline(val, barber),
                activeColor: Colors.green,
              ),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => userDataProvider.refreshUserData(),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Welcome Card
              _buildWelcomeCard(barber),
              const SizedBox(height: 24),
              
              // Today's Stats
              const Text(
                'Today\'s Summary',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(child: _buildStatCard('Bookings', '0', Icons.event_available, Colors.blue)),
                  const SizedBox(width: 16),
                  Expanded(child: _buildStatCard('Earnings', 'Rs.0', Icons.payments, Colors.green)),
                ],
              ),
              
              const SizedBox(height: 24),
              
              // Profile Status Warning
              if (!barber.isProfileComplete)
                _buildWarningCard(),

              const SizedBox(height: 24),

              // Quick Actions
              const Text(
                'Quick Actions',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              _buildActionTile(
                Icons.schedule, 
                'Manage Schedule', 
                'Set your working hours and days off',
                () {}
              ),
              _buildActionTile(
                Icons.photo_library, 
                'Shop Gallery', 
                'Upload photos of your work and salon',
                () {}
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWelcomeCard(Barber barber) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 30,
            backgroundImage: NetworkImage(barber.imageUrl),
            backgroundColor: Colors.grey[800],
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Welcome, ${barber.name}',
                  style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                ),
                Text(
                  barber.status == 'approved' ? 'Professional Barber' : 'Pending Approval',
                  style: TextStyle(color: Colors.grey[400], fontSize: 14),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 12),
          Text(
            value,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          Text(
            title,
            style: TextStyle(color: Colors.grey[600], fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildWarningCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.amber[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber[200]!),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: Colors.amber),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Complete your profile to appear in search results.',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            ),
          ),
          TextButton(
            onPressed: () {},
            child: const Text('Complete'),
          ),
        ],
      ),
    );
  }

  Widget _buildActionTile(IconData icon, String title, String subtitle, VoidCallback onTap) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[100]!),
      ),
      child: ListTile(
        onTap: onTap,
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.grey[50],
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: Colors.black),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(subtitle, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
        trailing: const Icon(Icons.chevron_right, size: 20),
      ),
    );
  }
}

