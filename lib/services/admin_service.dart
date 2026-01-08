import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/auth_service.dart';

/// Admin Service - Handles all admin-specific operations
/// THIS IS THE CORE SECURITY LAYER
class AdminService {
  static final AdminService _instance = AdminService._internal();
  factory AdminService() => _instance;
  AdminService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Check if current user is an admin
  /// This checks against a secure admin list in Firestore
  Future<bool> isCurrentUserAdmin() async {
    final user = _auth.currentUser;
    if (user == null) return false;

    try {
      final adminDoc = await _firestore
          .collection('admins')
          .doc(user.uid)
          .get();

      return adminDoc.exists && adminDoc.data()?['isActive'] == true;
    } catch (e) {
      return false;
    }
  }

  /// Get current admin's details
  Future<Map<String, dynamic>?> getAdminDetails() async {
    final user = _auth.currentUser;
    if (user == null) return null;

    try {
      final adminDoc = await _firestore
          .collection('admins')
          .doc(user.uid)
          .get();

      if (adminDoc.exists) {
        return adminDoc.data();
      }
    } catch (e) {
      return null;
    }
    return null;
  }

  // ==================== BARBER APPROVAL SYSTEM ====================

  /// Stream pending barber applications
  Stream<List<Map<String, dynamic>>> streamPendingBarbers() {
    return _firestore
        .collection('users')
        .where('role', isEqualTo: UserRole.barber.name)
        .where('status', isEqualTo: BarberStatus.pending.name)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => {
          'id': doc.id,
          ...doc.data(),
        }).toList());
  }

  /// Stream approved barbers
  Stream<List<Map<String, dynamic>>> streamApprovedBarbers() {
    return _firestore
        .collection('users')
        .where('role', isEqualTo: UserRole.barber.name)
        .where('status', isEqualTo: BarberStatus.approved.name)
        .orderBy('approvedAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => {
          'id': doc.id,
          ...doc.data(),
        }).toList());
  }

  /// Stream rejected barbers
  Stream<List<Map<String, dynamic>>> streamRejectedBarbers() {
    return _firestore
        .collection('users')
        .where('role', isEqualTo: UserRole.barber.name)
        .where('status', isEqualTo: BarberStatus.rejected.name)
        .orderBy('rejectedAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => {
          'id': doc.id,
          ...doc.data(),
        }).toList());
  }

  /// Approve a barber
  Future<void> approveBarber(String barberId) async {
    final adminUser = _auth.currentUser;
    if (adminUser == null) throw Exception('Not authenticated');

    // Security: Verify admin status
    if (!await isCurrentUserAdmin()) {
      throw Exception('Unauthorized: Admin access required');
    }

    await _firestore.collection('users').doc(barberId).update({
      'status': BarberStatus.approved.name,
      'approvedAt': FieldValue.serverTimestamp(),
      'approvedBy': adminUser.uid,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // Log the action
    await _logAdminAction(
      action: 'approve_barber',
      targetId: barberId,
      adminId: adminUser.uid,
    );
  }

  /// Reject a barber with reason
  Future<void> rejectBarber(String barberId, String reason) async {
    final adminUser = _auth.currentUser;
    if (adminUser == null) throw Exception('Not authenticated');

    if (!await isCurrentUserAdmin()) {
      throw Exception('Unauthorized: Admin access required');
    }

    await _firestore.collection('users').doc(barberId).update({
      'status': BarberStatus.rejected.name,
      'rejectedAt': FieldValue.serverTimestamp(),
      'rejectedBy': adminUser.uid,
      'rejectionReason': reason,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    await _logAdminAction(
      action: 'reject_barber',
      targetId: barberId,
      adminId: adminUser.uid,
      metadata: {'reason': reason},
    );
  }

  /// Disable an approved barber
  Future<void> disableBarber(String barberId, String reason) async {
    final adminUser = _auth.currentUser;
    if (adminUser == null) throw Exception('Not authenticated');

    if (!await isCurrentUserAdmin()) {
      throw Exception('Unauthorized: Admin access required');
    }

    await _firestore.collection('users').doc(barberId).update({
      'status': BarberStatus.rejected.name,
      'isOnline': false,
      'disabledAt': FieldValue.serverTimestamp(),
      'disabledBy': adminUser.uid,
      'disableReason': reason,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    await _logAdminAction(
      action: 'disable_barber',
      targetId: barberId,
      adminId: adminUser.uid,
      metadata: {'reason': reason},
    );
  }

  // ==================== REVIEW MODERATION ====================

  /// Get all reviews for moderation
  Stream<List<Map<String, dynamic>>> streamAllReviews() {
    return _firestore
        .collection('reviews')
        .orderBy('createdAt', descending: true)
        .limit(100)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => {
          'id': doc.id,
          ...doc.data(),
        }).toList());
  }

  /// Hide a review
  Future<void> hideReview(String reviewId, String reason) async {
    if (!await isCurrentUserAdmin()) {
      throw Exception('Unauthorized');
    }

    await _firestore.collection('reviews').doc(reviewId).update({
      'isHidden': true,
      'hiddenReason': reason,
      'hiddenAt': FieldValue.serverTimestamp(),
      'hiddenBy': _auth.currentUser?.uid,
    });

    await _logAdminAction(
      action: 'hide_review',
      targetId: reviewId,
      adminId: _auth.currentUser!.uid,
      metadata: {'reason': reason},
    );
  }

  // ==================== ADMIN LOGGING ====================

  Future<void> _logAdminAction({
    required String action,
    required String targetId,
    required String adminId,
    Map<String, dynamic>? metadata,
  }) async {
    await _firestore.collection('adminLogs').add({
      'action': action,
      'targetId': targetId,
      'adminId': adminId,
      'metadata': metadata ?? {},
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  // ==================== ADMIN SETUP (ONE-TIME) ====================

  /// Create an admin account - ONLY USE THIS MANUALLY IN FIRESTORE CONSOLE
  /// This is NOT exposed in the app for security
  static Future<void> _createAdminManually(String userId, String email) async {
    final firestore = FirebaseFirestore.instance;
    await firestore.collection('admins').doc(userId).set({
      'email': email,
      'isActive': true,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }
}

