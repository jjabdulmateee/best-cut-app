import 'package:flutter/material.dart';
import '../data/app_data.dart';

/// Admin Override Indicator - Shows when something was modified by admin
class AdminOverrideIndicator extends StatelessWidget {
  final DateTime? modifiedAt;
  final String? modifiedBy;
  final bool showBorder;

  const AdminOverrideIndicator({
    super.key,
    this.modifiedAt,
    this.modifiedBy,
    this.showBorder = false,
  });

  @override
  Widget build(BuildContext context) {
    if (modifiedBy != 'admin' && modifiedBy != 'Admin') {
      return const SizedBox.shrink();
    }

    final timeString = modifiedAt != null
        ? _formatTimeAgo(modifiedAt!)
        : 'Recently';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF2196F3).withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: showBorder ? Border.all(
          color: const Color(0xFF2196F3).withOpacity(0.3),
          width: 1,
        ) : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.admin_panel_settings,
            size: 14,
            color: const Color(0xFF2196F3),
          ),
          const SizedBox(width: 4),
          Text(
            'Updated by Admin $timeString',
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Color(0xFF2196F3),
            ),
          ),
        ],
      ),
    );
  }

  String _formatTimeAgo(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays > 0) {
      return '${difference.inDays}d ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m ago';
    } else {
      return 'just now';
    }
  }
}

/// Admin Override Banner - Shows as a banner for admin-modified items
class AdminOverrideBanner extends StatelessWidget {
  final String message;
  final DateTime? modifiedAt;

  const AdminOverrideBanner({
    super.key,
    required this.message,
    this.modifiedAt,
  });

  @override
  Widget build(BuildContext context) {
    final timeString = modifiedAt != null
        ? _formatTimeAgo(modifiedAt!)
        : '';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF2196F3).withOpacity(0.1),
        border: Border(
          left: BorderSide(
            color: const Color(0xFF2196F3),
            width: 3,
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.info_outline,
            size: 16,
            color: const Color(0xFF2196F3),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '$message${timeString.isNotEmpty ? ' $timeString' : ''}',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Color(0xFF2196F3),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatTimeAgo(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays > 0) {
      return '${difference.inDays} days ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours} hours ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes} minutes ago';
    } else {
      return 'just now';
    }
  }
}

/// Admin Override Status Icon - Small indicator for status changes
class AdminOverrideStatusIcon extends StatelessWidget {
  final bool wasModifiedByAdmin;

  const AdminOverrideStatusIcon({
    super.key,
    required this.wasModifiedByAdmin,
  });

  @override
  Widget build(BuildContext context) {
    if (!wasModifiedByAdmin) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: const Color(0xFF2196F3),
        shape: BoxShape.circle,
      ),
      child: const Icon(
        Icons.admin_panel_settings,
        size: 10,
        color: Colors.white,
      ),
    );
  }
}

/// Admin Protection Shield - Shows when booking is protected by admin oversight
class AdminProtectionShield extends StatelessWidget {
  final String message;
  final bool isActive;

  const AdminProtectionShield({
    super.key,
    this.message = 'Protected by admin oversight',
    this.isActive = true,
  });

  @override
  Widget build(BuildContext context) {
    if (!isActive) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF4CAF50).withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFF4CAF50).withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.shield,
            size: 16,
            color: const Color(0xFF4CAF50),
          ),
          const SizedBox(width: 6),
          Text(
            message,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Color(0xFF4CAF50),
            ),
          ),
        ],
      ),
    );
  }
}

/// Admin Action Banner - Shows for cancellations, refunds, or other admin actions
class AdminActionBanner extends StatelessWidget {
  final String action;
  final String reason;
  final DateTime? actionTime;
  final AdminActionType type;

  const AdminActionBanner({
    super.key,
    required this.action,
    required this.reason,
    this.actionTime,
    this.type = AdminActionType.info,
  });

  @override
  Widget build(BuildContext context) {
    final color = _getColorForType(type);
    final icon = _getIconForType(type);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: color.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  action,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            reason,
            style: TextStyle(
              fontSize: 13,
              color: color.withOpacity(0.8),
              height: 1.4,
            ),
          ),
          if (actionTime != null) ...[
            const SizedBox(height: 6),
            Text(
              'Action taken ${_formatTimeAgo(actionTime!)}',
              style: TextStyle(
                fontSize: 11,
                color: color.withOpacity(0.6),
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _formatTimeAgo(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays > 0) {
      return '${difference.inDays}d ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m ago';
    } else {
      return 'just now';
    }
  }

  Color _getColorForType(AdminActionType type) {
    switch (type) {
      case AdminActionType.info:
        return const Color(0xFF2196F3);
      case AdminActionType.warning:
        return const Color(0xFFFF9800);
      case AdminActionType.error:
        return const Color(0xFFF44336);
      case AdminActionType.success:
        return const Color(0xFF4CAF50);
    }
  }

  IconData _getIconForType(AdminActionType type) {
    switch (type) {
      case AdminActionType.info:
        return Icons.info_outline;
      case AdminActionType.warning:
        return Icons.warning_amber_rounded;
      case AdminActionType.error:
        return Icons.error_outline;
      case AdminActionType.success:
        return Icons.check_circle_outline;
    }
  }
}

/// Admin Dispute Guidance - Shows how to contact support for disputes
class AdminDisputeGuidance extends StatelessWidget {
  final String bookingId;
  final String contactEmail;

  const AdminDisputeGuidance({
    super.key,
    required this.bookingId,
    this.contactEmail = 'support@bestcut.pk',
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3E0),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFFFF9800).withOpacity(0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.help_outline,
                size: 20,
                color: const Color(0xFFFF9800),
              ),
              const SizedBox(width: 8),
              Text(
                'Need Help?',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFFFF9800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'If you disagree with this admin action, you can contact our support team with your booking reference.',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[700],
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey[300]!),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.email_outlined,
                  size: 18,
                  color: Colors.grey[600],
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Contact Support',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: Colors.grey[800],
                        ),
                      ),
                      Text(
                        contactEmail,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  'Booking: $bookingId',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey[500],
                    fontFamily: 'monospace',
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

/// System Freeze Alert - Shows when system is frozen
class SystemFreezeAlert extends StatelessWidget {
  final String reason;
  final VoidCallback? onRefresh;

  const SystemFreezeAlert({
    super.key,
    required this.reason,
    this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFF9800), Color(0xFFFF5722)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFF9800).withOpacity(0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Icon(
            Icons.warning_amber_rounded,
            size: 48,
            color: Colors.white,
          ),
          const SizedBox(height: 16),
          Text(
            'System Maintenance',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            reason,
            style: TextStyle(
              fontSize: 14,
              color: Colors.white.withOpacity(0.9),
              height: 1.4,
            ),
            textAlign: TextAlign.center,
          ),
          if (onRefresh != null) ...[
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh),
              label: const Text('Check Status'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFFFF9800),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Escrow Status Indicator - Shows payment escrow status
class EscrowStatusIndicator extends StatelessWidget {
  final EscrowStatus? status;
  final bool showDescription;

  const EscrowStatusIndicator({
    super.key,
    required this.status,
    this.showDescription = false,
  });

  @override
  Widget build(BuildContext context) {
    if (status == null) return const SizedBox.shrink();

    final color = _getStatusColor(status!);
    final text = _getStatusText(status!);
    final icon = _getStatusIcon(status!);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: color.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 16,
            color: color,
          ),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Color _getStatusColor(EscrowStatus status) {
    switch (status) {
      case EscrowStatus.held:
        return const Color(0xFFFF9800); // Orange
      case EscrowStatus.released:
        return const Color(0xFF4CAF50); // Green
      case EscrowStatus.refunded:
        return const Color(0xFF2196F3); // Blue
      case EscrowStatus.disputed:
        return const Color(0xFFF44336); // Red
      default:
        return const Color(0xFF9E9E9E); // Grey fallback
    }
  }

  String _getStatusText(EscrowStatus status) {
    switch (status) {
      case EscrowStatus.held:
        return 'Held in Escrow';
      case EscrowStatus.released:
        return 'Payment Released';
      case EscrowStatus.refunded:
        return 'Payment Refunded';
      case EscrowStatus.disputed:
        return 'Payment Disputed';
    }
  }

  IconData _getStatusIcon(EscrowStatus status) {
    switch (status) {
      case EscrowStatus.held:
        return Icons.lock_clock;
      case EscrowStatus.released:
        return Icons.check_circle_outline;
      case EscrowStatus.refunded:
        return Icons.undo;
      case EscrowStatus.disputed:
        return Icons.gavel;
    }
  }
}

/// Escrow Status Banner - Detailed escrow information
class EscrowStatusBanner extends StatelessWidget {
  final EscrowStatus? status;
  final int? amount;

  const EscrowStatusBanner({
    super.key,
    required this.status,
    this.amount,
  });

  @override
  Widget build(BuildContext context) {
    if (status == null) return const SizedBox.shrink();

    final color = _getStatusColor(status!);
    final title = _getStatusTitle(status!);
    final description = _getStatusDescription(status!);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: color.withOpacity(0.2),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                _getStatusIcon(status!),
                color: color,
                size: 24,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: color,
                      ),
                    ),
                    if (amount != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        'PKR ${amount!.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')}',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey[800],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            description,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[700],
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Color _getStatusColor(EscrowStatus status) {
    switch (status) {
      case EscrowStatus.held:
        return const Color(0xFFFF9800); // Orange
      case EscrowStatus.released:
        return const Color(0xFF4CAF50); // Green
      case EscrowStatus.refunded:
        return const Color(0xFF2196F3); // Blue
      case EscrowStatus.disputed:
        return const Color(0xFFF44336); // Red
    }
  }

  String _getStatusTitle(EscrowStatus status) {
    switch (status) {
      case EscrowStatus.held:
        return 'Payment Held in Escrow';
      case EscrowStatus.released:
        return 'Payment Released';
      case EscrowStatus.refunded:
        return 'Payment Refunded';
      case EscrowStatus.disputed:
        return 'Payment Under Dispute';
    }
  }

  String _getStatusDescription(EscrowStatus status) {
    switch (status) {
      case EscrowStatus.held:
        return 'Your payment is safely held by Best Cut until the service is completed. It will be automatically released to the barber or refunded based on the outcome.';
      case EscrowStatus.released:
        return 'Payment has been successfully released to the barber. Thank you for using Best Cut!';
      case EscrowStatus.refunded:
        return 'Your payment has been refunded to your wallet. The booking has been cancelled.';
      case EscrowStatus.disputed:
        return 'This payment is currently under dispute review. Best Cut admin will resolve this matter and notify you of the outcome.';
    }
  }

  IconData _getStatusIcon(EscrowStatus status) {
    switch (status) {
      case EscrowStatus.held:
        return Icons.account_balance_wallet;
      case EscrowStatus.released:
        return Icons.check_circle;
      case EscrowStatus.refunded:
        return Icons.undo;
      case EscrowStatus.disputed:
        return Icons.gavel;
    }
  }
}

/// Read-Only State Banner - Shows when actions are disabled
class ReadOnlyStateBanner extends StatelessWidget {
  final String reason;
  final IconData icon;

  const ReadOnlyStateBanner({
    super.key,
    required this.reason,
    this.icon = Icons.lock_outline,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            size: 20,
            color: Colors.grey[600],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              reason,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[700],
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Admin Trust Badge - Shows admin protection messaging
class AdminTrustBadge extends StatelessWidget {
  final String message;

  const AdminTrustBadge({
    super.key,
    this.message = 'Verified & Protected',
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF4CAF50), Color(0xFF66BB6A)],
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.verified,
            size: 14,
            color: Colors.white,
          ),
          const SizedBox(width: 4),
          Text(
            message,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

/// Trust Level Badge - Shows user's trust level
class TrustLevelBadge extends StatelessWidget {
  final TrustLevel trustLevel;
  final int? strikeCount;
  final bool showDescription;

  const TrustLevelBadge({
    super.key,
    required this.trustLevel,
    this.strikeCount,
    this.showDescription = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = _getTrustColor(trustLevel);
    final text = _getTrustText(trustLevel);
    final icon = _getTrustIcon(trustLevel);

    if (showDescription) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: color.withOpacity(0.3),
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Trust Level: $text',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
                if (strikeCount != null && strikeCount! > 0) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '$strikeCount strike${strikeCount! > 1 ? 's' : ''}',
                      style: const TextStyle(
                        fontSize: 10,
                        color: Colors.white,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            Text(
              _getTrustDescription(trustLevel),
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey[700],
                height: 1.4,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: color.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: color,
            ),
          ),
          if (strikeCount != null && strikeCount! > 0) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '$strikeCount',
                style: const TextStyle(
                  fontSize: 10,
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Color _getTrustColor(TrustLevel level) {
    switch (level) {
      case TrustLevel.excellent:
        return const Color(0xFF4CAF50); // Green
      case TrustLevel.good:
        return const Color(0xFF8BC34A); // Light Green
      case TrustLevel.warning:
        return const Color(0xFFFF9800); // Orange
      case TrustLevel.restricted:
        return const Color(0xFFF44336); // Red
    }
  }

  String _getTrustText(TrustLevel level) {
    switch (level) {
      case TrustLevel.excellent:
        return 'Excellent';
      case TrustLevel.good:
        return 'Good';
      case TrustLevel.warning:
        return 'Warning';
      case TrustLevel.restricted:
        return 'Restricted';
    }
  }

  IconData _getTrustIcon(TrustLevel level) {
    switch (level) {
      case TrustLevel.excellent:
        return Icons.verified;
      case TrustLevel.good:
        return Icons.thumb_up;
      case TrustLevel.warning:
        return Icons.warning;
      case TrustLevel.restricted:
        return Icons.block;
    }
  }

  String _getTrustDescription(TrustLevel level) {
    switch (level) {
      case TrustLevel.excellent:
        return 'No issues reported. Full access to all features.';
      case TrustLevel.good:
        return 'Minor issues noted. All features available.';
      case TrustLevel.warning:
        return 'Multiple issues reported. Some restrictions may apply.';
      case TrustLevel.restricted:
        return 'Account has trust restrictions due to policy violations. Limited access available.';
    }
  }
}

/// Strike Warning Banner - Shows when user has strikes
class StrikeWarningBanner extends StatelessWidget {
  final int strikeCount;
  final String? restrictionReason;
  final VoidCallback? onContactSupport;

  const StrikeWarningBanner({
    super.key,
    required this.strikeCount,
    this.restrictionReason,
    this.onContactSupport,
  });

  @override
  Widget build(BuildContext context) {
    if (strikeCount == 0) return const SizedBox.shrink();

    final isRestricted = strikeCount >= 3;
    final color = isRestricted ? const Color(0xFFF44336) : const Color(0xFFFF9800);
    final title = isRestricted ? 'Account Restricted' : 'Trust Warning';
    final icon = isRestricted ? Icons.block : Icons.warning;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: color.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: color,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$strikeCount strike${strikeCount > 1 ? 's' : ''} recorded',
                      style: TextStyle(
                        fontSize: 14,
                        color: color.withOpacity(0.8),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (restrictionReason != null) ...[
            const SizedBox(height: 12),
            Text(
              restrictionReason!,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[700],
                height: 1.4,
              ),
            ),
          ],
          if (onContactSupport != null) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onContactSupport,
                icon: const Icon(Icons.support_agent, size: 16),
                label: const Text('Contact Support'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: color,
                  side: BorderSide(color: color),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Admin Action Timeline Item - Shows in booking history
class AdminActionTimelineItem extends StatelessWidget {
  final String action;
  final String description;
  final DateTime timestamp;
  final AdminActionType type;

  const AdminActionTimelineItem({
    super.key,
    required this.action,
    required this.description,
    required this.timestamp,
    this.type = AdminActionType.info,
  });

  @override
  Widget build(BuildContext context) {
    final color = _getColorForType(type);

    return Container(
      margin: const EdgeInsets.only(left: 24, bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: color.withOpacity(0.2),
          width: 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.admin_panel_settings,
              size: 16,
              color: color,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      action,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: color,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      _formatTimeAgo(timestamp),
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[500],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey[700],
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatTimeAgo(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays > 0) {
      return '${difference.inDays}d ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m ago';
    } else {
      return 'just now';
    }
  }

  Color _getColorForType(AdminActionType type) {
    switch (type) {
      case AdminActionType.info:
        return const Color(0xFF2196F3);
      case AdminActionType.warning:
        return const Color(0xFFFF9800);
      case AdminActionType.error:
        return const Color(0xFFF44336);
      case AdminActionType.success:
        return const Color(0xFF4CAF50);
    }
  }
}

/// Enums for admin action types
enum AdminActionType {
  info,
  warning,
  error,
  success,
}