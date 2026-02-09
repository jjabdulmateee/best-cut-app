import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/barber.dart';
import '../models/barber_service.dart';
import '../models/slot.dart';
import '../data/user_data_provider.dart';
import '../services/firestore_service.dart';
import '../services/booking_engine_service.dart';
import 'booking_confirmation.dart';

class BookingScreen extends StatefulWidget {
  final Barber barber;

  const BookingScreen({super.key, required this.barber});

  @override
  State<BookingScreen> createState() => _BookingScreenState();
}

class _BookingScreenState extends State<BookingScreen> {
  final UserDataProvider _userDataProvider = UserDataProvider();
  final FirestoreService _firestoreService = FirestoreService();
  final BookingEngineService _bookingEngine = BookingEngineService();
  
  DateTime _selectedDate = DateTime.now();
  String? _selectedTimeSlot;
  Set<String> _bookedSlots = {};
  bool _isLoadingSlots = true;
  
  // Service selection
  List<BarberService> _availableServices = [];
  Set<String> _selectedServiceIds = {};
  bool _isLoadingServices = true;
  
  // Booking for family/friend
  bool _isBookingForOther = false;
  final TextEditingController _bookedForNameController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadBookedSlots();
    _loadServices();
  }

  @override
  void dispose() {
    _bookedForNameController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _loadServices() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('barberServices')
          .where('barberId', isEqualTo: widget.barber.id)
          .where('isEnabled', isEqualTo: true)
          .get();
      
      if (mounted) {
        setState(() {
          _availableServices = snap.docs
              .map((doc) => BarberService.fromMap(doc.data(), doc.id))
              .toList();
          _isLoadingServices = false;
        });
      }
    } catch (e) {
      print('⚠️ BookingScreen: Failed to load services: $e');
      if (mounted) {
        setState(() => _isLoadingServices = false);
      }
    }
  }

  Future<void> _loadBookedSlots() async {
    setState(() => _isLoadingSlots = true);
    
    final dateKey = '${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}';
    final slots = await _firestoreService.getBookedSlots(widget.barber.id, dateKey);
    
    if (mounted) {
      setState(() {
        _bookedSlots = slots;
        _isLoadingSlots = false;
        if (_selectedTimeSlot != null && slots.contains(_selectedTimeSlot)) {
          _selectedTimeSlot = null;
        }
      });
    }
  }

  int get _totalPrice {
    if (_selectedServiceIds.isEmpty) {
      return widget.barber.priceStartingPKR.toInt();
    }
    return _availableServices
        .where((s) => _selectedServiceIds.contains(s.id))
        .fold(0, (sum, s) => sum + s.pricePKR);
  }

  int get _totalDuration {
    if (_selectedServiceIds.isEmpty) return widget.barber.avgDurationMinutes;
    return _availableServices
        .where((s) => _selectedServiceIds.contains(s.id))
        .fold(0, (sum, s) => sum + s.durationMinutes);
  }

  @override
  Widget build(BuildContext context) {
    final barber = widget.barber;
    final isBookable = barber.isBookable;
    final walletBalance = _userDataProvider.customerWalletBalance;
    final price = _totalPrice;
    final hasEnoughBalance = walletBalance >= price;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Book Appointment',
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
      ),
      body: Column(
        children: [
          _buildBarberHeader(barber, isBookable),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!isBookable) _buildNotBookableWarning(barber),

                  // ── Service Selection ──
                  _buildServiceSelector(),
                  const SizedBox(height: 24),

                  // ── Date Selection ──
                  _buildDateSelector(),
                  const SizedBox(height: 24),

                  // ── Time Slots ──
                  _buildTimeSlots(barber),
                  const SizedBox(height: 24),

                  // ── Booking for Other ──
                  _buildBookingForOtherSection(),
                  const SizedBox(height: 24),

                  // Wallet Warning
                  if (!hasEnoughBalance && isBookable)
                    _buildInsufficientBalanceWarning(walletBalance, price),
                ],
              ),
            ),
          ),

          // Book Button
          _buildBookButton(barber, isBookable, hasEnoughBalance),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SERVICE SELECTOR — pick from barberServices collection
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildServiceSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Select Services',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            if (_selectedServiceIds.isNotEmpty)
              Text(
                '${_selectedServiceIds.length} selected',
                style: TextStyle(color: Colors.grey[600], fontSize: 13),
              ),
          ],
        ),
        const SizedBox(height: 12),

        if (_isLoadingServices)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          )
        else if (_availableServices.isEmpty)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Column(
                children: [
                  Icon(Icons.content_cut, size: 32, color: Colors.grey[400]),
                  const SizedBox(height: 8),
                  Text(
                    'No services listed yet',
                    style: TextStyle(color: Colors.grey[600], fontSize: 14),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Starting price: PKR ${widget.barber.priceStartingPKR.toInt()}',
                    style: TextStyle(
                      color: Colors.grey[500],
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          ..._availableServices.map((service) => _buildServiceTile(service)),
        
        // Price summary
        if (_selectedServiceIds.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A1A).withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Total: ${_selectedServiceIds.length} service(s) ~ $_totalDuration min',
                  style: TextStyle(color: Colors.grey[700], fontSize: 13),
                ),
                Text(
                  'PKR $_totalPrice',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Color(0xFF1A1A1A),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildServiceTile(BarberService service) {
    final isSelected = _selectedServiceIds.contains(service.id);
    return GestureDetector(
      onTap: () {
        setState(() {
          if (isSelected) {
            _selectedServiceIds.remove(service.id);
          } else {
            _selectedServiceIds.add(service.id);
          }
        });
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF1A1A1A).withValues(alpha: 0.06)
              : Colors.grey[50],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? const Color(0xFF1A1A1A) : Colors.grey[200]!,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            // Checkbox
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: isSelected ? const Color(0xFF1A1A1A) : Colors.white,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: isSelected
                      ? const Color(0xFF1A1A1A)
                      : Colors.grey[300]!,
                ),
              ),
              child: isSelected
                  ? const Icon(Icons.check, color: Colors.white, size: 16)
                  : null,
            ),
            const SizedBox(width: 12),
            // Emoji
            Text(service.emoji, style: const TextStyle(fontSize: 20)),
            const SizedBox(width: 10),
            // Name + duration
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    service.name,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: isSelected
                          ? const Color(0xFF1A1A1A)
                          : Colors.grey[800],
                    ),
                  ),
                  Text(
                    '${service.durationMinutes} min${service.isCombo ? ' • Combo' : ''}',
                    style: TextStyle(color: Colors.grey[500], fontSize: 12),
                  ),
                ],
              ),
            ),
            // Price
            Text(
              'PKR ${service.pricePKR}',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: isSelected
                    ? const Color(0xFF1A1A1A)
                    : Colors.grey[700],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // EXISTING WIDGETS (updated)
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildBarberHeader(Barber barber, bool isBookable) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        border: Border(bottom: BorderSide(color: Colors.grey[200]!)),
      ),
      child: Row(
        children: [
          Stack(
            children: [
              CircleAvatar(
                radius: 30,
                backgroundImage: NetworkImage(barber.imageUrl),
              ),
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    color: barber.statusColor,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      barber.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: barber.statusColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        barber.statusText,
                        style: TextStyle(
                          color: barber.statusColor,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                if (barber.shopName != null)
                  Text(
                    barber.shopName!,
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.access_time, size: 14, color: Colors.grey[500]),
                    const SizedBox(width: 4),
                    Text(
                      barber.formattedWorkingHours,
                      style: TextStyle(color: Colors.grey[600], fontSize: 12),
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
                _selectedServiceIds.isNotEmpty
                    ? 'PKR $_totalPrice'
                    : barber.formattedPrice,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
              if (_selectedServiceIds.isNotEmpty)
                Text(
                  '${_selectedServiceIds.length} service(s)',
                  style: TextStyle(color: Colors.grey[500], fontSize: 11),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNotBookableWarning(Barber barber) {
    String message;
    IconData icon;
    Color color;

    switch (barber.availabilityStatus) {
      case BarberAvailabilityStatus.offline:
        message = 'This barber is currently offline. You can still schedule for later.';
        icon = Icons.wifi_off;
        color = Colors.grey;
        break;
      case BarberAvailabilityStatus.closed:
        message = 'This shop is currently closed. Working hours: ${barber.formattedWorkingHours}';
        icon = Icons.schedule;
        color = Colors.red;
        break;
      case BarberAvailabilityStatus.dayOff:
        message = 'Today is this barber\'s day off. Please select another date.';
        icon = Icons.event_busy;
        color = Colors.orange;
        break;
      default:
        message = 'This barber is not available for booking right now.';
        icon = Icons.info_outline;
        color = Colors.grey;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: color, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDateSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Select Date',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 90,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: 14,
            itemBuilder: (context, index) {
              final date = DateTime.now().add(Duration(days: index));
              final isSelected = _selectedDate.day == date.day && 
                                 _selectedDate.month == date.month &&
                                 _selectedDate.year == date.year;
              final isDayOff = widget.barber.daysOff.contains(date.weekday);
              
              return GestureDetector(
                onTap: isDayOff ? null : () {
                  setState(() {
                    _selectedDate = date;
                    _selectedTimeSlot = null;
                  });
                  _loadBookedSlots();
                },
                child: Container(
                  width: 65,
                  margin: const EdgeInsets.only(right: 12),
                  decoration: BoxDecoration(
                    color: isSelected 
                        ? const Color(0xFF1A1A1A)
                        : isDayOff 
                            ? Colors.grey[200]
                            : Colors.grey[100],
                    borderRadius: BorderRadius.circular(12),
                    border: isSelected ? null : Border.all(
                      color: isDayOff ? Colors.grey[300]! : Colors.grey[200]!,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        _getDayName(date.weekday),
                        style: TextStyle(
                          color: isSelected 
                              ? Colors.white70 
                              : isDayOff ? Colors.grey[400] : Colors.grey[600],
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${date.day}',
                        style: TextStyle(
                          color: isSelected 
                              ? Colors.white 
                              : isDayOff ? Colors.grey[400] : Colors.black,
                          fontWeight: FontWeight.bold,
                          fontSize: 20,
                        ),
                      ),
                      if (isDayOff)
                        Text('Off', style: TextStyle(color: Colors.grey[400], fontSize: 10))
                      else
                        Text(
                          _getMonthName(date.month),
                          style: TextStyle(
                            color: isSelected ? Colors.white54 : Colors.grey[500],
                            fontSize: 10,
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildTimeSlots(Barber barber) {
    final slots = _getAvailableTimeSlots(barber);
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Select Time',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            if (_isLoadingSlots)
              const SizedBox(
                width: 16, height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (slots.isEmpty)
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Column(
                children: [
                  Icon(Icons.event_busy, size: 40, color: Colors.grey[400]),
                  const SizedBox(height: 12),
                  Text(
                    'No available slots for this date',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
          )
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              childAspectRatio: 2,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
            ),
            itemCount: slots.length,
            itemBuilder: (context, index) {
              final slot = slots[index];
              final isSelected = _selectedTimeSlot == slot;
              final isBooked = _bookedSlots.contains(slot);
              final isPast = _isSlotInPast(slot);
              final isDisabled = isBooked || isPast;
              
              return GestureDetector(
                onTap: isDisabled ? null : () {
                  setState(() => _selectedTimeSlot = slot);
                },
                child: Container(
                  decoration: BoxDecoration(
                    color: isSelected 
                        ? const Color(0xFF1A1A1A) 
                        : isBooked
                            ? Colors.red[50]
                            : isPast ? Colors.grey[200] : Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                    border: isBooked ? Border.all(color: Colors.red[200]!) : null,
                  ),
                  child: Stack(
                    children: [
                      Center(
                        child: Text(
                          slot,
                          style: TextStyle(
                            color: isSelected 
                                ? Colors.white 
                                : isDisabled ? Colors.grey[400] : Colors.black,
                            fontWeight: FontWeight.w500,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      if (isBooked)
                        Positioned(
                          top: 4, right: 4,
                          child: Container(
                            width: 8, height: 8,
                            decoration: const BoxDecoration(
                              color: Colors.red, shape: BoxShape.circle,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        
        if (_bookedSlots.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Row(
              children: [
                Container(
                  width: 10, height: 10,
                  decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
                Text('Already booked', style: TextStyle(color: Colors.grey[600], fontSize: 12)),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildBookingForOtherSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'Booking for someone else?',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const Spacer(),
            Switch(
              value: _isBookingForOther,
              onChanged: (value) {
                setState(() {
                  _isBookingForOther = value;
                  if (!value) {
                    _bookedForNameController.clear();
                    _notesController.clear();
                  }
                });
              },
              activeColor: const Color(0xFF1A1A1A),
            ),
          ],
        ),
        if (_isBookingForOther) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _bookedForNameController,
            decoration: InputDecoration(
              labelText: 'Name of person *',
              hintText: 'Enter their name',
              filled: true,
              fillColor: Colors.grey[100],
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              prefixIcon: const Icon(Icons.person_outline),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _notesController,
            maxLines: 2,
            decoration: InputDecoration(
              labelText: 'Special notes (optional)',
              hintText: 'Any preferences or instructions',
              filled: true,
              fillColor: Colors.grey[100],
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              prefixIcon: const Icon(Icons.note_outlined),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Payment will be deducted from your wallet',
            style: TextStyle(color: Colors.grey[600], fontSize: 12),
          ),
        ],
      ],
    );
  }

  Widget _buildInsufficientBalanceWarning(int balance, int price) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.red[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red[200]!),
      ),
      child: Row(
        children: [
          const Icon(Icons.account_balance_wallet, color: Colors.red),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Insufficient wallet balance',
                  style: TextStyle(color: Colors.red, fontWeight: FontWeight.w600),
                ),
                Text(
                  'Current: PKR $balance | Required: PKR $price',
                  style: const TextStyle(color: Colors.red, fontSize: 12),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Add Funds'),
          ),
        ],
      ),
    );
  }

  Widget _buildBookButton(Barber barber, bool isBookable, bool hasEnoughBalance) {
    final canBook = _selectedTimeSlot != null && 
                    hasEnoughBalance && 
                    (!_isBookingForOther || _bookedForNameController.text.trim().isNotEmpty);

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
          children: [
            if (_selectedTimeSlot != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${_formatDate(_selectedDate)} at $_selectedTimeSlot',
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                    Text(
                      'PKR $_totalPrice',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ],
                ),
              ),
            SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton(
                onPressed: canBook ? _confirmBooking : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1A1A1A),
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.grey[300],
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  _getButtonText(hasEnoughBalance),
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────── Helpers ───────────────────────

  String _getButtonText(bool hasEnoughBalance) {
    if (!hasEnoughBalance) return 'Insufficient Balance';
    if (_selectedTimeSlot == null) return 'Select a Time Slot';
    if (_isBookingForOther && _bookedForNameController.text.trim().isEmpty) {
      return 'Enter Name';
    }
    return 'Confirm Booking — PKR $_totalPrice';
  }

  String _getDayName(int weekday) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return days[weekday - 1];
  }

  String _getMonthName(int month) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return months[month - 1];
  }

  String _formatDate(DateTime date) {
    return '${_getDayName(date.weekday)}, ${date.day} ${_getMonthName(date.month)}';
  }

  List<String> _getAvailableTimeSlots(Barber barber) {
    final slots = <String>[];
    final startParts = barber.workStartHour.split(':');
    final endParts = barber.workEndHour.split(':');
    final startHour = int.tryParse(startParts[0]) ?? 9;
    final endHour = int.tryParse(endParts[0]) ?? 22;
    
    for (int hour = startHour; hour < endHour; hour++) {
      slots.add('${hour.toString().padLeft(2, '0')}:00');
      slots.add('${hour.toString().padLeft(2, '0')}:30');
    }
    return slots;
  }

  bool _isSlotInPast(String slot) {
    final now = DateTime.now();
    final isToday = _selectedDate.day == now.day && 
                    _selectedDate.month == now.month &&
                    _selectedDate.year == now.year;
    if (!isToday) return false;
    
    final parts = slot.split(':');
    final slotHour = int.tryParse(parts[0]) ?? 0;
    final slotMinute = int.tryParse(parts[1]) ?? 0;
    
    return slotHour < now.hour || 
           (slotHour == now.hour && slotMinute <= now.minute);
  }

  void _confirmBooking() {
    final barber = widget.barber;
    final parts = _selectedTimeSlot!.split(':');
    final hour = int.parse(parts[0]);
    final minute = int.parse(parts[1]);
    
    final bookingDateTime = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      hour,
      minute,
    );

    // Gather selected service names for display
    final selectedNames = _availableServices
        .where((s) => _selectedServiceIds.contains(s.id))
        .map((s) => s.name)
        .toList();

    final booking = Booking(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      barberId: barber.id,
      barberName: barber.name,
      shopName: barber.shopName,
      barberImageUrl: barber.imageUrl,
      barberAddress: barber.address,
      bookingDateTime: bookingDateTime,
      timeSlot: _selectedTimeSlot!,
      pricePKR: _totalPrice,
      status: BookingStatus.pending,
      createdAt: DateTime.now(),
      customerId: _userDataProvider.userId,
      customerName: _userDataProvider.customerName,
      customerImageUrl: _userDataProvider.customerImageUrl,
      customerRatingScore: _userDataProvider.customerRating,
      isBookingForOther: _isBookingForOther,
      bookedForName: _isBookingForOther ? _bookedForNameController.text.trim() : null,
      bookedForNotes: _isBookingForOther && _notesController.text.trim().isNotEmpty 
          ? _notesController.text.trim() 
          : null,
      selectedServices: selectedNames,
      serviceIds: _selectedServiceIds.toList(),
    );

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => BookingConfirmationScreen(
          barber: barber.copyWith(calculatedDistance: barber.calculatedDistance),
          booking: booking,
        ),
      ),
    );
  }
}
