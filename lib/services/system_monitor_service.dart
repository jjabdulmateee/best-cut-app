import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// System Monitor Service - Handles global system state and admin controls
class SystemMonitorService extends ChangeNotifier {
  static final SystemMonitorService _instance = SystemMonitorService._internal();
  factory SystemMonitorService() => _instance;

  SystemMonitorService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // ==================== SYSTEM FREEZE MONITORING ====================

  /// Global system freeze status
  bool _isSystemFrozen = false;
  bool get isSystemFrozen => _isSystemFrozen;

  /// System freeze reason/message
  String _freezeReason = '';
  String get freezeReason => _freezeReason;

  /// Stream subscription for system status
  StreamSubscription? _systemStatusSubscription;

  /// Start monitoring system status
  void startSystemMonitoring() {
    _systemStatusSubscription?.cancel();
    _systemStatusSubscription = _firestore
        .collection('platform')
        .doc('config')
        .snapshots()
        .listen(
          (doc) {
            if (doc.exists) {
              final data = doc.data()!;
              final wasFrozen = _isSystemFrozen;
              _isSystemFrozen = data['emergencyFreeze'] == true;
              _freezeReason = data['freezeReason'] ?? 'System is under maintenance';

              // Notify listeners if freeze status changed
              if (wasFrozen != _isSystemFrozen) {
                notifyListeners();
              }
            }
          },
          onError: (error) {
            debugPrint('⚠️ SystemMonitor: platform/config listener error (non-critical): $error');
          },
        );
  }

  /// Stop monitoring system status
  void stopSystemMonitoring() {
    _systemStatusSubscription?.cancel();
    _systemStatusSubscription = null;
  }

  // ==================== ACCOUNT DISABLE MONITORING ====================

  /// Current user account disabled status
  bool _isAccountDisabled = false;
  bool get isAccountDisabled => _isAccountDisabled;

  /// Account disable reason
  String _disableReason = '';
  String get disableReason => _disableReason;

  /// Stream subscription for user account status
  StreamSubscription? _accountStatusSubscription;

  /// Start monitoring current user's account status
  void startAccountMonitoring(String userId) {
    _accountStatusSubscription?.cancel(); // Cancel existing subscription

    _accountStatusSubscription = _firestore
        .collection('users')
        .doc(userId)
        .snapshots()
        .listen(
          (doc) {
            if (doc.exists) {
              final data = doc.data()!;
              final wasDisabled = _isAccountDisabled;
              _isAccountDisabled = data['isDisabled'] == true;
              _disableReason = data['disableReason'] ?? 'Your account has been disabled';

              // Notify listeners if disable status changed
              if (wasDisabled != _isAccountDisabled) {
                notifyListeners();
              }
            }
          },
          onError: (error) {
            debugPrint('⚠️ SystemMonitor: account status listener error (non-critical): $error');
          },
        );
  }

  /// Stop monitoring account status
  void stopAccountMonitoring() {
    _accountStatusSubscription?.cancel();
    _accountStatusSubscription = null;
  }

  // ==================== COMBINED STATUS CHECKS ====================

  /// Check if any critical system restriction is active
  bool get hasSystemRestrictions => _isSystemFrozen || _isAccountDisabled;

  /// Get appropriate error message for current restrictions
  String get restrictionMessage {
    if (_isSystemFrozen) return _freezeReason;
    if (_isAccountDisabled) return _disableReason;
    return '';
  }

  /// Check if booking creation is allowed
  bool get canCreateBookings => !_isSystemFrozen && !_isAccountDisabled;

  /// Check if payments are allowed
  bool get canMakePayments => !_isSystemFrozen && !_isAccountDisabled;

  /// Check if withdrawals are allowed
  bool get canWithdrawFunds => !_isSystemFrozen && !_isAccountDisabled;

  /// Check if profile updates are allowed
  bool get canUpdateProfile => !_isSystemFrozen && !_isAccountDisabled;

  // ==================== LIFECYCLE MANAGEMENT ====================

  /// Initialize monitoring for a user
  void initializeForUser(String userId) {
    startSystemMonitoring();
    startAccountMonitoring(userId);
  }

  /// Cleanup all monitoring
  void cleanup() {
    stopSystemMonitoring();
    stopAccountMonitoring();
    _isSystemFrozen = false;
    _freezeReason = '';
    _isAccountDisabled = false;
    _disableReason = '';
  }

  // ==================== ADMIN OVERRIDE DETECTION ====================

  /// Check if a booking was last modified by admin
  Future<bool> wasBookingModifiedByAdmin(String bookingId) async {
    try {
      final doc = await _firestore.collection('bookings').doc(bookingId).get();
      if (!doc.exists) return false;

      final data = doc.data()!;
      return data['lastModifiedBy'] == 'admin' ||
             data['adminOverride'] == true;
    } catch (e) {
      return false;
    }
  }

  /// Get admin modification timestamp for a booking
  Future<DateTime?> getBookingAdminModifiedTime(String bookingId) async {
    try {
      final doc = await _firestore.collection('bookings').doc(bookingId).get();
      if (!doc.exists) return null;

      final data = doc.data()!;
      final timestamp = data['adminModifiedAt'];
      if (timestamp is Timestamp) {
        return timestamp.toDate();
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  // ==================== UTILITY METHODS ====================

  /// Force refresh system status
  Future<void> refreshSystemStatus() async {
    try {
      final doc = await _firestore.collection('platform').doc('config').get();
      if (doc.exists) {
        final data = doc.data()!;
        _isSystemFrozen = data['emergencyFreeze'] == true;
        _freezeReason = data['freezeReason'] ?? 'System is under maintenance';
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Failed to refresh system status: $e');
    }
  }

  /// Force refresh account status
  Future<void> refreshAccountStatus(String userId) async {
    try {
      final doc = await _firestore.collection('users').doc(userId).get();
      if (doc.exists) {
        final data = doc.data()!;
        _isAccountDisabled = data['isDisabled'] == true;
        _disableReason = data['disableReason'] ?? 'Your account has been disabled';
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Failed to refresh account status: $e');
    }
  }
}