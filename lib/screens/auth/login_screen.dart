import 'package:firebase_auth/firebase_auth.dart' show PhoneAuthCredential;
import 'package:flutter/material.dart';
import '../../services/auth_service.dart';
import '../../main.dart';
import 'signup_screen.dart';
import 'forgot_password_screen.dart';
import 'otp_screen.dart';

class LoginScreen extends StatefulWidget {
  /// Expected role for this login (from role selection screen)
  final UserRole? expectedRole;
  
  const LoginScreen({super.key, this.expectedRole});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _authService = AuthService();
  
  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _errorMessage;

  // Email regex for better validation
  final _emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    // ── Resolve identifier: email OR phone number ──
    // If the user typed a phone number, normalize it to E.164 and look up the
    // account email in `phone_registry`, then continue with the normal
    // email/password sign-in using that email.
    final identifier = _emailController.text.trim();
    String email = identifier;

    if (AuthService.looksLikePhoneNumber(identifier)) {
      final lookup = await _authService.resolveEmailForPhone(identifier);
      if (!mounted) return;
      if (!lookup.isFound) {
        setState(() {
          _isLoading = false;
          _errorMessage = lookup.userMessage;
        });
        return;
      }
      email = lookup.email!;
    }

    // Use role-checked sign-in when a role is expected (centralized in AuthService).
    // This ensures a barber can NEVER enter the customer section and vice versa.
    final AuthResult result;
    if (widget.expectedRole != null) {
      result = await _authService.signInWithRoleCheck(
        email: email,
        password: _passwordController.text,
        expectedRole: widget.expectedRole!,
      );
    } else {
      // Fallback for direct login without role context (unlikely in normal flow)
      result = await _authService.signIn(
        email: email,
        password: _passwordController.text,
      );
    }

    if (!mounted) return;

    if (result.isSuccess) {
      // Navigate to AuthWrapper which will route to the correct screen
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const AuthWrapper()),
        (route) => false,
      );
    } else if (result.isRoleMismatch) {
      // Role mismatch — show friendly dialog with navigation to correct section
      setState(() => _isLoading = false);
      if (mounted) _showRoleMismatchDialog(result.actualRole!);
    } else {
      setState(() {
        _isLoading = false;
        _errorMessage = result.error;
      });
    }
  }

  // ── One-Tap Demo (for evaluators) ─────────────────────────────────────────
  //
  // These numbers are registered in Firebase Console → Authentication →
  // Sign-in method → Phone → "Phone numbers for testing" with code 123456.
  // They go through the SAME native flow as any real number:
  //   verifyPhoneNumber → codeSent → PhoneAuthProvider.credential → signInWithCredential
  // Firebase intercepts test numbers on its backend (no SMS, fixed code), so
  // there is no mock branch or dev flag anywhere in this path.

  static const String _demoCustomerPhone = '+923001234567';
  static const String _demoBarberPhone = '+923007654321';
  static const String _demoOtp = '123456';

  /// Which demo button is currently running (null when idle).
  UserRole? _demoInProgress;
  bool _demoOtpOpen = false;
  bool _demoSignedIn = false;

  bool get _anyActionRunning => _isLoading || _demoInProgress != null;

  Future<void> _handleDemoLogin(UserRole role) async {
    if (_anyActionRunning) return;

    final phone =
        role == UserRole.customer ? _demoCustomerPhone : _demoBarberPhone;

    setState(() {
      _demoInProgress = role;
      _errorMessage = null;
      _demoOtpOpen = false;
      _demoSignedIn = false;
    });

    // Phone is normalized to E.164 inside AuthService before verifyPhoneNumber.
    await _authService.startPhoneVerification(
      phone: phone,
      onCodeSent: (verificationId, resendToken) =>
          _openDemoOtpScreen(phone, role, verificationId, resendToken),
      onVerificationCompleted: (credential) =>
          _onDemoAutoVerified(credential, role),
      onFailed: (message) {
        if (!mounted) return;
        setState(() {
          _demoInProgress = null;
          _errorMessage = message;
        });
      },
    );
  }

  /// Pre-fills the fixed test OTP and auto-submits it through signInWithPhone.
  Future<void> _openDemoOtpScreen(
    String phone,
    UserRole role,
    String verificationId,
    int? resendToken,
  ) async {
    if (!mounted || _demoSignedIn || _demoOtpOpen) return;

    final roleLabel = role == UserRole.customer ? 'Customer' : 'Barber';
    _demoOtpOpen = true;
    final verified = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => OtpScreen(
          phoneNumber: phone,
          verificationId: verificationId,
          resendToken: resendToken,
          title: 'Demo $roleLabel Sign-In',
          initialCode: _demoOtp,
          autoSubmit: true,
          onSubmit: (vid, code) async {
            final result = await _authService.signInWithPhone(
              verificationId: vid,
              smsCode: code,
            );
            if (result.isSuccess) _demoSignedIn = true;
            return result;
          },
          onAutoVerified: (credential) async {
            final result =
                await _authService.signInWithPhoneCredential(credential);
            if (result.isSuccess) _demoSignedIn = true;
            return result;
          },
        ),
      ),
    );
    _demoOtpOpen = false;
    if (!mounted) return;

    if (verified == true || _demoSignedIn) {
      await _finishDemoLogin(role);
    } else {
      setState(() => _demoInProgress = null);
    }
  }

  /// Android instant verification / auto-retrieval path.
  Future<void> _onDemoAutoVerified(
      PhoneAuthCredential credential, UserRole role) async {
    if (!mounted || _demoSignedIn) return;

    final result = await _authService.signInWithPhoneCredential(credential);
    if (!mounted) return;

    if (result.isSuccess) {
      _demoSignedIn = true;
      if (_demoOtpOpen) {
        Navigator.of(context).pop(true); // _openDemoOtpScreen resumes
      } else {
        await _finishDemoLogin(role);
      }
    } else if (!_demoOtpOpen) {
      setState(() {
        _demoInProgress = null;
        _errorMessage = result.error;
      });
    }
  }

  /// Phone sign-in succeeded. Make sure a Firestore profile exists for the demo
  /// account (first sign-in only), then hand off to AuthWrapper which routes by
  /// the profile's role.
  Future<void> _finishDemoLogin(UserRole role) async {
    final result = await _authService.ensureProfileForPhoneUser(
      role: role,
      displayName: role == UserRole.customer ? 'Demo Customer' : 'Demo Barber',
    );
    if (!mounted) return;

    if (!result.isSuccess) {
      setState(() {
        _demoInProgress = null;
        _errorMessage = result.error;
      });
      return;
    }

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AuthWrapper()),
      (route) => false,
    );
  }

  /// Shows a friendly dialog when the user tries to log into the wrong section.
  /// Offers direct navigation to the correct role section.
  void _showRoleMismatchDialog(String actualRole) {
    final isActuallyBarber = actualRole == 'barber';

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.orange[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.swap_horiz, color: Colors.orange[700]),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text('Wrong Section', style: TextStyle(fontSize: 18)),
            ),
          ],
        ),
        content: Text(
          isActuallyBarber
              ? 'This account is registered as a Barber.\n\n'
                'Please use the "Continue as Barber" option to sign in to your barber account.'
              : 'This account is registered as a Customer.\n\n'
                'Please use the "Continue as Customer" option to sign in to your customer account.',
          style: const TextStyle(fontSize: 15, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx); // Close dialog
              // Pop back to welcome screen, then push correct role auth screen
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(
                  builder: (_) => RoleAuthScreen(
                    role: isActuallyBarber ? UserRole.barber : UserRole.customer,
                  ),
                ),
                (route) => route.isFirst, // Keep only the welcome screen
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1A1A1A),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
              elevation: 0,
            ),
            child: Text(
              isActuallyBarber ? 'Go to Barber Login' : 'Go to Customer Login',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  /// Validates the "Email or Phone Number" field.
  String? _validateIdentifier(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) {
      return 'Please enter your email or phone number';
    }

    if (AuthService.looksLikePhoneNumber(v)) {
      final normalized = AuthService.normalizePhoneToE164(v);
      final digits = normalized.replaceAll(RegExp(r'[^\d]'), '');
      if (digits.length < 8) return 'Phone number is too short';
      if (digits.length > 15) return 'Phone number is too long';
      return null;
    }

    if (!_emailRegex.hasMatch(v)) {
      return 'Enter a valid email address or phone number (e.g. 03XX-XXXXXXX)';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final hasExpectedRole = widget.expectedRole != null;
    final isBarber = widget.expectedRole == UserRole.barber;
    final roleTitle = isBarber ? 'Barber' : 'Customer';
    final roleIcon = isBarber ? Icons.content_cut : Icons.person_outline;
    
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: hasExpectedRole 
          ? AppBar(
              backgroundColor: Colors.white,
              elevation: 0,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back, color: Color(0xFF1A1A1A)),
                onPressed: () => Navigator.pop(context),
              ),
            )
          : null,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(height: hasExpectedRole ? 20 : 60),
                
                // Logo (only show if no expected role, i.e., direct access)
                if (!hasExpectedRole) ...[
                  Center(
                    child: Container(
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
                  ),
                  const SizedBox(height: 24),
                ],
                
                const Text(
                  'Welcome Back',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF1A1A1A),
                    letterSpacing: -0.5,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Sign in to continue',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey[600],
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                
                // Show role badge if expected role is set
                if (hasExpectedRole) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF5F5F5),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: const Color(0xFF1A1A1A),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            roleIcon,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Signing in as $roleTitle',
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF1A1A1A),
                              ),
                            ),
                            Text(
                              isBarber ? 'Service provider account' : 'Customer account',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                ],

                // Error message
                if (_errorMessage != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red[200]!),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.error_outline, color: Colors.red[700], size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: TextStyle(color: Colors.red[700], fontSize: 14),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                ],

                // Email OR phone field
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  autocorrect: false,
                  decoration: InputDecoration(
                    labelText: 'Email or Phone Number',
                    hintText: 'you@example.com or 03XX-XXXXXXX',
                    prefixIcon: const Icon(Icons.alternate_email),
                    filled: true,
                    fillColor: const Color(0xFFF5F5F5),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFF1A1A1A), width: 2),
                    ),
                    errorBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.red[400]!, width: 1),
                    ),
                    focusedErrorBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.red[400]!, width: 2),
                    ),
                  ),
                  validator: _validateIdentifier,
                ),
                const SizedBox(height: 16),

                // Password field
                TextFormField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _handleLogin(),
                  decoration: InputDecoration(
                    labelText: 'Password',
                    hintText: 'Enter your password',
                    prefixIcon: const Icon(Icons.lock_outlined),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword ? Icons.visibility_off : Icons.visibility,
                        color: Colors.grey[600],
                      ),
                      onPressed: () {
                        setState(() => _obscurePassword = !_obscurePassword);
                      },
                    ),
                    filled: true,
                    fillColor: const Color(0xFFF5F5F5),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFF1A1A1A), width: 2),
                    ),
                    errorBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.red[400]!, width: 1),
                    ),
                    focusedErrorBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.red[400]!, width: 2),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter your password';
                    }
                    if (value.length < 6) {
                      return 'Password must be at least 6 characters';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),

                // Forgot password
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const ForgotPasswordScreen(),
                        ),
                      );
                    },
                    child: const Text(
                      'Forgot Password?',
                      style: TextStyle(
                        color: Color(0xFF1A1A1A),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Sign In button
                SizedBox(
                  height: 54,
                  child: ElevatedButton(
                    onPressed: _anyActionRunning ? null : _handleLogin,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1A1A1A),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Text(
                            'Sign In',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 28),

                // ── One-Tap Demo (evaluators) ──
                Row(
                  children: [
                    Expanded(child: Divider(color: Colors.grey[300])),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text(
                        'FOR EVALUATORS',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.2,
                          color: Colors.grey[600],
                        ),
                      ),
                    ),
                    Expanded(child: Divider(color: Colors.grey[300])),
                  ],
                ),
                const SizedBox(height: 16),
                // Only show the demo button matching this section's role.
                // With no role context (direct access) both are shown.
                if (widget.expectedRole != UserRole.barber)
                  _DemoButton(
                    icon: Icons.person_outline,
                    label: 'One-Tap Demo Customer',
                    phoneLabel: '+92 300 1234567',
                    isRunning: _demoInProgress == UserRole.customer,
                    enabled: !_anyActionRunning,
                    onPressed: () => _handleDemoLogin(UserRole.customer),
                  ),
                if (!hasExpectedRole) const SizedBox(height: 12),
                if (widget.expectedRole != UserRole.customer)
                  _DemoButton(
                    icon: Icons.content_cut,
                    label: 'One-Tap Demo Barber',
                    phoneLabel: '+92 300 7654321',
                    isRunning: _demoInProgress == UserRole.barber,
                    enabled: !_anyActionRunning,
                    onPressed: () => _handleDemoLogin(UserRole.barber),
                  ),
                const SizedBox(height: 10),
                Text(
                  'Signs in through the real Firebase phone OTP flow using a '
                  'Firebase test number (code 123456 is pre-filled and auto-submitted).',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: Colors.grey[600], height: 1.4),
                ),
                const SizedBox(height: 24),

                // Sign up link
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      "Don't have an account? ",
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 15,
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => SignUpScreen(
                              preSelectedRole: widget.expectedRole,
                            ),
                          ),
                        );
                      },
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(0, 0),
                      ),
                      child: const Text(
                        'Sign Up',
                        style: TextStyle(
                          color: Color(0xFF1A1A1A),
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Prominent one-tap demo button used by evaluators.
class _DemoButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final String phoneLabel;
  final bool isRunning;
  final bool enabled;
  final VoidCallback onPressed;

  const _DemoButton({
    required this.icon,
    required this.label,
    required this.phoneLabel,
    required this.isRunning,
    required this.enabled,
    required this.onPressed,
  });

  static const Color _accent = Color(0xFF1565C0);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 60,
      child: ElevatedButton(
        onPressed: enabled ? onPressed : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: _accent,
          foregroundColor: Colors.white,
          disabledBackgroundColor: _accent.withValues(alpha: isRunning ? 1.0 : 0.45),
          disabledForegroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 0,
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(10),
              ),
              child: isRunning
                  ? const Padding(
                      padding: EdgeInsets.all(8),
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : Icon(icon, size: 20, color: Colors.white),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    isRunning ? 'Verifying with Firebase…' : '$phoneLabel  ·  OTP 123456',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.85),
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.bolt, size: 22, color: Colors.white),
          ],
        ),
      ),
    );
  }
}
