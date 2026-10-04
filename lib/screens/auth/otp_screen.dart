import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/auth_service.dart';

/// OTP Verification Screen — accepts the 6-digit code sent by Firebase Phone Auth.
///
/// This screen is deliberately agnostic about WHAT happens with the code:
/// the caller supplies [onSubmit] (e.g. link the phone to the current user during
/// signup, or sign in with the phone for the login demo). The screen pops with
/// `true` once [onSubmit] succeeds, or `null`/`false` if the user backs out.
///
/// Resending is handled here via [AuthService.startPhoneVerification] with the
/// `forceResendingToken` Firebase handed back in `codeSent`.
class OtpScreen extends StatefulWidget {
  /// Phone number in E.164 format (already normalized by the caller).
  final String phoneNumber;

  /// `verificationId` from the `codeSent` callback.
  final String verificationId;

  /// `resendToken` from the `codeSent` callback (Android only, may be null).
  final int? resendToken;

  /// Called with the current verificationId and the 6-digit code.
  final Future<AuthResult> Function(String verificationId, String smsCode)
      onSubmit;

  /// Optional: called when Android auto-retrieves/instantly verifies the number
  /// after a resend and the credential carries no readable SMS code.
  final Future<AuthResult> Function(PhoneAuthCredential credential)?
      onAutoVerified;

  /// Heading shown at the top of the screen.
  final String title;

  /// Optional code to pre-fill (used by the evaluator demo buttons).
  final String? initialCode;

  /// When true and [initialCode] is a full 6-digit code, the screen submits
  /// automatically on first frame.
  final bool autoSubmit;

  const OtpScreen({
    super.key,
    required this.phoneNumber,
    required this.verificationId,
    required this.onSubmit,
    this.resendToken,
    this.onAutoVerified,
    this.title = 'Verify your phone',
    this.initialCode,
    this.autoSubmit = false,
  });

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  static const int _codeLength = 6;
  static const int _resendCooldownSeconds = 60;

  final _codeController = TextEditingController();
  final _focusNode = FocusNode();
  final _authService = AuthService();

  late String _verificationId;
  int? _resendToken;

  bool _isSubmitting = false;
  bool _isResending = false;
  bool _completed = false;
  String? _errorMessage;
  String? _infoMessage;

  Timer? _cooldownTimer;
  int _secondsLeft = _resendCooldownSeconds;

  bool get _hasFullCode => _codeController.text.length == _codeLength;

  @override
  void initState() {
    super.initState();
    _verificationId = widget.verificationId;
    _resendToken = widget.resendToken;
    _startCooldown();

    final initial = widget.initialCode;
    if (initial != null && initial.isNotEmpty) {
      _codeController.text = initial;
      if (widget.autoSubmit && initial.length == _codeLength) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _submit());
      }
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focusNode.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _codeController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  // ── Cooldown ──────────────────────────────────────────────────────────────

  void _startCooldown() {
    _cooldownTimer?.cancel();
    _secondsLeft = _resendCooldownSeconds;
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_secondsLeft <= 1) {
        timer.cancel();
        setState(() => _secondsLeft = 0);
      } else {
        setState(() => _secondsLeft--);
      }
    });
  }

  // ── Submit ────────────────────────────────────────────────────────────────

  Future<void> _submit() async {
    if (_isSubmitting || _completed) return;
    final code = _codeController.text.trim();
    if (code.length != _codeLength) {
      setState(() => _errorMessage = 'Please enter the $_codeLength-digit code.');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
      _infoMessage = null;
    });
    _focusNode.unfocus();

    final result = await widget.onSubmit(_verificationId, code);
    if (!mounted) return;

    if (result.isSuccess) {
      _completed = true;
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _isSubmitting = false;
        _errorMessage = result.error ?? 'Verification failed. Please try again.';
      });
      _codeController.clear();
      _focusNode.requestFocus();
    }
  }

  Future<void> _handleAutoVerified(PhoneAuthCredential credential) async {
    if (_completed || _isSubmitting || !mounted) return;

    // Android often includes the SMS code on auto-retrieval — just fill & submit
    // through the normal path so the user sees what happened.
    final smsCode = credential.smsCode;
    if (smsCode != null && smsCode.length == _codeLength) {
      _codeController.text = smsCode;
      await _submit();
      return;
    }

    final handler = widget.onAutoVerified;
    if (handler == null) return;

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });
    final result = await handler(credential);
    if (!mounted) return;
    if (result.isSuccess) {
      _completed = true;
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _isSubmitting = false;
        _errorMessage = result.error;
      });
    }
  }

  // ── Resend ────────────────────────────────────────────────────────────────

  Future<void> _resend() async {
    if (_isResending || _isSubmitting || _secondsLeft > 0) return;

    setState(() {
      _isResending = true;
      _errorMessage = null;
      _infoMessage = null;
    });

    await _authService.startPhoneVerification(
      phone: widget.phoneNumber,
      forceResendingToken: _resendToken,
      onCodeSent: (verificationId, resendToken) {
        if (!mounted) return;
        setState(() {
          _verificationId = verificationId;
          _resendToken = resendToken;
          _isResending = false;
          _infoMessage = 'A new code has been sent.';
        });
        _codeController.clear();
        _startCooldown();
        _focusNode.requestFocus();
      },
      onVerificationCompleted: (credential) {
        if (!mounted) return;
        setState(() => _isResending = false);
        _handleAutoVerified(credential);
      },
      onFailed: (message) {
        if (!mounted) return;
        setState(() {
          _isResending = false;
          _errorMessage = message;
        });
      },
    );
  }

  // ── UI ────────────────────────────────────────────────────────────────────

  /// `+923001234567` → `+92 300 1234567`; other countries shown as-is.
  String get _displayPhone {
    final p = widget.phoneNumber;
    if (p.startsWith('+92') && p.length == 13) {
      return '+92 ${p.substring(3, 6)} ${p.substring(6)}';
    }
    return p;
  }

  @override
  Widget build(BuildContext context) {
    final isDemoPrefilled = widget.initialCode != null;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF1A1A1A)),
          onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(false),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 20),
              Center(
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A1A),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(Icons.sms_outlined,
                      color: Colors.white, size: 36),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                widget.title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1A1A1A),
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 8),
              Text.rich(
                TextSpan(
                  text: 'Enter the $_codeLength-digit code sent to\n',
                  style: TextStyle(fontSize: 16, color: Colors.grey[600], height: 1.4),
                  children: [
                    TextSpan(
                      text: _displayPhone,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1A1A1A),
                      ),
                    ),
                  ],
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),

              // Demo notice (only when a code was pre-filled by the caller)
              if (isDemoPrefilled) ...[
                const _Banner(
                  icon: Icons.science_outlined,
                  color: Colors.blue,
                  text: 'Demo account — verification code pre-filled. '
                      'Firebase handles this test number natively.',
                ),
                const SizedBox(height: 16),
              ],

              // Error
              if (_errorMessage != null) ...[
                _Banner(
                  icon: Icons.error_outline,
                  color: Colors.red,
                  text: _errorMessage!,
                ),
                const SizedBox(height: 16),
              ],

              // Info
              if (_infoMessage != null) ...[
                _Banner(
                  icon: Icons.check_circle_outline,
                  color: Colors.green,
                  text: _infoMessage!,
                ),
                const SizedBox(height: 16),
              ],

              // Code input
              TextField(
                controller: _codeController,
                focusNode: _focusNode,
                enabled: !_isSubmitting,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.done,
                textAlign: TextAlign.center,
                autofillHints: const [AutofillHints.oneTimeCode],
                maxLength: _codeLength,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(_codeLength),
                ],
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 14,
                  color: Color(0xFF1A1A1A),
                ),
                decoration: InputDecoration(
                  counterText: '',
                  hintText: '••••••',
                  hintStyle: TextStyle(
                    fontSize: 32,
                    letterSpacing: 14,
                    color: Colors.grey[400],
                  ),
                  filled: true,
                  fillColor: const Color(0xFFF5F5F5),
                  contentPadding: const EdgeInsets.symmetric(vertical: 20),
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
                    borderSide:
                        const BorderSide(color: Color(0xFF1A1A1A), width: 2),
                  ),
                ),
                onChanged: (value) {
                  setState(() => _errorMessage = null);
                  if (value.length == _codeLength) _submit();
                },
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 24),

              // Verify button
              SizedBox(
                height: 54,
                child: ElevatedButton(
                  onPressed: (_isSubmitting || !_hasFullCode) ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1A1A1A),
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: const Color(0xFF1A1A1A).withValues(alpha: 0.4),
                    disabledForegroundColor: Colors.white70,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: _isSubmitting
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text(
                          'Verify',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 24),

              // Resend
              Center(
                child: _isResending
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Color(0xFF1A1A1A),
                        ),
                      )
                    : _secondsLeft > 0
                        ? Text(
                            'Resend code in 0:${_secondsLeft.toString().padLeft(2, '0')}',
                            style: TextStyle(color: Colors.grey[600], fontSize: 15),
                          )
                        : TextButton(
                            onPressed: _isSubmitting ? null : _resend,
                            child: const Text(
                              'Resend code',
                              style: TextStyle(
                                color: Color(0xFF1A1A1A),
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
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

class _Banner extends StatelessWidget {
  final IconData icon;
  final MaterialColor color;
  final String text;

  const _Banner({
    required this.icon,
    required this.color,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color[200]!),
      ),
      child: Row(
        children: [
          Icon(icon, color: color[700], size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: color[700], fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }
}
