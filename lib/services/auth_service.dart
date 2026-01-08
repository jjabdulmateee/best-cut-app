import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Authentication Service - Handles all Firebase Auth operations
class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Current Firebase user
  User? get currentUser => _auth.currentUser;

  /// Stream of auth state changes
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  /// Check if user is logged in
  bool get isLoggedIn => currentUser != null;

  /// Sign up with email and password
  /// Creates user in Firebase Auth and Firestore users collection
  /// Each user can ONLY have ONE role - either Customer OR Barber
  Future<AuthResult> signUp({
    required String email,
    required String password,
    required String name,
    required String phone,
    required UserRole role,
  }) async {
    try {
      // Create user in Firebase Auth
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      if (credential.user == null) {
        return AuthResult.failure('Failed to create user');
      }

      final userId = credential.user!.uid;

      // Create user document in Firestore with ONLY the selected role
      final Map<String, dynamic> userData = {
        'id': userId,
        'email': email,
        'name': name,
        'phone': phone,
        'role': role.name, // This determines if user is Customer OR Barber
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      // Add role-specific fields based on ONLY the selected role
      if (role == UserRole.customer) {
        // Customer-specific fields
        userData['walletBalance'] = 5000; // Initial wallet balance (PKR)
        userData['rating'] = 5.0;
        userData['totalBookings'] = 0;
        userData['cancelledBookings'] = 0;
        userData['imageUrl'] = 'https://i.pravatar.cc/150?u=$userId';
      } else if (role == UserRole.barber) {
        // Barber-specific fields
        userData['status'] = BarberStatus.pending.name; // Requires admin approval
        userData['shopName'] = '';
        userData['address'] = '';
        userData['latitude'] = 0.0;
        userData['longitude'] = 0.0;
        userData['rating'] = 0.0;
        userData['totalReviews'] = 0;
        userData['priceStartingPKR'] = 0;
        userData['isOnline'] = false;
        userData['services'] = <String>[];
        userData['walletBalance'] = 0;
        userData['imageUrl'] = 'https://i.pravatar.cc/150?u=$userId';
        userData['workStartHour'] = 9;
        userData['workEndHour'] = 18;
        userData['slotDurationMinutes'] = 30;
        userData['avgDurationMinutes'] = 30;
      }

      // Save to Firestore - ONE document per user with their role
      await _firestore.collection('users').doc(userId).set(userData);

      return AuthResult.success(userId);
    } on FirebaseAuthException catch (e) {
      return AuthResult.failure(_getAuthErrorMessage(e.code));
    } on FirebaseException catch (e) {
      return AuthResult.failure(_getAuthErrorMessage(e.code ?? 'unknown'));
    } catch (e) {
      // Log the actual error for debugging
      print('Signup error: $e');
      return AuthResult.failure('Registration failed: ${e.toString().split(']').last.trim()}');
    }
  }

  /// Sign in with email and password
  Future<AuthResult> signIn({
    required String email,
    required String password,
  }) async {
    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      if (credential.user == null) {
        return AuthResult.failure('Failed to sign in');
      }

      return AuthResult.success(credential.user!.uid);
    } on FirebaseAuthException catch (e) {
      return AuthResult.failure(_getAuthErrorMessage(e.code));
    } on FirebaseException catch (e) {
      return AuthResult.failure(_getAuthErrorMessage(e.code ?? 'unknown'));
    } catch (e) {
      print('Signin error: $e');
      return AuthResult.failure('Sign in failed: ${e.toString().split(']').last.trim()}');
    }
  }

  /// Sign out
  Future<void> signOut() async {
    await _auth.signOut();
  }

  /// Send password reset email
  Future<AuthResult> sendPasswordResetEmail(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
      return AuthResult.success(null);
    } on FirebaseAuthException catch (e) {
      return AuthResult.failure(_getAuthErrorMessage(e.code));
    } on FirebaseException catch (e) {
      return AuthResult.failure(_getAuthErrorMessage(e.code ?? 'unknown'));
    } catch (e) {
      return AuthResult.failure('Failed to send reset email');
    }
  }

  /// Get user data from Firestore
  Future<Map<String, dynamic>?> getUserData(String userId) async {
    try {
      final doc = await _firestore.collection('users').doc(userId).get();
      return doc.data();
    } catch (e) {
      print('Get user data error: $e');
      return null;
    }
  }

  /// Stream user data from Firestore
  Stream<Map<String, dynamic>?> streamUserData(String userId) {
    return _firestore
        .collection('users')
        .doc(userId)
        .snapshots()
        .map((doc) => doc.data());
  }

  /// Get user role
  Future<UserRole?> getUserRole(String userId) async {
    final data = await getUserData(userId);
    if (data == null) return null;
    return UserRole.values.firstWhere(
      (r) => r.name == data['role'],
      orElse: () => UserRole.customer,
    );
  }

  /// Check if barber is approved
  Future<BarberStatus> getBarberStatus(String userId) async {
    final data = await getUserData(userId);
    if (data == null) return BarberStatus.pending;
    final statusStr = data['status'] as String?;
    return BarberStatus.values.firstWhere(
      (s) => s.name == statusStr,
      orElse: () => BarberStatus.pending,
    );
  }

  /// Convert Firebase Auth error codes to user-friendly messages
  String _getAuthErrorMessage(String code) {
    switch (code) {
      case 'email-already-in-use':
        return 'This email is already registered. Please sign in instead.';
      case 'invalid-email':
        return 'Please enter a valid email address.';
      case 'operation-not-allowed':
        return 'Email/password accounts are not enabled. Please contact support.';
      case 'weak-password':
        return 'Password is too weak. Use at least 6 characters with numbers.';
      case 'user-disabled':
        return 'This account has been disabled. Please contact support.';
      case 'user-not-found':
        return 'No account found with this email. Please create an account.';
      case 'wrong-password':
        return 'Incorrect password. Please try again.';
      case 'invalid-credential':
        return 'Invalid email or password. Please check and try again.';
      case 'too-many-requests':
        return 'Too many failed attempts. Please try again in a few minutes.';
      case 'network-request-failed':
        return 'Network error. Please check your internet connection.';
      case 'permission-denied':
        return 'Permission denied. Please try again.';
      default:
        return 'Authentication failed. Please try again.';
    }
  }
}

/// Result class for auth operations
class AuthResult {
  final bool isSuccess;
  final String? userId;
  final String? error;

  AuthResult._({
    required this.isSuccess,
    this.userId,
    this.error,
  });

  factory AuthResult.success(String? userId) {
    return AuthResult._(isSuccess: true, userId: userId);
  }

  factory AuthResult.failure(String error) {
    return AuthResult._(isSuccess: false, error: error);
  }
}

/// User roles - A user can ONLY be ONE of these
enum UserRole {
  customer, // Haircut seeker
  barber,   // Service provider
}

/// Barber approval status
enum BarberStatus {
  pending,
  approved,
  rejected,
}

extension BarberStatusExtension on BarberStatus {
  String get displayName {
    switch (this) {
      case BarberStatus.pending:
        return 'Pending Approval';
      case BarberStatus.approved:
        return 'Approved';
      case BarberStatus.rejected:
        return 'Rejected';
    }
  }

  String get description {
    switch (this) {
      case BarberStatus.pending:
        return 'Your application is under review. You will be notified once approved.';
      case BarberStatus.approved:
        return 'Your account is approved. You can now accept bookings.';
      case BarberStatus.rejected:
        return 'Your application was rejected. Please contact support for more information.';
    }
  }
}
