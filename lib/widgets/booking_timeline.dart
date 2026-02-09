import 'package:flutter/material.dart';
import '../models/slot.dart';
import 'admin_override_indicator.dart';

/// Booking Timeline - Shows complete booking history with admin interventions
class BookingTimeline extends StatelessWidget {
  final Booking booking;
  final Map<String, bool> adminModifiedBookings;
  final Map<String, DateTime?> adminModifiedTimes;

  const BookingTimeline({
    super.key,
    required this.booking,
    required this.adminModifiedBookings,
    required this.adminModifiedTimes,
  });

  @override
  Widget build(BuildContext context) {
    final timelineItems = _buildTimelineItems();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Booking Timeline',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Color(0xFF1A1A1A),
          ),
        ),
        const SizedBox(height: 16),
        ...timelineItems,
      ],
    );
  }

  List<Widget> _buildTimelineItems() {
    final items = <Widget>[];

    // Booking Created
    items.add(_TimelineItem(
      icon: Icons.add_circle_outline,
      iconColor: const Color(0xFF4CAF50),
      title: 'Booking Created',
      subtitle: 'Booking request submitted',
      timestamp: booking.createdAt,
      isFirst: true,
    ));

    // Admin Override (if any)
    if (adminModifiedBookings[booking.id] == true) {
      items.add(_TimelineItem(
        icon: Icons.admin_panel_settings,
        iconColor: const Color(0xFF2196F3),
        title: 'Updated by Admin',
        subtitle: 'Administrator reviewed and modified this booking',
        timestamp: adminModifiedTimes[booking.id] ?? booking.createdAt,
        showAdminBadge: true,
      ));
    }

    // Booking Confirmed
    if (booking.status == BookingStatus.confirmed ||
        booking.status == BookingStatus.completed ||
        booking.status == BookingStatus.cancelledByCustomer ||
        booking.status == BookingStatus.cancelledByBarber) {
      items.add(_TimelineItem(
        icon: Icons.check_circle_outline,
        iconColor: const Color(0xFF4CAF50),
        title: 'Booking Confirmed',
        subtitle: 'Barber accepted your booking request',
        timestamp: booking.acceptedAt ?? booking.createdAt,
      ));
    }

    // Job Started (if applicable)
    if (booking.status == BookingStatus.completed) {
      items.add(_TimelineItem(
        icon: Icons.play_circle_outline,
        iconColor: const Color(0xFF2196F3),
        title: 'Job Started',
        subtitle: 'Barber began the service',
        timestamp: booking.startedAt ?? booking.createdAt,
      ));
    }

    // Booking Completed
    if (booking.status == BookingStatus.completed) {
      items.add(_TimelineItem(
        icon: Icons.check_circle,
        iconColor: const Color(0xFF4CAF50),
        title: 'Job Completed',
        subtitle: 'Service completed successfully',
        timestamp: booking.updatedAt ?? booking.createdAt,
        isLast: true,
      ));

      // Add rating if available
      if (booking.customerRating != null) {
        items.add(_TimelineItem(
          icon: Icons.star,
          iconColor: const Color(0xFFFFB800),
          title: 'Rating Submitted',
          subtitle: 'You rated this service ${booking.customerRating}/5',
          timestamp: booking.updatedAt ?? booking.createdAt,
          isLast: true,
        ));
      }
    }

    // Cancellation (customer)
    else if (booking.status == BookingStatus.cancelledByCustomer) {
      items.add(_TimelineItem(
        icon: Icons.cancel,
        iconColor: const Color(0xFFF44336),
        title: 'Cancelled by Customer',
        subtitle: booking.cancellationReason ?? 'Booking was cancelled',
        timestamp: booking.updatedAt ?? booking.createdAt,
        isLast: true,
      ));

      // Add refund info if applicable
      items.add(_TimelineItem(
        icon: Icons.account_balance_wallet,
        iconColor: const Color(0xFF4CAF50),
        title: 'Refund Processed',
        subtitle: '50% refund issued to your wallet',
        timestamp: booking.updatedAt ?? booking.createdAt,
        isLast: true,
      ));
    }

    // Cancellation (barber)
    else if (booking.status == BookingStatus.cancelledByBarber) {
      items.add(_TimelineItem(
        icon: Icons.cancel,
        iconColor: const Color(0xFFF44336),
        title: 'Cancelled by Barber',
        subtitle: booking.cancellationReason ?? 'Booking was cancelled by barber',
        timestamp: booking.updatedAt ?? booking.createdAt,
        isLast: true,
      ));

      // Add refund info
      items.add(_TimelineItem(
        icon: Icons.account_balance_wallet,
        iconColor: const Color(0xFF4CAF50),
        title: 'Full Refund Issued',
        subtitle: 'Refund processed to your wallet',
        timestamp: booking.updatedAt ?? booking.createdAt,
        isLast: true,
      ));
    }

    return items;
  }
}

/// Individual timeline item
class _TimelineItem extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final DateTime timestamp;
  final bool isFirst;
  final bool isLast;
  final bool showAdminBadge;

  const _TimelineItem({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.timestamp,
    this.isFirst = false,
    this.isLast = false,
    this.showAdminBadge = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Timeline line and icon
        SizedBox(
          width: 40,
          child: Column(
            children: [
              if (!isFirst)
                Container(
                  width: 2,
                  height: 20,
                  color: Colors.grey[300],
                ),
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.1),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: iconColor.withOpacity(0.3),
                    width: 1,
                  ),
                ),
                child: Icon(
                  icon,
                  size: 16,
                  color: iconColor,
                ),
              ),
              if (!isLast)
                Container(
                  width: 2,
                  height: 20,
                  color: Colors.grey[300],
                ),
            ],
          ),
        ),

        const SizedBox(width: 12),

        // Content
        Expanded(
          child: Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: Colors.grey[200]!,
                width: 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1A1A1A),
                        ),
                      ),
                    ),
                    if (showAdminBadge)
                      const AdminTrustBadge(message: 'Admin Action'),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey[600],
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _formatTimestamp(timestamp),
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey[500],
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);

    if (difference.inDays == 0) {
      return 'Today at ${_formatTime(timestamp)}';
    } else if (difference.inDays == 1) {
      return 'Yesterday at ${_formatTime(timestamp)}';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} days ago at ${_formatTime(timestamp)}';
    } else {
      return '${timestamp.day}/${timestamp.month}/${timestamp.year} at ${_formatTime(timestamp)}';
    }
  }

  String _formatTime(DateTime time) {
    final hour = time.hour > 12 ? time.hour - 12 : (time.hour == 0 ? 12 : time.hour);
    final amPm = time.hour >= 12 ? 'PM' : 'AM';
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute $amPm';
  }
}

/// Admin Trust Signals Banner
class AdminTrustSignalsBanner extends StatelessWidget {
  const AdminTrustSignalsBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFE3F2FD), Color(0xFFBBDEFB)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFF2196F3).withOpacity(0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.verified_user,
                color: const Color(0xFF2196F3),
                size: 24,
              ),
              const SizedBox(width: 8),
              Text(
                'Admin Protected',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF2196F3),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Your booking is protected by Best Cut\'s admin oversight. We monitor all transactions and can intervene if needed for your safety.',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[700],
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _TrustSignal(
                icon: Icons.security,
                text: 'Secure Payments',
              ),
              const SizedBox(width: 16),
              _TrustSignal(
                icon: Icons.support_agent,
                text: '24/7 Support',
              ),
              const SizedBox(width: 16),
              _TrustSignal(
                icon: Icons.verified,
                text: 'Verified Barbers',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Individual trust signal
class _TrustSignal extends StatelessWidget {
  final IconData icon;
  final String text;

  const _TrustSignal({
    required this.icon,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          icon,
          size: 16,
          color: const Color(0xFF4CAF50),
        ),
        const SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: Colors.grey[700],
          ),
        ),
      ],
    );
  }
}