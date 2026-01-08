import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/barber.dart';
import '../models/slot.dart';
import '../models/customer.dart';
import '../services/auth_service.dart';
import '../services/map_service.dart'; // For GeoPoint

/// Firestore Service - Handles all Firestore CRUD operations
class FirestoreService {
  static final FirestoreService _instance = FirestoreService._internal();
  factory FirestoreService() => _instance;
  FirestoreService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // ==================== USERS (CUSTOMERS & BARBERS) ====================

  /// Get user data stream
  Stream<Map<String, dynamic>?> streamUser(String userId) {
    return _firestore.collection('users').doc(userId).snapshots().map((doc) => doc.data());
  }

  /// Get a single user document
  Future<Map<String, dynamic>?> getUser(String userId) async {
    final doc = await _firestore.collection('users').doc(userId).get();
    return doc.data();
  }

  /// Update user data
  Future<void> updateUser(String userId, Map<String, dynamic> data) async {
    await _firestore.collection('users').doc(userId).update({
      ...data,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Update user location
  Future<void> updateUserLocation(String userId, GeoPoint location) async {
    await _firestore.collection('users').doc(userId).update({
      'latitude': location.latitude,
      'longitude': location.longitude,
      'lastLocationUpdate': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // ==================== BARBERS ====================

  /// Get stream of all approved barbers
  Stream<List<Barber>> streamApprovedBarbers() {
    return _firestore
        .collection('users')
        .where('role', isEqualTo: UserRole.barber.name)
        .where('status', isEqualTo: BarberStatus.approved.name)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => Barber.fromMap(doc.data())).toList());
  }

  /// Get a single barber by ID
  Future<Barber?> getBarber(String barberId) async {
    final doc = await _firestore.collection('users').doc(barberId).get();
    if (doc.exists && doc.data()?['role'] == UserRole.barber.name) {
      return Barber.fromMap(doc.data()!);
    }
    return null;
  }

  /// Toggle barber online/offline with location sync
  Future<void> updateBarberAvailability(String barberId, bool isOnline, {GeoPoint? currentLocation}) async {
    final Map<String, dynamic> data = {
      'isOnline': isOnline,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    
    if (currentLocation != null) {
      data['latitude'] = currentLocation.latitude;
      data['longitude'] = currentLocation.longitude;
      data['lastLocationUpdate'] = FieldValue.serverTimestamp();
    }
    
    await _firestore.collection('users').doc(barberId).update(data);
  }

  /// Update barber's working schedule
  Future<void> updateBarberSchedule(String barberId, {
    required String workStartHour,
    required String workEndHour,
    required List<int> daysOff,
  }) async {
    await _firestore.collection('users').doc(barberId).update({
      'workStartHour': workStartHour,
      'workEndHour': workEndHour,
      'daysOff': daysOff,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Update barber's shop gallery
  Future<void> updateBarberGallery(String barberId, List<String> urls) async {
    await _firestore.collection('users').doc(barberId).update({
      'galleryUrls': urls,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // ==================== BOOKINGS ====================

  /// Add a new booking
  Future<void> addBooking(Booking booking) async {
    await _firestore.collection('bookings').doc(booking.id).set(booking.toMap());
  }

  /// Update booking status
  Future<void> updateBookingStatus(String bookingId, BookingStatus status, {String? cancellationReason, String? cancelledBy}) async {
    await _firestore.collection('bookings').doc(bookingId).update({
      'status': status.name,
      'cancellationReason': cancellationReason,
      'cancelledBy': cancelledBy,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Stream customer's bookings
  Stream<List<Booking>> streamCustomerBookings(String customerId) {
    return _firestore
        .collection('bookings')
        .where('customerId', isEqualTo: customerId)
        .orderBy('bookingDateTime', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => Booking.fromMap(doc.data())).toList());
  }

  /// Stream barber's bookings
  Stream<List<Booking>> streamBarberBookings(String barberId) {
    return _firestore
        .collection('bookings')
        .where('barberId', isEqualTo: barberId)
        .orderBy('bookingDateTime', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => Booking.fromMap(doc.data())).toList());
  }

  // ==================== WALLET TRANSACTIONS ====================

  /// Add a new wallet transaction
  Future<void> addWalletTransaction(String userId, Map<String, dynamic> transactionData) async {
    await _firestore.collection('users').doc(userId).collection('transactions').add({
      ...transactionData,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Stream user's wallet transactions
  Stream<List<Map<String, dynamic>>> streamWalletTransactions(String userId) {
    return _firestore
        .collection('users')
        .doc(userId)
        .collection('transactions')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => doc.data()).toList());
  }

  // ==================== BARBER SLOTS / AVAILABILITY ====================

  /// Update barber's closed slots for a specific date
  Future<void> updateBarberClosedSlots(String barberId, String dateKey, Set<int> closedSlots) async {
    await _firestore.collection('barberAvailability').doc('${barberId}_$dateKey').set({
      'barberId': barberId,
      'dateKey': dateKey,
      'closedSlots': closedSlots.toList(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Get stream of barber's closed slots for a specific date
  Stream<Set<int>> streamBarberClosedSlots(String barberId, String dateKey) {
    return _firestore
        .collection('barberAvailability')
        .doc('${barberId}_$dateKey')
        .snapshots()
        .map((doc) {
      if (doc.exists && doc.data() != null && doc.data()!['closedSlots'] is List) {
        return (doc.data()!['closedSlots'] as List).cast<int>().toSet();
      }
      return <int>{};
    });
  }

  // ==================== SEED DATA ====================

  /// Creates initial seed data for testing purposes
  Future<void> createSeedData() async {
    final usersCollection = _firestore.collection('users');
    
    // Check if seed data already exists to prevent duplicates
    final querySnapshot = await usersCollection.limit(1).get();
    if (querySnapshot.docs.isNotEmpty) {
      return;
    }

    final List<Map<String, dynamic>> seedBarbers = [
      {
        'id': 'b1',
        'email': 'ali@bestcut.pk',
        'name': 'Ali Raza',
        'role': UserRole.barber.name,
        'status': BarberStatus.approved.name,
        'shopName': 'The Gentlemen\'s Club',
        'latitude': 31.5204, // Lahore Center
        'longitude': 74.3587,
        'rating': 4.9,
        'isOnline': true,
        'priceStartingPKR': 800,
        'imageUrl': 'https://i.pravatar.cc/150?u=b1',
        'workStartHour': "09:00",
        'workEndHour': "22:00",
        'daysOff': [7], // Sunday Off
        'galleryUrls': [
          'https://images.unsplash.com/photo-1585747860715-2ba37e788b70?w=500',
          'https://images.unsplash.com/photo-1503951914875-452162b0f3f1?w=500',
        ],
      },
      {
        'id': 'b2',
        'email': 'hamza@bestcut.pk',
        'name': 'Hamza Sheikh',
        'role': UserRole.barber.name,
        'status': BarberStatus.approved.name,
        'shopName': 'Elite Cuts',
        'latitude': 31.5254, // ~500m North
        'longitude': 74.3637,
        'rating': 4.7,
        'isOnline': true,
        'priceStartingPKR': 1200,
        'imageUrl': 'https://i.pravatar.cc/150?u=b2',
        'workStartHour': "10:00",
        'workEndHour': "20:00",
        'daysOff': [],
        'galleryUrls': [
          'https://images.unsplash.com/photo-1621605815841-db897c45331f?w=500',
        ],
      }
    ];

    for (final b in seedBarbers) {
      await usersCollection.doc(b['id']).set({
        ...b,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
  }
}
