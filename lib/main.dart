import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_options.dart';
import 'services/auth_service.dart';
import 'services/system_monitor_service.dart';
import 'config/dev_config.dart';
import 'data/user_data_provider.dart';
import 'screens/main_navigation.dart';
import 'screens/barber/barber_main_navigation.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/signup_screen.dart';
import 'screens/auth/barber_application_status_screen.dart';
import 'screens/maintenance_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  print('🚀 main: Starting app initialization...');

  // Initialize Firebase
  print('🔥 main: Initializing Firebase...');
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  print('✅ main: Firebase initialized successfully');

  // Configure Firestore settings
  print('🔧 main: Configuring Firestore...');
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
    cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
  );
  print('✅ main: Firestore configured');

  // Quick Firebase Auth check (no Firestore query - rules would deny it)
  print('🔍 main: Checking Firebase Auth...');
  final authUser = FirebaseAuth.instance.currentUser;
  print('👤 main: FirebaseAuth currentUser: ${authUser?.uid ?? 'NULL'}');

  // Set preferred orientations
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  runApp(const BestCutApp());
}

class BestCutApp extends StatelessWidget {
  const BestCutApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Best Cut',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1A1A1A),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: Colors.white,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          elevation: 0,
          iconTheme: IconThemeData(color: Color(0xFF1A1A1A)),
          titleTextStyle: TextStyle(
            color: Color(0xFF1A1A1A),
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF1A1A1A),
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
            textStyle: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        textTheme: const TextTheme(
          headlineLarge: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w700,
            color: Color(0xFF1A1A1A),
            letterSpacing: -0.5,
          ),
          headlineMedium: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: Color(0xFF1A1A1A),
          ),
          titleLarge: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Color(0xFF1A1A1A),
          ),
          bodyLarge: TextStyle(
            fontSize: 16,
            color: Color(0xFF1A1A1A),
          ),
          bodyMedium: TextStyle(
            fontSize: 14,
            color: Color(0xFF6B6B6B),
          ),
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          color: Colors.white,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFFF5F5F5),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
        ),
      ),
      home: const SplashScreen(),
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
      ),
    );

    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOutBack),
      ),
    );

    _controller.forward();

    // Navigate after splash
    _navigateAfterSplash();
    // NOTE: Seed data creation removed — Firestore rules deny unauthenticated
    // writes to the users collection, so createSeedData() always fails.
    // Seed data should be managed via admin tools or Cloud Functions.
  }

  Future<void> _navigateAfterSplash() async {
    // Wait for splash animation (2 seconds)
    await Future.delayed(const Duration(milliseconds: 2000));
    
    if (mounted) {
      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) =>
              const AuthWrapper(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
          transitionDuration: const Duration(milliseconds: 400),
        ),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            return FadeTransition(
              opacity: _fadeAnimation,
              child: ScaleTransition(
                scale: _scaleAnimation,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Logo Icon
                    Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A1A1A),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: const Icon(
                        Icons.content_cut,
                        color: Colors.white,
                        size: 50,
                      ),
                    ),
                    const SizedBox(height: 24),
                    // App Name
                    const Text(
                      'Best Cut',
                      style: TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF1A1A1A),
                        letterSpacing: -1,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Skip the wait, book your cut',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey[600],
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// AuthWrapper - Handles authentication state and routes users appropriately
class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  bool _initialized = false;
  final SystemMonitorService _systemMonitor = SystemMonitorService();
  late final Stream<User?> _authStream;
  Future<Map<String, dynamic>?>? _userDataFuture;
  String? _currentUserId;

  @override
  void initState() {
    super.initState();
    // Subscribe to auth state ONCE — never re-register
    _authStream = FirebaseAuth.instance.authStateChanges();
    // System monitoring starts AFTER user data loads (see _initializeAndGetUserData)
    _systemMonitor.addListener(_onSystemStatusChanged);
  }

  @override
  void dispose() {
    _systemMonitor.removeListener(_onSystemStatusChanged);
    _systemMonitor.cleanup();
    super.dispose();
  }

  void _onSystemStatusChanged() {
    if (mounted) setState(() {});
  }

  /// Retry loading user data — resets all cached state and triggers rebuild
  void _retryLoadingUserData() {
    debugPrint('🔄 AuthWrapper: Retrying user data load...');
    setState(() {
      _userDataFuture = null;
      _currentUserId = null;
      _initialized = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: _authStream,
      builder: (context, snapshot) {
        // Still checking auth state from local persistence
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _LoadingScreen();
        }

        // Not logged in — show welcome/role selection screen
        if (!snapshot.hasData || snapshot.data == null) {
          _currentUserId = null;
          _userDataFuture = null;
          UserDataProvider().clear();
          return const WelcomeScreen();
        }

        // User is authenticated — cache the future per userId
        final uid = snapshot.data!.uid;
        if (_currentUserId != uid || _userDataFuture == null) {
          _currentUserId = uid;
          _userDataFuture = _initializeAndGetUserData(uid);
        }

        return FutureBuilder<Map<String, dynamic>?>(
          future: _userDataFuture,
          builder: (context, userSnapshot) {
            // Still loading user data — show spinner
            if (userSnapshot.connectionState == ConnectionState.waiting) {
              return const _LoadingScreen();
            }

            final userData = userSnapshot.data;

            // ── User data is null — show error screen IMMEDIATELY ──
            // No timer, no background polling. The user decides when to retry.
            if (userData == null) {
              debugPrint('🚨 AuthWrapper: User data null for $uid — showing error screen');
              return _buildErrorScreen();
            }

            // ── System / account restrictions ──
            final isAccountDisabled = userData['isDisabled'] == true;
            final disableReason = userData['disableReason'] as String?;
            final isSystemFrozen = _systemMonitor.isSystemFrozen;
            final freezeReason = _systemMonitor.freezeReason;

            if (isSystemFrozen || isAccountDisabled) {
              return MaintenanceScreen(
                isSystemFrozen: isSystemFrozen,
                isAccountDisabled: isAccountDisabled,
                freezeReason: freezeReason,
                disableReason: disableReason,
              );
            }

            // ── Route by role ──
            final role = userData['role'] as String?;

            if (role == UserRole.barber.name) {
              final statusStr = userData['status'] as String?;
              final status = BarberStatus.values.firstWhere(
                (s) => s.name == statusStr,
                orElse: () => BarberStatus.draft,
              );

              // DEV MODE: Skip approval gating when ENABLE_BARBER_APPROVAL is false
              // This allows barbers to access the full app immediately during development
              // while keeping all approval infrastructure intact for production launch.
              if (ENABLE_BARBER_APPROVAL && status.isBlocked) {
                // Unapproved barber → locked into application portal
                return BarberApplicationStatusScreen(
                  status: status,
                  rejectionReason: userData['rejectionReason'] as String?,
                );
              }

              // Approved barber (or approval disabled in dev mode)
              return const BarberMainNavigation();
            }

            // Customer
            return const MainNavigation();
          },
        );
      },
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Error screen — shown instantly when user data can't be loaded.
  // Offers "Try Again" (retry) and "Sign Out" (reset).
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildErrorScreen() {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: Colors.orange[100],
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Icon(
                  Icons.cloud_off_rounded,
                  color: Colors.orange[700],
                  size: 40,
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Unable to Load Profile',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1A1A1A),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'We couldn\'t load your profile. This is usually caused by '
                'a slow internet connection or a temporary server issue.\n\n'
                'Please check your connection and try again.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  color: Colors.grey[600],
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 32),
              // ── Try Again ──
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: _retryLoadingUserData,
                  icon: const Icon(Icons.refresh, size: 20),
                  label: const Text('Try Again', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1A1A1A),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // ── Sign Out ──
              SizedBox(
                width: double.infinity,
                height: 50,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    debugPrint('🔄 AuthWrapper: User chose to sign out');
                    UserDataProvider().clear();
                    await FirebaseAuth.instance.signOut();
                  },
                  icon: const Icon(Icons.logout, size: 20),
                  label: const Text('Sign Out', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red[700],
                    side: BorderSide(color: Colors.red[300]!),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Fetch user data with retry. Returns null only when ALL attempts fail.
  //
  // IMPORTANT — this method NEVER creates a fake "basic profile".
  // Creating a fallback profile is DANGEROUS because:
  //  1. It overwrites existing barber docs with role:'customer'
  //  2. It corrupts real user data
  //  3. It violates Firestore rules (changing protected fields)
  //
  // If the profile truly doesn't exist (partial signup), the user will see
  // the error screen and can sign out, then re-create their account.
  // ─────────────────────────────────────────────────────────────────────────
  Future<Map<String, dynamic>?> _initializeAndGetUserData(String userId) async {
    debugPrint('🔐 AuthWrapper: Loading user data for $userId');

    // Quick sanity check — Firebase must be initialized
    try {
      FirebaseAuth.instance.app;
      FirebaseFirestore.instance.app;
    } catch (e) {
      debugPrint('💥 AuthWrapper: Firebase not initialized: $e');
      return null;
    }

    // Attempt 1
    Map<String, dynamic>? userData;
    try {
      userData = await AuthService().getUserData(userId).timeout(
        const Duration(seconds: 8),
        onTimeout: () {
          debugPrint('⏰ AuthWrapper: Attempt 1 timed out');
          throw TimeoutException('Profile loading timeout');
        },
      );
    } catch (e) {
      debugPrint('⚠️ AuthWrapper: Attempt 1 error: $e');
    }

    // Attempt 2 — wait 2 seconds then retry
    if (userData == null) {
      debugPrint('🔄 AuthWrapper: Attempt 1 returned null, retrying in 2s...');
      await Future.delayed(const Duration(seconds: 2));
      try {
        userData = await AuthService().getUserData(userId).timeout(
          const Duration(seconds: 8),
          onTimeout: () {
            debugPrint('⏰ AuthWrapper: Attempt 2 timed out');
            throw TimeoutException('Profile loading timeout (retry)');
          },
        );
      } catch (e) {
        debugPrint('⚠️ AuthWrapper: Attempt 2 error: $e');
      }
    }

    if (userData == null) {
      debugPrint('❌ AuthWrapper: Both attempts failed for $userId — returning null');
      return null;
    }

    debugPrint('✅ AuthWrapper: Profile loaded — Role: ${userData['role']}');

    // Start background services now that Firestore connection is confirmed working
    if (!_initialized) {
      _initialized = true;
      // System monitoring: reads platform/config (admin-only in rules).
      // For non-admin users the listener will get PERMISSION_DENIED and
      // silently stop — _isSystemFrozen stays false, which is correct.
      _systemMonitor.startSystemMonitoring();
      Future.microtask(() {
        UserDataProvider().initialize().then((_) {
          debugPrint('✅ AuthWrapper: UserDataProvider initialized');
        }).catchError((e) {
          debugPrint('⚠️ AuthWrapper: UserDataProvider init failed (non-critical): $e');
        });
      });
    }

    return userData;
  }
}

class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(
                Icons.content_cut,
                color: Colors.white,
                size: 40,
              ),
            ),
            const SizedBox(height: 24),
            const CircularProgressIndicator(
              color: Color(0xFF1A1A1A),
              strokeWidth: 2,
            ),
          ],
        ),
      ),
    );
  }
}

/// WelcomeScreen - Role selection first (like your screenshot)
/// Users choose "Continue as Customer" or "Continue as Barber" first
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const Spacer(flex: 3),
              // Logo and branding
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A1A),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: const Icon(
                  Icons.content_cut,
                  color: Colors.white,
                  size: 50,
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Best Cut',
                style: TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1A1A1A),
                  letterSpacing: -1,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'The smart way to get your haircut',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey[600],
                ),
                textAlign: TextAlign.center,
              ),
              const Spacer(flex: 4),
              
              // Continue as Customer button (primary action)
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const RoleAuthScreen(role: UserRole.customer),
                      ),
                    );
                  },
                  icon: const Icon(Icons.person_outline, size: 22),
                  label: const Text(
                    'Continue as Customer',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1A1A1A),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              
              // Continue as Barber button (secondary action)
              SizedBox(
                width: double.infinity,
                height: 56,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const RoleAuthScreen(role: UserRole.barber),
                      ),
                    );
                  },
                  icon: const Icon(Icons.content_cut, size: 22),
                  label: const Text(
                    'Continue as Barber',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF1A1A1A),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    side: const BorderSide(
                      color: Color(0xFF1A1A1A),
                      width: 1.5,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 32),
              
              // Terms
              Text.rich(
                TextSpan(
                  text: 'By continuing, you agree to our ',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                  children: const [
                    TextSpan(
                      text: 'Terms of Service',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1A1A1A),
                      ),
                    ),
                    TextSpan(text: ' and '),
                    TextSpan(
                      text: 'Privacy Policy',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1A1A1A),
                      ),
                    ),
                  ],
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}

/// RoleAuthScreen - Shows Sign In / Create Account options for a specific role
class RoleAuthScreen extends StatelessWidget {
  final UserRole role;
  
  const RoleAuthScreen({super.key, required this.role});

  @override
  Widget build(BuildContext context) {
    final isCustomer = role == UserRole.customer;
    final roleTitle = isCustomer ? 'Customer' : 'Barber';
    final roleIcon = isCustomer ? Icons.person_outline : Icons.content_cut;
    
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF1A1A1A)),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const Spacer(flex: 2),
              // Role Icon
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A1A),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Icon(
                  roleIcon,
                  color: Colors.white,
                  size: 40,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                '$roleTitle Account',
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1A1A1A),
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                isCustomer 
                    ? 'Book haircuts from the best barbers'
                    : 'Offer your services and grow your business',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey[600],
                ),
                textAlign: TextAlign.center,
              ),
              
              if (!isCustomer) ...[
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue[200]!),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.blue[700], size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Barber accounts require admin approval before you can accept bookings.',
                          style: TextStyle(color: Colors.blue[700], fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              
              const Spacer(flex: 3),
              
              // Sign In button
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => LoginScreen(expectedRole: role),
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1A1A1A),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: const Text(
                    'Sign In',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              
              // Create Account button
              SizedBox(
                width: double.infinity,
                height: 56,
                child: OutlinedButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => SignUpScreen(preSelectedRole: role),
                      ),
                    );
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF1A1A1A),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    side: const BorderSide(
                      color: Color(0xFF1A1A1A),
                      width: 1.5,
                    ),
                  ),
                  child: const Text(
                    'Create Account',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}

// Keep RoleSelectionScreen for backward compatibility
class RoleSelectionScreen extends StatelessWidget {
  const RoleSelectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const WelcomeScreen();
  }
}
