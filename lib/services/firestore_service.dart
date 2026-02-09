import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/barber.dart';
import '../models/slot.dart';
import '../models/customer.dart';
import '../services/auth_service.dart';
import '../services/map_service.dart' hide GeoPoint; // Use Firestore's GeoPoint

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

  /// Get stream of all approved barbers (for map display - shows all shops)
  Stream<List<Barber>> streamApprovedBarbers() {
    return _firestore
        .collection('users')
        .where('role', isEqualTo: UserRole.barber.name)
        .where('status', isEqualTo: BarberStatus.approved.name)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) {
          final data = doc.data();
          data['id'] = doc.id;
          return Barber.fromMap(data);
        }).toList());
  }

  /// Get stream of online barbers only (for booking eligibility)
  Stream<List<Barber>> streamOnlineBarbers() {
    return _firestore
        .collection('users')
        .where('role', isEqualTo: UserRole.barber.name)
        .where('status', isEqualTo: BarberStatus.approved.name)
        .where('isOnline', isEqualTo: true)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) {
          final data = doc.data();
          data['id'] = doc.id;
          return Barber.fromMap(data);
        }).toList());
  }

  /// Get a single barber by ID
  Future<Barber?> getBarber(String barberId) async {
    final doc = await _firestore.collection('users').doc(barberId).get();
    if (doc.exists && doc.data()?['role'] == UserRole.barber.name) {
      final data = doc.data()!;
      data['id'] = doc.id;
      return Barber.fromMap(data);
    }
    return null;
  }

  /// Stream a single barber (for real-time updates)
  Stream<Barber?> streamBarber(String barberId) {
    return _firestore
        .collection('users')
        .doc(barberId)
        .snapshots()
        .map((doc) {
      if (doc.exists && doc.data()?['role'] == UserRole.barber.name) {
        final data = doc.data()!;
        data['id'] = doc.id;
        return Barber.fromMap(data);
      }
      return null;
    });
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

  /// Get booked slots for a barber on a specific date
  Future<Set<String>> getBookedSlots(String barberId, String dateKey) async {
    final date = DateTime.parse(dateKey);
    final startOfDay = DateTime(date.year, date.month, date.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    final snapshot = await _firestore
        .collection('bookings')
        .where('barberId', isEqualTo: barberId)
        .where('bookingDateTime', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
        .where('bookingDateTime', isLessThan: Timestamp.fromDate(endOfDay))
        .where('status', whereIn: ['pending', 'confirmed'])
        .get();

    return snapshot.docs.map((doc) => doc.data()['timeSlot'] as String).toSet();
  }

  /// Stream booked slots for a barber on a specific date
  Stream<Set<String>> streamBookedSlots(String barberId, String dateKey) {
    final date = DateTime.parse(dateKey);
    final startOfDay = DateTime(date.year, date.month, date.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    return _firestore
        .collection('bookings')
        .where('barberId', isEqualTo: barberId)
        .where('bookingDateTime', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
        .where('bookingDateTime', isLessThan: Timestamp.fromDate(endOfDay))
        .where('status', whereIn: ['pending', 'confirmed'])
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => doc.data()['timeSlot'] as String).toSet());
  }

  /// Check if a specific time slot is available
  Future<bool> isSlotAvailable(String barberId, DateTime dateTime, String timeSlot) async {
    final dateKey = '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')}';
    final bookedSlots = await getBookedSlots(barberId, dateKey);
    return !bookedSlots.contains(timeSlot);
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
        'phone': '+92 300 1234567',
        'role': UserRole.barber.name,
        'status': BarberStatus.approved.name,
        'shopName': 'The Gentlemen\'s Club',
        'latitude': 31.5204, // Lahore Center
        'longitude': 74.3587,
        'rating': 4.9,
        'reviewsCount': 127,
        'isOnline': true,
        'priceStartingPKR': 800,
        'avgDurationMinutes': 30,
        'imageUrl': 'https://i.pravatar.cc/150?u=b1',
        'workStartHour': '09:00',
        'workEndHour': '22:00',
        'daysOff': [7], // Sunday Off
        'bio': 'Professional barber with 10+ years of experience. Specializing in modern cuts and classic styles.',
        'address': 'Shop #12, Liberty Market, Lahore',
        'services': ['Haircut', 'Beard Trim', 'Hair Wash', 'Hot Towel Shave'],
        'galleryUrls': [
          'https://images.unsplash.com/photo-1585747860715-2ba37e788b70?w=500',
          'https://images.unsplash.com/photo-1503951914875-452162b0f3f1?w=500',
        ],
      },
      {
        'id': 'b2',
        'email': 'hamza@bestcut.pk',
        'name': 'Hamza Sheikh',
        'phone': '+92 300 9876543',
        'role': UserRole.barber.name,
        'status': BarberStatus.approved.name,
        'shopName': 'Elite Cuts',
        'latitude': 31.5254, // ~500m North
        'longitude': 74.3637,
        'rating': 4.7,
        'reviewsCount': 89,
        'isOnline': true,
        'priceStartingPKR': 1200,
        'avgDurationMinutes': 45,
        'imageUrl': 'https://i.pravatar.cc/150?u=b2',
        'workStartHour': '10:00',
        'workEndHour': '20:00',
        'daysOff': [],
        'bio': 'Premium grooming experience. Expert in fades, textures, and beard styling.',
        'address': 'MM Alam Road, Gulberg III, Lahore',
        'services': ['Premium Haircut', 'Designer Beard', 'Scalp Treatment', 'Hair Coloring'],
        'galleryUrls': [
          'https://images.unsplash.com/photo-1621605815841-db897c45331f?w=500',
        ],
      },
      {
        'id': 'b3',
        'email': 'ahmed@bestcut.pk',
        'name': 'Ahmed Khan',
        'phone': '+92 321 5551234',
        'role': UserRole.barber.name,
        'status': BarberStatus.approved.name,
        'shopName': 'Style Station',
        'latitude': 31.5154, // ~500m South
        'longitude': 74.3527,
        'rating': 4.5,
        'reviewsCount': 56,
        'isOnline': false, // Offline barber for testing
        'priceStartingPKR': 600,
        'avgDurationMinutes': 25,
        'imageUrl': 'https://i.pravatar.cc/150?u=b3',
        'workStartHour': '08:00',
        'workEndHour': '18:00',
        'daysOff': [5, 7], // Friday and Sunday Off
        'bio': 'Quick and affordable cuts. No wait, no fuss.',
        'address': 'Model Town Extension, Lahore',
        'services': ['Basic Haircut', 'Beard Trim', 'Kids Haircut'],
        'galleryUrls': [],
      },
      {
        'id': 'b4',
        'email': 'usman@bestcut.pk',
        'name': 'Usman Malik',
        'phone': '+92 333 7778899',
        'role': UserRole.barber.name,
        'status': BarberStatus.approved.name,
        'shopName': 'The Barber House',
        'latitude': 31.5304, // Further North
        'longitude': 74.3687,
        'rating': 4.8,
        'reviewsCount': 203,
        'isOnline': true,
        'priceStartingPKR': 1500,
        'avgDurationMinutes': 60,
        'imageUrl': 'https://i.pravatar.cc/150?u=b4',
        'workStartHour': '11:00',
        'workEndHour': '23:00',
        'daysOff': [1], // Monday Off
        'bio': 'Luxury grooming experience. Award-winning barber with international certifications.',
        'address': 'DHA Phase 5, Lahore',
        'services': ['Executive Haircut', 'Royal Shave', 'Hair Treatment', 'Facial', 'Massage'],
        'galleryUrls': [
          'https://images.unsplash.com/photo-1599351431202-1e0f0137899a?w=500',
          'https://images.unsplash.com/photo-1622296089863-eb7fc530daa8?w=500',
          'https://images.unsplash.com/photo-1493256338651-d82f7acb2b38?w=500',
        ],
      },
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
