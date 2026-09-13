import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Two-stage session, mirroring `src/stores/authStore.ts` in the Next.js
/// dashboard.
///
/// Logging in does **not** sign the student in. The token returned by
/// `POST /v1/auth/login` is held as a *pending* session — in memory only, so it
/// dies with the process exactly like the web's `sessionStorage` — and is
/// promoted to persistent storage only by [activateSession], which the OTP
/// screen calls after `POST /v1/auth/phone/verify` succeeds.
///
/// [currentToken] returns the pending token while verification is in flight so
/// the verify call itself can authenticate.
class SessionManager {
  SessionManager._internal();
  static final SessionManager _instance = SessionManager._internal();
  factory SessionManager() => _instance;

  static const _storage = FlutterSecureStorage();
  static const _tokenKey = 'auth_token';

  // ---- pending (pre-verification) ----
  String? _pendingToken;
  Map<String, dynamic>? _pendingUser;

  // ---- active (verified) ----
  String? _activeTokenCache;
  bool _activeLoaded = false;

  /// Notifies listeners when the session is cleared (e.g. a 401 anywhere).
  final ValueNotifier<int> sessionRevoked = ValueNotifier<int>(0);

  // ------------------------------------------------------------------
  // Pending session
  // ------------------------------------------------------------------

  /// Stores the login/register result without signing the student in.
  void setPendingAuth({required String token, Map<String, dynamic>? user}) {
    _pendingToken = token;
    _pendingUser = user;
  }

  String? get pendingToken => _pendingToken;
  Map<String, dynamic>? get pendingUser => _pendingUser;

  void clearPendingAuth() {
    _pendingToken = null;
    _pendingUser = null;
  }

  /// Promotes the pending token to persistent storage. Call only after OTP
  /// verification succeeds.
  Future<bool> activateSession() async {
    final token = _pendingToken;
    if (token == null || token.isEmpty) return false;
    await _storage.write(key: _tokenKey, value: token);
    _activeTokenCache = token;
    _activeLoaded = true;
    clearPendingAuth();
    return true;
  }

  // ------------------------------------------------------------------
  // Active session
  // ------------------------------------------------------------------

  /// The verified token, or `null` when the student is not signed in.
  Future<String?> getActiveToken() async {
    if (_activeLoaded) return _activeTokenCache;
    _activeTokenCache = await _storage.read(key: _tokenKey);
    _activeLoaded = true;
    return _activeTokenCache;
  }

  /// Token for outgoing requests: the verified one, else the pending one so the
  /// OTP screen can authenticate its own verify call.
  Future<String?> currentToken() async {
    final active = await getActiveToken();
    if (active != null && active.isNotEmpty) return active;
    return _pendingToken;
  }

  /// Synchronous best-effort read, for call sites that cannot await
  /// (e.g. a WebSocket authorizer callback). Returns `null` before the first
  /// [getActiveToken].
  String? currentTokenSync() {
    if (_activeTokenCache != null && _activeTokenCache!.isNotEmpty) {
      return _activeTokenCache;
    }
    return _pendingToken;
  }

  /// Writes a token straight to persistent storage, bypassing the pending
  /// stage. Only for flows the backend already treats as verified (password
  /// reset completion).
  Future<void> setActiveToken(String token) async {
    await _storage.write(key: _tokenKey, value: token);
    _activeTokenCache = token;
    _activeLoaded = true;
    clearPendingAuth();
  }

  Future<bool> get isSignedIn async {
    final t = await getActiveToken();
    return t != null && t.isNotEmpty;
  }

  /// Drops both stages. Called on logout and on any unhandled 401.
  Future<void> clear() async {
    clearPendingAuth();
    _activeTokenCache = null;
    _activeLoaded = true;
    await _storage.delete(key: _tokenKey);
    sessionRevoked.value++;
  }
}
