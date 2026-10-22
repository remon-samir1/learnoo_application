import 'dart:io';
import 'dart:math';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Device identity, mirroring the Next.js dashboard.
///
/// Two separate things travel to the backend and they must not be confused:
///
///  * **Device name** — a human label (`device_name` in the login/register
///    body) the dashboard shows to staff. The web sends `learnoo-web`; we send
///    the real device model so an approval request is recognisable.
///  * **Device id** — the stable identifier the backend ties the session to,
///    sent as the `X-Device-ID` header on *every* request exactly like
///    `src/lib/api.ts` → `createHeaders()`. The web stores a `crypto.randomUUID()`
///    in the `learnoo_device_id` cookie plus `localStorage` and accepts a stored
///    value only when it is 16–255 characters long ( `src/lib/device-id.ts` ).
///    We keep the same format (a random RFC 4122 v4 UUID string) and the same
///    length rule, persisted in secure storage so it survives reinstalls on iOS
///    and app restarts everywhere.
///
/// When the id does not match the device the account is bound to, the backend
/// refuses the login with `code: device_transfer_required`, and the student can
/// ask staff to move the account to this device.
class DeviceService {
  /// Secure-storage key for the generated id. Same name as the web cookie.
  static const String deviceIdKey = 'learnoo_device_id';

  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  /// Resolved once per process so the per-request header costs nothing.
  static String? _cachedDeviceId;

  static Future<String> getDeviceName() async {
    final DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
    try {
      if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        return '${androidInfo.brand} ${androidInfo.model}';
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        return iosInfo.name;
      } else if (Platform.isWindows) {
        final windowsInfo = await deviceInfo.windowsInfo;
        return windowsInfo.computerName;
      } else if (Platform.isLinux) {
        final linuxInfo = await deviceInfo.linuxInfo;
        return linuxInfo.name;
      } else if (Platform.isMacOS) {
        final macInfo = await deviceInfo.macOsInfo;
        return macInfo.computerName;
      }
    } catch (e) {
      return 'Unknown Device';
    }
    return 'Web/Unknown';
  }

  /// The `X-Device-ID` value for this installation, generated on first use and
  /// then stable. Never logged — it identifies the student's device.
  static Future<String> deviceId() async {
    final cached = _cachedDeviceId;
    if (cached != null) return cached;

    String? stored;
    try {
      stored = await _storage.read(key: deviceIdKey);
    } catch (_) {
      stored = null;
    }

    if (isValidDeviceId(stored)) {
      _cachedDeviceId = stored;
      return stored!;
    }

    final generated = generateDeviceId();
    try {
      await _storage.write(key: deviceIdKey, value: generated);
    } catch (_) {
      // Storage unavailable: keep the id for this process at least, so the
      // whole session is seen as one device.
    }
    _cachedDeviceId = generated;
    return generated;
  }

  /// The web's acceptance rule for a stored id (`device-id.ts`): anything
  /// shorter than 16 or longer than 255 characters is discarded and replaced.
  static bool isValidDeviceId(String? value) =>
      value != null && value.length >= 16 && value.length <= 255;

  /// A random RFC 4122 version 4 UUID, the same shape `crypto.randomUUID()`
  /// produces on the web, lowercase and hyphenated.
  static String generateDeviceId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
    bytes[8] = (bytes[8] & 0x3f) | 0x80; // variant 1
    final hex = bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
        '${hex.substring(20)}';
  }

  /// Test seam: drops the in-process cache so the next [deviceId] re-reads.
  static void resetCacheForTesting() => _cachedDeviceId = null;
}
