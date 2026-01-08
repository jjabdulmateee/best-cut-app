import 'package:flutter/material.dart';
import '../../services/auth_service.dart';
import '../../data/user_data_provider.dart';
import '../../main.dart';

class BarberPendingScreen extends StatefulWidget {
  final BarberStatus status;
  final String? rejectionReason;

  const BarberPendingScreen({
    super.key,
    required this.status,
    this.rejectionReason,
  });

  @override
  State<BarberPendingScreen> createState() => _BarberPendingScreenState();
}

class _BarberPendingScreenState extends State<BarberPendingScreen> {
  final _authService = AuthService();
  bool _isRefreshing = false;
  late BarberStatus _currentStatus;
  String? _currentRejectionReason;

  @override
  void initState() {
    super.initState();
    _currentStatus = widget.status;
    _currentRejectionReason = widget.rejectionReason;
  }

  Future<void> _refreshStatus() async {
    setState(() => _isRefreshing = true);

    try {
      final user = _authService.currentUser;
      if (user != null) {
        final newStatus = await _authService.getBarberStatus(user.uid);
        final userData = await _authService.getUserData(user.uid);
        
        if (!mounted) return;

        if (newStatus == BarberStatus.approved) {
          // Status changed to approved - navigate to barber app
          await UserDataProvider().initialize();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.white),
                    SizedBox(width: 8),
                    Text('Your account has been approved!'),
                  ],
                ),
                backgroundColor: Color(0xFF00AA5B),
              ),
            );
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const AuthWrapper()),
              (route) => false,
            );
          }
        } else {
          setState(() {
            _currentStatus = newStatus;
            _currentRejectionReason = userData?['rejectionReason'] as String?;
            _isRefreshing = false;
          });
          
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  newStatus == BarberStatus.pending 
                      ? 'Still pending approval...' 
                      : 'Status: ${newStatus.displayName}',
                ),
                duration: const Duration(seconds: 2),
              ),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isRefreshing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to refresh status. Try again.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _handleSignOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Sign Out'),
        content: const Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sign Out', style: TextStyle(color: Color(0xFF1A1A1A))),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      UserDataProvider().clear();
      await _authService.signOut();
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const AuthWrapper()),
          (route) => false,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refreshStatus,
          color: const Color(0xFF1A1A1A),
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: SizedBox(
                height: MediaQuery.of(context).size.height - 
                        MediaQuery.of(context).padding.top - 
                        MediaQuery.of(context).padding.bottom - 48,
                child: Column(
                  children: [
                    const Spacer(),
                    // Status Icon
                    Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        color: _getStatusColor().withOpacity(0.1),
                        borderRadius: BorderRadius.circular(30),
                      ),
                      child: _isRefreshing
                          ? Center(
                              child: CircularProgressIndicator(
                                color: _getStatusColor(),
                                strokeWidth: 3,
                              ),
                            )
                          : Icon(
                              _getStatusIcon(),
                              size: 60,
                              color: _getStatusColor(),
                            ),
                    ),
                    const SizedBox(height: 32),
                    // Status Title
                    Text(
                      _currentStatus.displayName,
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        color: _getStatusColor(),
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Status Description
                    Text(
                      _currentStatus.description,
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey[600],
                        height: 1.5,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    if (_currentStatus == BarberStatus.rejected && 
                        _currentRejectionReason != null) ...[
                      const SizedBox(height: 24),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.red[50],
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.red[200]!),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.info_outline, color: Colors.red[700], size: 20),
                                const SizedBox(width: 8),
                                Text(
                                  'Rejection Reason',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.red[700],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _currentRejectionReason!,
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.red[700],
                                height: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 32),
                    // Info cards for pending status
                    if (_currentStatus == BarberStatus.pending) ...[
                      const _InfoCard(
                        icon: Icons.schedule,
                        title: 'Review Time',
                        subtitle: 'Usually within 24-48 hours',
                      ),
                      const SizedBox(height: 12),
                      const _InfoCard(
                        icon: Icons.notifications_active,
                        title: 'We\'ll Notify You',
                        subtitle: 'Check your email for updates',
                      ),
                      const SizedBox(height: 12),
                      const _InfoCard(
                        icon: Icons.support_agent,
                        title: 'Need Help?',
                        subtitle: 'Contact support@bestcut.pk',
                      ),
                    ],
                    // Re-apply option for rejected
                    if (_currentStatus == BarberStatus.rejected) ...[
                      const _InfoCard(
                        icon: Icons.restart_alt,
                        title: 'Want to Re-apply?',
                        subtitle: 'Contact support to discuss your application',
                      ),
                    ],
                    const Spacer(),
                    // Refresh button
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: ElevatedButton.icon(
                        onPressed: _isRefreshing ? null : _refreshStatus,
                        icon: _isRefreshing
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.refresh),
                        label: Text(
                          _isRefreshing ? 'Checking...' : 'Check Status',
                          style: const TextStyle(
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
                    // Sign Out button
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: OutlinedButton.icon(
                        onPressed: _handleSignOut,
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
                    const SizedBox(height: 16),
                    // Pull to refresh hint
                    Text(
                      'Pull down to refresh',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[500],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Color _getStatusColor() {
    switch (_currentStatus) {
      case BarberStatus.pending:
        return Colors.orange;
      case BarberStatus.approved:
        return Colors.green;
      case BarberStatus.rejected:
        return Colors.red;
    }
  }

  IconData _getStatusIcon() {
    switch (_currentStatus) {
      case BarberStatus.pending:
        return Icons.hourglass_empty;
      case BarberStatus.approved:
        return Icons.check_circle;
      case BarberStatus.rejected:
        return Icons.cancel;
    }
  }
}

class _InfoCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _InfoCard({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F5F5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icon,
              color: const Color(0xFF1A1A1A),
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1A1A1A),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
