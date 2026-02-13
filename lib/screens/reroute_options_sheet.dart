import 'package:flutter/material.dart';
import '../models/slot.dart';
import '../services/booking_engine_service.dart';
import 'reroute_barber_selection_screen.dart';

// ============================================================================
// REROUTE OPTIONS BOTTOM SHEET — Phase 4
// ============================================================================
//
// Triggered when booking.assignmentExpired == true
// Shows the customer two choices:
//   1. Cancel Booking (refund rules from Phase 1 apply)
//   2. Find Another Barber (opens barber selection)
//
// UI guarantees: visible, clear text, action buttons, real Firestore data
// ============================================================================

/// Show the reroute options bottom sheet for an expired assignment.
/// Returns true if the customer chose to cancel, false otherwise.
Future<bool?> showRerouteOptionsSheet(
  BuildContext context,
  Booking booking,
) async {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    isDismissible: false,
    enableDrag: false,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _RerouteOptionsSheet(booking: booking),
  );
}

class _RerouteOptionsSheet extends StatefulWidget {
  final Booking booking;

  const _RerouteOptionsSheet({required this.booking});

  @override
  State<_RerouteOptionsSheet> createState() => _RerouteOptionsSheetState();
}

class _RerouteOptionsSheetState extends State<_RerouteOptionsSheet> {
  final BookingEngineService _engine = BookingEngineService();
  bool _isCancelling = false;

  Future<void> _handleCancel() async {
    setState(() => _isCancelling = true);

    final result = await _engine.cancelBooking(
      widget.booking.id,
      reason: 'Cancelled after barber did not respond',
    );

    if (mounted) {
      setState(() => _isCancelling = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.message),
          backgroundColor: result.success ? const Color(0xFF4CAF50) : Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );

      Navigator.pop(context, true); // true = cancelled
    }
  }

  void _handleFindAnotherBarber() {
    Navigator.pop(context, false); // close sheet
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RerouteBarberSelectionScreen(booking: widget.booking),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canReroute = widget.booking.canReroute;
    final reroutesUsed = widget.booking.rerouteCount;
    final reroutesLeft = BookingEngineService.maxReroutes - reroutesUsed;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Handle ──
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 24),

              // ── Icon + Title ──
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.schedule,
                  color: Colors.orange,
                  size: 32,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Barber Didn\'t Respond',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1A1A1A),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'The barber didn\'t respond within the 30-minute window. '
                'Your payment is safe and untouched.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 20),

              // ── Booking Summary ──
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey[200]!),
                ),
                child: Column(
                  children: [
                    _summaryRow('Service', widget.booking.selectedServices.isNotEmpty
                        ? widget.booking.selectedServices.join(', ')
                        : 'Haircut'),
                    const SizedBox(height: 8),
                    _summaryRow('Appointment', '${widget.booking.shortDate} at ${widget.booking.timeSlot}'),
                    const SizedBox(height: 8),
                    _summaryRow('Escrow Amount', 'PKR ${widget.booking.pricePKR}',
                        valueColor: const Color(0xFF4CAF50)),
                    if (reroutesUsed > 0) ...[
                      const SizedBox(height: 8),
                      _summaryRow('Reroutes Used', '$reroutesUsed of ${BookingEngineService.maxReroutes}',
                          valueColor: Colors.orange),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // ── Action Buttons ──

              // 1. Find Another Barber
              if (canReroute) ...[
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _handleFindAnotherBarber,
                    icon: const Icon(Icons.search, size: 20),
                    label: Text('Find Another Barber ($reroutesLeft left)'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1A1A1A),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      textStyle: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ] else ...[
                // Max reroutes reached message
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.red.withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline, color: Colors.red, size: 20),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'We couldn\'t find a barber in time. You can cancel for a refund.',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.red[700],
                            height: 1.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],

              // 2. Cancel Booking
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _isCancelling ? null : _handleCancel,
                  icon: _isCancelling
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.close, size: 20),
                  label: Text(_isCancelling ? 'Cancelling...' : 'Cancel Booking'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    side: const BorderSide(color: Colors.red),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _summaryRow(String label, String value, {Color? valueColor}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 13, color: Colors.grey[600]),
        ),
        Flexible(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: valueColor ?? const Color(0xFF1A1A1A),
            ),
            textAlign: TextAlign.end,
          ),
        ),
      ],
    );
  }
}
