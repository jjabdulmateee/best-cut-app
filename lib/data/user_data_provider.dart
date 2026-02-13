import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/auth_service.dart';
import '../services/cloud_functions_service.dart';
import '../services/system_monitor_service.dart';
import '../services/error_message_service.dart';

/// Re-export for convenience
export '../services/cloud_functions_service.dart';
import '../models/barber.dart';
import '../models/slot.dart';
import 'app_data.dart';

/// UserDataProvider - Manages current user's data and syncs with Firestore
/// This replaces in-memory AppData for logged-in user operations
class UserDataProvider extends ChangeNotifier {
  static final UserDataProvider _instance = UserDataProvider._internal();
  factory UserDataProvider() => _instance;
  UserDataProvider._internal();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final AuthService _authService = AuthService();
  final CloudFunctionsService _cloudFunctions = CloudFunctionsService();
  final SystemMonitorService _systemMonitor = SystemMonitorService();

  // Current user data
  Map<String, dynamic>? _userData;
  UserRole? _userRole;
  String? _userId;
  
  // Subscriptions
  StreamSubscription? _userDataSubscription;
  StreamSubscription? _bookingsSubscription;
  StreamSubscription? _transactionsSubscription;

  // Cached data
  List<Booking> _bookings = [];
  List<WalletTransaction> _customerTransactions = [];
  List<BarberTransaction> _barberTransactions = [];
  List<Barber> _approvedBarbers = [];

  // Getters
  Map<String, dynamic>? get userData => _userData;
  UserRole? get userRole => _userRole;
  String? get userId => _userId;
  bool get isLoggedIn => _auth.currentUser != null;

  // System monitoring getters
  bool get isSystemFrozen => _systemMonitor.isSystemFrozen;
  bool get isAccountDisabled => _systemMonitor.isAccountDisabled;
  bool get hasSystemRestrictions => _systemMonitor.hasSystemRestrictions;
  String get restrictionMessage => _systemMonitor.restrictionMessage;
  bool get canCreateBookings => _systemMonitor.canCreateBookings;
  bool get canMakePayments => _systemMonitor.canMakePayments;
  bool get canWithdrawFunds => _systemMonitor.canWithdrawFunds;
  bool get canUpdateProfile => _systemMonitor.canUpdateProfile;
  
  // ── Defensive helpers: Firestore values can arrive as int, double, or String
  //    depending on how they were written. These helpers prevent type cast crashes.
  static int _safeInt(dynamic value, [int fallback = 0]) {
    if (value == null) return fallback;
    if (value is int) return value;
    if (value is double) return value.toInt();
    return int.tryParse(value.toString()) ?? fallback;
  }

  static String _safeString(dynamic value, [String fallback = '']) {
    if (value == null) return fallback;
    return value.toString();
  }

  static double _safeDouble(dynamic value, [double fallback = 0.0]) {
    if (value == null) return fallback;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    return double.tryParse(value.toString()) ?? fallback;
  }

  /// Parse workStartHour / workEndHour from Firestore.
  /// Handles: int (9), String ("09:00"), or null.
  static String _parseHour(dynamic value, String fallback) {
    if (value == null) return fallback;
    if (value is String) return value;
    if (value is int) return '${value.toString().padLeft(2, '0')}:00';
    return value.toString();
  }

  // Universal getter for wallet balance (works for both customer and barber)
  int get walletBalance => _safeInt(_userData?['walletBalance']);
  
  // Customer getters
  int get customerWalletBalance => _safeInt(_userData?['walletBalance']);
  String get customerName => _safeString(_userData?['name']);
  String get customerEmail => _safeString(_userData?['email']);
  String get customerPhone => _safeString(_userData?['phone']);
  String get customerImageUrl => _safeString(_userData?['imageUrl']);
  double get customerRating => _safeDouble(_userData?['rating'], 5.0);
  List<Booking> get customerBookings => _bookings;
  List<WalletTransaction> get customerTransactions => _customerTransactions;
  List<Barber> get approvedBarbers => _approvedBarbers;

  // Barber getters
  bool get isBarberOnline => _userData?['isOnline'] as bool? ?? false;
  int get barberWalletBalance => _safeInt(_userData?['walletBalance']);
  String get barberName => _safeString(_userData?['name']);
  String get barberShopName => _safeString(_userData?['shopName']);
  String get barberAddress => _safeString(_userData?['address']);
  String get barberImageUrl => _safeString(_userData?['imageUrl']);
  double get barberRating => _safeDouble(_userData?['rating']);
  int get barberTotalReviews => _safeInt(_userData?['totalReviews']);
  int get barberPriceStartingPKR => _safeInt(_userData?['priceStartingPKR']);
  List<String> get barberServices => List<String>.from(_userData?['services'] ?? []);
  int get workStartHour => _safeInt(_userData?['workStartHour'], 9);
  int get workEndHour => _safeInt(_userData?['workEndHour'], 18);
  int get slotDurationMinutes => _safeInt(_userData?['slotDurationMinutes'], 30);
  BarberStatus get barberStatus {
    final statusStr = _safeString(_userData?['status'], 'draft');
    return BarberStatus.values.firstWhere(
      (s) => s.name == statusStr,
      orElse: () => BarberStatus.draft,
    );
  }
  List<Booking> get barberBookings => _bookings;
  List<BarberTransaction> get barberTransactions => _barberTransactions;

  Barber? get barberData {
    if (_userData == null || _userRole != UserRole.barber) return null;
    return Barber.fromMap(_userData!);
  }

  // Derived data — Phase 3 lifecycle-aware
  List<Booking> get upcomingBookings => _bookings
      .where((b) => (b.status == BookingStatus.confirmed || b.status == BookingStatus.pending) 
          && b.bookingDateTime.isAfter(DateTime.now()))
      .toList()
    ..sort((a, b) => a.bookingDateTime.compareTo(b.bookingDateTime));

  /// Bookings currently in progress (barber started)
  List<Booking> get inProgressBookings => _bookings
      .where((b) => b.status == BookingStatus.inProgress)
      .toList();

  List<Booking> get completedBookings => _bookings
      .where((b) => b.status == BookingStatus.completed)
      .toList();

  List<Booking> get cancelledBookings => _bookings
      .where((b) => b.status.isCancelled || b.status == BookingStatus.rejected)
      .toList();

  List<Booking> get todayBookings {
    final today = DateTime.now();
    return _bookings.where((b) =>
        b.bookingDateTime.year == today.year &&
        b.bookingDateTime.month == today.month &&
        b.bookingDateTime.day == today.day
    ).toList()..sort((a, b) => a.bookingDateTime.compareTo(b.bookingDateTime));
  }

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

  int get weekEarnings {
    final now = DateTime.now();
    final weekStart = now.subtract(Duration(days: now.weekday - 1));
    return _barberTransactions
        .where((t) =>
            t.type == BarberTransactionType.earning &&
            t.createdAt.isAfter(weekStart.subtract(const Duration(days: 1))))
        .fold(0, (sum, t) => sum + t.amount);
  }

  int get monthEarnings {
    final now = DateTime.now();
    return _barberTransactions
        .where((t) =>
            t.type == BarberTransactionType.earning &&
            t.createdAt.year == now.year &&
            t.createdAt.month == now.month)
        .fold(0, (sum, t) => sum + t.amount);
  }

  /// Initialize user data - call this after login
  Future<void> initialize() async {
    final user = _auth.currentUser;
    if (user == null) return;

    _userId = user.uid;

    // Start system monitoring for admin controls
    _systemMonitor.initializeForUser(user.uid);
    
    // Get initial user data
    final userData = await _authService.getUserData(user.uid);
    if (userData != null) {
      _userData = userData;
      _userRole = UserRole.values.firstWhere(
        (r) => r.name == userData['role'],
        orElse: () => UserRole.customer,
      );
      notifyListeners();
    }

    // Subscribe to user data changes
    _userDataSubscription = _firestore
        .collection('users')
        .doc(user.uid)
        .snapshots()
        .listen((doc) {
          if (doc.exists) {
            _userData = doc.data();
            notifyListeners();
          }
        });

    // Subscribe to bookings
    _subscribeToBookings();
    
    // Subscribe to transactions
    _subscribeToTransactions();
    
    // If customer, subscribe to approved barbers
    if (_userRole == UserRole.customer) {
      _subscribeToApprovedBarbers();
    }
  }

  /// Update barber profile (SECURE - via Cloud Functions)
  Future<void> updateBarberProfile({
    required String name,
    required String phone,
    required String shopName,
    required String address,
  }) async {
    try {
      // Check system restrictions first
      if (!canUpdateProfile) {
        throw Exception('Cannot update profile: $restrictionMessage');
      }

      await _cloudFunctions.updateBarberProfile(
        name: name,
        phone: phone,
        shopName: shopName,
        address: address,
      );
    } catch (e) {
      debugPrint('Update barber profile error: $e');
      rethrow;
    }
  }

  /// Update customer profile (SECURE - via Cloud Functions)
  Future<void> updateCustomerProfile({
    required String name,
    required String phone,
  }) async {
    try {
      // Check system restrictions first
      if (!canUpdateProfile) {
        throw Exception('Cannot update profile: $restrictionMessage');
      }

      await _cloudFunctions.updateCustomerProfile(
        name: name,
        phone: phone,
      );
    } catch (e) {
      debugPrint('Update customer profile error: $e');
      rethrow;
    }
  }

  void _subscribeToBookings() {
    final userId = _userId;
    if (userId == null) return;

    final query = _userRole == UserRole.barber
        ? _firestore.collection('bookings').where('barberId', isEqualTo: userId)
        : _firestore.collection('bookings').where('customerId', isEqualTo: userId);

    _bookingsSubscription = query
        .orderBy('bookingDateTime', descending: true)
        .snapshots()
        .listen((snapshot) {
          _bookings = snapshot.docs.map((doc) {
            final data = doc.data();
            data['id'] = doc.id;
            return Booking.fromMap(data);
          }).toList();
          notifyListeners();
        });
  }

  void _subscribeToTransactions() {
    final userId = _userId;
    if (userId == null) return;

    final userType = _userRole == UserRole.barber ? 'barber' : 'customer';
    
    _transactionsSubscription = _firestore
        .collection('transactions')
        .where('userId', isEqualTo: userId)
        .where('userType', isEqualTo: userType)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .listen((snapshot) {
          if (_userRole == UserRole.customer) {
            _customerTransactions = snapshot.docs.map((doc) {
              final data = doc.data();
              final typeStr = _safeString(data['type'], 'payment');
              final type = TransactionType.values.firstWhere(
                (t) => t.name == typeStr,
                orElse: () => TransactionType.payment,
              );
              
              DateTime createdAt;
              final createdAtField = data['createdAt'];
              if (createdAtField is Timestamp) {
                createdAt = createdAtField.toDate();
              } else {
                createdAt = DateTime.now();
              }
              
              return WalletTransaction(
                id: doc.id,
                type: type,
                amount: _safeInt(data['amount']),
                description: _safeString(data['description']),
                createdAt: createdAt,
              );
            }).toList();
          } else {
            _barberTransactions = snapshot.docs.map((doc) {
              final data = doc.data();
              final typeStr = _safeString(data['type'], 'earning');
              final type = BarberTransactionType.values.firstWhere(
                (t) => t.name == typeStr,
                orElse: () => BarberTransactionType.earning,
              );
              
              DateTime createdAt;
              final createdAtField = data['createdAt'];
              if (createdAtField is Timestamp) {
                createdAt = createdAtField.toDate();
              } else {
                createdAt = DateTime.now();
              }
              
              return BarberTransaction(
                id: doc.id,
                type: type,
                amount: _safeInt(data['amount']),
                description: _safeString(data['description']),
                createdAt: createdAt,
              );
            }).toList();
          }
          notifyListeners();
        });
  }

  void _subscribeToApprovedBarbers() {
    _firestore
        .collection('users')
        .where('role', isEqualTo: UserRole.barber.name)
        .where('status', isEqualTo: BarberStatus.approved.name)
        .snapshots()
        .listen((snapshot) {
          _approvedBarbers = snapshot.docs.map((doc) {
            final data = doc.data();
            data['id'] = doc.id;
            return Barber.fromMap(data);
          }).toList();
          notifyListeners();
        });
  }

  /// Clear data on logout
  void clear() {
    _userDataSubscription?.cancel();
    _bookingsSubscription?.cancel();
    _transactionsSubscription?.cancel();
    _systemMonitor.cleanup();
    _userData = null;
    _userRole = null;
    _userId = null;
    _bookings = [];
    _customerTransactions = [];
    _barberTransactions = [];
    _approvedBarbers = [];
    notifyListeners();
  }

  /// Refresh current user data
  Future<void> refreshUserData() async {
    await initialize();
  }

  // ==================== CUSTOMER OPERATIONS ====================

  /// Add money to customer wallet (SECURE - via Cloud Functions)
  Future<void> addMoneyToWallet(int amount, String description, String paymentMethod) async {
    try {
      // Check system restrictions first
      if (hasSystemRestrictions) {
        throw Exception('System restrictions active: $restrictionMessage');
      }

      await _cloudFunctions.addMoneyToWallet(
        amount: amount,
        description: description,
        paymentMethod: paymentMethod,
      );
    } catch (e) {
      debugPrint('Add money to wallet error: $e');
      rethrow;
    }
  }

  /// Pay from customer wallet (SECURE - via Cloud Functions)
  Future<CloudFunctionResult> payFromWallet(int amount, String bookingId, String description) async {
    try {
      // Check system restrictions first
      if (hasSystemRestrictions) {
        return CloudFunctionResult.error(
          userMessage: restrictionMessage,
          errorType: ErrorType.maintenance,
          supportSuggestion: 'Please wait for system maintenance to complete.',
          technicalError: 'System restrictions active',
        );
      }

      return await _cloudFunctions.payFromWallet(
        amount: amount,
        bookingId: bookingId,
        description: description,
      );
    } catch (e) {
      debugPrint('Pay from wallet error: $e');
      return CloudFunctionResult.error(
        userMessage: 'Payment failed. Please try again.',
        errorType: ErrorType.error,
        supportSuggestion: 'Contact support@bestcut.pk if the problem persists.',
        technicalError: e.toString(),
      );
    }
  }

  /// Refund to customer wallet (SECURE - via Cloud Functions)
  Future<void> refundToWallet(int amount, String bookingId, String description, String refundReason) async {
    try {
      await _cloudFunctions.refundToWallet(
        amount: amount,
        bookingId: bookingId,
        description: description,
        refundReason: refundReason,
      );
    } catch (e) {
      debugPrint('Refund to wallet error: $e');
      rethrow;
    }
  }

  /// Create a new booking (SECURE - via Cloud Functions)
  Future<String> createBooking({
    required String barberId,
    required DateTime bookingDateTime,
    required String timeSlot,
    required int pricePKR,
    required String paymentMethod,
  }) async {
    try {
      // Check system restrictions first
      if (!canCreateBookings) {
        throw Exception('Cannot create bookings: $restrictionMessage');
      }

      final result = await _cloudFunctions.createBooking(
        barberId: barberId,
        bookingDateTime: bookingDateTime,
        timeSlot: timeSlot,
        pricePKR: pricePKR,
        paymentMethod: paymentMethod,
      );

      if (result['success'] == true) {
        return result['bookingId'];
      } else {
        throw Exception(result['error'] ?? 'Failed to create booking');
      }
    } catch (e) {
      debugPrint('Create booking error: $e');
      rethrow;
    }
  }

  /// Cancel booking by customer (SECURE - via Cloud Functions)
  Future<void> cancelBookingByCustomer(String bookingId, {String reason = 'Cancelled by customer'}) async {
    try {
      await _cloudFunctions.cancelBookingByCustomer(
        bookingId: bookingId,
        reason: reason,
      );
    } catch (e) {
      debugPrint('Cancel booking by customer error: $e');
      rethrow;
    }
  }

  // ==================== BARBER OPERATIONS ====================

  /// Check if barber can go online
  String? canBarberGoOnline() {
    if (barberStatus != BarberStatus.approved) {
      return 'Your account must be approved before going online';
    }
    final name = _safeString(_userData?['name']);
    final imageUrl = _safeString(_userData?['imageUrl']);
    if (name.isEmpty) {
      return 'Please complete your profile name';
    }
    if (imageUrl.isEmpty || !imageUrl.startsWith('http')) {
      return 'Please upload a profile photo';
    }
    
    // Check working hours
    if (!isWithinWorkingHours) {
      return 'You can only go online during your working hours (${formattedWorkingHours})';
    }
    
    // Check if today is day off
    final now = DateTime.now();
    final daysOff = List<int>.from(_userData?['daysOff'] ?? []);
    if (daysOff.contains(now.weekday)) {
      return 'Today is your day off. Update your schedule to go online.';
    }
    
    return null; // Can go online
  }

  /// Check if current time is within barber's working hours
  bool get isWithinWorkingHours {
    final now = DateTime.now();
    
    // Check if today is a day off
    final daysOff = List<int>.from(_userData?['daysOff'] ?? []);
    if (daysOff.contains(now.weekday)) return false;

    // Parse working hours — handles both int (9) and String ("09:00")
    final startStr = _parseHour(_userData?['workStartHour'], '09:00');
    final endStr = _parseHour(_userData?['workEndHour'], '22:00');
    
    final startParts = startStr.split(':');
    final endParts = endStr.split(':');
    
    if (startParts.length != 2 || endParts.length != 2) return false;
    
    final startHour = int.tryParse(startParts[0]) ?? 9;
    final startMin = int.tryParse(startParts[1]) ?? 0;
    final endHour = int.tryParse(endParts[0]) ?? 22;
    final endMin = int.tryParse(endParts[1]) ?? 0;

    double nowDouble = now.hour + now.minute / 60.0;
    double startDouble = startHour + startMin / 60.0;
    double endDouble = endHour + endMin / 60.0;

    return nowDouble >= startDouble && nowDouble <= endDouble;
  }

  /// Get formatted working hours string
  String get formattedWorkingHours {
    final startStr = _parseHour(_userData?['workStartHour'], '09:00');
    final endStr = _parseHour(_userData?['workEndHour'], '22:00');
    return '$startStr - $endStr';
  }

  /// Get barber's days off
  List<int> get barberDaysOff => List<int>.from(_userData?['daysOff'] ?? []);

  /// Set barber online status with validation (SECURE - via Cloud Functions)
  Future<bool> setBarberOnlineStatus(bool isOnline) async {
    try {
      // Check system restrictions first
      if (hasSystemRestrictions) {
        throw Exception('System restrictions active: $restrictionMessage');
      }

    // If going online, validate
    if (isOnline) {
      final validationError = canBarberGoOnline();
      if (validationError != null) {
          throw Exception(validationError);
        }
      }

      final result = await _cloudFunctions.updateBarberOnlineStatus(isOnline);
      return result['success'] == true;
    } catch (e) {
      debugPrint('Set barber online status error: $e');
      return false;
    }
  }

  /// Toggle barber online status
  Future<void> toggleBarberOnlineStatus() async {
    final userId = _userId;
    if (userId == null) return;

    await _firestore.collection('users').doc(userId).update({
      'isOnline': !isBarberOnline,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Get pending booking requests for barber
  List<Booking> get pendingBookingRequests => _bookings
      .where((b) => b.status == BookingStatus.pending)
      .toList()
    ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

  /// Get active job — Phase 3 lifecycle aware.
  /// Priority: inProgress > confirmed (today, nearest time)
  Booking? get activeJob {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // HIGHEST PRIORITY: Any booking that's currently in progress
    final liveJobs = _bookings.where((b) => b.status == BookingStatus.inProgress).toList();
    if (liveJobs.isNotEmpty) {
      liveJobs.sort((a, b) => a.bookingDateTime.compareTo(b.bookingDateTime));
      return liveJobs.first;
    }

    // NEXT: Confirmed bookings for today (accepted, waiting to start)
    final todayAccepted = _bookings.where((b) => 
      b.status == BookingStatus.confirmed &&
      b.bookingDateTime.year == today.year &&
      b.bookingDateTime.month == today.month &&
      b.bookingDateTime.day == today.day
    ).toList();
    
    if (todayAccepted.isEmpty) return null;
    
    todayAccepted.sort((a, b) => a.bookingDateTime.compareTo(b.bookingDateTime));
    
    for (var booking in todayAccepted) {
      final bookingEnd = booking.bookingDateTime.add(const Duration(minutes: 45));
      if (now.isBefore(bookingEnd)) {
        return booking;
      }
    }
    
    return null;
  }

  /// Accept a booking request (SECURE - via Cloud Functions)
  Future<bool> acceptBookingRequest(String bookingId) async {
    try {
      // Check system restrictions first
      if (hasSystemRestrictions) {
        throw Exception('System restrictions active: $restrictionMessage');
      }

      final result = await _cloudFunctions.acceptBookingRequest(bookingId);
      return result['success'] == true;
    } catch (e) {
      debugPrint('Accept booking request error: $e');
      rethrow;
    }
  }

  /// Reject a booking request (SECURE - via Cloud Functions)
  Future<bool> rejectBookingRequest(String bookingId, {String reason = 'Barber unavailable'}) async {
    try {
      final result = await _cloudFunctions.rejectBookingRequest(
        bookingId: bookingId,
        reason: reason,
      );
      return result['success'] == true;
    } catch (e) {
      debugPrint('Reject booking request error: $e');
      rethrow;
    }
  }

  /// Start a job (mark as in progress) (SECURE - via Cloud Functions)
  Future<bool> startJob(String bookingId) async {
    try {
      // Check system restrictions first
      if (hasSystemRestrictions) {
        throw Exception('System restrictions active: $restrictionMessage');
      }

      final result = await _cloudFunctions.startJob(bookingId);
      return result['success'] == true;
    } catch (e) {
      debugPrint('Start job error: $e');
      rethrow;
    }
  }

  /// Update working hours (SECURE - via Cloud Functions)
  Future<void> updateWorkingHours(String startHour, String endHour, {List<int>? daysOff}) async {
    try {
      await _cloudFunctions.updateBarberWorkingHours(
        startHour: startHour,
        endHour: endHour,
        daysOff: daysOff ?? barberDaysOff,
      );
    } catch (e) {
      debugPrint('Update working hours error: $e');
      rethrow;
    }
  }

  /// Update days off
  Future<void> updateDaysOff(List<int> daysOff) async {
    final userId = _userId;
    if (userId == null) return;

    await _firestore.collection('users').doc(userId).update({
      'daysOff': daysOff,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Toggle slot availability (SECURE - via Cloud Functions)
  Future<void> toggleSlotAvailability(String dateKey, int slotIndex) async {
    try {
      // Get current closed slots
      final currentClosed = await getClosedSlots(dateKey);
      final newClosedSlots = List<int>.from(currentClosed);

      if (newClosedSlots.contains(slotIndex)) {
        newClosedSlots.remove(slotIndex);
    } else {
        newClosedSlots.add(slotIndex);
      }

      await _cloudFunctions.updateBarberClosedSlots(
        dateKey: dateKey,
        closedSlots: newClosedSlots,
      );
    } catch (e) {
      debugPrint('Toggle slot availability error: $e');
      rethrow;
    }
  }

  /// Get closed slots for a date
  Future<Set<int>> getClosedSlots(String dateKey) async {
    final userId = _userId;
    if (userId == null) return {};

    final doc = await _firestore.collection('slots').doc('${userId}_$dateKey').get();
    if (!doc.exists) return {};
    
    final data = doc.data();
    return Set<int>.from(data?['closedSlots'] ?? []);
  }

  /// Complete booking and add earning (SECURE - via Cloud Functions)
  Future<void> completeBooking(String bookingId, int customerRating, String? comment) async {
    try {
      // Check system restrictions first
      if (hasSystemRestrictions) {
        throw Exception('System restrictions active: $restrictionMessage');
      }

      await _cloudFunctions.completeBooking(
        bookingId: bookingId,
        customerRating: customerRating,
        comment: comment,
      );
    } catch (e) {
      debugPrint('Complete booking error: $e');
      rethrow;
    }
  }


  /// Cancel booking by barber (SECURE - via Cloud Functions)
  Future<void> cancelBookingByBarber(String bookingId, String reason) async {
    try {
      await _cloudFunctions.cancelBookingByBarber(
        bookingId: bookingId,
        reason: reason,
      );
    } catch (e) {
      debugPrint('Cancel booking by barber error: $e');
      rethrow;
    }
  }

  /// Withdraw from barber wallet (SECURE - via Cloud Functions)
  Future<bool> withdrawBarberFunds(int amount, String description, String withdrawalMethod) async {
    try {
      // Check system restrictions first
      if (!canWithdrawFunds) {
        throw Exception('Cannot withdraw funds: $restrictionMessage');
      }

      final result = await _cloudFunctions.withdrawBarberFunds(
        amount: amount,
        description: description,
        withdrawalMethod: withdrawalMethod,
      );

      return result['success'] == true;
    } catch (e) {
      debugPrint('Withdraw barber funds error: $e');
      rethrow;
    }
  }

  // ==================== ACCOUNT SCREEN OPERATIONS ====================

  /// Get saved addresses
  List<Map<String, dynamic>> get savedAddresses {
    final addresses = _userData?['savedAddresses'];
    if (addresses == null) return [];
    return List<Map<String, dynamic>>.from(addresses);
  }

  /// Get notification preferences
  Map<String, bool> get notificationPrefs {
    final prefs = _userData?['notificationPrefs'];
    if (prefs == null) {
      return {'bookingUpdates': true, 'promotions': true};
    }
    return Map<String, bool>.from(prefs);
  }

  /// Update personal information (name, phone)
  Future<bool> updatePersonalInfo({String? name, String? phone}) async {
    final userId = _userId;
    if (userId == null) return false;

    final updates = <String, dynamic>{
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (name != null && name.isNotEmpty) updates['name'] = name;
    if (phone != null && phone.isNotEmpty) updates['phone'] = phone;

    try {
      await _firestore.collection('users').doc(userId).update(updates);
      return true;
    } catch (e) {
      debugPrint('Update personal info error: $e');
      return false;
    }
  }

  /// Add a new address
  Future<bool> addAddress(Map<String, dynamic> address) async {
    final userId = _userId;
    if (userId == null) return false;

    try {
      final addresses = List<Map<String, dynamic>>.from(savedAddresses);
      address['id'] = DateTime.now().millisecondsSinceEpoch.toString();
      addresses.add(address);
      
      await _firestore.collection('users').doc(userId).update({
        'savedAddresses': addresses,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return true;
    } catch (e) {
      debugPrint('Add address error: $e');
      return false;
    }
  }

  /// Update an existing address
  Future<bool> updateAddress(String addressId, Map<String, dynamic> address) async {
    final userId = _userId;
    if (userId == null) return false;

    try {
      final addresses = List<Map<String, dynamic>>.from(savedAddresses);
      final index = addresses.indexWhere((a) => a['id'] == addressId);
      if (index == -1) return false;
      
      address['id'] = addressId;
      addresses[index] = address;
      
      await _firestore.collection('users').doc(userId).update({
        'savedAddresses': addresses,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return true;
    } catch (e) {
      debugPrint('Update address error: $e');
      return false;
    }
  }

  /// Delete an address
  Future<bool> deleteAddress(String addressId) async {
    final userId = _userId;
    if (userId == null) return false;

    try {
      final addresses = List<Map<String, dynamic>>.from(savedAddresses);
      addresses.removeWhere((a) => a['id'] == addressId);
      
      await _firestore.collection('users').doc(userId).update({
        'savedAddresses': addresses,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return true;
    } catch (e) {
      debugPrint('Delete address error: $e');
      return false;
    }
  }

  /// Set default address
  Future<bool> setDefaultAddress(String addressId) async {
    final userId = _userId;
    if (userId == null) return false;

    try {
      final addresses = List<Map<String, dynamic>>.from(savedAddresses);
      for (var addr in addresses) {
        addr['isDefault'] = addr['id'] == addressId;
      }
      
      await _firestore.collection('users').doc(userId).update({
        'savedAddresses': addresses,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return true;
    } catch (e) {
      debugPrint('Set default address error: $e');
      return false;
    }
  }

  /// Update notification preference
  Future<bool> updateNotificationPref(String key, bool value) async {
    final userId = _userId;
    if (userId == null) return false;

    try {
      final prefs = Map<String, bool>.from(notificationPrefs);
      prefs[key] = value;
      
      await _firestore.collection('users').doc(userId).update({
        'notificationPrefs': prefs,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return true;
    } catch (e) {
      debugPrint('Update notification pref error: $e');
      return false;
    }
  }

  /// Sign out
  Future<void> signOut() async {
    clear();
    await _auth.signOut();
  }

  // ==================== DISPUTE OPERATIONS ====================

  /// Create a dispute for a booking
  Future<bool> createDispute({
    required String bookingId,
    required DisputeReason reason,
    required String description,
  }) async {
    try {
      // Check system restrictions first
      if (hasSystemRestrictions) {
        throw Exception('System restrictions active: $restrictionMessage');
      }

      final result = await _cloudFunctions.createDispute(
        bookingId: bookingId,
        reason: reason,
        description: description,
      );

      return result['success'] == true;
    } catch (e) {
      debugPrint('Create dispute error: $e');
      rethrow;
    }
  }

  /// Get user's disputes
  Future<List<Dispute>> getUserDisputes() async {
    try {
      final result = await _cloudFunctions.getUserDisputes();

      if (result['success'] == true && result['disputes'] is List) {
        return (result['disputes'] as List)
            .map((d) => Dispute.fromMap(d as Map<String, dynamic>))
            .toList();
      }

      return [];
    } catch (e) {
      debugPrint('Get user disputes error: $e');
      return [];
    }
  }

  /// Check if a booking can be disputed
  bool canDisputeBooking(String bookingId) {
    try {
      final booking = _bookings.firstWhere((b) => b.id == bookingId, orElse: () => throw StateError('Booking not found'));
      // Can dispute if booking is completed or cancelled (not by customer)
      return booking.status == BookingStatus.completed ||
             (booking.status.isCancelled && booking.cancelledBy != 'customer');
    } catch (e) {
      return false;
    }
  }

  /// Check if booking actions are locked
  bool areBookingActionsLocked(String bookingId) {
    try {
      final booking = _bookings.firstWhere((b) => b.id == bookingId, orElse: () => throw StateError('Booking not found'));

      // Actions locked if dispute is active, system frozen, or admin restrictions
      return booking.isLockedByDispute ||
             isSystemFrozen ||
             isAccountDisabled;
    } catch (e) {
      return false;
    }
  }

  /// Get reason why booking actions are locked
  String? getBookingLockReason(String bookingId) {
    try {
      final booking = _bookings.firstWhere((b) => b.id == bookingId, orElse: () => throw StateError('Booking not found'));

      if (booking.isLockedByDispute) {
        return 'Actions disabled while dispute is under review';
      }

      if (isSystemFrozen) {
        return 'System maintenance in progress. Actions temporarily disabled.';
      }

      if (isAccountDisabled) {
        return 'Account restrictions active. Please contact support.';
      }

      return null;
    } catch (e) {
      return null;
    }
  }

  // ==================== ADMIN OVERRIDE AWARENESS ====================

  /// Check if a booking was last modified by admin
  Future<bool> wasBookingModifiedByAdmin(String bookingId) async {
    return await _systemMonitor.wasBookingModifiedByAdmin(bookingId);
  }

  /// Get admin modification timestamp for a booking
  Future<DateTime?> getBookingAdminModifiedTime(String bookingId) async {
    return await _systemMonitor.getBookingAdminModifiedTime(bookingId);
  }

  /// Check if current user account is disabled
  bool get isCurrentAccountDisabled => _systemMonitor.isAccountDisabled;

  /// Get account disable reason
  String get accountDisableReason => _systemMonitor.disableReason;
}

