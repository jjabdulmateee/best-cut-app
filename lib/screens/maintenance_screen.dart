import 'package:flutter/material.dart';
import '../data/user_data_provider.dart';

/// Maintenance Screen - Shows when system is frozen or account is disabled
class MaintenanceScreen extends StatefulWidget {
  final bool isSystemFrozen;
  final bool isAccountDisabled;
  final String? freezeReason;
  final String? disableReason;

  const MaintenanceScreen({
    super.key,
    required this.isSystemFrozen,
    required this.isAccountDisabled,
    this.freezeReason,
    this.disableReason,
  });

  @override
  State<MaintenanceScreen> createState() => _MaintenanceScreenState();
}

class _MaintenanceScreenState extends State<MaintenanceScreen> {
  final _userDataProvider = UserDataProvider();

  @override
  Widget build(BuildContext context) {
    final isSystemFrozen = widget.isSystemFrozen;
    final isAccountDisabled = widget.isAccountDisabled;

    String title;
    String message;
    String subtitle;
    IconData icon;
    Color iconColor;

    if (isSystemFrozen) {
      title = 'System Maintenance';
      message = widget.freezeReason ?? 'The system is currently under maintenance';
      subtitle = 'Please check back later. We apologize for any inconvenience.';
      icon = Icons.build;
      iconColor = Colors.orange;
    } else if (isAccountDisabled) {
      title = 'Account Disabled';
      message = widget.disableReason ?? 'Your account has been disabled';
      subtitle = 'Please contact support for more information.';
      icon = Icons.account_circle;
      iconColor = Colors.red;
    } else {
      // Fallback
      title = 'Service Unavailable';
      message = 'Service is temporarily unavailable';
      subtitle = 'Please try again later.';
      icon = Icons.error_outline;
      iconColor = Colors.grey;
    }

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Spacer(),
              // Icon
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(30),
                ),
                child: Icon(
                  icon,
                  size: 60,
                  color: iconColor,
                ),
              ),
              const SizedBox(height: 32),
              // Title
              Text(
                title,
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: iconColor,
                  letterSpacing: -0.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              // Message
              Text(
                message,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1A1A1A),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              // Subtitle
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey[600],
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),

              // Admin Protection Notice
              if (isSystemFrozen) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE3F2FD),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: const Color(0xFF2196F3).withOpacity(0.3),
                    ),
                  ),
                  child: Column(
                    children: [
                      const Row(
                        children: [
                          Icon(
                            Icons.security,
                            color: Color(0xFF2196F3),
                            size: 20,
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Admin Protected',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF2196F3),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'This temporary pause is part of Best Cut\'s safety measures. Your bookings and payments are fully protected.',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey[700],
                          height: 1.4,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
              const SizedBox(height: 40),
              // Action buttons
              if (isSystemFrozen) ...[
                // Refresh button for system freeze
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton.icon(
                    onPressed: _refreshSystemStatus,
                    icon: const Icon(Icons.refresh),
                    label: const Text(
                      'Check Status',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1A1A1A),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ] else if (isAccountDisabled) ...[
                // Contact support button for disabled accounts
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton.icon(
                    onPressed: _contactSupport,
                    icon: const Icon(Icons.support_agent),
                    label: const Text(
                      'Contact Support',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1A1A1A),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                // Sign out button
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: OutlinedButton.icon(
                    onPressed: _signOut,
                    icon: const Icon(Icons.logout),
                    label: const Text(
                      'Sign Out',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF1A1A1A),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      side: const BorderSide(
                        color: Color(0xFF1A1A1A),
                        width: 1.5,
                      ),
                    ),
                  ),
                ),
              ],
              const Spacer(),
              // Footer
              Text(
                'Best Cut',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[500],
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _refreshSystemStatus() async {
    // This will trigger the system monitor to refresh and potentially update the UI
    setState(() {});
  }

  void _contactSupport() {
    // TODO: Implement contact support functionality
    // Could open email, phone, or chat support
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Please contact support@bestcut.pk'),
        duration: Duration(seconds: 3),
      ),
    );
  }

  Future<void> _signOut() async {
    await _userDataProvider.signOut();
    // Navigation will be handled by the AuthWrapper
  }
}