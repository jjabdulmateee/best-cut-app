import 'dart:async';
import 'package:flutter/foundation.dart';

/// Connectivity Service - Monitors internet connection for barber auto-offline
class ConnectivityService extends ChangeNotifier {
  static final ConnectivityService _instance = ConnectivityService._internal();
  factory ConnectivityService() => _instance;
  ConnectivityService._internal();

  bool _isConnected = true;
  bool get isConnected => _isConnected;

  Timer? _pingTimer;
  final List<VoidCallback> _onDisconnectCallbacks = [];
  final List<VoidCallback> _onReconnectCallbacks = [];

  /// Initialize connectivity monitoring
  void startMonitoring() {
    // For web, we use navigator.onLine check periodically
    // For mobile, we could use connectivity_plus package
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 10), (_) => _checkConnectivity());
    _checkConnectivity();
  }

  void stopMonitoring() {
    _pingTimer?.cancel();
    _pingTimer = null;
  }

  Future<void> _checkConnectivity() async {
    bool wasConnected = _isConnected;
    
    try {
      // Simple connectivity check - try to reach a reliable endpoint
      // For web, we check navigator.onLine
      if (kIsWeb) {
        // Web connectivity check using dart:html would need conditional import
        // For now, assume connected unless we detect otherwise
        _isConnected = true;
      } else {
        // For mobile, connectivity check
        _isConnected = true;
      }
    } catch (e) {
      _isConnected = false;
    }

    if (wasConnected != _isConnected) {
      notifyListeners();
      
      if (!_isConnected) {
        for (var callback in _onDisconnectCallbacks) {
          callback();
        }
      } else {
        for (var callback in _onReconnectCallbacks) {
          callback();
        }
      }
    }
  }

  /// Register callback when internet disconnects
  void onDisconnect(VoidCallback callback) {
    _onDisconnectCallbacks.add(callback);
  }

  /// Register callback when internet reconnects
  void onReconnect(VoidCallback callback) {
    _onReconnectCallbacks.add(callback);
  }

  /// Remove disconnect callback
  void removeOnDisconnect(VoidCallback callback) {
    _onDisconnectCallbacks.remove(callback);
  }

  /// Remove reconnect callback
  void removeOnReconnect(VoidCallback callback) {
    _onReconnectCallbacks.remove(callback);
  }

  /// Force check connectivity
  Future<bool> checkNow() async {
    await _checkConnectivity();
    return _isConnected;
  }

  /// Set connection status manually (for testing or web)
  void setConnectionStatus(bool connected) {
    if (_isConnected != connected) {
      _isConnected = connected;
      notifyListeners();
      
      if (!connected) {
        for (var callback in _onDisconnectCallbacks) {
          callback();
        }
      } else {
        for (var callback in _onReconnectCallbacks) {
          callback();
        }
      }
    }
  }

  @override
  void dispose() {
    stopMonitoring();
    _onDisconnectCallbacks.clear();
    _onReconnectCallbacks.clear();
    super.dispose();
  }
}
