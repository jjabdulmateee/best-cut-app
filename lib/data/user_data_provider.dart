import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/auth_service.dart';
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
  
  // Customer getters
  int get customerWalletBalance => _userData?['walletBalance'] as int? ?? 0;
  String get customerName => _userData?['name'] as String? ?? '';
  String get customerEmail => _userData?['email'] as String? ?? '';
  String get customerPhone => _userData?['phone'] as String? ?? '';
  String get customerImageUrl => _userData?['imageUrl'] as String? ?? '';
  double get customerRating => (_userData?['rating'] as num?)?.toDouble() ?? 5.0;
  List<Booking> get customerBookings => _bookings;
  List<WalletTransaction> get customerTransactions => _customerTransactions;
  List<Barber> get approvedBarbers => _approvedBarbers;

  // Barber getters
  bool get isBarberOnline => _userData?['isOnline'] as bool? ?? false;
  int get barberWalletBalance => _userData?['walletBalance'] as int? ?? 0;
  String get barberName => _userData?['name'] as String? ?? '';
  String get barberShopName => _userData?['shopName'] as String? ?? '';
  String get barberAddress => _userData?['address'] as String? ?? '';
  String get barberImageUrl => _userData?['imageUrl'] as String? ?? '';
  double get barberRating => (_userData?['rating'] as num?)?.toDouble() ?? 0.0;
  int get barberTotalReviews => _userData?['totalReviews'] as int? ?? 0;
  int get barberPriceStartingPKR => _userData?['priceStartingPKR'] as int? ?? 0;
  List<String> get barberServices => List<String>.from(_userData?['services'] ?? []);
  int get workStartHour => _userData?['workStartHour'] as int? ?? 9;
  int get workEndHour => _userData?['workEndHour'] as int? ?? 18;
  int get slotDurationMinutes => _userData?['slotDurationMinutes'] as int? ?? 30;
  BarberStatus get barberStatus {
    final statusStr = _userData?['status'] as String?;
    return BarberStatus.values.firstWhere(
      (s) => s.name == statusStr,
      orElse: () => BarberStatus.pending,
    );
  }
  List<Booking> get barberBookings => _bookings;
  List<BarberTransaction> get barberTransactions => _barberTransactions;

  // Derived data
  List<Booking> get upcomingBookings => _bookings
      .where((b) => b.status == BookingStatus.confirmed && b.bookingDateTime.isAfter(DateTime.now()))
      .toList()
    ..sort((a, b) => a.bookingDateTime.compareTo(b.bookingDateTime));

  List<Booking> get completedBookings => _bookings
      .where((b) => b.status == BookingStatus.completed)
      .toList();

  List<Booking> get cancelledBookings => _bookings
      .where((b) => b.status.isCancelled)
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
              final typeStr = data['type'] as String? ?? 'payment';
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
                amount: data['amount'] as int? ?? 0,
                description: data['description'] as String? ?? '',
                createdAt: createdAt,
              );
            }).toList();
          } else {
            _barberTransactions = snapshot.docs.map((doc) {
              final data = doc.data();
              final typeStr = data['type'] as String? ?? 'earning';
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
                amount: data['amount'] as int? ?? 0,
                description: data['description'] as String? ?? '',
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
            // Calculate mock distance for now (would use real location in production)
            final mockDistance = (doc.id.hashCode % 50) / 10.0;
            return Barber.fromMap(data, calculatedDistance: mockDistance);
          }).toList();
          notifyListeners();
        });
  }

  /// Clear data on logout
  void clear() {
    _userDataSubscription?.cancel();
    _bookingsSubscription?.cancel();
    _transactionsSubscription?.cancel();
    _userData = null;
    _userRole = null;
    _userId = null;
    _bookings = [];
    _customerTransactions = [];
    _barberTransactions = [];
    _approvedBarbers = [];
    notifyListeners();
  }

  // ==================== CUSTOMER OPERATIONS ====================

  /// Add money to customer wallet
  Future<void> addMoneyToWallet(int amount, String description) async {
    final userId = _userId;
    if (userId == null) return;

    final newBalance = customerWalletBalance + amount;
    
    await _firestore.collection('users').doc(userId).update({
      'walletBalance': newBalance,
    });

    await _firestore.collection('transactions').add({
      'userId': userId,
      'userType': 'customer',
      'type': TransactionType.topUp.name,
      'amount': amount,
      'description': description,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Pay from customer wallet
  Future<bool> payFromWallet(int amount, String description) async {
    final userId = _userId;
    if (userId == null) return false;

    if (customerWalletBalance < amount) return false;

    final newBalance = customerWalletBalance - amount;
    
    await _firestore.collection('users').doc(userId).update({
      'walletBalance': newBalance,
    });

    await _firestore.collection('transactions').add({
      'userId': userId,
      'userType': 'customer',
      'type': TransactionType.payment.name,
      'amount': amount,
      'description': description,
      'createdAt': FieldValue.serverTimestamp(),
    });

    return true;
  }

  /// Refund to customer wallet
  Future<void> refundToWallet(int amount, String description) async {
    final userId = _userId;
    if (userId == null) return;

    final newBalance = customerWalletBalance + amount;
    
    await _firestore.collection('users').doc(userId).update({
      'walletBalance': newBalance,
    });

    await _firestore.collection('transactions').add({
      'userId': userId,
      'userType': 'customer',
      'type': TransactionType.refund.name,
      'amount': amount,
      'description': description,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Create a new booking
  Future<String> createBooking(Booking booking) async {
    final bookingData = booking.toMap();
    bookingData['createdAt'] = FieldValue.serverTimestamp();
    bookingData['updatedAt'] = FieldValue.serverTimestamp();
    
    final doc = await _firestore.collection('bookings').add(bookingData);
    return doc.id;
  }

  /// Cancel booking by customer (50% refund)
  Future<void> cancelBookingByCustomer(String bookingId) async {
    final booking = _bookings.firstWhere((b) => b.id == bookingId);
    final refundAmount = (booking.pricePKR / 2).round();

    await _firestore.collection('bookings').doc(bookingId).update({
      'status': BookingStatus.cancelledByCustomer.name,
      'cancellationReason': 'Cancelled by customer',
      'cancelledBy': 'customer',
      'updatedAt': FieldValue.serverTimestamp(),
    });

    await refundToWallet(refundAmount, 'Refund (50%) for cancelled booking - ${booking.barberName}');
  }

  // ==================== BARBER OPERATIONS ====================

  /// Toggle barber online status
  Future<void> toggleBarberOnlineStatus() async {
    final userId = _userId;
    if (userId == null) return;

    await _firestore.collection('users').doc(userId).update({
      'isOnline': !isBarberOnline,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Update working hours
  Future<void> updateWorkingHours(int startHour, int endHour, int slotDuration) async {
    final userId = _userId;
    if (userId == null) return;

    await _firestore.collection('users').doc(userId).update({
      'workStartHour': startHour,
      'workEndHour': endHour,
      'slotDurationMinutes': slotDuration,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Toggle slot availability
  Future<void> toggleSlotAvailability(String dateKey, int slotIndex) async {
    final userId = _userId;
    if (userId == null) return;

    final docRef = _firestore.collection('slots').doc('${userId}_$dateKey');
    final doc = await docRef.get();
    
    List<int> closedSlots = [];
    if (doc.exists) {
      final data = doc.data();
      closedSlots = List<int>.from(data?['closedSlots'] ?? []);
    }

    if (closedSlots.contains(slotIndex)) {
      closedSlots.remove(slotIndex);
    } else {
      closedSlots.add(slotIndex);
    }

    await docRef.set({
      'barberId': userId,
      'dateKey': dateKey,
      'closedSlots': closedSlots,
      'updatedAt': FieldValue.serverTimestamp(),
    });
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

  /// Complete booking and add earning
  Future<void> completeBooking(String bookingId, int customerRating, String? comment) async {
    final userId = _userId;
    if (userId == null) return;

    final booking = _bookings.firstWhere((b) => b.id == bookingId);

    await _firestore.collection('bookings').doc(bookingId).update({
      'status': BookingStatus.completed.name,
      'customerRating': customerRating,
      'customerRatingComment': comment,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // Add earning
    await _addBarberEarning(booking.pricePKR, 'Haircut - ${booking.customerName ?? 'Customer'}');

    // Update customer rating if exists
    if (booking.customerId != null) {
      await _updateCustomerRating(booking.customerId!, customerRating);
    }
  }

  Future<void> _addBarberEarning(int amount, String description) async {
    final userId = _userId;
    if (userId == null) return;

    final newBalance = barberWalletBalance + amount;
    
    await _firestore.collection('users').doc(userId).update({
      'walletBalance': newBalance,
    });

    await _firestore.collection('transactions').add({
      'userId': userId,
      'userType': 'barber',
      'type': BarberTransactionType.earning.name,
      'amount': amount,
      'description': description,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _updateCustomerRating(String customerId, int newRating) async {
    final customerDoc = await _firestore.collection('users').doc(customerId).get();
    if (!customerDoc.exists) return;

    final customerData = customerDoc.data()!;
    final currentRating = (customerData['rating'] as num?)?.toDouble() ?? 5.0;
    final totalBookings = customerData['totalBookings'] as int? ?? 0;
    
    final updatedRating = ((currentRating * totalBookings) + newRating) / (totalBookings + 1);
    
    await _firestore.collection('users').doc(customerId).update({
      'rating': double.parse(updatedRating.toStringAsFixed(1)),
    });
  }

  /// Cancel booking by barber (100% refund)
  Future<void> cancelBookingByBarber(String bookingId, String reason) async {
    final booking = _bookings.firstWhere((b) => b.id == bookingId);

    await _firestore.collection('bookings').doc(bookingId).update({
      'status': BookingStatus.cancelledByBarber.name,
      'cancellationReason': reason,
      'cancelledBy': 'barber',
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // Refund customer (100%)
    if (booking.customerId != null) {
      final customerDoc = await _firestore.collection('users').doc(booking.customerId!).get();
      if (customerDoc.exists) {
        final currentBalance = customerDoc.data()?['walletBalance'] as int? ?? 0;
        await _firestore.collection('users').doc(booking.customerId!).update({
          'walletBalance': currentBalance + booking.pricePKR,
        });
        
        await _firestore.collection('transactions').add({
          'userId': booking.customerId,
          'userType': 'customer',
          'type': TransactionType.refund.name,
          'amount': booking.pricePKR,
          'description': 'Full refund - Booking cancelled by barber',
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
    }
  }

  /// Withdraw from barber wallet
  Future<bool> withdrawBarberFunds(int amount, String description) async {
    final userId = _userId;
    if (userId == null) return false;

    if (barberWalletBalance < amount) return false;

    final newBalance = barberWalletBalance - amount;
    
    await _firestore.collection('users').doc(userId).update({
      'walletBalance': newBalance,
    });

    await _firestore.collection('transactions').add({
      'userId': userId,
      'userType': 'barber',
      'type': BarberTransactionType.withdrawal.name,
      'amount': amount,
      'description': description,
      'createdAt': FieldValue.serverTimestamp(),
    });

    return true;
  }

  /// Sign out
  Future<void> signOut() async {
    clear();
    await _auth.signOut();
  }
}

