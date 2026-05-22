import 'package:connectivity_plus/connectivity_plus.dart';

class ConnectivityService {
  static final ConnectivityService _instance = ConnectivityService._internal();
  factory ConnectivityService() => _instance;
  ConnectivityService._internal();

  final Connectivity _connectivity = Connectivity();

  /// Check if the device has an active internet connection
  /// Returns true if connected to wifi, mobile, ethernet, or other network types
  Future<bool> hasConnection() async {
    final List<ConnectivityResult> results = await _connectivity.checkConnectivity();
    
    // Check if any connection type indicates internet access
    for (final result in results) {
      if (result == ConnectivityResult.wifi ||
          result == ConnectivityResult.mobile ||
          result == ConnectivityResult.ethernet ||
          result == ConnectivityResult.vpn ||
          result == ConnectivityResult.other) {
        return true;
      }
    }
    
    return false;
  }

  /// Get the current connectivity status as a stream
  Stream<List<ConnectivityResult>> get onConnectivityChanged {
    return _connectivity.onConnectivityChanged;
  }

  /// Get human-readable connection type name
  String getConnectionTypeName(List<ConnectivityResult> results) {
    if (results.isEmpty) return 'No Connection';
    
    final names = results.map((result) {
      switch (result) {
        case ConnectivityResult.wifi:
          return 'WiFi';
        case ConnectivityResult.mobile:
          return 'Mobile';
        case ConnectivityResult.ethernet:
          return 'Ethernet';
        case ConnectivityResult.vpn:
          return 'VPN';
        case ConnectivityResult.bluetooth:
          return 'Bluetooth';
        case ConnectivityResult.other:
          return 'Other';
        case ConnectivityResult.satellite:
          return 'Satellite';
        case ConnectivityResult.none:
          return 'No Connection';
      }
    }).toList();
    
    return names.join(', ');
  }
}
