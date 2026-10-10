import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/slot.dart';
import '../models/customer.dart';

/// Global app data store (simulated state management)
/// In production, this would be replaced with proper state management
class AppData extends ChangeNotifier {
  static final AppData _instance = AppData._internal();
  factory AppData() => _instance;
  AppData._internal() {
    // Initialize demo bookings for barber mode
    _initializeDemoBookings();
  }
  
  void _initializeDemoBookings() {
    final now = DateTime.now();
    
    // Demo bookings for barber (Ahmed Khan - id: '1')
    _bookings.addAll([
      // Upcoming booking - today
      Booking(
        id: 'demo_1',
        barberId: '1',
        barberName: 'Ahmed Khan',
        shopName: 'Royal Cuts',
        barberImageUrl: 'https://i.pravatar.cc/150?img=11',
        barberAddress: 'F-7 Markaz, Islamabad',
        bookingDateTime: DateTime(now.year, now.month, now.day, 14, 0),
        timeSlot: '2:00 PM',
        pricePKR: 450,
        status: BookingStatus.confirmed,
        createdAt: now.subtract(const Duration(hours: 2)),
        paymentMethod: PaymentMethod.wallet,
        customerId: 'c1',
        customerName: 'Ali Hassan',
        customerImageUrl: 'https://i.pravatar.cc/150?img=33',
        customerRatingScore: 4.5,
      ),
      // Upcoming booking - today
      Booking(
        id: 'demo_2',
        barberId: '1',
        barberName: 'Ahmed Khan',
        shopName: 'Royal Cuts',
        barberImageUrl: 'https://i.pravatar.cc/150?img=11',
        barberAddress: 'F-7 Markaz, Islamabad',
        bookingDateTime: DateTime(now.year, now.month, now.day, 15, 30),
        timeSlot: '3:30 PM',
        pricePKR: 350,
        status: BookingStatus.confirmed,
        createdAt: now.subtract(const Duration(hours: 1)),
        paymentMethod: PaymentMethod.jazzcash,
        customerId: 'c2',
        customerName: 'Usman Khan',
        customerImageUrl: 'https://i.pravatar.cc/150?img=52',
        customerRatingScore: 4.8,
      ),
      // Upcoming booking - tomorrow
      Booking(
        id: 'demo_3',
        barberId: '1',
        barberName: 'Ahmed Khan',
        shopName: 'Royal Cuts',
        barberImageUrl: 'https://i.pravatar.cc/150?img=11',
        barberAddress: 'F-7 Markaz, Islamabad',
        bookingDateTime: DateTime(now.year, now.month, now.day + 1, 10, 0),
        timeSlot: '10:00 AM',
        pricePKR: 500,
        status: BookingStatus.confirmed,
        createdAt: now.subtract(const Duration(hours: 5)),
        paymentMethod: PaymentMethod.easypaisa,
        customerId: 'c3',
        customerName: 'Fahad Ali',
        customerImageUrl: 'https://i.pravatar.cc/150?img=57',
        customerRatingScore: 3.5,
      ),
      // Completed booking - yesterday
      Booking(
        id: 'demo_4',
        barberId: '1',
        barberName: 'Ahmed Khan',
        shopName: 'Royal Cuts',
        barberImageUrl: 'https://i.pravatar.cc/150?img=11',
        barberAddress: 'F-7 Markaz, Islamabad',
        bookingDateTime: now.subtract(const Duration(days: 1)),
        timeSlot: '11:00 AM',
        pricePKR: 400,
        status: BookingStatus.completed,
        createdAt: now.subtract(const Duration(days: 1, hours: 3)),
        paymentMethod: PaymentMethod.wallet,
        customerId: 'c1',
        customerName: 'Ali Hassan',
        customerImageUrl: 'https://i.pravatar.cc/150?img=33',
        customerRatingScore: 4.5,
        customerRating: 5,
        customerRatingComment: 'Great customer, very punctual!',
      ),
      // Cancelled booking
      Booking(
        id: 'demo_5',
        barberId: '1',
        barberName: 'Ahmed Khan',
        shopName: 'Royal Cuts',
        barberImageUrl: 'https://i.pravatar.cc/150?img=11',
        barberAddress: 'F-7 Markaz, Islamabad',
        bookingDateTime: now.subtract(const Duration(days: 2)),
        timeSlot: '3:00 PM',
        pricePKR: 350,
        status: BookingStatus.cancelledByCustomer,
        createdAt: now.subtract(const Duration(days: 2, hours: 5)),
        paymentMethod: PaymentMethod.wallet,
        customerId: 'c3',
        customerName: 'Fahad Ali',
        customerImageUrl: 'https://i.pravatar.cc/150?img=57',
        customerRatingScore: 3.5,
        cancellationReason: 'Cancelled by customer',
        cancelledBy: 'customer',
      ),
    ]);
  }

  // ==================== CUSTOMER DATA ====================
  
  // Customer Wallet Balance
  int _walletBalance = 5000; // PKR
  int get walletBalance => _walletBalance;

  // ==================== BARBER DATA ====================
  
  // Current logged-in barber (simulated - using first barber as default)
  final String _currentBarberId = '1';
  String get currentBarberId => _currentBarberId;
  
  // Barber Online Status
  bool _isBarberOnline = false;
  bool get isBarberOnline => _isBarberOnline;
  
  // Barber Wallet Balance
  int _barberWalletBalance = 12500; // PKR
  int get barberWalletBalance => _barberWalletBalance;
  
  // Barber Working Hours
  int _workStartHour = 9;
  int _workEndHour = 18;
  int _slotDurationMinutes = 30;
  int get workStartHour => _workStartHour;
  int get workEndHour => _workEndHour;
  int get slotDurationMinutes => _slotDurationMinutes;
  
  // Barber Transactions
  final List<BarberTransaction> _barberTransactions = [
    BarberTransaction(
      id: '1',
      type: BarberTransactionType.earning,
      amount: 500,
      description: 'Haircut - Hassan Ali',
      createdAt: DateTime.now().subtract(const Duration(days: 1)),
    ),
    BarberTransaction(
      id: '2',
      type: BarberTransactionType.earning,
      amount: 450,
      description: 'Haircut + Beard - Usman Khan',
      createdAt: DateTime.now().subtract(const Duration(days: 1)),
    ),
    BarberTransaction(
      id: '3',
      type: BarberTransactionType.withdrawal,
      amount: 5000,
      description: 'Withdrawal to JazzCash',
      createdAt: DateTime.now().subtract(const Duration(days: 3)),
    ),
    BarberTransaction(
      id: '4',
      type: BarberTransactionType.earning,
      amount: 600,
      description: 'Premium Cut - Bilal Ahmed',
      createdAt: DateTime.now().subtract(const Duration(days: 3)),
    ),
    BarberTransaction(
      id: '5',
      type: BarberTransactionType.earning,
      amount: 350,
      description: 'Haircut - Kamran Shahid',
      createdAt: DateTime.now().subtract(const Duration(days: 5)),
    ),
  ];
  List<BarberTransaction> get barberTransactions => List.unmodifiable(_barberTransactions);
  
  // Barber Slot Availability (day -> slot index -> available)
  final Map<String, Set<int>> _closedSlots = {};
  
  // Customers database (for barber to rate)
  final Map<String, Customer> _customers = {
    'c1': const Customer(
      id: 'c1',
      name: 'Ali Hassan',
      phoneNumber: '0300****123',
      imageUrl: 'https://i.pravatar.cc/150?img=33',
      rating: 4.5,
      totalBookings: 12,
      cancelledBookings: 1,
    ),
    'c2': const Customer(
      id: 'c2',
      name: 'Usman Khan',
      phoneNumber: '0321****456',
      imageUrl: 'https://i.pravatar.cc/150?img=52',
      rating: 4.8,
      totalBookings: 8,
      cancelledBookings: 0,
    ),
    'c3': const Customer(
      id: 'c3',
      name: 'Fahad Ali',
      phoneNumber: '0333****789',
      imageUrl: 'https://i.pravatar.cc/150?img=57',
      rating: 3.5,
      totalBookings: 5,
      cancelledBookings: 2,
    ),
  };
  Map<String, Customer> get customers => Map.unmodifiable(_customers);
  
  // Toggle barber online status
  void toggleBarberOnline() {
    _isBarberOnline = !_isBarberOnline;
    notifyListeners();
  }
  
  void setBarberOnline(bool value) {
    _isBarberOnline = value;
    notifyListeners();
  }
  
  // Update working hours
  void updateWorkingHours(int startHour, int endHour, int slotDuration) {
    _workStartHour = startHour;
    _workEndHour = endHour;
    _slotDurationMinutes = slotDuration;
    notifyListeners();
  }
  
  // Toggle slot availability
  void toggleSlotAvailability(String dateKey, int slotIndex) {
    _closedSlots[dateKey] ??= {};
    if (_closedSlots[dateKey]!.contains(slotIndex)) {
      _closedSlots[dateKey]!.remove(slotIndex);
    } else {
      _closedSlots[dateKey]!.add(slotIndex);
    }
    notifyListeners();
  }
  
  // Check if slot is closed by barber
  bool isSlotClosed(String dateKey, int slotIndex) {
    return _closedSlots[dateKey]?.contains(slotIndex) ?? false;
  }
  
  // Get closed slots for a date
  Set<int> getClosedSlots(String dateKey) {
    return _closedSlots[dateKey] ?? {};
  }
  
  // Add earning to barber wallet
  void addBarberEarning(int amount, String description) {
    _barberWalletBalance += amount;
    _barberTransactions.insert(
      0,
      BarberTransaction(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        type: BarberTransactionType.earning,
        amount: amount,
        description: description,
        createdAt: DateTime.now(),
      ),
    );
    notifyListeners();
  }
  
  // Withdraw from barber wallet
  bool withdrawBarberFunds(int amount, String description) {
    if (_barberWalletBalance >= amount) {
      _barberWalletBalance -= amount;
      _barberTransactions.insert(
        0,
        BarberTransaction(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          type: BarberTransactionType.withdrawal,
          amount: amount,
          description: description,
          createdAt: DateTime.now(),
        ),
      );
      notifyListeners();
      return true;
    }
    return false;
  }
  
  // Get today's earnings
  int get todayEarnings {
    final today = DateTime.now();
    return _barberTransactions
        .where((t) => 
            t.type == BarberTransactionType.earning &&
            t.createdAt.year == today.year &&
            t.createdAt.month == today.month &&
            t.createdAt.day == today.day)
        .fold(0, (sum, t) => sum + t.amount);
  }
  
  // Get this week's earnings
  int get weekEarnings {
    final now = DateTime.now();
    final weekStart = now.subtract(Duration(days: now.weekday - 1));
    return _barberTransactions
        .where((t) => 
            t.type == BarberTransactionType.earning &&
            t.createdAt.isAfter(weekStart.subtract(const Duration(days: 1))))
        .fold(0, (sum, t) => sum + t.amount);
  }
  
  // Get this month's earnings
  int get monthEarnings {
    final now = DateTime.now();
    return _barberTransactions
        .where((t) => 
            t.type == BarberTransactionType.earning &&
            t.createdAt.year == now.year &&
            t.createdAt.month == now.month)
        .fold(0, (sum, t) => sum + t.amount);
  }
  
  // Get barber's bookings
  List<Booking> get barberBookings => _bookings
      .where((b) => b.barberId == _currentBarberId)
      .toList();
  
  // Get barber's upcoming bookings
  List<Booking> get barberUpcomingBookings => barberBookings
      .where((b) => 
          (b.status == BookingStatus.confirmed || b.status == BookingStatus.pending) && 
          b.bookingDateTime.isAfter(DateTime.now()))
      .toList()
      ..sort((a, b) => a.bookingDateTime.compareTo(b.bookingDateTime));
  
  // Get barber's today bookings
  List<Booking> get barberTodayBookings {
    final today = DateTime.now();
    return barberBookings
        .where((b) => 
            b.bookingDateTime.year == today.year &&
            b.bookingDateTime.month == today.month &&
            b.bookingDateTime.day == today.day)
        .toList()
        ..sort((a, b) => a.bookingDateTime.compareTo(b.bookingDateTime));
  }
  
  // Get barber's completed bookings
  List<Booking> get barberCompletedBookings => barberBookings
      .where((b) => b.status == BookingStatus.completed)
      .toList();
  
  // Get barber's cancelled bookings
  List<Booking> get barberCancelledBookings => barberBookings
      .where((b) => b.status.isCancelled)
      .toList();
  
  // Mark booking as completed and add earning
  void completeBooking(String bookingId, int customerRating, String? comment) {
    final index = _bookings.indexWhere((b) => b.id == bookingId);
    if (index != -1) {
      final oldBooking = _bookings[index];
      _bookings[index] = Booking(
        id: oldBooking.id,
        barberId: oldBooking.barberId,
        barberName: oldBooking.barberName,
        shopName: oldBooking.shopName,
        barberImageUrl: oldBooking.barberImageUrl,
        barberAddress: oldBooking.barberAddress,
        bookingDateTime: oldBooking.bookingDateTime,
        timeSlot: oldBooking.timeSlot,
        pricePKR: oldBooking.pricePKR,
        status: BookingStatus.completed,
        createdAt: oldBooking.createdAt,
        paymentMethod: oldBooking.paymentMethod,
        customerRating: customerRating,
        customerRatingComment: comment,
        customerId: oldBooking.customerId,
        customerName: oldBooking.customerName,
        customerImageUrl: oldBooking.customerImageUrl,
      );
      
      // Add earning to barber wallet
      addBarberEarning(oldBooking.pricePKR, 'Haircut - ${oldBooking.customerName ?? 'Customer'}');
      
      // Update customer rating if customer exists
      if (oldBooking.customerId != null && _customers.containsKey(oldBooking.customerId)) {
        final customer = _customers[oldBooking.customerId]!;
        // Simple rating update (average with new rating)
        final newRating = ((customer.rating * customer.totalBookings) + customerRating) / 
                          (customer.totalBookings + 1);
        _customers[oldBooking.customerId!] = Customer(
          id: customer.id,
          name: customer.name,
          phoneNumber: customer.phoneNumber,
          imageUrl: customer.imageUrl,
          rating: double.parse(newRating.toStringAsFixed(1)),
          totalBookings: customer.totalBookings,
          cancelledBookings: customer.cancelledBookings,
        );
      }
      
      notifyListeners();
    }
  }
  
  // Update customer rating
  void updateCustomerRating(String customerId, double newRating) {
    if (_customers.containsKey(customerId)) {
      final customer = _customers[customerId]!;
      _customers[customerId] = Customer(
        id: customer.id,
        name: customer.name,
        phoneNumber: customer.phoneNumber,
        imageUrl: customer.imageUrl,
        rating: newRating,
        totalBookings: customer.totalBookings,
        cancelledBookings: customer.cancelledBookings,
      );
      notifyListeners();
    }
  }

  // Selected Payment Method
  PaymentMethod _selectedPaymentMethod = PaymentMethod.wallet;
  PaymentMethod get selectedPaymentMethod => _selectedPaymentMethod;

  // Bookings History
  final List<Booking> _bookings = [];
  List<Booking> get bookings => List.unmodifiable(_bookings);

  // Wallet Transactions
  final List<WalletTransaction> _transactions = [
    WalletTransaction(
      id: '1',
      type: TransactionType.topUp,
      amount: 5000,
      description: 'Initial top-up via JazzCash',
      createdAt: DateTime.now().subtract(const Duration(days: 7)),
    ),
  ];
  List<WalletTransaction> get transactions => List.unmodifiable(_transactions);

  // Payment Methods
  final List<PaymentMethodItem> _paymentMethods = [
    const PaymentMethodItem(
      method: PaymentMethod.wallet,
      name: 'Best Cut Wallet',
      subtitle: null,
      isDefault: true,
    ),
    const PaymentMethodItem(
      method: PaymentMethod.jazzcash,
      name: 'JazzCash',
      subtitle: '0300****567',
      isDefault: false,
    ),
    const PaymentMethodItem(
      method: PaymentMethod.easypaisa,
      name: 'Easypaisa',
      subtitle: '0321****890',
      isDefault: false,
    ),
    const PaymentMethodItem(
      method: PaymentMethod.bank,
      name: 'Bank Account',
      subtitle: 'HBL ****1234',
      isDefault: false,
    ),
  ];
  List<PaymentMethodItem> get paymentMethods => List.unmodifiable(_paymentMethods);

  // Set selected payment method
  void setPaymentMethod(PaymentMethod method) {
    _selectedPaymentMethod = method;
    notifyListeners();
  }

  // Add money to wallet
  void addMoney(int amount, String description) {
    _walletBalance += amount;
    _transactions.insert(
      0,
      WalletTransaction(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        type: TransactionType.topUp,
        amount: amount,
        description: description,
        createdAt: DateTime.now(),
      ),
    );
    notifyListeners();
  }

  // Deduct from wallet (booking payment)
  bool payFromWallet(int amount, String description) {
    if (_walletBalance >= amount) {
      _walletBalance -= amount;
      _transactions.insert(
        0,
        WalletTransaction(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          type: TransactionType.payment,
          amount: amount,
          description: description,
          createdAt: DateTime.now(),
        ),
      );
      notifyListeners();
      return true;
    }
    return false;
  }

  // Refund to wallet
  void refundToWallet(int amount, String description) {
    _walletBalance += amount;
    _transactions.insert(
      0,
      WalletTransaction(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        type: TransactionType.refund,
        amount: amount,
        description: description,
        createdAt: DateTime.now(),
      ),
    );
    notifyListeners();
  }

  // Add booking
  void addBooking(Booking booking) {
    _bookings.insert(0, booking);
    notifyListeners();
  }

  // Update booking status
  void updateBookingStatus(String bookingId, BookingStatus status, {String? cancellationReason}) {
    final index = _bookings.indexWhere((b) => b.id == bookingId);
    if (index != -1) {
      final oldBooking = _bookings[index];
      _bookings[index] = Booking(
        id: oldBooking.id,
        barberId: oldBooking.barberId,
        barberName: oldBooking.barberName,
        shopName: oldBooking.shopName,
        barberImageUrl: oldBooking.barberImageUrl,
        barberAddress: oldBooking.barberAddress,
        bookingDateTime: oldBooking.bookingDateTime,
        timeSlot: oldBooking.timeSlot,
        pricePKR: oldBooking.pricePKR,
        status: status,
        createdAt: oldBooking.createdAt,
        paymentMethod: oldBooking.paymentMethod,
        cancellationReason: cancellationReason,
        cancelledBy: status == BookingStatus.cancelledByCustomer 
            ? 'customer' 
            : status == BookingStatus.cancelledByBarber 
                ? 'barber' 
                : null,
        customerId: oldBooking.customerId,
        customerName: oldBooking.customerName,
        customerImageUrl: oldBooking.customerImageUrl,
        customerRatingScore: oldBooking.customerRatingScore,
        customerRating: oldBooking.customerRating,
        customerRatingComment: oldBooking.customerRatingComment,
      );
      notifyListeners();
    }
  }

  // Cancel booking by customer (50% refund)
  void cancelBookingByCustomer(String bookingId) {
    final index = _bookings.indexWhere((b) => b.id == bookingId);
    if (index != -1) {
      final booking = _bookings[index];
      final refundAmount = (booking.pricePKR / 2).round();
      
      updateBookingStatus(
        bookingId, 
        BookingStatus.cancelledByCustomer,
        cancellationReason: 'Cancelled by customer',
      );
      
      refundToWallet(refundAmount, 'Refund (50%) for cancelled booking - ${booking.barberName}');
    }
  }

  // Cancel booking by barber (100% refund)
  void cancelBookingByBarber(String bookingId, String reason) {
    final index = _bookings.indexWhere((b) => b.id == bookingId);
    if (index != -1) {
      final booking = _bookings[index];
      
      updateBookingStatus(
        bookingId, 
        BookingStatus.cancelledByBarber,
        cancellationReason: reason,
      );
      
      refundToWallet(booking.pricePKR, 'Full refund - Booking cancelled by barber');
    }
  }

  // Get upcoming bookings
  List<Booking> get upcomingBookings => _bookings
      .where((b) => 
          b.status.isActive && 
          b.bookingDateTime.isAfter(DateTime.now()))
      .toList();

  // Get past bookings
  List<Booking> get pastBookings => _bookings
      .where((b) => 
          b.status.isTerminal ||
          (b.status.isActive && b.bookingDateTime.isBefore(DateTime.now())))
      .toList();
}

/// Payment Method Enum
enum PaymentMethod {
  wallet,
  jazzcash,
  easypaisa,
  bank,
  cash,
}

extension PaymentMethodExtension on PaymentMethod {
  String get displayName {
    switch (this) {
      case PaymentMethod.wallet:
        return 'Best Cut Wallet';
      case PaymentMethod.jazzcash:
        return 'JazzCash';
      case PaymentMethod.easypaisa:
        return 'Easypaisa';
      case PaymentMethod.bank:
        return 'Bank Account';
      case PaymentMethod.cash:
        return 'Cash';
    }
  }

  String get iconAsset {
    switch (this) {
      case PaymentMethod.wallet:
        return 'wallet';
      case PaymentMethod.jazzcash:
        return 'jazzcash';
      case PaymentMethod.easypaisa:
        return 'easypaisa';
      case PaymentMethod.bank:
        return 'bank';
      case PaymentMethod.cash:
        return 'cash';
    }
  }
}

/// Payment Method Item for list
class PaymentMethodItem {
  final PaymentMethod method;
  final String name;
  final String? subtitle;
  final bool isDefault;

  const PaymentMethodItem({
    required this.method,
    required this.name,
    this.subtitle,
    this.isDefault = false,
  });
}

/// Transaction Type
enum TransactionType {
  topUp,
  payment,
  refund,
}

extension TransactionTypeExtension on TransactionType {
  String get displayName {
    switch (this) {
      case TransactionType.topUp:
        return 'Top Up';
      case TransactionType.payment:
        return 'Payment';
      case TransactionType.refund:
        return 'Refund';
    }
  }

  bool get isCredit {
    return this == TransactionType.topUp || this == TransactionType.refund;
  }
}

/// Wallet Transaction
class WalletTransaction {
  final String id;
  final TransactionType type;
  final int amount;
  final String description;
  final DateTime createdAt;

  const WalletTransaction({
    required this.id,
    required this.type,
    required this.amount,
    required this.description,
    required this.createdAt,
  });

  String get formattedAmount {
    final prefix = type.isCredit ? '+' : '-';
    return '$prefix PKR $amount';
  }

  String get formattedDate {
    final now = DateTime.now();
    final diff = now.difference(createdAt);

    if (diff.inDays == 0) {
      return 'Today';
    } else if (diff.inDays == 1) {
      return 'Yesterday';
    } else if (diff.inDays < 7) {
      return '${diff.inDays} days ago';
    } else {
      return '${createdAt.day}/${createdAt.month}/${createdAt.year}';
    }
  }
}

/// Dispute Reason Options
enum DisputeReason {
  serviceNotProvided,
  poorServiceQuality,
  wrongPricing,
  lateArrival,
  barberUnprofessional,
  bookingCancelledUnfairly,
  paymentIssue,
  other;

  String get reasonDisplayName {
    switch (this) {
      case DisputeReason.serviceNotProvided:
        return 'Service Not Provided';
      case DisputeReason.poorServiceQuality:
        return 'Poor Service Quality';
      case DisputeReason.wrongPricing:
        return 'Wrong Pricing';
      case DisputeReason.lateArrival:
        return 'Late Arrival';
      case DisputeReason.barberUnprofessional:
        return 'Barber Unprofessional';
      case DisputeReason.bookingCancelledUnfairly:
        return 'Booking Cancelled Unfairly';
      case DisputeReason.paymentIssue:
        return 'Payment Issue';
      case DisputeReason.other:
        return 'Other';
    }
  }
}

/// Dispute Status
enum DisputeStatus {
  open,           // Dispute filed, under review
  investigating,  // Admin investigating
  resolved,       // Dispute resolved
  closed,         // Final decision made
}

/// Escrow Status
enum EscrowStatus {
  held,           // Payment held in escrow
  released,       // Payment released to barber
  refunded,       // Payment refunded to customer
  disputed,       // Payment disputed, held in escrow
}

/// Trust Level based on strikes/warnings
enum TrustLevel {
  excellent,      // 0 strikes, full trust
  good,          // 1 strike, minor issues
  warning,       // 2 strikes, caution advised
  restricted,    // 3+ strikes, restricted access
}

/// Dispute Data Model
class Dispute {
  final String id;
  final String bookingId;
  final String customerId;
  final String barberId;
  final DisputeReason reason;
  final String description;
  final DisputeStatus status;
  final DateTime createdAt;
  final DateTime? resolvedAt;
  final String? adminResolution;
  final String? adminNotes;

  const Dispute({
    required this.id,
    required this.bookingId,
    required this.customerId,
    required this.barberId,
    required this.reason,
    required this.description,
    required this.status,
    required this.createdAt,
    this.resolvedAt,
    this.adminResolution,
    this.adminNotes,
  });

  factory Dispute.fromMap(Map<String, dynamic> map) {
    return Dispute(
      id: map['id'] ?? '',
      bookingId: map['bookingId'] ?? '',
      customerId: map['customerId'] ?? '',
      barberId: map['barberId'] ?? '',
      reason: DisputeReason.values.firstWhere(
        (r) => r.name == map['reason'],
        orElse: () => DisputeReason.other,
      ),
      description: map['description'] ?? '',
      status: DisputeStatus.values.firstWhere(
        (s) => s.name == map['status'],
        orElse: () => DisputeStatus.open,
      ),
      createdAt: (map['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      resolvedAt: (map['resolvedAt'] as Timestamp?)?.toDate(),
      adminResolution: map['adminResolution'],
      adminNotes: map['adminNotes'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'bookingId': bookingId,
      'customerId': customerId,
      'barberId': barberId,
      'reason': reason.name,
      'description': description,
      'status': status.name,
      'createdAt': Timestamp.fromDate(createdAt),
      'resolvedAt': resolvedAt != null ? Timestamp.fromDate(resolvedAt!) : null,
      'adminResolution': adminResolution,
      'adminNotes': adminNotes,
    };
  }

  String get reasonDisplayName {
    switch (reason) {
      case DisputeReason.serviceNotProvided:
        return 'Service Not Provided';
      case DisputeReason.poorServiceQuality:
        return 'Poor Service Quality';
      case DisputeReason.wrongPricing:
        return 'Incorrect Pricing';
      case DisputeReason.lateArrival:
        return 'Late Arrival';
      case DisputeReason.barberUnprofessional:
        return 'Unprofessional Behavior';
      case DisputeReason.bookingCancelledUnfairly:
        return 'Unfair Cancellation';
      case DisputeReason.paymentIssue:
        return 'Payment Issue';
      case DisputeReason.other:
        return 'Other';
    }
  }

  String get statusDisplayName {
    switch (status) {
      case DisputeStatus.open:
        return 'Under Review';
      case DisputeStatus.investigating:
        return 'Investigating';
      case DisputeStatus.resolved:
        return 'Resolved';
      case DisputeStatus.closed:
        return 'Closed';
    }
  }

  Color get statusColor {
    switch (status) {
      case DisputeStatus.open:
        return const Color(0xFFFF9800); // Orange
      case DisputeStatus.investigating:
        return const Color(0xFF2196F3); // Blue
      case DisputeStatus.resolved:
        return const Color(0xFF4CAF50); // Green
      case DisputeStatus.closed:
        return const Color(0xFF9E9E9E); // Grey
    }
  }
}

/// Trust/Strike Information
class TrustInfo {
  final int strikeCount;
  final List<String> recentWarnings;
  final DateTime? lastStrikeDate;
  final String? restrictionReason;
  final bool isRestricted;

  const TrustInfo({
    required this.strikeCount,
    required this.recentWarnings,
    this.lastStrikeDate,
    this.restrictionReason,
    this.isRestricted = false,
  });

  factory TrustInfo.fromMap(Map<String, dynamic> map) {
    return TrustInfo(
      strikeCount: map['strikeCount'] ?? 0,
      recentWarnings: List<String>.from(map['recentWarnings'] ?? []),
      lastStrikeDate: (map['lastStrikeDate'] as Timestamp?)?.toDate(),
      restrictionReason: map['restrictionReason'],
      isRestricted: map['isRestricted'] ?? false,
    );
  }

  TrustLevel get trustLevel {
    if (isRestricted) return TrustLevel.restricted;
    if (strikeCount >= 3) return TrustLevel.warning;
    if (strikeCount >= 1) return TrustLevel.good;
    return TrustLevel.excellent;
  }

  Color get trustColor {
    switch (trustLevel) {
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

  String get trustBadgeText {
    switch (trustLevel) {
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

  String get trustDescription {
    switch (trustLevel) {
      case TrustLevel.excellent:
        return 'No issues reported. Full access to all features.';
      case TrustLevel.good:
        return 'Minor issues noted. All features available.';
      case TrustLevel.warning:
        return 'Multiple issues reported. Some restrictions may apply.';
      case TrustLevel.restricted:
        return restrictionReason ?? 'Account restrictions active due to policy violations.';
    }
  }
}

/// Barber Transaction Type
enum BarberTransactionType {
  earning,
  withdrawal,
  refund,
}

extension BarberTransactionTypeExtension on BarberTransactionType {
  String get displayName {
    switch (this) {
      case BarberTransactionType.earning:
        return 'Earning';
      case BarberTransactionType.withdrawal:
        return 'Withdrawal';
      case BarberTransactionType.refund:
        return 'Refund';
    }
  }

  bool get isCredit {
    return this == BarberTransactionType.earning;
  }
}

/// Barber Transaction
class BarberTransaction {
  final String id;
  final BarberTransactionType type;
  final int amount;
  final String description;
  final DateTime createdAt;

  const BarberTransaction({
    required this.id,
    required this.type,
    required this.amount,
    required this.description,
    required this.createdAt,
  });

  String get formattedAmount {
    final prefix = type.isCredit ? '+' : '-';
    return '$prefix PKR $amount';
  }

  String get formattedDate {
    final now = DateTime.now();
    final diff = now.difference(createdAt);
    
    if (diff.inDays == 0) {
      return 'Today';
    } else if (diff.inDays == 1) {
      return 'Yesterday';
    } else if (diff.inDays < 7) {
      return '${diff.inDays} days ago';
    } else {
      return '${createdAt.day}/${createdAt.month}/${createdAt.year}';
    }
  }
}

