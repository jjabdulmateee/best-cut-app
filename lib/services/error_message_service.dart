import 'package:cloud_functions/cloud_functions.dart';

/// Error Message Service - Maps Cloud Function errors to human-readable messages
class ErrorMessageService {
  static final ErrorMessageService _instance = ErrorMessageService._internal();
  factory ErrorMessageService() => _instance;
  ErrorMessageService._internal();

  /// Convert Firebase Functions error to user-friendly message
  String getUserFriendlyMessage(dynamic error) {
    if (error is! FirebaseFunctionsException) {
      return _getGenericErrorMessage(error);
    }

    // Map specific error codes to user-friendly messages
    switch (error.code) {
      // System Freeze Errors
      case 'system-frozen':
      case 'maintenance-mode':
        return 'The system is currently under maintenance. Please try again later. All bookings and payments are temporarily paused for safety.';

      case 'emergency-freeze':
        return 'System operations are temporarily suspended for safety. Please check back in a few minutes.';

      // Account Status Errors
      case 'account-disabled':
        return 'Your account has been temporarily disabled. Please contact support@bestcut.pk for assistance.';

      case 'account-suspended':
        return 'Your account is currently suspended. Contact support to resolve this.';

      case 'account-restricted':
        return 'Your account has restrictions that prevent this action. Please contact support.';

      // Payment Errors
      case 'payment-blocked':
        return 'This payment has been blocked for safety reasons. Please contact support if you believe this is an error.';

      case 'insufficient-funds':
        return 'Insufficient funds in your wallet. Please add money or use a different payment method.';

      case 'payment-failed':
        return 'Payment could not be processed. Please check your payment method and try again.';

      case 'wallet-locked':
        return 'Your wallet is temporarily locked. This may be due to recent activity. Please contact support.';

      // Booking Errors
      case 'booking-frozen':
        return 'This booking has been frozen by admin. Please contact support for assistance.';

      case 'booking-blocked':
        return 'This booking action has been blocked. Please contact support if you need help.';

      case 'booking-cancelled-by-admin':
        return 'This booking was cancelled by an administrator. Please check your email for details.';

      case 'booking-modified-by-admin':
        return 'This booking was recently updated by an administrator. Please refresh to see the latest status.';

      case 'slot-unavailable':
        return 'This time slot is no longer available. Please choose a different time.';

      case 'barber-unavailable':
        return 'This barber is currently unavailable. Please choose another barber.';

      // Permission Errors
      case 'permission-denied':
        return 'You don\'t have permission to perform this action. Please contact support if this seems incorrect.';

      case 'admin-required':
        return 'This action requires administrator approval. Your request has been submitted.';

      // Network/Connection Errors
      case 'network-error':
        return 'Connection problem. Please check your internet and try again.';

      case 'timeout':
        return 'Request timed out. Please try again in a moment.';

      // Dispute Errors
      case 'dispute-already-exists':
        return 'A dispute has already been filed for this booking. Please wait for resolution.';

      case 'dispute-not-allowed':
        return 'Disputes can only be filed for completed or cancelled bookings.';

      case 'dispute-frozen':
        return 'This dispute is currently frozen by admin review. Please contact support.';

      // Escrow Errors
      case 'escrow-not-released':
        return 'Payment is still held in escrow. Please wait for admin review.';

      case 'escrow-already-processed':
        return 'This payment has already been processed and cannot be disputed.';

      // Trust/Strike Errors
      case 'trust-restricted':
        return 'Your account has trust restrictions. Please contact support to resolve.';

      case 'strike-limit-exceeded':
        return 'Too many violations detected. Account access limited.';

      // Validation Errors
      case 'invalid-request':
        return 'The request could not be processed. Please check your information and try again.';

      case 'validation-error':
        return 'Some information appears to be incorrect. Please review and try again.';

      // Default cases
      default:
        return _getGenericErrorMessage(error);
    }
  }

  /// Get generic error message for non-Firebase errors
  String _getGenericErrorMessage(dynamic error) {
    final errorString = error.toString().toLowerCase();

    // Check for common error patterns
    if (errorString.contains('network') || errorString.contains('connection')) {
      return 'Network connection issue. Please check your internet and try again.';
    }

    if (errorString.contains('timeout')) {
      return 'Request timed out. Please try again.';
    }

    if (errorString.contains('permission') || errorString.contains('unauthorized')) {
      return 'You don\'t have permission for this action. Please contact support.';
    }

    if (errorString.contains('maintenance') || errorString.contains('frozen')) {
      return 'System is under maintenance. Please try again later.';
    }

    if (errorString.contains('disabled') || errorString.contains('suspended')) {
      return 'Your account has been disabled. Please contact support.';
    }

    // Default generic message
    return 'Something went wrong. Please try again, or contact support if the problem persists.';
  }

  /// Get specific error type for UI styling
  ErrorType getErrorType(dynamic error) {
    if (error is! FirebaseFunctionsException) {
      return ErrorType.error;
    }

    switch (error.code) {
      case 'system-frozen':
      case 'maintenance-mode':
      case 'emergency-freeze':
        return ErrorType.maintenance;

      case 'account-disabled':
      case 'account-suspended':
      case 'account-restricted':
        return ErrorType.account;

      case 'booking-frozen':
      case 'booking-blocked':
      case 'booking-cancelled-by-admin':
      case 'booking-modified-by-admin':
      case 'dispute-frozen':
      case 'trust-restricted':
      case 'strike-limit-exceeded':
        return ErrorType.admin;

      case 'payment-blocked':
      case 'wallet-locked':
        return ErrorType.payment;

      case 'network-error':
      case 'timeout':
        return ErrorType.network;

      default:
        return ErrorType.error;
    }
  }

  /// Get appropriate icon for error type
  String getErrorIcon(ErrorType type) {
    switch (type) {
      case ErrorType.maintenance:
        return '🔧';
      case ErrorType.account:
        return '🚫';
      case ErrorType.admin:
        return '👨‍💼';
      case ErrorType.payment:
        return '💳';
      case ErrorType.network:
        return '📶';
      case ErrorType.error:
        return '⚠️';
    }
  }

  /// Check if error indicates system freeze
  bool isSystemFrozen(dynamic error) {
    if (error is FirebaseFunctionsException) {
      return error.code == 'system-frozen' ||
             error.code == 'maintenance-mode' ||
             error.code == 'emergency-freeze' ||
             error.message?.contains('frozen') == true ||
             error.message?.contains('maintenance') == true;
    }
    return false;
  }

  /// Check if error indicates account disabled
  bool isAccountDisabled(dynamic error) {
    if (error is FirebaseFunctionsException) {
      return error.code == 'account-disabled' ||
             error.code == 'account-suspended' ||
             error.code == 'account-restricted' ||
             error.message?.contains('disabled') == true ||
             error.message?.contains('suspended') == true;
    }
    return false;
  }

  /// Check if error indicates admin action
  bool isAdminAction(dynamic error) {
    if (error is FirebaseFunctionsException) {
      return error.code.contains('admin') ||
             error.code == 'booking-frozen' ||
             error.code == 'booking-blocked' ||
             error.message?.contains('admin') == true;
    }
    return false;
  }

  /// Get support contact suggestion based on error
  String getSupportSuggestion(dynamic error) {
    if (isAdminAction(error)) {
      return 'If you disagree with this admin action, contact support@bestcut.pk with your booking reference.';
    }

    if (isAccountDisabled(error)) {
      return 'Contact support@bestcut.pk to resolve your account status.';
    }

    if (isSystemFrozen(error)) {
      return 'This is temporary. Please try again later or contact support if urgent.';
    }

    return 'Contact support@bestcut.pk if this problem persists.';
  }
}

/// Error types for UI styling
enum ErrorType {
  maintenance,  // System maintenance/freeze
  account,      // Account disabled/suspended
  admin,        // Admin action/block
  payment,      // Payment/wallet issues
  network,      // Network/connection issues
  error,        // Generic errors
}