import 'package:firebase_auth/firebase_auth.dart' show PhoneAuthCredential;
import 'package:flutter/material.dart';
import '../../services/auth_service.dart';
import '../../data/user_data_provider.dart';
import '../../config/dev_config.dart';
import '../../main.dart';
import 'otp_screen.dart';

class SignUpScreen extends StatefulWidget {
  /// Pre-selected role from the role selection screen
  /// If provided, the role selector is hidden and this role is used
  final UserRole? preSelectedRole;
  
  const SignUpScreen({super.key, this.preSelectedRole});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _authService = AuthService();

  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  String? _errorMessage;
  late UserRole _selectedRole;

  // Validation patterns
  final _emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');

  @override
  void initState() {
    super.initState();
    // Use pre-selected role or default to customer
    _selectedRole = widget.preSelectedRole ?? UserRole.customer;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  // ── Signup flow ───────────────────────────────────────────────────────────
  //
  //   1. createAuthAccount      → Firebase Auth user + phone uniqueness check
  //   2. startPhoneVerification → Firebase sends OTP (verifyPhoneNumber)
  //   3. OtpScreen              → user enters 6-digit code
  //   4. linkPhoneToCurrentUser → PhoneAuthProvider.credential + linkWithCredential
  //   5. completeSignUpProfile  → Firestore users / barber_applications / phone_registry
  //
  // Cancelling or failing anywhere between 1 and 5 deletes the Auth user.

  /// True once Firebase has linked the verified phone to the new account.
  bool _phoneLinked = false;

  /// True while the OTP screen is on top of the navigation stack.
  bool _otpScreenOpen = false;

  /// Set once the flow has reached a terminal state (profile written OR
  /// aborted) so late Firebase callbacks can't re-enter it.
  bool _flowFinished = false;

  String get _normalizedPhone =>
      AuthService.normalizePhoneToE164(_phoneController.text.trim());

  Future<void> _handleSignUp() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _phoneLinked = false;
      _otpScreenOpen = false;
      _flowFinished = false;
    });

    // Stage 1: Create Auth account, then check the phone isn't already taken.
    final created = await _authService.createAuthAccount(
      email: _emailController.text.trim(),
      password: _passwordController.text,
      phone: _phoneController.text.trim(),
    );
    if (!mounted) return;

    if (!created.isSuccess) {
      setState(() {
        _isLoading = false;
        _errorMessage = created.error;
      });
      return;
    }

    // Stage 2: Ask Firebase to send the OTP. The phone is normalized to E.164
    // inside AuthService before it reaches verifyPhoneNumber.
    await _authService.startPhoneVerification(
      phone: _phoneController.text.trim(),
      onCodeSent: _openOtpScreen,
      onVerificationCompleted: _onPhoneAutoVerified,
      onFailed: (message) => _abortSignUp(message),
    );
  }

  /// Stage 3: Show the OTP screen; on success link the phone & finish signup.
  Future<void> _openOtpScreen(String verificationId, int? resendToken) async {
    if (!mounted || _phoneLinked || _otpScreenOpen) return;

    _otpScreenOpen = true;
    final verified = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => OtpScreen(
          phoneNumber: _normalizedPhone,
          verificationId: verificationId,
          resendToken: resendToken,
          // Stage 4: PhoneAuthProvider.credential + linkWithCredential
          onSubmit: (vid, code) async {
            final result = await _authService.linkPhoneToCurrentUser(
              verificationId: vid,
              smsCode: code,
            );
            if (result.isSuccess) _phoneLinked = true;
            return result;
          },
          onAutoVerified: (credential) async {
            final result =
                await _authService.linkPhoneCredentialToCurrentUser(credential);
            if (result.isSuccess) _phoneLinked = true;
            return result;
          },
        ),
      ),
    );
    _otpScreenOpen = false;
    if (!mounted) return;

    if (verified == true || _phoneLinked) {
      await _completeSignUp();
    } else {
      await _abortSignUp(
          'Phone verification was cancelled. Your account was not created.');
    }
  }

  /// Android instant verification / SMS auto-retrieval: Firebase handed us a
  /// ready credential, so link it directly without the user typing the code.
  Future<void> _onPhoneAutoVerified(PhoneAuthCredential credential) async {
    if (!mounted || _phoneLinked) return;

    final result =
        await _authService.linkPhoneCredentialToCurrentUser(credential);
    if (!mounted) return;

    if (result.isSuccess) {
      _phoneLinked = true;
      if (_otpScreenOpen) {
        // Pop the OTP screen; _openOtpScreen resumes and completes signup.
        Navigator.of(context).pop(true);
      } else {
        await _completeSignUp();
      }
    } else if (!_otpScreenOpen) {
      // No OTP screen to fall back to — surface the error.
      await _abortSignUp(result.error ?? 'Phone verification failed.');
    }
    // If the OTP screen is open and auto-link failed, let the user type the code.
  }

  /// Stage 5: Write the Firestore profile now that the phone is verified.
  Future<void> _completeSignUp() async {
    if (_flowFinished || !mounted) return;
    _flowFinished = true;

    final result = await _authService.completeSignUpProfile(
      name: _nameController.text.trim(),
      email: _emailController.text.trim(),
      phone: _phoneController.text.trim(),
      role: _selectedRole,
    );

    if (!mounted) return;

    if (result.isSuccess) {
      if (_selectedRole == UserRole.barber) {
        // DEV MODE: If approval is disabled, barbers get instant access
        // Show different dialog based on mode
        setState(() => _isLoading = false);
        if (ENABLE_BARBER_APPROVAL) {
          _showBarberPendingDialog();
        } else {
          _showBarberInstantAccessDialog();
        }
      } else {
        // Customer signup - go directly to app
        if (mounted) {
          _showSuccessAndNavigate();
        }
      }
    } else {
      setState(() {
        _isLoading = false;
        _errorMessage = result.error;
      });
    }
  }

  /// Delete the half-created Auth account and show [message] on the form.
  Future<void> _abortSignUp(String message) async {
    if (_flowFinished) return;
    _flowFinished = true; // block any late callbacks from continuing
    await _authService.abortSignUp();
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      _errorMessage = message;
    });
  }

  void _showSuccessAndNavigate() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            Icon(Icons.check_circle, color: Colors.white),
            SizedBox(width: 8),
            Text('Account created successfully!'),
          ],
        ),
        backgroundColor: Color(0xFF00AA5B),
        duration: Duration(seconds: 2),
      ),
    );

    // Navigate to AuthWrapper
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AuthWrapper()),
      (route) => false,
    );
  }

  String? _validateEmail(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please enter your email';
    }
    if (!_emailRegex.hasMatch(value)) {
      return 'Please enter a valid email address';
    }
    return null;
  }

  String? _validatePhone(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please enter your phone number';
    }
    // Normalize to E.164 and validate
    final normalized = AuthService.normalizePhoneToE164(value);
    final digits = normalized.replaceAll(RegExp(r'[^\d]'), '');
    if (digits.length < 8) {
      return 'Phone number is too short';
    }
    if (digits.length > 15) {
      return 'Phone number is too long';
    }
    if (!normalized.startsWith('+')) {
      return 'Please include country code (e.g. +92 for Pakistan)';
    }
    return null;
  }

  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please enter a password';
    }
    if (value.length < 6) {
      return 'Password must be at least 6 characters';
    }
    if (!value.contains(RegExp(r'[0-9]'))) {
      return 'Password must contain at least one number';
    }
    return null;
  }

  void _showBarberPendingDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.orange[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.schedule, color: Colors.orange[700]),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Application Submitted',
                style: TextStyle(fontSize: 18),
              ),
            ),
          ],
        ),
        content: const Text(
          'Your barber application has been submitted successfully!\n\n'
          'Your account is pending approval. You will be notified once your account is approved by the admin.\n\n'
          'In the meantime, you can log in to check your application status.',
          style: TextStyle(fontSize: 15, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () {
              // Clear the navigation stack and go back to welcome screen
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const AuthWrapper()),
                (route) => false,
              );
            },
            child: const Text(
              'Got it',
              style: TextStyle(
                color: Color(0xFF1A1A1A),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // DEV MODE: Instant access dialog for barbers when approval is disabled
  void _showBarberInstantAccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.green[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.check_circle, color: Colors.green[700]),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Account Created!',
                style: TextStyle(fontSize: 18),
              ),
            ),
          ],
        ),
        content: const Text(
          'Your barber account has been created successfully!\n\n'
          'You can now access all barber features and start accepting bookings.',
          style: TextStyle(fontSize: 15, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const AuthWrapper()),
                (route) => false,
              );
            },
            child: const Text(
              'Get Started',
              style: TextStyle(
                color: Color(0xFF1A1A1A),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isBarber = _selectedRole == UserRole.barber;
    final roleTitle = isBarber ? 'Barber' : 'Customer';
    final roleIcon = isBarber ? Icons.content_cut : Icons.person_outline;
    
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
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 20),
                const Text(
                  'Create Account',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF1A1A1A),
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Join Best Cut today',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 24),

                // Show selected role as a badge (not editable when pre-selected)
                if (widget.preSelectedRole != null) ...[
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
                              'Creating as $roleTitle',
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF1A1A1A),
                              ),
                            ),
                            Text(
                              isBarber ? 'Service provider account' : 'Book haircuts',
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
                  const SizedBox(height: 16),
                ] else ...[
                  // Show role selector only if no pre-selected role
                  const Text(
                    'I want to',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1A1A1A),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _RoleOption(
                          icon: Icons.person_outline,
                          label: 'Book Haircuts',
                          subtitle: 'Customer',
                          isSelected: _selectedRole == UserRole.customer,
                          onTap: () {
                            setState(() => _selectedRole = UserRole.customer);
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _RoleOption(
                          icon: Icons.content_cut,
                          label: 'Offer Services',
                          subtitle: 'Barber',
                          isSelected: _selectedRole == UserRole.barber,
                          onTap: () {
                            setState(() => _selectedRole = UserRole.barber);
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
                
                // Barber approval notice (conditional based on dev mode)
                if (isBarber) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: ENABLE_BARBER_APPROVAL ? Colors.blue[50] : Colors.green[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: ENABLE_BARBER_APPROVAL ? Colors.blue[200]! : Colors.green[200]!,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          ENABLE_BARBER_APPROVAL ? Icons.info_outline : Icons.check_circle_outline,
                          color: ENABLE_BARBER_APPROVAL ? Colors.blue[700] : Colors.green[700],
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            ENABLE_BARBER_APPROVAL
                                ? 'Barber accounts require admin approval before activation.'
                                : 'Instant activation - you can start accepting bookings immediately after signup.',
                            style: TextStyle(
                              color: ENABLE_BARBER_APPROVAL ? Colors.blue[700] : Colors.green[700],
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
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
                  const SizedBox(height: 16),
                ],

                // Name field
                TextFormField(
                  controller: _nameController,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  decoration: _inputDecoration(
                    label: 'Full Name',
                    hint: 'Enter your full name',
                    icon: Icons.person_outline,
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter your name';
                    }
                    if (value.length < 2) {
                      return 'Name must be at least 2 characters';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Email field
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  autocorrect: false,
                  decoration: _inputDecoration(
                    label: 'Email',
                    hint: 'Enter your email',
                    icon: Icons.email_outlined,
                  ),
                  validator: _validateEmail,
                ),
                const SizedBox(height: 16),

                // Phone field (E.164 global format, supports all countries)
                TextFormField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.next,
                  decoration: _inputDecoration(
                    label: 'Phone Number',
                    hint: '03XX-XXXXXXX or +92 3XX XXXXXXX',
                    icon: Icons.phone_outlined,
                  ).copyWith(
                    helperText: 'We\'ll send a 6-digit verification code to this number',
                  ),
                  validator: _validatePhone,
                ),
                const SizedBox(height: 16),

                // Password field
                TextFormField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  textInputAction: TextInputAction.next,
                  decoration: _inputDecoration(
                    label: 'Password',
                    hint: 'Min 6 characters with a number',
                    icon: Icons.lock_outlined,
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword ? Icons.visibility_off : Icons.visibility,
                        color: Colors.grey[600],
                      ),
                      onPressed: () {
                        setState(() => _obscurePassword = !_obscurePassword);
                      },
                    ),
                  ),
                  validator: _validatePassword,
                ),
                const SizedBox(height: 16),

                // Confirm Password field
                TextFormField(
                  controller: _confirmPasswordController,
                  obscureText: _obscureConfirmPassword,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _handleSignUp(),
                  decoration: _inputDecoration(
                    label: 'Confirm Password',
                    hint: 'Re-enter your password',
                    icon: Icons.lock_outlined,
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureConfirmPassword ? Icons.visibility_off : Icons.visibility,
                        color: Colors.grey[600],
                      ),
                      onPressed: () {
                        setState(() => _obscureConfirmPassword = !_obscureConfirmPassword);
                      },
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please confirm your password';
                    }
                    if (value != _passwordController.text) {
                      return 'Passwords do not match';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 32),

                // Sign Up button
                SizedBox(
                  height: 54,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _handleSignUp,
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
                        : Text(
                            isBarber ? 'Submit Application' : 'Create Account',
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 24),

                // Sign in link
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Already have an account? ',
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 15,
                      ),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(0, 0),
                      ),
                      child: const Text(
                        'Sign In',
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

  InputDecoration _inputDecoration({
    required String label,
    required String hint,
    required IconData icon,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: Icon(icon),
      suffixIcon: suffixIcon,
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
    );
  }
}

class _RoleOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final bool isSelected;
  final VoidCallback onTap;

  const _RoleOption({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF1A1A1A) : const Color(0xFFF5F5F5),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? const Color(0xFF1A1A1A) : Colors.transparent,
            width: 2,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              size: 32,
              color: isSelected ? Colors.white : const Color(0xFF1A1A1A),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: isSelected ? Colors.white : const Color(0xFF1A1A1A),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 12,
                color: isSelected ? Colors.white70 : Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
