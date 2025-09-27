import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;

class ConnectivityService {
  static final ConnectivityService _instance = ConnectivityService._internal();
  factory ConnectivityService() => _instance;
  ConnectivityService._internal();

  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  bool _isOnline = true;
  bool get isOnline => _isOnline;

  final StreamController<bool> _connectivityController =
      StreamController<bool>.broadcast();
  Stream<bool> get connectivityStream => _connectivityController.stream;

  Future<void> initialize() async {
    // Check initial connectivity
    await _checkConnectivity();

    // Listen to connectivity changes
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen(
      _onConnectivityChanged,
    );
  }

  Future<void> _checkConnectivity() async {
    try {
      final result = await _connectivity.checkConnectivity();
      final wasOnline = _isOnline;
      _isOnline = result.any((r) => r != ConnectivityResult.none);

      if (wasOnline != _isOnline) {
        _connectivityController.add(_isOnline);
      }
    } catch (e) {
      // Assume offline on error
      _isOnline = false;
      _connectivityController.add(false);
    }
  }

  void _onConnectivityChanged(List<ConnectivityResult> result) {
    final wasOnline = _isOnline;
    _isOnline = result.any((r) => r != ConnectivityResult.none);

    if (wasOnline != _isOnline) {
      _connectivityController.add(_isOnline);
    }
  }

  Future<bool> testConnection() async {
    if (!_isOnline) return false;

    try {
      final response = await http
          .get(Uri.parse('https://www.google.com'))
          .timeout(const Duration(seconds: 5));

      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  Future<void> dispose() async {
    await _connectivitySubscription?.cancel();
    await _connectivityController.close();
  }
}
