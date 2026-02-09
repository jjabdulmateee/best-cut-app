import 'package:flutter/material.dart';
import '../models/barber.dart';
import '../models/slot.dart';
import '../data/user_data_provider.dart';
import '../data/app_data.dart' show PaymentMethod, EscrowStatus;
import '../services/firestore_service.dart';
import '../services/booking_engine_service.dart';
import '../widgets/admin_override_indicator.dart';
import '../screens/dispute_creation_screen.dart';

class BookingConfirmationScreen extends StatefulWidget {
  final Barber barber;
  final Booking booking;

  const BookingConfirmationScreen({
    super.key,
    required this.barber,
    required this.booking,
  });

  @override
  State<BookingConfirmationScreen> createState() =>
      _BookingConfirmationScreenState();
}

class _BookingConfirmationScreenState extends State<BookingConfirmationScreen> {
  bool _isLoading = false;
  final UserDataProvider _userDataProvider = UserDataProvider();
  final FirestoreService _firestoreService = FirestoreService();
  PaymentMethod _selectedPaymentMethod = PaymentMethod.wallet;
  String? _errorMessage;

  @override
  Widget build(BuildContext context) {
    final booking = widget.booking;
    final barber = widget.barber;
    final walletBalance = _userDataProvider.customerWalletBalance;
    final hasEnoughBalance = walletBalance >= booking.pricePKR;

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
          'Confirm Booking',
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
            // Barber Card
            _buildBarberCard(barber),
            const SizedBox(height: 20),

            // Booking Details
            _buildBookingDetails(booking),
            const SizedBox(height: 20),

            // Admin Protection Notice
            Container(
              padding: const EdgeInsets.all(16),
              margin: const EdgeInsets.symmetric(horizontal: 16),
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
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.verified_user,
                        color: const Color(0xFF2196F3),
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Admin Protected Booking',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF2196F3),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Your booking is monitored and protected by Best Cut administrators. We ensure safe transactions and can intervene if any issues arise.',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey[700],
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Escrow Status (for completed bookings)
            if (booking.status == BookingStatus.completed) ...[
              EscrowStatusBanner(
                status: booking.escrowStatus ?? EscrowStatus.released,
                amount: booking.pricePKR,
              ),
              const SizedBox(height: 20),
            ],

            // Dispute Status (if dispute exists)
            if (booking.hasActiveDispute) ...[
              Container(
                padding: const EdgeInsets.all(16),
                margin: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF3E0),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFFF9800).withOpacity(0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.gavel,
                          color: const Color(0xFFFF9800),
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                booking.disputeStatusText,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: const Color(0xFFFF9800),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Your dispute is being reviewed by Best Cut admin',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[700],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],

            // Dispute Option (for eligible bookings)
            if (_userDataProvider.canDisputeBooking(booking.id) &&
                !booking.hasActiveDispute) ...[
              Container(
                padding: const EdgeInsets.all(16),
                margin: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey[300]!),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.help_outline,
                          color: Colors.grey[600],
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Not satisfied?',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey[800],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'If you have concerns about this booking, you can file a dispute. Our admin team will review and resolve the matter.',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey[700],
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: () async {
                          final result = await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => DisputeCreationScreen(booking: booking),
                            ),
                          );

                          if (result == true && mounted) {
                            // Refresh booking data
                            setState(() {});
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Dispute submitted. You will be notified of the outcome.'),
                                backgroundColor: Color(0xFF4CAF50),
                              ),
                            );
                          }
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFFFF9800),
                          side: const BorderSide(color: Color(0xFFFF9800)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: const Text('File Dispute'),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],

            // Booking for someone else section
            if (booking.isBookingForOther) ...[
              _buildBookingForOtherInfo(booking),
              const SizedBox(height: 20),
            ],

            // Price Summary
            _buildPriceSummary(booking, walletBalance),
            const SizedBox(height: 20),

            // Support Section
            Container(
              padding: const EdgeInsets.all(16),
              margin: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF8E1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: const Color(0xFFFFB800).withOpacity(0.3),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.help_outline,
                        color: const Color(0xFFFF9800),
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Need Help?',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFFFF9800),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Questions about your booking or need to make changes? Contact our support team.',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey[700],
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            // TODO: Open support chat or email
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Contact support@bestcut.pk for assistance'),
                                duration: Duration(seconds: 3),
                              ),
                            );
                          },
                          icon: const Icon(Icons.email_outlined, size: 16),
                          label: const Text('Contact Support'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFFFF9800),
                            side: const BorderSide(color: Color(0xFFFF9800)),
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            textStyle: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Cancellation Policy
            _buildCancellationPolicy(),
            const SizedBox(height: 20),

            // Payment Method
            _buildPaymentMethod(hasEnoughBalance),
            
            // Error Message
            if (_errorMessage != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red[200]!),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: Colors.red, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: const TextStyle(color: Colors.red, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            
            const SizedBox(height: 100),
          ],
        ),
      ),
      bottomSheet: _buildBottomBar(booking, hasEnoughBalance),
    );
  }

  Widget _buildBarberCard(Barber barber) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFEEEEEE)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          // Barber Image
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.network(
              barber.imageUrl,
              width: 70,
              height: 70,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => Container(
                width: 70,
                height: 70,
                color: Colors.grey[200],
                child: const Icon(Icons.person, color: Colors.grey),
              ),
            ),
          ),
          const SizedBox(width: 16),
          // Barber Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  barber.name,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1A1A1A),
                  ),
                ),
                const SizedBox(height: 4),
                if (barber.shopName != null)
                  Text(
                    barber.shopName!,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey[600],
                    ),
                  ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.star, color: Colors.amber, size: 16),
                    const SizedBox(width: 4),
                    Text(
                      barber.rating.toStringAsFixed(1),
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '(${barber.reviewsCount} reviews)',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[500],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Status badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: barber.statusColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: barber.statusColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  barber.statusText,
                  style: TextStyle(
                    color: barber.statusColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBookingDetails(Booking booking) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          _buildDetailRow(
            Icons.calendar_today_outlined,
            'Date',
            booking.formattedDate,
          ),
          const Divider(height: 24),
          _buildDetailRow(
            Icons.access_time,
            'Time',
            booking.timeSlot,
          ),
          const Divider(height: 24),
          _buildDetailRow(
            Icons.timer_outlined,
            'Duration',
            '~${widget.barber.avgDurationMinutes} minutes',
          ),
          if (widget.barber.address != null) ...[
            const Divider(height: 24),
            _buildDetailRow(
              Icons.location_on_outlined,
              'Location',
              widget.barber.address!,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBookingForOtherInfo(Booking booking) {
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
              Icon(Icons.people_outline, color: Colors.blue[700], size: 20),
              const SizedBox(width: 8),
              Text(
                'Booking for Someone Else',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: Colors.blue[700],
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildInfoRow('Name', booking.bookedForName ?? 'N/A'),
          if (booking.bookedForNotes != null && booking.bookedForNotes!.isNotEmpty) ...[
            const SizedBox(height: 8),
            _buildInfoRow('Notes', booking.bookedForNotes!),
          ],
          const SizedBox(height: 8),
          Text(
            'Payment will be deducted from your wallet',
            style: TextStyle(
              color: Colors.blue[600],
              fontSize: 12,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 60,
          child: Text(
            label,
            style: TextStyle(
              color: Colors.blue[700],
              fontSize: 13,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: const Color(0xFF1A1A1A), size: 20),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[500],
              ),
            ),
            Text(
              value,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1A1A1A),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPriceSummary(Booking booking, int walletBalance) {
    final hasEnoughBalance = walletBalance >= booking.pricePKR;
    
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
            'Price Summary',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1A1A1A),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Service fee', style: TextStyle(color: Colors.grey[600])),
              Text('PKR ${booking.pricePKR}',
                  style: const TextStyle(fontWeight: FontWeight.w500)),
            ],
          ),
          const Divider(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Total',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
              Text('PKR ${booking.pricePKR}',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 18)),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: hasEnoughBalance ? Colors.green[50] : Colors.red[50],
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.account_balance_wallet,
                  size: 16,
                  color: hasEnoughBalance ? Colors.green[700] : Colors.red[700],
                ),
                const SizedBox(width: 8),
                Text(
                  'Wallet Balance: PKR $walletBalance',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: hasEnoughBalance ? Colors.green[700] : Colors.red[700],
                  ),
                ),
                if (!hasEnoughBalance) ...[
                  const Spacer(),
                  Text(
                    'Insufficient',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.red[700],
                      fontWeight: FontWeight.w600,
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

  Widget _buildCancellationPolicy() {
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
              Icon(Icons.info_outline, color: Colors.orange[700], size: 20),
              const SizedBox(width: 8),
              Text(
                'Cancellation Policy',
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
            '• Max 2 reschedules per booking\n'
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

  Widget _buildPaymentMethod(bool hasEnoughBalance) {
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
            'Payment Method',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1A1A1A),
            ),
          ),
          const SizedBox(height: 16),
          _buildPaymentOption(
            PaymentMethod.wallet,
            'Best Cut Wallet',
            Icons.account_balance_wallet,
            subtitle: hasEnoughBalance ? 'Recommended' : 'Insufficient balance',
            enabled: hasEnoughBalance,
          ),
          const SizedBox(height: 12),
          _buildPaymentOption(
            PaymentMethod.cash,
            'Cash Payment',
            Icons.payments_outlined,
            subtitle: 'Pay at the shop',
            enabled: true,
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentOption(
    PaymentMethod method,
    String title,
    IconData icon, {
    String? subtitle,
    bool enabled = true,
  }) {
    final isSelected = _selectedPaymentMethod == method;
    
    return GestureDetector(
      onTap: enabled
          ? () {
              setState(() {
                _selectedPaymentMethod = method;
              });
            }
          : null,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF1A1A1A).withValues(alpha: 0.05) : Colors.grey[50],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? const Color(0xFF1A1A1A) : Colors.grey[200]!,
            width: isSelected ? 2 : 1,
          ),
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
                color: enabled ? const Color(0xFF1A1A1A) : Colors.grey,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                      color: enabled ? const Color(0xFF1A1A1A) : Colors.grey,
                    ),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: enabled ? Colors.grey[600] : Colors.grey,
                      ),
                    ),
                ],
              ),
            ),
            if (isSelected)
              Container(
                width: 24,
                height: 24,
                decoration: const BoxDecoration(
                  color: Color(0xFF1A1A1A),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check, color: Colors.white, size: 16),
              )
            else
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey[300]!),
                  shape: BoxShape.circle,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBar(Booking booking, bool hasEnoughBalance) {
    final paymentValid = _selectedPaymentMethod == PaymentMethod.cash || hasEnoughBalance;
    final actionsLocked = _userDataProvider.areBookingActionsLocked(booking.id);
    final canConfirm = paymentValid && !actionsLocked;
    
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Lock state banner
            if (actionsLocked) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                color: const Color(0xFFFFF3E0),
                child: Row(
                  children: [
                    Icon(
                      Icons.lock_outline,
                      color: const Color(0xFFFF9800),
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _userDataProvider.getBookingLockReason(booking.id) ?? 'Booking actions are currently disabled',
                        style: TextStyle(
                          fontSize: 14,
                          color: const Color(0xFFFF9800),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton(
            onPressed: canConfirm && !_isLoading ? _confirmBooking : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1A1A1A),
              foregroundColor: Colors.white,
              disabledBackgroundColor: Colors.grey[300],
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: _isLoading
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : Text(
                    actionsLocked
                        ? 'Booking Locked'
                        : canConfirm
                            ? 'Confirm & Pay PKR ${booking.pricePKR}'
                            : 'Add Funds to Wallet',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
          ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmBooking() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final booking = widget.booking;
      final engine = BookingEngineService();

      // Create booking via the Booking Engine (Phase 1)
      final result = await engine.createBooking(
        barberId: booking.barberId,
        serviceIds: booking.serviceIds.isNotEmpty
            ? booking.serviceIds
            : ['default'],
        appointmentTime: booking.bookingDateTime,
        timeSlot: booking.timeSlot,
        totalPrice: booking.pricePKR,
        barberName: booking.barberName,
        shopName: booking.shopName,
        barberImageUrl: booking.barberImageUrl,
        barberAddress: booking.barberAddress,
        paymentMethod: _selectedPaymentMethod.name,
        isBookingForOther: booking.isBookingForOther,
        bookedForName: booking.bookedForName,
        bookedForNotes: booking.bookedForNotes,
        selectedServiceNames: booking.selectedServices,
      );

      if (!result.success) {
        setState(() {
          _errorMessage = result.message;
        });
        return;
      }

      // Deduct from wallet if payment method is wallet
      if (_selectedPaymentMethod == PaymentMethod.wallet) {
        final paymentResult = await _userDataProvider.payFromWallet(
          booking.pricePKR,
          result.bookingId ?? booking.id,
          'Booking payment - ${widget.barber.name}',
        );

        if (!paymentResult.isSuccess) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(paymentResult.userMessage ?? 'Payment failed'),
                backgroundColor: Colors.red,
                duration: const Duration(seconds: 5),
                action: paymentResult.supportSuggestion != null
                    ? SnackBarAction(
                        label: 'Help',
                        textColor: Colors.white,
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(paymentResult.supportSuggestion!),
                              duration: const Duration(seconds: 10),
                            ),
                          );
                        },
                      )
                    : null,
              ),
            );
          }
          return;
        }
      }

      if (mounted) {
        // Show success dialog
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: const BoxDecoration(
                    color: Color(0xFF00C853),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.check, color: Colors.white, size: 40),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Booking Confirmed!',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Your appointment with ${widget.barber.name} on ${booking.formattedDate} at ${booking.timeSlot} has been confirmed.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 14,
                  ),
                ),
                if (booking.isBookingForOther) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Booked for: ${booking.bookedForName}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ],
              ],
            ),
            actions: [
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pop(); // Close dialog
                    Navigator.of(context).popUntil((route) => route.isFirst); // Go to home
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1A1A1A),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Done',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to create booking. Please try again.';
      });
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }
}


