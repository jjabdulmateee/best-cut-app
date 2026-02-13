import 'package:flutter/material.dart';
import '../models/slot.dart';
import '../models/barber.dart';
import '../services/booking_engine_service.dart';

// ============================================================================
// REROUTE BARBER SELECTION SCREEN — Phase 4
// ============================================================================
//
// Opened when customer chooses "Find Another Barber" from reroute options.
// Shows all eligible barbers (approved, valid serviceMode).
// Does NOT hide bad barbers — Uber shows everyone, user decides.
// Sorted by: rating, then availability.
//
// On selection: calls BookingEngineService.rerouteBooking()
//   - Updates barberId in same booking document
//   - Resets assignment timer (30 min)
//   - Increments rerouteCount
//   - Escrow untouched
// ============================================================================

class RerouteBarberSelectionScreen extends StatefulWidget {
  final Booking booking;

  const RerouteBarberSelectionScreen({super.key, required this.booking});

  @override
  State<RerouteBarberSelectionScreen> createState() =>
      _RerouteBarberSelectionScreenState();
}

class _RerouteBarberSelectionScreenState
    extends State<RerouteBarberSelectionScreen> {
  final BookingEngineService _engine = BookingEngineService();
  List<Barber>? _barbers;
  bool _isLoading = true;
  bool _isRerouting = false;
  String? _selectedBarberId;

  @override
  void initState() {
    super.initState();
    _loadEligibleBarbers();
  }

  Future<void> _loadEligibleBarbers() async {
    setState(() => _isLoading = true);

    final barbers = await _engine.getEligibleBarbersForReroute(
      currentBarberId: widget.booking.barberId,
      serviceMode: widget.booking.serviceMode,
    );

    if (mounted) {
      setState(() {
        _barbers = barbers;
        _isLoading = false;
      });
    }
  }

  Future<void> _rerouteToBarber(Barber barber) async {
    setState(() {
      _isRerouting = true;
      _selectedBarberId = barber.id;
    });

    final result = await _engine.rerouteBooking(
      widget.booking.id,
      newBarber: barber,
    );

    if (mounted) {
      setState(() => _isRerouting = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(
                result.success ? Icons.check_circle : Icons.error,
                color: Colors.white,
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(result.message)),
            ],
          ),
          backgroundColor: result.success ? const Color(0xFF00C853) : Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );

      if (result.success) {
        Navigator.pop(context, true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final reroutesLeft = BookingEngineService.maxReroutes - widget.booking.rerouteCount;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF1A1A1A)),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Choose a New Barber',
          style: TextStyle(
            color: Color(0xFF1A1A1A),
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
      ),
      body: Column(
        children: [
          // ── Info Banner ──
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: Colors.blue.withValues(alpha: 0.05),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.info_outline, color: Colors.blue, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Your payment is safe',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1A1A1A),
                        ),
                      ),
                      Text(
                        'PKR ${widget.booking.pricePKR} escrow stays untouched. '
                        '$reroutesLeft reroute(s) remaining.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── Barber List ──
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _barbers == null || _barbers!.isEmpty
                    ? _buildEmptyState()
                    : RefreshIndicator(
                        onRefresh: _loadEligibleBarbers,
                        child: ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _barbers!.length,
                          itemBuilder: (context, index) =>
                              _buildBarberCard(_barbers![index]),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            const Text(
              'No Available Barbers',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1A1A1A),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'No eligible barbers are available right now. '
              'You can try again later or cancel for a refund.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.grey[600]),
            ),
            const SizedBox(height: 24),
            OutlinedButton(
              onPressed: _loadEligibleBarbers,
              child: const Text('Refresh'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBarberCard(Barber barber) {
    final isSelected = _selectedBarberId == barber.id;
    final isOnline = barber.isOnline;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: isSelected
            ? Border.all(color: const Color(0xFF1A1A1A), width: 2)
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
          Row(
            children: [
              // Avatar
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  color: Colors.grey[200],
                  image: barber.imageUrl.isNotEmpty && barber.imageUrl.startsWith('http')
                      ? DecorationImage(
                          image: NetworkImage(barber.imageUrl),
                          fit: BoxFit.cover,
                        )
                      : null,
                ),
                child: !barber.imageUrl.startsWith('http')
                    ? const Icon(Icons.content_cut, color: Colors.grey)
                    : null,
              ),
              const SizedBox(width: 14),
              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            barber.name,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF1A1A1A),
                            ),
                          ),
                        ),
                        // Online indicator
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: isOnline
                                ? const Color(0xFF00C853).withValues(alpha: 0.1)
                                : Colors.grey.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: isOnline ? const Color(0xFF00C853) : Colors.grey,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                isOnline ? 'Online' : 'Offline',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: isOnline ? const Color(0xFF00C853) : Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (barber.shopName != null && barber.shopName!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        barber.shopName!,
                        style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                      ),
                    ],
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(Icons.star, color: Color(0xFFFFB800), size: 16),
                        const SizedBox(width: 4),
                        Text(
                          barber.rating.toStringAsFixed(1),
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF1A1A1A),
                          ),
                        ),
                        Text(
                          ' (${barber.reviewsCount})',
                          style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                        ),
                        const SizedBox(width: 16),
                        if (barber.address != null) ...[
                          Icon(Icons.location_on, size: 14, color: Colors.grey[500]),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              barber.address!,
                              style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Select button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isRerouting
                  ? null
                  : () => _rerouteToBarber(barber),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1A1A1A),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: isSelected && _isRerouting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation(Colors.white),
                      ),
                    )
                  : const Text(
                      'Select This Barber',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
