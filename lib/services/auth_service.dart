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

  // ===========================================================================
  // Sign up — staged flow with phone verification
  // ===========================================================================
  //
  // Signup is split into stages so the phone number is verified via Firebase
  // Phone Auth BEFORE any Firestore profile is written:
  //
  //   1. createAuthAccount()        — email/password Auth user + phone uniqueness
  //   2. startPhoneVerification()   — FirebaseAuth.verifyPhoneNumber (sends OTP)
  //   3. linkPhoneToCurrentUser()   — PhoneAuthProvider.credential + linkWithCredential
  //   4. completeSignUpProfile()    — users / barber_applications / phone_registry
  //
  // abortSignUp() deletes the Auth user if the flow is cancelled or fails
  // between stages 1 and 4, so no orphaned accounts are left behind.
  //
  // NOTE: The phone uniqueness check needs an authenticated user because the
  // `phone_registry` Firestore rules deny unauthenticated reads. That is why
  // stage 1 creates the Auth account first and then checks uniqueness — and
  // deletes the account again if the phone is already taken.

  /// Stage 1: Create the Firebase Auth account and check phone uniqueness.
  ///
  /// On success the user is signed in (but has NO Firestore profile yet).
  /// If the phone is already registered, the just-created Auth user is
  /// deleted and a failure is returned.
  Future<AuthResult> createAuthAccount({
    required String email,
    required String password,
    required String phone,
  }) async {
    final normalizedPhone = normalizePhoneToE164(phone);
    print('🔐 AuthService.createAuthAccount: email=$email, phone=$phone → $normalizedPhone');

    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      final user = credential.user;
      if (user == null) {
        print('❌ AuthService.createAuthAccount: credential.user is null');
        return AuthResult.failure('Failed to create user - no user returned');
      }
      print('✅ AuthService.createAuthAccount: Auth user created - UID: ${user.uid}');

      // Phone uniqueness check (requires auth — see note above)
      final existingUserId = await isPhoneNumberTaken(normalizedPhone);
      if (existingUserId != null) {
        print('❌ AuthService.createAuthAccount: Phone $normalizedPhone already registered to $existingUserId');
        await _deleteUserQuietly(user);
        return AuthResult.failure(
            'This phone number is already registered with another account. '
            'Please use a different number or sign in to your existing account.');
      }

      return AuthResult.success(user.uid);
    } on FirebaseAuthException catch (e) {
      print('❌ AuthService.createAuthAccount: FirebaseAuthException - Code: ${e.code}, Message: ${e.message}');
      return AuthResult.failure(_getAuthErrorMessage(e.code));
    } on FirebaseException catch (e) {
      print('❌ AuthService.createAuthAccount: FirebaseException - Code: ${e.code}, Message: ${e.message}');
      return AuthResult.failure(_getAuthErrorMessage(e.code));
    } catch (e) {
      print('❌ AuthService.createAuthAccount: Unexpected error: $e');
      return AuthResult.failure('Registration failed: ${e.toString().split(']').last.trim()}');
    }
  }

  /// Stage 4: Write the Firestore profile for the currently signed-in user.
  ///
  /// Requires that the current user has a VERIFIED phone number linked
  /// (i.e. [linkPhoneToCurrentUser] succeeded) and that it matches [phone].
  /// If any Firestore write fails, the Auth user is deleted so the account
  /// isn't orphaned and the user can retry signup cleanly.
  Future<AuthResult> completeSignUpProfile({
    required String name,
    required String email,
    required String phone,
    required UserRole role,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      return AuthResult.failure('Your session expired. Please sign up again.');
    }

    final normalizedPhone = normalizePhoneToE164(phone);

    // Defensive: the profile must only be created for a phone Firebase has
    // actually verified and linked to this account.
    if (user.phoneNumber != normalizedPhone) {
      print('❌ AuthService.completeSignUpProfile: Verified phone (${user.phoneNumber}) '
          'does not match submitted phone ($normalizedPhone)');
      await _deleteUserQuietly(user);
      return AuthResult.failure(
          'Phone verification did not complete. Please sign up again.');
    }

    try {
      await _writeProfileDocuments(
        userId: user.uid,
        name: name,
        email: email,
        normalizedPhone: normalizedPhone,
        role: role,
      );
      return AuthResult.success(user.uid);
    } catch (firestoreError) {
      // Firestore write failed — delete the auth user so the account isn't orphaned.
      print('💥 AuthService.completeSignUpProfile: Firestore write failed: $firestoreError');
      print('🧹 AuthService.completeSignUpProfile: Cleaning up orphaned auth user...');
      await _deleteUserQuietly(user);
      return AuthResult.failure(
          'Account setup failed. Please check your internet connection and try again.');
    }
  }

  /// Abort an in-progress signup: deletes the current (profile-less) Auth user.
  /// Safe to call when nothing is signed in. Falls back to signOut if the
  /// delete fails (e.g. network) so the app never sits on an orphaned session.
  Future<void> abortSignUp() async {
    final user = _auth.currentUser;
    if (user == null) return;
    print('🧹 AuthService.abortSignUp: Deleting incomplete account ${user.uid}');
    await _deleteUserQuietly(user);
  }

  Future<void> _deleteUserQuietly(User user) async {
    try {
      await user.delete();
      print('✅ AuthService: Auth user ${user.uid} deleted');
    } catch (e) {
      print('⚠️ AuthService: Could not delete auth user ${user.uid}: $e — signing out instead');
      try {
        await _auth.signOut();
      } catch (_) {}
    }
  }

  /// Writes users/{uid}, barber_applications/{uid} (barbers only) and
  /// phone_registry/{phone}. Throws on failure — callers decide cleanup.
  Future<void> _writeProfileDocuments({
    required String userId,
    required String name,
    required String email,
    required String normalizedPhone,
    required UserRole role,
  }) async {
    // Create user document in Firestore with ONLY the selected role
    final Map<String, dynamic> userData = {
      'id': userId,
      'email': email,
      'name': name,
      'phone': normalizedPhone, // Stored in E.164 format for global support
      'phoneVerified': true, // Set only after Firebase Phone Auth succeeded
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

    // Save user profile to Firestore
    print('💾 AuthService: Creating Firestore user document for $userId...');
    await _firestore.collection('users').doc(userId).set(userData);
    print('✅ AuthService: Firestore user document created');

    // If barber, also create a barber application document for admin review
    // DEV MODE: Still create the application document even when approval is disabled
    // (maintains data integrity and keeps infrastructure ready for production)
    if (role == UserRole.barber) {
      print('📋 AuthService: Creating barber application document...');
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
      print('✅ AuthService: Barber application document created');
    }

    // Register phone number for uniqueness enforcement
    print('📱 AuthService: Registering phone in phone_registry...');
    await _registerPhoneNumber(
      e164Phone: normalizedPhone,
      userId: userId,
      role: role,
    );
    print('✅ AuthService: Phone registered successfully');
  }

  // ===========================================================================
  // Firebase Phone Authentication
  // ===========================================================================
  //
  // These methods are plain wrappers over the native Firebase Phone Auth API.
  // There is intentionally NO special-casing of Firebase "test phone numbers":
  // numbers registered in Firebase Console → Authentication → Phone →
  // "Phone numbers for testing" are intercepted by Firebase itself (no SMS is
  // sent, the configured fixed code is accepted) through this exact code path.

  /// Stage 2: Start phone verification via [FirebaseAuth.verifyPhoneNumber].
  ///
  /// [phone] is normalized to E.164 before being sent to Firebase.
  ///
  /// - [onCodeSent] fires when Firebase has dispatched the OTP. Keep the
  ///   `verificationId` — it's needed to build the credential — and the
  ///   `resendToken` for [forceResendingToken] on resend.
  /// - [onVerificationCompleted] (Android only) fires when the SMS was
  ///   auto-retrieved or the number was instantly verified. The credential can
  ///   be passed straight to [linkPhoneCredentialToCurrentUser] /
  ///   [signInWithPhoneCredential] without the user typing anything.
  /// - [onFailed] receives a user-friendly error message.
  Future<void> startPhoneVerification({
    required String phone,
    required void Function(String verificationId, int? resendToken) onCodeSent,
    required void Function(String message) onFailed,
    void Function(PhoneAuthCredential credential)? onVerificationCompleted,
    void Function(String verificationId)? onAutoRetrievalTimeout,
    int? forceResendingToken,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final normalizedPhone = normalizePhoneToE164(phone);
    print('📱 AuthService.startPhoneVerification: $phone → $normalizedPhone'
        '${forceResendingToken != null ? ' (resend)' : ''}');

    try {
      await _auth.verifyPhoneNumber(
        phoneNumber: normalizedPhone,
        timeout: timeout,
        forceResendingToken: forceResendingToken,
        verificationCompleted: (PhoneAuthCredential credential) {
          print('✅ AuthService.startPhoneVerification: verificationCompleted (auto)');
          onVerificationCompleted?.call(credential);
        },
        verificationFailed: (FirebaseAuthException e) {
          print('❌ AuthService.startPhoneVerification: verificationFailed - '
              'Code: ${e.code}, Message: ${e.message}');
          onFailed(_getAuthErrorMessage(e.code));
        },
        codeSent: (String verificationId, int? resendToken) {
          print('📨 AuthService.startPhoneVerification: codeSent');
          onCodeSent(verificationId, resendToken);
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          print('⏰ AuthService.startPhoneVerification: codeAutoRetrievalTimeout');
          onAutoRetrievalTimeout?.call(verificationId);
        },
      );
    } on FirebaseAuthException catch (e) {
      print('❌ AuthService.startPhoneVerification: FirebaseAuthException - Code: ${e.code}');
      onFailed(_getAuthErrorMessage(e.code));
    } catch (e) {
      print('❌ AuthService.startPhoneVerification: Unexpected error: $e');
      onFailed('Could not start phone verification. Please try again.');
    }
  }

  /// Stage 3: Link the verified phone number to the currently signed-in user.
  ///
  /// Builds the credential with [PhoneAuthProvider.credential] from the
  /// [verificationId] returned in `codeSent` and the 6-digit [smsCode] the
  /// user entered, then calls [User.linkWithCredential].
  Future<AuthResult> linkPhoneToCurrentUser({
    required String verificationId,
    required String smsCode,
  }) {
    final credential = PhoneAuthProvider.credential(
      verificationId: verificationId,
      smsCode: smsCode.trim(),
    );
    return linkPhoneCredentialToCurrentUser(credential);
  }

  /// Link an already-built [PhoneAuthCredential] (e.g. from Android
  /// auto-retrieval via `verificationCompleted`) to the current user.
  Future<AuthResult> linkPhoneCredentialToCurrentUser(
      PhoneAuthCredential credential) async {
    final user = _auth.currentUser;
    if (user == null) {
      return AuthResult.failure('Your session expired. Please sign up again.');
    }

    try {
      print('🔗 AuthService.linkPhoneCredentialToCurrentUser: Linking phone to ${user.uid}...');
      final result = await user.linkWithCredential(credential);
      final linkedPhone = result.user?.phoneNumber ?? user.phoneNumber;
      print('✅ AuthService.linkPhoneCredentialToCurrentUser: Linked $linkedPhone');
      return AuthResult.success(user.uid);
    } on FirebaseAuthException catch (e) {
      print('❌ AuthService.linkPhoneCredentialToCurrentUser: FirebaseAuthException - '
          'Code: ${e.code}, Message: ${e.message}');
      return AuthResult.failure(_getAuthErrorMessage(e.code));
    } catch (e) {
      print('❌ AuthService.linkPhoneCredentialToCurrentUser: Unexpected error: $e');
      return AuthResult.failure('Phone verification failed. Please try again.');
    }
  }

  /// Sign in with a phone number using the OTP the user entered.
  ///
  /// Builds the credential with [PhoneAuthProvider.credential] and calls
  /// [FirebaseAuth.signInWithCredential]. Used by the login screen's demo
  /// buttons (and any future phone-login flow).
  Future<AuthResult> signInWithPhone({
    required String verificationId,
    required String smsCode,
  }) {
    final credential = PhoneAuthProvider.credential(
      verificationId: verificationId,
      smsCode: smsCode.trim(),
    );
    return signInWithPhoneCredential(credential);
  }

  /// Sign in with an already-built [PhoneAuthCredential].
  Future<AuthResult> signInWithPhoneCredential(
      PhoneAuthCredential credential) async {
    try {
      print('🔐 AuthService.signInWithPhoneCredential: Signing in with phone credential...');
      final result = await _auth.signInWithCredential(credential);
      final user = result.user;
      if (user == null) {
        return AuthResult.failure('Failed to sign in - no user returned');
      }
      print('✅ AuthService.signInWithPhoneCredential: SUCCESS - UID: ${user.uid}, '
          'Phone: ${user.phoneNumber}, New user: ${result.additionalUserInfo?.isNewUser}');
      return AuthResult.success(user.uid);
    } on FirebaseAuthException catch (e) {
      print('❌ AuthService.signInWithPhoneCredential: FirebaseAuthException - '
          'Code: ${e.code}, Message: ${e.message}');
      return AuthResult.failure(_getAuthErrorMessage(e.code));
    } catch (e) {
      print('❌ AuthService.signInWithPhoneCredential: Unexpected error: $e');
      return AuthResult.failure('Sign in failed. Please try again.');
    }
  }

  /// Ensure a phone-authenticated user has a Firestore profile.
  ///
  /// A user signing in with phone for the very first time has a Firebase Auth
  /// account but no `users/{uid}` document. [AuthWrapper] deliberately never
  /// fabricates profiles, so this creates one (same shape as signup) using the
  /// phone Firebase verified. If a profile already exists it is left untouched
  /// and its existing role wins.
  Future<AuthResult> ensureProfileForPhoneUser({
    required UserRole role,
    required String displayName,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      return AuthResult.failure('Your session expired. Please sign in again.');
    }
    final phone = user.phoneNumber;
    if (phone == null || phone.isEmpty) {
      return AuthResult.failure('No verified phone number on this account.');
    }

    final existing = await getUserData(user.uid);
    if (existing != null) {
      print('ℹ️ AuthService.ensureProfileForPhoneUser: Profile exists (role: ${existing['role']})');
      return AuthResult.success(user.uid);
    }

    try {
      print('🆕 AuthService.ensureProfileForPhoneUser: First sign-in — creating ${role.name} profile');
      await _writeProfileDocuments(
        userId: user.uid,
        name: displayName,
        email: user.email ?? '',
        normalizedPhone: normalizePhoneToE164(phone),
        role: role,
      );
      return AuthResult.success(user.uid);
    } catch (e) {
      print('💥 AuthService.ensureProfileForPhoneUser: Profile creation failed: $e');
      // Don't leave a profile-less session behind — AuthWrapper would show
      // the "Unable to Load Profile" screen.
      try {
        await _auth.signOut();
      } catch (_) {}
      return AuthResult.failure(
          'Account setup failed. Please check your internet connection and try again.');
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

      // ── Phone authentication ──
      case 'invalid-phone-number':
      case 'missing-phone-number':
        return 'Please enter a valid phone number with country code (e.g. +92 3XX XXXXXXX).';
      case 'invalid-verification-code':
        return 'Incorrect verification code. Please check the 6-digit code and try again.';
      case 'invalid-verification-id':
      case 'session-expired':
        return 'This verification code has expired. Please request a new code.';
      case 'credential-already-in-use':
      case 'account-exists-with-different-credential':
        return 'This phone number is already linked to another account.';
      case 'provider-already-linked':
        return 'A phone number is already linked to this account.';
      case 'quota-exceeded':
        return 'SMS limit reached. Please try again later.';
      case 'captcha-check-failed':
      case 'missing-client-identifier':
      case 'app-not-authorized':
        return 'Phone verification could not be completed on this device. Please try again.';
      case 'requires-recent-login':
        return 'Please sign in again to continue.';
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
