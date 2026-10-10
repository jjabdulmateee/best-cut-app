import 'package:flutter/material.dart';
import '../models/slot.dart';
import '../models/barber.dart';
import '../services/booking_engine_service.dart';
import '../services/firestore_service.dart';
import 'reroute_options_sheet.dart';

// ============================================================================
// BOOKING DETAILS SCREEN — Phase 1 + Phase 4 (Smart Rerouting)
// ============================================================================
//
// Shows booking details with three engine actions:
//   1. Cancel — time-based refund rules (>5h full, 2-5h 80/10/10, ≤2h blocked)
//   2. Reschedule — max 2, max 30 days, no within 2h, locked after barber switch
//   3. Switch Barber — price diff handled, locks rescheduling after
// ============================================================================

class BookingDetailsScreen extends StatefulWidget {
  final Booking booking;

  const BookingDetailsScreen({super.key, required this.booking});

  @override
  State<BookingDetailsScreen> createState() => _BookingDetailsScreenState();
}

class _BookingDetailsScreenState extends State<BookingDetailsScreen> {
  final BookingEngineService _engine = BookingEngineService();
  final FirestoreService _firestoreService = FirestoreService();
  late Booking _booking;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _booking = widget.booking;
  }

  /// Refresh booking data from Firestore
  Future<void> _refreshBooking() async {
    var fresh = await _engine.getBooking(_booking.id);

    // 15-MIN TIMEOUT: if the barber never answered, reroute now and re-read.
    if (fresh != null && _engine.needsAutoReroute(fresh)) {
      await _engine.autoRerouteIfExpired(fresh);
      fresh = await _engine.getBooking(_booking.id) ?? fresh;
    }

    final updated = fresh;
    if (updated != null && mounted) {
      setState(() => _booking = updated);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isActive = _booking.status.isActive;
    final hoursUntil = _engine.getHoursUntilAppointment(_booking);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF1A1A1A)),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Booking Details',
          style: TextStyle(
            color: Color(0xFF1A1A1A),
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Status banner
            _buildStatusBanner(),
            const SizedBox(height: 12),

            // ── Phase 4: Expired Assignment Alert ──
            if (_booking.needsRerouteDecision) ...[
              _buildExpiredAssignmentBanner(),
              const SizedBox(height: 12),
            ],

            // ── Phase 4: Reroute History ──
            if (_booking.rerouteCount > 0) ...[
              _buildRerouteInfoBanner(),
              const SizedBox(height: 12),
            ],

            // Lifecycle progress (for active bookings)
            if (isActive || _booking.status == BookingStatus.completed) ...[
              _buildCustomerLifecycleProgress(),
              const SizedBox(height: 12),
            ],
            const SizedBox(height: 8),

            // Barber card
            _buildBarberCard(),
            const SizedBox(height: 20),

            // Services list
            if (_booking.selectedServices.isNotEmpty) ...[
              _buildServicesCard(),
              const SizedBox(height: 20),
            ],

            // Appointment details
            _buildDetailsCard(),
            const SizedBox(height: 20),

            // Payment info
            _buildPaymentCard(),
            const SizedBox(height: 20),

            // Booking engine info (reschedule/switch status)
            if (isActive) ...[
              _buildEngineStatusCard(),
              const SizedBox(height: 20),
            ],

            // Cancellation policy
            _buildCancellationPolicyCard(),
            const SizedBox(height: 20),

            // Cancellation / rejection details
            if (_booking.status.isCancelled || _booking.status == BookingStatus.rejected) ...[
              _buildCancellationDetailsCard(),
              const SizedBox(height: 20),
            ],

            // ── Action Buttons ──
            if (isActive && hoursUntil > 0) ...[
              _buildActionButtons(),
              const SizedBox(height: 20),
            ],

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // STATUS BANNER
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildStatusBanner() {
    Color bgColor;
    Color iconColor;
    IconData icon;
    String title;
    String subtitle;

    switch (_booking.status) {
      case BookingStatus.pending:
        if (_booking.assignmentExpired) {
          bgColor = Colors.red.withValues(alpha: 0.1);
          iconColor = Colors.red;
          icon = Icons.timer_off;
          title = 'Barber Didn\'t Respond';
          subtitle = 'Choose what to do next';
        } else {
          bgColor = Colors.orange.withValues(alpha: 0.1);
          iconColor = Colors.orange;
          icon = Icons.schedule;
          title = 'Waiting for Barber';
          subtitle = 'Your request is being reviewed';
        }
        break;
      case BookingStatus.rerouting:
        bgColor = const Color(0xFF9C27B0).withValues(alpha: 0.1);
        iconColor = const Color(0xFF9C27B0);
        icon = Icons.alt_route;
        title = 'Finding Another Barber';
        subtitle = 'The barber didn\'t respond in 15 minutes — '
            'routing your request to the next nearest barber';
        break;
      case BookingStatus.confirmed:
        bgColor = const Color(0xFF00AA5B).withValues(alpha: 0.1);
        iconColor = const Color(0xFF00AA5B);
        icon = Icons.check_circle;
        title = 'Barber Accepted';
        subtitle = _booking.isUpcoming
            ? 'Your appointment is scheduled'
            : 'Ready to begin';
        break;
      case BookingStatus.inProgress:
        bgColor = const Color(0xFF2196F3).withValues(alpha: 0.1);
        iconColor = const Color(0xFF2196F3);
        icon = Icons.play_circle_filled;
        title = 'In Progress';
        subtitle = 'Your haircut is happening now';
        break;
      case BookingStatus.completed:
        bgColor = const Color(0xFF276EF1).withValues(alpha: 0.1);
        iconColor = const Color(0xFF276EF1);
        icon = Icons.done_all;
        title = 'Completed';
        subtitle = 'Service completed successfully';
        break;
      case BookingStatus.rejected:
        bgColor = const Color(0xFFFF4444).withValues(alpha: 0.1);
        iconColor = const Color(0xFFFF4444);
        icon = Icons.cancel;
        title = 'Barber Declined';
        subtitle = _booking.refundAmount != null
            ? 'Full refund of PKR ${_booking.refundAmount} issued'
            : 'Full refund issued to your wallet';
        break;
      case BookingStatus.cancelledByCustomer:
        bgColor = const Color(0xFFFF4444).withValues(alpha: 0.1);
        iconColor = const Color(0xFFFF4444);
        icon = Icons.cancel;
        title = 'Cancelled by You';
        subtitle = _booking.refundAmount != null
            ? 'PKR ${_booking.refundAmount} refunded'
            : 'Booking cancelled';
        break;
      case BookingStatus.cancelledByBarber:
        bgColor = const Color(0xFFFF4444).withValues(alpha: 0.1);
        iconColor = const Color(0xFFFF4444);
        icon = Icons.cancel;
        title = 'Cancelled by Barber';
        subtitle = 'Full refund credited to your wallet';
        break;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: iconColor, size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1A1A1A),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BARBER CARD
  // ═══════════════════════════════════════════════════════════════════════════

  /// Customer-facing lifecycle progress indicator
  Widget _buildCustomerLifecycleProgress() {
    final steps = [
      ('Requested', Icons.schedule),
      ('Accepted', Icons.check_circle),
      ('In Progress', Icons.play_circle_filled),
      ('Completed', Icons.verified),
    ];
    final currentStep = switch (_booking.status) {
      BookingStatus.pending => 0,
      BookingStatus.confirmed => 1,
      BookingStatus.inProgress => 2,
      BookingStatus.completed => 3,
      _ => 0,
    };

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Booking Progress',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF666666)),
          ),
          const SizedBox(height: 12),
          Row(
            children: List.generate(steps.length * 2 - 1, (index) {
              if (index.isOdd) {
                final stepIdx = index ~/ 2;
                final isComplete = stepIdx < currentStep;
                return Expanded(
                  child: Container(
                    height: 3,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      color: isComplete ? const Color(0xFF00C853) : Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                );
              }
              final stepIdx = index ~/ 2;
              final isComplete = stepIdx <= currentStep;
              final isCurrent = stepIdx == currentStep;

              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: isCurrent ? 32 : 26,
                    height: isCurrent ? 32 : 26,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isComplete
                          ? const Color(0xFF00C853)
                          : Colors.grey[300],
                      border: isCurrent
                          ? Border.all(color: const Color(0xFF00C853), width: 3)
                          : null,
                    ),
                    child: Icon(
                      steps[stepIdx].$2,
                      color: isComplete ? Colors.white : Colors.grey[500],
                      size: isCurrent ? 16 : 14,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    steps[stepIdx].$1,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
                      color: isComplete ? const Color(0xFF1A1A1A) : Colors.grey[500],
                    ),
                  ),
                ],
              );
            }),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PHASE 4: EXPIRED ASSIGNMENT + REROUTE BANNERS
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildExpiredAssignmentBanner() {
    return GestureDetector(
      onTap: () async {
        final result = await showRerouteOptionsSheet(context, _booking);
        if (result != null) {
          _refreshBooking(); // Refresh after any action
        }
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Colors.orange.withValues(alpha: 0.15),
              Colors.red.withValues(alpha: 0.1),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.timer_off, color: Colors.orange, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Barber Didn\'t Respond',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1A1A1A),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Tap to choose: find another barber or cancel.',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey[700],
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios, color: Colors.orange, size: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildRerouteInfoBanner() {
    final reroutesLeft = BookingEngineService.maxReroutes - _booking.rerouteCount;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.blue.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          const Icon(Icons.swap_horiz, color: Colors.blue, size: 18),
          const SizedBox(width: 10),
          Text(
            'Rerouted ${_booking.rerouteCount} time(s)',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1A1A1A),
            ),
          ),
          const Spacer(),
          Text(
            '$reroutesLeft left',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBarberCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFEEEEEE)),
      ),
      child: Row(
        children: [
          Container(
            width: 70,
            height: 70,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: Colors.grey[200],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image.network(
                _booking.barberImageUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) =>
                    Icon(Icons.person, color: Colors.grey[400], size: 36),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _booking.barberName,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1A1A1A),
                  ),
                ),
                if (_booking.shopName != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    _booking.shopName!,
                    style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                  ),
                ],
                if (_booking.barberAddress != null) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(Icons.location_on_outlined,
                          size: 14, color: Colors.grey[500]),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          _booking.barberAddress!,
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey[600]),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
                // Barber switched indicator
                if (_booking.barberSwitched) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.blue[50],
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'Switched from original barber',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.blue[700],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SERVICES CARD
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildServicesCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFAFA),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Services',
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1A1A1A)),
          ),
          const SizedBox(height: 12),
          ...(_booking.selectedServices).map(
            (name) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  const Icon(Icons.check_circle_outline,
                      size: 18, color: Color(0xFF00AA5B)),
                  const SizedBox(width: 10),
                  Text(
                    name,
                    style: const TextStyle(fontSize: 14),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // APPOINTMENT DETAILS
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildDetailsCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFAFA),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Appointment Details',
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1A1A1A)),
          ),
          const SizedBox(height: 16),
          _buildDetailRow(
            icon: Icons.confirmation_number_outlined,
            label: 'Booking ID',
            value:
                '#${_booking.id.length > 6 ? _booking.id.substring(_booking.id.length - 6) : _booking.id}',
          ),
          const SizedBox(height: 14),
          _buildDetailRow(
            icon: Icons.calendar_today_outlined,
            label: 'Date',
            value: _booking.formattedDate,
          ),
          const SizedBox(height: 14),
          _buildDetailRow(
            icon: Icons.access_time,
            label: 'Time',
            value: _booking.timeSlot,
          ),
          if (_booking.rescheduleCount > 0) ...[
            const SizedBox(height: 14),
            _buildDetailRow(
              icon: Icons.replay,
              label: 'Rescheduled',
              value: '${_booking.rescheduleCount} time(s)',
            ),
          ],
          const SizedBox(height: 14),
          _buildDetailRow(
            icon: Icons.event_note,
            label: 'Booked On',
            value: _formatDateTime(_booking.createdAt),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 18, color: const Color(0xFF1A1A1A)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: TextStyle(fontSize: 12, color: Colors.grey[500])),
              const SizedBox(height: 1),
              Text(
                value,
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1A1A1A)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PAYMENT CARD
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildPaymentCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFEEEEEE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Payment Summary',
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1A1A1A)),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Service(s)',
                  style: TextStyle(fontSize: 14, color: Colors.grey[600])),
              Text(
                _booking.formattedPrice,
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1A1A1A)),
              ),
            ],
          ),
          // Price difference from barber switch
          if (_booking.barberSwitched && _booking.originalPrice != null) ...[
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Original price',
                    style:
                        TextStyle(fontSize: 13, color: Colors.grey[500])),
                Text(
                  'PKR ${_booking.originalPrice}',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey[500],
                    decoration: TextDecoration.lineThrough,
                  ),
                ),
              ],
            ),
          ],
          // Refund info
          if (_booking.refundAmount != null) ...[
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Refund',
                    style: TextStyle(fontSize: 14, color: Colors.green[700])),
                Text(
                  'PKR ${_booking.refundAmount}',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.green[700],
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 14),
          Container(height: 1, color: const Color(0xFFEEEEEE)),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Total',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1A1A1A)),
              ),
              Text(
                _booking.formattedPrice,
                style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1A1A1A)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BOOKING ENGINE STATUS (reschedule/switch info)
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildEngineStatusCard() {
    final reschedulePolicy = _engine.getReschedulePolicy(_booking);
    final cancellationPolicy = _engine.getCancellationPolicy(_booking);
    final hoursUntil = _engine.getHoursUntilAppointment(_booking);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue[50],
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.blue[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline, color: Colors.blue[700], size: 20),
              const SizedBox(width: 8),
              Text(
                'Booking Options',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: Colors.blue[700],
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Time until appointment
          _buildInfoTile(
            Icons.timer_outlined,
            'Time until appointment',
            hoursUntil > 24
                ? '${hoursUntil ~/ 24} day(s) ${(hoursUntil % 24).toStringAsFixed(0)}h'
                : '${hoursUntil.toStringAsFixed(1)} hours',
          ),
          const SizedBox(height: 8),
          // Reschedule status
          _buildInfoTile(
            Icons.replay,
            'Reschedule',
            reschedulePolicy.allowed
                ? '${reschedulePolicy.remainingReschedules} remaining'
                : reschedulePolicy.message,
            isWarning: !reschedulePolicy.allowed,
          ),
          const SizedBox(height: 8),
          // Cancellation status
          _buildInfoTile(
            Icons.cancel_outlined,
            'Cancellation',
            cancellationPolicy.allowed
                ? '${cancellationPolicy.refundPercent}% refund'
                : 'Blocked (within 2h)',
            isWarning: !cancellationPolicy.allowed,
          ),
          if (_booking.barberSwitched) ...[
            const SizedBox(height: 8),
            _buildInfoTile(
              Icons.swap_horiz,
              'Barber Switch',
              'Completed — rescheduling locked',
              isWarning: true,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInfoTile(IconData icon, String label, String value,
      {bool isWarning = false}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon,
            size: 16,
            color: isWarning ? Colors.orange[700] : Colors.blue[600]),
        const SizedBox(width: 8),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: TextStyle(fontSize: 13, color: Colors.grey[700]),
              children: [
                TextSpan(
                  text: '$label: ',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                TextSpan(
                  text: value,
                  style: TextStyle(
                    color: isWarning ? Colors.orange[700] : null,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CANCELLATION POLICY CARD
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildCancellationPolicyCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.orange[50],
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.orange[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.policy_outlined, color: Colors.orange[700], size: 20),
              const SizedBox(width: 8),
              Text(
                'Cancellation & Reschedule Policy',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: Colors.orange[700],
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '• More than 5 hours before: Full refund (100%)\n'
            '• 2–5 hours before: 80% refund, 10% barber, 10% platform\n'
            '• Less than 2 hours: Cancellation blocked\n'
            '\n'
            '• Maximum 2 reschedules per booking\n'
            '• New date must be within 30 days\n'
            '• No reschedule within 2 hours of appointment\n'
            '• Switching barber locks rescheduling',
            style: TextStyle(
              fontSize: 13,
              color: Colors.orange[800],
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CANCELLATION DETAILS (for cancelled bookings)
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildCancellationDetailsCard() {
    final isByBarber =
        _booking.status == BookingStatus.cancelledByBarber;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF0F0),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFFCCCC)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.info_outline,
                  color: Color(0xFFFF4444), size: 20),
              SizedBox(width: 8),
              Text(
                'Cancellation Details',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1A1A1A)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_booking.cancellationReason != null)
            Text(
              'Reason: ${_booking.cancellationReason}',
              style: TextStyle(fontSize: 13, color: Colors.grey[700]),
            ),
          if (_booking.refundAmount != null) ...[
            const SizedBox(height: 8),
            Text(
              'Refund: PKR ${_booking.refundAmount}',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.green[700],
              ),
            ),
          ],
          if (isByBarber) ...[
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.popUntil(context, (route) => route.isFirst);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF276EF1),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  elevation: 0,
                ),
                child: const Text('Find Another Barber',
                    style:
                        TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ACTION BUTTONS — Cancel, Reschedule, Switch Barber
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildActionButtons() {
    final cancellationPolicy = _engine.getCancellationPolicy(_booking);
    final reschedulePolicy = _engine.getReschedulePolicy(_booking);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Actions',
          style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1A1A1A)),
        ),
        const SizedBox(height: 12),

        // ── Reschedule Button ──
        _buildActionButton(
          icon: Icons.replay,
          label: 'Reschedule Booking',
          subtitle: reschedulePolicy.allowed
              ? '${reschedulePolicy.remainingReschedules} reschedule(s) remaining'
              : reschedulePolicy.message,
          color: const Color(0xFF276EF1),
          enabled: reschedulePolicy.allowed,
          onTap: () => _showRescheduleSheet(),
        ),
        const SizedBox(height: 10),

        // ── Switch Barber Button ──
        _buildActionButton(
          icon: Icons.swap_horiz,
          label: 'Switch Barber',
          subtitle: _booking.barberSwitched
              ? 'Already switched'
              : 'Change to a different barber',
          color: const Color(0xFFFF9800),
          enabled: !_booking.barberSwitched,
          onTap: () => _showSwitchBarberSheet(),
        ),
        const SizedBox(height: 10),

        // ── Cancel Button ──
        _buildActionButton(
          icon: Icons.cancel_outlined,
          label: 'Cancel Booking',
          subtitle: cancellationPolicy.allowed
              ? '${cancellationPolicy.refundPercent}% refund (PKR ${cancellationPolicy.refundAmount})'
              : cancellationPolicy.message,
          color: const Color(0xFFFF4444),
          enabled: cancellationPolicy.allowed,
          onTap: () => _showCancelSheet(cancellationPolicy),
        ),
      ],
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required String subtitle,
    required Color color,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: enabled
              ? color.withValues(alpha: 0.06)
              : Colors.grey[100],
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: enabled
                ? color.withValues(alpha: 0.3)
                : Colors.grey[300]!,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: enabled
                    ? color.withValues(alpha: 0.12)
                    : Colors.grey[200],
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon,
                  color: enabled ? color : Colors.grey[400], size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: enabled
                          ? const Color(0xFF1A1A1A)
                          : Colors.grey[500],
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: enabled ? Colors.grey[600] : Colors.grey[400],
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (enabled)
              Icon(Icons.chevron_right, color: Colors.grey[400], size: 22),
            if (!enabled)
              Icon(Icons.lock_outline, color: Colors.grey[400], size: 18),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CANCEL SHEET
  // ═══════════════════════════════════════════════════════════════════════════

  void _showCancelSheet(CancellationPolicy policy) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 24),
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: const Color(0xFFFF4444).withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.warning_amber_rounded,
                  color: Color(0xFFFF4444), size: 32),
            ),
            const SizedBox(height: 20),
            const Text(
              'Cancel Booking?',
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1A1A1A)),
            ),
            const SizedBox(height: 16),

            // Policy details
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: policy.tier == 'full'
                    ? Colors.green[50]
                    : Colors.orange[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: policy.tier == 'full'
                      ? Colors.green[200]!
                      : Colors.orange[200]!,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        policy.tier == 'full'
                            ? Icons.check_circle
                            : Icons.info_outline,
                        color: policy.tier == 'full'
                            ? Colors.green[700]
                            : Colors.orange[700],
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        policy.tier == 'full'
                            ? 'Full Refund'
                            : 'Partial Refund (80%)',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: policy.tier == 'full'
                              ? Colors.green[700]
                              : Colors.orange[700],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    policy.message,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey[700],
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.grey[700],
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      side: BorderSide(color: Colors.grey[300]!),
                    ),
                    child: const Text('Keep Booking',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isLoading
                        ? null
                        : () async {
                            setState(() => _isLoading = true);
                            Navigator.pop(ctx);

                            final result =
                                await _engine.cancelBooking(_booking.id);

                            if (mounted) {
                              setState(() => _isLoading = false);

                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(result.message),
                                  backgroundColor: result.success
                                      ? const Color(0xFF00AA5B)
                                      : const Color(0xFFFF4444),
                                ),
                              );

                              if (result.success) {
                                await _refreshBooking();
                              }
                            }
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF4444),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                    child: const Text('Cancel Booking',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ),
            SizedBox(height: MediaQuery.of(ctx).padding.bottom + 10),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // RESCHEDULE SHEET
  // ═══════════════════════════════════════════════════════════════════════════

  void _showRescheduleSheet() {
    DateTime selectedDate = DateTime.now().add(const Duration(days: 1));
    String? selectedSlot;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final slots = _generateTimeSlots();
          return Container(
            padding: const EdgeInsets.all(24),
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(ctx).size.height * 0.8,
            ),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Reschedule Booking',
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1A1A1A)),
                ),
                const SizedBox(height: 4),
                Text(
                  '${BookingEngineService.maxReschedules - _booking.rescheduleCount} reschedule(s) remaining. Max ${BookingEngineService.maxForwardDays} days ahead.',
                  style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                ),
                const SizedBox(height: 20),

                // Date picker
                const Text('Select New Date',
                    style:
                        TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                const SizedBox(height: 10),
                SizedBox(
                  height: 80,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: BookingEngineService.maxForwardDays,
                    itemBuilder: (_, index) {
                      final date =
                          DateTime.now().add(Duration(days: index + 1));
                      final isSelected =
                          selectedDate.day == date.day &&
                              selectedDate.month == date.month &&
                              selectedDate.year == date.year;
                      return GestureDetector(
                        onTap: () => setSheetState(
                            () => selectedDate = date),
                        child: Container(
                          width: 56,
                          margin: const EdgeInsets.only(right: 10),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? const Color(0xFF1A1A1A)
                                : Colors.grey[100],
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                _dayAbbr(date.weekday),
                                style: TextStyle(
                                    color: isSelected
                                        ? Colors.white70
                                        : Colors.grey[600],
                                    fontSize: 11),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${date.day}',
                                style: TextStyle(
                                  color: isSelected
                                      ? Colors.white
                                      : Colors.black,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                ),
                              ),
                              Text(
                                _monthAbbr(date.month),
                                style: TextStyle(
                                    color: isSelected
                                        ? Colors.white54
                                        : Colors.grey[500],
                                    fontSize: 10),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 20),

                // Time picker
                const Text('Select New Time',
                    style:
                        TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                const SizedBox(height: 10),
                Flexible(
                  child: GridView.builder(
                    shrinkWrap: true,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 4,
                      childAspectRatio: 2.2,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                    ),
                    itemCount: slots.length,
                    itemBuilder: (_, i) {
                      final s = slots[i];
                      final sel = selectedSlot == s;
                      return GestureDetector(
                        onTap: () =>
                            setSheetState(() => selectedSlot = s),
                        child: Container(
                          decoration: BoxDecoration(
                            color: sel
                                ? const Color(0xFF1A1A1A)
                                : Colors.grey[100],
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Center(
                            child: Text(
                              s,
                              style: TextStyle(
                                color: sel
                                    ? Colors.white
                                    : Colors.black,
                                fontWeight: FontWeight.w500,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 20),

                // Confirm button
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: selectedSlot == null
                        ? null
                        : () async {
                            Navigator.pop(ctx);

                            // Defensive: never let a malformed "HH:mm" crash
                            // the view — bail out with a message instead.
                            final time = parseTimeSlot(selectedSlot);
                            if (time == null) {
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                        'That time slot looks invalid. Please pick another.'),
                                    backgroundColor: Color(0xFFFF4444),
                                  ),
                                );
                              }
                              return;
                            }

                            setState(() => _isLoading = true);

                            final newDt = DateTime(
                              selectedDate.year,
                              selectedDate.month,
                              selectedDate.day,
                              time.hour,
                              time.minute,
                            );

                            final result =
                                await _engine.rescheduleBooking(
                              _booking.id,
                              newDateTime: newDt,
                              newTimeSlot: selectedSlot!,
                            );

                            if (mounted) {
                              setState(() => _isLoading = false);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(result.message),
                                  backgroundColor: result.success
                                      ? const Color(0xFF00AA5B)
                                      : const Color(0xFFFF4444),
                                ),
                              );
                              if (result.success) {
                                await _refreshBooking();
                              }
                            }
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF276EF1),
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: Colors.grey[300],
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text(
                      selectedSlot != null
                          ? 'Reschedule to $selectedSlot'
                          : 'Select a Time',
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                SizedBox(
                    height: MediaQuery.of(ctx).padding.bottom + 10),
              ],
            ),
          );
        },
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SWITCH BARBER SHEET
  // ═══════════════════════════════════════════════════════════════════════════

  void _showSwitchBarberSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _SwitchBarberSheet(
        currentBooking: _booking,
        engine: _engine,
        firestoreService: _firestoreService,
        onSwitched: (result) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(result.message),
                backgroundColor: result.success
                    ? const Color(0xFF00AA5B)
                    : const Color(0xFFFF4444),
              ),
            );
            if (result.success) {
              _refreshBooking();
            }
          }
        },
      ),
    );
  }

  // ─────────────────────── Utilities ───────────────────────

  List<String> _generateTimeSlots() {
    final slots = <String>[];
    for (int h = 8; h < 22; h++) {
      slots.add('${h.toString().padLeft(2, '0')}:00');
      slots.add('${h.toString().padLeft(2, '0')}:30');
    }
    return slots;
  }

  String _dayAbbr(int weekday) {
    const d = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return d[weekday - 1];
  }

  String _monthAbbr(int month) {
    const m = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return m[month - 1];
  }

  String _formatDateTime(DateTime dt) {
    final monthNames = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${monthNames[dt.month - 1]} ${dt.day}, ${dt.year}';
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// SWITCH BARBER SHEET — Stateful widget for barber list
// ═══════════════════════════════════════════════════════════════════════════

class _SwitchBarberSheet extends StatefulWidget {
  final Booking currentBooking;
  final BookingEngineService engine;
  final FirestoreService firestoreService;
  final void Function(BookingEngineResult) onSwitched;

  const _SwitchBarberSheet({
    required this.currentBooking,
    required this.engine,
    required this.firestoreService,
    required this.onSwitched,
  });

  @override
  State<_SwitchBarberSheet> createState() => _SwitchBarberSheetState();
}

class _SwitchBarberSheetState extends State<_SwitchBarberSheet> {
  List<Barber> _barbers = [];
  bool _loading = true;
  bool _switching = false;

  @override
  void initState() {
    super.initState();
    _loadBarbers();
  }

  Future<void> _loadBarbers() async {
    // Stream first snapshot of approved barbers
    try {
      final barbers = await widget.firestoreService.streamApprovedBarbers().first;
      if (mounted) {
        setState(() {
          _barbers = barbers
              .where((b) => b.id != widget.currentBooking.barberId)
              .toList();
          _loading = false;
        });
      }
    } catch (e) {
      // Don't spin forever on a Firestore error — fall through to the
      // "No other barbers available" empty state.
      debugPrint('⚠️ RerouteSheet: Failed to load barbers: $e');
      if (mounted) {
        setState(() {
          _barbers = [];
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.75,
      ),
      padding: const EdgeInsets.all(24),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Switch Barber',
            style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1A1A1A)),
          ),
          const SizedBox(height: 4),
          Text(
            'Price differences will be adjusted. Rescheduling will be locked after switching.',
            style: TextStyle(fontSize: 13, color: Colors.grey[600]),
          ),
          const SizedBox(height: 16),

          if (_loading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(40),
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else if (_barbers.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(40),
                child: Text(
                  'No other barbers available',
                  style: TextStyle(color: Colors.grey[600]),
                ),
              ),
            )
          else
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _barbers.length,
                itemBuilder: (_, i) => _buildBarberTile(_barbers[i]),
              ),
            ),

          SizedBox(height: MediaQuery.of(context).padding.bottom + 10),
        ],
      ),
    );
  }

  Widget _buildBarberTile(Barber barber) {
    final currentPrice = widget.currentBooking.pricePKR;
    final newPrice = barber.priceStartingPKR.toInt();
    final diff = newPrice - currentPrice;

    return GestureDetector(
      onTap: _switching
          ? null
          : () => _confirmSwitch(barber, newPrice),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.grey[50],
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.grey[200]!),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 26,
              backgroundImage: NetworkImage(barber.imageUrl),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    barber.name,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 15),
                  ),
                  if (barber.shopName != null)
                    Text(
                      barber.shopName!,
                      style:
                          TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                  Row(
                    children: [
                      const Icon(Icons.star, size: 14, color: Colors.amber),
                      const SizedBox(width: 2),
                      Text(
                        barber.rating.toStringAsFixed(1),
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'PKR $newPrice',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 15),
                ),
                if (diff != 0)
                  Text(
                    diff > 0 ? '+PKR $diff' : '-PKR ${diff.abs()}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: diff > 0 ? Colors.red : Colors.green,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _confirmSwitch(Barber barber, int newPrice) {
    final diff = newPrice - widget.currentBooking.pricePKR;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Switch to ${barber.name}?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (diff > 0)
              Text(
                  'You will be charged an additional PKR $diff.')
            else if (diff < 0)
              Text(
                  'You will receive PKR ${diff.abs()} back.')
            else
              const Text('No price change.'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.orange[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded,
                      color: Colors.orange[700], size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Rescheduling will be locked after this switch.',
                      style: TextStyle(
                          fontSize: 12, color: Colors.orange[800]),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              setState(() => _switching = true);

              final result = await widget.engine.switchBarber(
                widget.currentBooking.id,
                newBarber: barber,
                newPrice: newPrice,
              );

              if (mounted) {
                setState(() => _switching = false);
                Navigator.pop(context); // Close the sheet
                widget.onSwitched(result);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF9800),
              foregroundColor: Colors.white,
            ),
            child: const Text('Switch'),
          ),
        ],
      ),
    );
  }
}
