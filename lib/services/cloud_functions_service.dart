import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../data/app_data.dart';
import 'error_message_service.dart';

/// Result class for Cloud Function operations
class CloudFunctionResult {
  final bool isSuccess;
  final Map<String, dynamic>? data;
  final String? userMessage;
  final ErrorType? errorType;
  final String? supportSuggestion;
  final String? technicalError;

  CloudFunctionResult._({
    required this.isSuccess,
    this.data,
    this.userMessage,
    this.errorType,
    this.supportSuggestion,
    this.technicalError,
  });

  factory CloudFunctionResult.success(Map<String, dynamic> data) {
    return CloudFunctionResult._(
      isSuccess: true,
      data: data,
    );
  }

  factory CloudFunctionResult.error({
    required String userMessage,
    required ErrorType errorType,
    required String supportSuggestion,
    String? technicalError,
  }) {
    return CloudFunctionResult._(
      isSuccess: false,
      userMessage: userMessage,
      errorType: errorType,
      supportSuggestion: supportSuggestion,
      technicalError: technicalError,
    );
  }
}

/// Cloud Functions Service - Handles all secure backend operations
/// NO DIRECT FIRESTORE WRITES ALLOWED - Everything goes through Cloud Functions
class CloudFunctionsService {
  static final CloudFunctionsService _instance = CloudFunctionsService._internal();
  factory CloudFunctionsService() => _instance;

  CloudFunctionsService._internal();

  final FirebaseFunctions _functions = FirebaseFunctions.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Get current user ID
  String? get _currentUserId => _auth.currentUser?.uid;

  // ==================== WALLET OPERATIONS ====================

  /// Pay from customer wallet (booking payment)
  Future<CloudFunctionResult> payFromWallet({
    required int amount,
    required String bookingId,
    required String description,
  }) async {
    final userId = _currentUserId;
    if (userId == null) {
      return CloudFunctionResult.error(
        userMessage: 'Authentication required. Please sign in again.',
        errorType: ErrorType.error,
        supportSuggestion: 'Try signing out and back in.',
        technicalError: 'User not authenticated',
      );
    }

    try {
      final result = await _functions.httpsCallable('payFromWallet').call({
        'userId': userId,
        'amount': amount,
        'bookingId': bookingId,
        'description': description,
      });

      return _handleCloudFunctionResult(result.data, null);
    } catch (e) {
      return _handleCloudFunctionResult(null, e);
    }
  }

  /// Refund to customer wallet
  Future<Map<String, dynamic>> refundToWallet({
    required int amount,
    required String bookingId,
    required String description,
    required String refundReason,
  }) async {
    final userId = _currentUserId;
    if (userId == null) throw Exception('User not authenticated');

    final result = await _functions.httpsCallable('refundToWallet').call({
      'userId': userId,
      'amount': amount,
      'bookingId': bookingId,
      'description': description,
      'refundReason': refundReason,
    });

    return Map<String, dynamic>.from(result.data);
  }

  /// Add money to customer wallet
  Future<Map<String, dynamic>> addMoneyToWallet({
    required int amount,
    required String description,
    required String paymentMethod,
  }) async {
    final userId = _currentUserId;
    if (userId == null) throw Exception('User not authenticated');

    final result = await _functions.httpsCallable('addMoneyToWallet').call({
      'userId': userId,
      'amount': amount,
      'description': description,
      'paymentMethod': paymentMethod,
    });

    return Map<String, dynamic>.from(result.data);
  }

  /// Withdraw from barber wallet
  Future<Map<String, dynamic>> withdrawBarberFunds({
    required int amount,
    required String description,
    required String withdrawalMethod,
  }) async {
    final userId = _currentUserId;
    if (userId == null) throw Exception('User not authenticated');

    final result = await _functions.httpsCallable('withdrawBarberFunds').call({
      'barberId': userId,
      'amount': amount,
      'description': description,
      'withdrawalMethod': withdrawalMethod,
    });

    return Map<String, dynamic>.from(result.data);
  }

  // ==================== BOOKING OPERATIONS ====================

  /// Create a new booking
  Future<Map<String, dynamic>> createBooking({
    required String barberId,
    required DateTime bookingDateTime,
    required String timeSlot,
    required int pricePKR,
    required String paymentMethod,
  }) async {
    final userId = _currentUserId;
    if (userId == null) throw Exception('User not authenticated');

    final result = await _functions.httpsCallable('createBooking').call({
      'customerId': userId,
      'barberId': barberId,
      'bookingDateTime': bookingDateTime.toIso8601String(),
      'timeSlot': timeSlot,
      'pricePKR': pricePKR,
      'paymentMethod': paymentMethod,
    });

    return Map<String, dynamic>.from(result.data);
  }

  /// Accept booking request (barber only)
  Future<Map<String, dynamic>> acceptBookingRequest(String bookingId) async {
    final userId = _currentUserId;
    if (userId == null) throw Exception('User not authenticated');

    final result = await _functions.httpsCallable('acceptBookingRequest').call({
      'barberId': userId,
      'bookingId': bookingId,
    });

    return Map<String, dynamic>.from(result.data);
  }

  /// Reject booking request (barber only)
  Future<Map<String, dynamic>> rejectBookingRequest({
    required String bookingId,
    required String reason,
  }) async {
    final userId = _currentUserId;
    if (userId == null) throw Exception('User not authenticated');

    final result = await _functions.httpsCallable('rejectBookingRequest').call({
      'barberId': userId,
      'bookingId': bookingId,
      'reason': reason,
    });

    return Map<String, dynamic>.from(result.data);
  }

  /// Complete booking (barber only)
  Future<Map<String, dynamic>> completeBooking({
    required String bookingId,
    required int customerRating,
    String? comment,
  }) async {
    final userId = _currentUserId;
    if (userId == null) throw Exception('User not authenticated');

    final result = await _functions.httpsCallable('completeBooking').call({
      'barberId': userId,
      'bookingId': bookingId,
      'customerRating': customerRating,
      'customerComment': comment,
    });

    return Map<String, dynamic>.from(result.data);
  }

  /// Cancel booking by customer
  Future<Map<String, dynamic>> cancelBookingByCustomer({
    required String bookingId,
    required String reason,
  }) async {
    final userId = _currentUserId;
    if (userId == null) throw Exception('User not authenticated');

    final result = await _functions.httpsCallable('cancelBookingByCustomer').call({
      'customerId': userId,
      'bookingId': bookingId,
      'reason': reason,
    });

    return Map<String, dynamic>.from(result.data);
  }

  /// Cancel booking by barber
  Future<Map<String, dynamic>> cancelBookingByBarber({
    required String bookingId,
    required String reason,
  }) async {
    final userId = _currentUserId;
    if (userId == null) throw Exception('User not authenticated');

    final result = await _functions.httpsCallable('cancelBookingByBarber').call({
      'barberId': userId,
      'bookingId': bookingId,
      'reason': reason,
    });

    return Map<String, dynamic>.from(result.data);
  }

  // ==================== BARBER OPERATIONS ====================

  /// Update barber profile
  Future<Map<String, dynamic>> updateBarberProfile({
    required String name,
    required String phone,
    required String shopName,
    required String address,
  }) async {
    final userId = _currentUserId;
    if (userId == null) throw Exception('User not authenticated');

    final result = await _functions.httpsCallable('updateBarberProfile').call({
      'barberId': userId,
      'name': name,
      'phone': phone,
      'shopName': shopName,
      'address': address,
    });

    return Map<String, dynamic>.from(result.data);
  }

  /// Update barber working hours
  Future<Map<String, dynamic>> updateBarberWorkingHours({
    required String startHour,
    required String endHour,
    required List<int> daysOff,
  }) async {
    final userId = _currentUserId;
    if (userId == null) throw Exception('User not authenticated');

    final result = await _functions.httpsCallable('updateBarberWorkingHours').call({
      'barberId': userId,
      'startHour': startHour,
      'endHour': endHour,
      'daysOff': daysOff,
    });

    return Map<String, dynamic>.from(result.data);
  }

  /// Update barber closed slots
  Future<Map<String, dynamic>> updateBarberClosedSlots({
    required String dateKey,
    required List<int> closedSlots,
  }) async {
    final userId = _currentUserId;
    if (userId == null) throw Exception('User not authenticated');

    final result = await _functions.httpsCallable('updateBarberClosedSlots').call({
      'barberId': userId,
      'dateKey': dateKey,
      'closedSlots': closedSlots,
    });

    return Map<String, dynamic>.from(result.data);
  }

  // ==================== CUSTOMER OPERATIONS ====================

  /// Update customer profile
  Future<Map<String, dynamic>> updateCustomerProfile({
    required String name,
    required String phone,
  }) async {
    final userId = _currentUserId;
    if (userId == null) throw Exception('User not authenticated');

    final result = await _functions.httpsCallable('updateCustomerProfile').call({
      'customerId': userId,
      'name': name,
      'phone': phone,
    });

    return Map<String, dynamic>.from(result.data);
  }

  /// Update customer notification preferences
  Future<Map<String, dynamic>> updateNotificationPreferences({
    required Map<String, bool> preferences,
  }) async {
    final userId = _currentUserId;
    if (userId == null) throw Exception('User not authenticated');

    final result = await _functions.httpsCallable('updateNotificationPreferences').call({
      'userId': userId,
      'preferences': preferences,
    });

    return Map<String, dynamic>.from(result.data);
  }

  /// Update customer saved addresses
  Future<Map<String, dynamic>> updateSavedAddresses({
    required List<Map<String, dynamic>> addresses,
  }) async {
    final userId = _currentUserId;
    if (userId == null) throw Exception('User not authenticated');

    final result = await _functions.httpsCallable('updateSavedAddresses').call({
      'customerId': userId,
      'addresses': addresses,
    });

    return Map<String, dynamic>.from(result.data);
  }

  /// Update barber online status
  Future<Map<String, dynamic>> updateBarberOnlineStatus(bool isOnline) async {
    final userId = _currentUserId;
    if (userId == null) throw Exception('User not authenticated');

    final result = await _functions.httpsCallable('updateBarberOnlineStatus').call({
      'barberId': userId,
      'isOnline': isOnline,
    });

    return Map<String, dynamic>.from(result.data);
  }

  /// Start a job (barber only)
  Future<Map<String, dynamic>> startJob(String bookingId) async {
    final userId = _currentUserId;
    if (userId == null) throw Exception('User not authenticated');

    final result = await _functions.httpsCallable('startJob').call({
      'barberId': userId,
      'bookingId': bookingId,
    });

    return Map<String, dynamic>.from(result.data);
  }

  // ==================== REROUTING OPERATIONS (Phase 4) ====================

  /// Reroute booking to a new barber (customer only)
  /// Uses the server-side rerouteBooking Cloud Function for atomicity
  Future<Map<String, dynamic>> rerouteBooking({
    required String bookingId,
    required String newBarberId,
  }) async {
    final userId = _currentUserId;
    if (userId == null) throw Exception('User not authenticated');

    final result = await _functions.httpsCallable('rerouteBooking').call({
      'bookingId': bookingId,
      'newBarberId': newBarberId,
    });

    return Map<String, dynamic>.from(result.data);
  }

  // ==================== DISPUTE OPERATIONS ====================

  /// Create a dispute for a booking
  Future<Map<String, dynamic>> createDispute({
    required String bookingId,
    required DisputeReason reason,
    required String description,
  }) async {
    final userId = _currentUserId;
    if (userId == null) throw Exception('User not authenticated');

    final result = await _functions.httpsCallable('createDispute').call({
      'customerId': userId,
      'bookingId': bookingId,
      'reason': reason.name,
      'description': description,
    });

    return Map<String, dynamic>.from(result.data);
  }

  /// Get dispute details
  Future<Map<String, dynamic>> getDispute(String disputeId) async {
    final result = await _functions.httpsCallable('getDispute').call({
      'disputeId': disputeId,
    });

    return Map<String, dynamic>.from(result.data);
  }

  /// Get disputes for current user
  Future<Map<String, dynamic>> getUserDisputes() async {
    final userId = _currentUserId;
    if (userId == null) throw Exception('User not authenticated');

    final result = await _functions.httpsCallable('getUserDisputes').call({
      'userId': userId,
    });

    return Map<String, dynamic>.from(result.data);
  }

  // ==================== ERROR HANDLING ====================

  final ErrorMessageService _errorService = ErrorMessageService();

  /// Enhanced error handling with user-friendly messages
  CloudFunctionResult _handleCloudFunctionResult(dynamic result, dynamic error) {
    if (error != null) {
      return CloudFunctionResult.error(
        userMessage: _errorService.getUserFriendlyMessage(error),
        errorType: _errorService.getErrorType(error),
        supportSuggestion: _errorService.getSupportSuggestion(error),
        technicalError: error.toString(),
      );
    }

    if (result is Map<String, dynamic>) {
      final success = result['success'] == true;
      if (success) {
        return CloudFunctionResult.success(result);
      } else {
        // Handle server-side error responses
        final errorCode = result['errorCode'] as String?;
        final errorMessage = result['errorMessage'] as String?;
        final mockError = FirebaseFunctionsException(
          code: errorCode ?? 'unknown',
          message: errorMessage ?? 'Unknown error from server',
          details: result,
        );

        return CloudFunctionResult.error(
          userMessage: _errorService.getUserFriendlyMessage(mockError),
          errorType: _errorService.getErrorType(mockError),
          supportSuggestion: _errorService.getSupportSuggestion(mockError),
          technicalError: mockError.toString(),
        );
      }
    }

    return CloudFunctionResult.error(
      userMessage: 'Unexpected response from server. Please try again.',
      errorType: ErrorType.error,
      supportSuggestion: 'Contact support@bestcut.pk if this problem persists.',
      technicalError: 'Invalid response format: $result',
    );
  }
}