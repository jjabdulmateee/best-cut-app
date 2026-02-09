import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../config/dev_config.dart';

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
    print('🔐 AuthService.signUp: Starting signup for email: $email, role: ${role.name}');

    // Normalize phone to E.164 before anything else
    final normalizedPhone = normalizePhoneToE164(phone);
    print('📱 AuthService.signUp: Normalized phone: $phone → $normalizedPhone');

    try {
      // Create user in Firebase Auth
      print('📧 AuthService.signUp: Calling Firebase createUserWithEmailAndPassword...');
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      print('🔑 AuthService.signUp: Firebase createUserWithEmailAndPassword completed');

      if (credential.user == null) {
        print('❌ AuthService.signUp: credential.user is null');
        return AuthResult.failure('Failed to create user - no user returned');
      }

      final userId = credential.user!.uid;
      final userEmail = credential.user!.email;
      print('✅ AuthService.signUp: Firebase Auth SUCCESS - UID: $userId, Email: $userEmail');

      // Check phone uniqueness AFTER auth creation (we need auth to read Firestore)
      final existingUserId = await isPhoneNumberTaken(normalizedPhone);
      if (existingUserId != null) {
        // Phone already taken — delete the just-created auth user and abort
        print('❌ AuthService.signUp: Phone $normalizedPhone already registered to $existingUserId');
        await credential.user!.delete();
        return AuthResult.failure(
            'This phone number is already registered with another account. '
            'Please use a different number or sign in to your existing account.');
      }

      // Create user document in Firestore with ONLY the selected role
      final Map<String, dynamic> userData = {
        'id': userId,
        'email': email,
        'name': name,
        'phone': normalizedPhone, // Stored in E.164 format for global support
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
        userData['savedAddresses'] = <Map<String, dynamic>>[];
        userData['notificationPrefs'] = {
          'bookingUpdates': true,
          'promotions': true,
        };
      } else if (role == UserRole.barber) {
        // Barber-specific fields
        // DEV MODE: If approval is disabled, barbers are instantly approved
        final barberStatus = ENABLE_BARBER_APPROVAL 
            ? BarberStatus.draft.name 
            : BarberStatus.approved.name;
        
        userData['status'] = barberStatus; // Requires admin approval (or instant in dev mode)
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
        userData['notificationPrefs'] = {
          'bookingUpdates': true,
          'promotions': true,
        };
        
        if (!ENABLE_BARBER_APPROVAL) {
          print('⚠️ DEV MODE: Barber approval disabled - auto-approving barber');
        }
      }

      // ── Firestore writes (wrapped so we can clean up on failure) ──
      // If ANY Firestore write fails, delete the Firebase Auth user to prevent
      // orphaned accounts. Without this cleanup, the user can't sign up again
      // (email-already-in-use) and can't sign in (no Firestore profile).
      try {
        // Save user profile to Firestore
        print('💾 AuthService.signUp: Creating Firestore user document for $userId...');
        await _firestore.collection('users').doc(userId).set(userData);
        print('✅ AuthService.signUp: Firestore user document created');

        // If barber, also create a barber application document for admin review
        // DEV MODE: Still create the application document even when approval is disabled
        // (maintains data integrity and keeps infrastructure ready for production)
        if (role == UserRole.barber) {
          print('📋 AuthService.signUp: Creating barber application document...');
          final applicationStatus = ENABLE_BARBER_APPROVAL 
              ? BarberStatus.draft.name 
              : BarberStatus.approved.name;
          
          await _firestore.collection('barber_applications').doc(userId).set({
            'userId': userId,
            'name': name,
            'email': email,
            'phone': normalizedPhone,
            'status': applicationStatus,
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
          print('✅ AuthService.signUp: Barber application document created');
        }

        // Register phone number for uniqueness enforcement
        print('📱 AuthService.signUp: Registering phone in phone_registry...');
        await _registerPhoneNumber(
          e164Phone: normalizedPhone,
          userId: userId,
          role: role,
        );
        print('✅ AuthService.signUp: Phone registered successfully');
      } catch (firestoreError) {
        // Firestore write failed — delete the auth user so the account isn't orphaned.
        // The user will be able to retry signup cleanly.
        print('💥 AuthService.signUp: Firestore write failed: $firestoreError');
        print('🧹 AuthService.signUp: Cleaning up orphaned auth user...');
        try {
          await credential.user!.delete();
          print('✅ AuthService.signUp: Orphaned auth user deleted');
        } catch (deleteError) {
          print('⚠️ AuthService.signUp: Could not delete orphaned auth user: $deleteError');
        }
        return AuthResult.failure(
          'Account setup failed. Please check your internet connection and try again.');
      }

      return AuthResult.success(userId);
    } on FirebaseAuthException catch (e) {
      print('❌ AuthService.signUp: FirebaseAuthException - Code: ${e.code}, Message: ${e.message}');
      return AuthResult.failure(_getAuthErrorMessage(e.code));
    } on FirebaseException catch (e) {
      print('❌ AuthService.signUp: FirebaseException - Code: ${e.code ?? 'unknown'}, Message: ${e.message}');
      return AuthResult.failure(_getAuthErrorMessage(e.code ?? 'unknown'));
    } catch (e) {
      print('❌ AuthService.signUp: Unexpected error: $e');
      return AuthResult.failure('Registration failed: ${e.toString().split(']').last.trim()}');
    }
  }

  /// Sign in with email and password
  Future<AuthResult> signIn({
    required String email,
    required String password,
  }) async {
    print('🔐 AuthService.signIn: Starting sign in for email: $email');

    try {
      print('📧 AuthService.signIn: Calling Firebase signInWithEmailAndPassword...');
      final credential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      print('🔑 AuthService.signIn: Firebase signInWithEmailAndPassword completed');

      if (credential.user == null) {
        print('❌ AuthService.signIn: credential.user is null');
        return AuthResult.failure('Failed to sign in - no user returned');
      }

      final uid = credential.user!.uid;
      final userEmail = credential.user!.email;
      print('✅ AuthService.signIn: SUCCESS - UID: $uid, Email: $userEmail');
      print('🔍 AuthService.signIn: Checking auth.currentUser...');
      print('👤 AuthService.signIn: auth.currentUser: ${_auth.currentUser?.uid ?? 'NULL'}');

      return AuthResult.success(uid);
    } on FirebaseAuthException catch (e) {
      print('❌ AuthService.signIn: FirebaseAuthException - Code: ${e.code}, Message: ${e.message}');
      return AuthResult.failure(_getAuthErrorMessage(e.code));
    } on FirebaseException catch (e) {
      print('❌ AuthService.signIn: FirebaseException - Code: ${e.code ?? 'unknown'}, Message: ${e.message}');
      return AuthResult.failure(_getAuthErrorMessage(e.code ?? 'unknown'));
    } catch (e) {
      print('❌ AuthService.signIn: Unexpected error: $e');
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
      print('🔍 AuthService: Fetching user data for $userId');
      final doc = await _firestore.collection('users').doc(userId).get();

      if (doc.exists) {
        final data = doc.data();
        print('✅ AuthService: User data found - Role: ${data?['role']}, Status: ${data?['status']}');
        return data;
      } else {
        print('❌ AuthService: User document does not exist for $userId');
        return null;
      }
    } catch (e) {
      print('💥 AuthService: Error fetching user data for $e');
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

  /// Check barber approval status from user document (quick access)
  Future<BarberStatus> getBarberStatus(String userId) async {
    final data = await getUserData(userId);
    if (data == null) return BarberStatus.draft;
    final statusStr = data['status'] as String?;
    return BarberStatus.values.firstWhere(
      (s) => s.name == statusStr,
      orElse: () => BarberStatus.draft,
    );
  }

  /// Get barber application status from /barber_applications/{uid}
  /// This is the canonical source of truth for barber approval status.
  /// Used by BarberApplicationStatusScreen to refresh status from the application collection.
  Future<BarberStatus> getBarberApplicationStatus(String userId) async {
    try {
      final doc = await _firestore.collection('barber_applications').doc(userId).get();
      if (!doc.exists) {
        // No application doc found - fallback to user doc status
        return getBarberStatus(userId);
      }
      final statusStr = doc.data()?['status'] as String?;
      return BarberStatus.values.firstWhere(
        (s) => s.name == statusStr,
        orElse: () => BarberStatus.draft,
      );
    } catch (e) {
      print('💥 AuthService: Error fetching barber application: $e');
      // Fallback to user doc status on error
      return getBarberStatus(userId);
    }
  }

  // ===========================================================================
  // Role-safe sign-in (centralized role validation)
  // ===========================================================================

  /// Sign in with email, password, AND expected role validation.
  /// If the account's role doesn't match [expectedRole], the user is
  /// immediately signed out and a [AuthResult.roleMismatch] is returned.
  ///
  /// This is the ONLY sign-in method that should be called from role-specific
  /// login screens (customer login, barber login). It ensures a barber can
  /// never enter the customer section and vice versa.
  Future<AuthResult> signInWithRoleCheck({
    required String email,
    required String password,
    required UserRole expectedRole,
  }) async {
    // Step 1: Basic Firebase Auth sign-in
    final result = await signIn(email: email, password: password);
    if (!result.isSuccess || result.userId == null) return result;

    // Step 2: Fetch user data to verify role
    final userData = await getUserData(result.userId!);
    if (userData == null) {
      await signOut();
      return AuthResult.failure(
          'Unable to verify your account. Please try again.');
    }

    // Step 3: Role check — enforce strict separation
    final userRole = userData['role'] as String?;
    if (userRole != expectedRole.name) {
      // IMMEDIATELY sign out — user must not remain authenticated
      await signOut();

      final actualRoleName = userRole == 'barber' ? 'Barber' : 'Customer';
      final expectedRoleName =
          expectedRole == UserRole.barber ? 'Barber' : 'Customer';

      return AuthResult.roleMismatch(
        actualRole: userRole ?? 'unknown',
        message: 'This account is registered as a $actualRoleName.\n'
            'You are trying to sign in from the $expectedRoleName section.',
      );
    }

    return result;
  }

  // ===========================================================================
  // Phone number handling (E.164 format, global support)
  // ===========================================================================

  /// Normalize a phone number to E.164 format.
  ///
  /// Handles:
  /// - Pakistan local: `03001234567`  → `+923001234567`
  /// - Pakistan with country code: `923001234567` → `+923001234567`
  /// - International: `+14155552671` → `+14155552671` (kept as-is)
  /// - Strips spaces, dashes, parentheses
  ///
  /// E.164 is the global standard used by Twilio, Firebase Phone Auth, etc.
  /// Ready for future OTP verification and password recovery.
  static String normalizePhoneToE164(String phone) {
    String cleaned = phone.trim();
    final hasPlus = cleaned.startsWith('+');
    // Strip all non-digit characters
    cleaned = cleaned.replaceAll(RegExp(r'[^\d]'), '');

    if (hasPlus && cleaned.isNotEmpty) {
      // Already has +, just re-attach it
      return '+$cleaned';
    }

    // Pakistan local format: 03XX... → +923XX...
    if (cleaned.startsWith('03') && cleaned.length >= 10) {
      return '+92${cleaned.substring(1)}';
    }

    // Already has country code without +: 923XX... → +923XX...
    if (cleaned.startsWith('92') && cleaned.length >= 11) {
      return '+$cleaned';
    }

    // Fallback: attach + prefix (user should provide country code)
    return '+$cleaned';
  }

  /// Check if a phone number is already registered.
  /// Uses the `/phone_registry/{e164Phone}` collection for O(1) lookup.
  /// Returns the existing userId if taken, null otherwise.
  Future<String?> isPhoneNumberTaken(String e164Phone) async {
    try {
      final doc =
          await _firestore.collection('phone_registry').doc(e164Phone).get();
      if (doc.exists) {
        return doc.data()?['userId'] as String?;
      }
      return null;
    } catch (e) {
      print('⚠️ AuthService: Phone uniqueness check failed: $e');
      // On error, allow signup to proceed (don't block on transient errors)
      return null;
    }
  }

  /// Register a phone number in the registry (called during signup).
  Future<void> _registerPhoneNumber({
    required String e164Phone,
    required String userId,
    required UserRole role,
  }) async {
    await _firestore.collection('phone_registry').doc(e164Phone).set({
      'userId': userId,
      'role': role.name,
      'createdAt': FieldValue.serverTimestamp(),
    });
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

  /// True when login succeeded but the account role doesn't match
  /// the section the user tried to log in from (e.g. barber in customer login).
  final bool isRoleMismatch;

  /// The actual role of the account (set when isRoleMismatch == true).
  final String? actualRole;

  AuthResult._({
    required this.isSuccess,
    this.userId,
    this.error,
    this.isRoleMismatch = false,
    this.actualRole,
  });

  factory AuthResult.success(String? userId) {
    return AuthResult._(isSuccess: true, userId: userId);
  }

  factory AuthResult.failure(String error) {
    return AuthResult._(isSuccess: false, error: error);
  }

  /// Login succeeded but the account belongs to a different role.
  /// The user has already been signed out automatically.
  factory AuthResult.roleMismatch({
    required String actualRole,
    required String message,
  }) {
    return AuthResult._(
      isSuccess: false,
      error: message,
      isRoleMismatch: true,
      actualRole: actualRole,
    );
  }
}

/// User roles - A user can ONLY be ONE of these
enum UserRole {
  customer, // Haircut seeker
  barber,   // Service provider
}

/// Barber application/approval status
/// Status lifecycle: draft → submitted → underReview → approved/rejected/needMoreDocs
enum BarberStatus {
  draft,        // Initial state after barber signup
  submitted,    // Barber has submitted their application for review
  underReview,  // Admin is actively reviewing the application
  needMoreDocs, // Admin requested additional documents from the barber
  approved,     // Barber is approved to provide services
  rejected,     // Application was rejected
  pending,      // Legacy status - treated same as draft for backward compatibility
}

extension BarberStatusExtension on BarberStatus {
  String get displayName {
    switch (this) {
      case BarberStatus.draft:
      case BarberStatus.pending:
        return 'Thank you for applying';
      case BarberStatus.submitted:
        return 'Application Submitted';
      case BarberStatus.underReview:
        return 'Under Review';
      case BarberStatus.needMoreDocs:
        return 'Additional Documents Required';
      case BarberStatus.approved:
        return 'Approved';
      case BarberStatus.rejected:
        return 'Application Rejected';
    }
  }

  String get description {
    switch (this) {
      case BarberStatus.draft:
      case BarberStatus.pending:
        return 'We are reviewing your application.\nOur team may request additional documents.\nYou will be notified once approved.\n\nہم آپ کی درخواست کا جائزہ لے رہے ہیں۔\nہماری ٹیم مزید دستاویزات کی درخواست کر سکتی ہے۔\nمنظوری کے بعد آپ کو مطلع کیا جائے گا۔';
      case BarberStatus.submitted:
        return 'Your application has been submitted and is in the review queue.\nWe will notify you once our team begins reviewing.\n\nآپ کی درخواست جمع کرا دی گئی ہے اور جائزے کی قطار میں ہے۔';
      case BarberStatus.underReview:
        return 'Your application is currently being reviewed by our team.\nThis usually takes 24-48 hours. We appreciate your patience.\n\nآپ کی درخواست ہماری ٹیم کے جائزے میں ہے۔';
      case BarberStatus.needMoreDocs:
        return 'We need additional documents to process your application.\nPlease check your email for details on what is needed.\n\nآپ کی درخواست پر کارروائی کے لیے مزید دستاویزات درکار ہیں۔';
      case BarberStatus.approved:
        return 'Your account is approved! You can now accept bookings and offer your services.';
      case BarberStatus.rejected:
        return 'Your application was not approved at this time.\nPlease contact support for more information.\n\nآپ کی درخواست اس وقت منظور نہیں ہوئی۔';
    }
  }

  /// Whether this status blocks barber from using barber features.
  /// Only 'approved' barbers can access barber features (services, bookings, go online).
  bool get isBlocked => this != BarberStatus.approved;
}
