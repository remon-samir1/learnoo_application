import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

import '../network/api_constants.dart';

/// Where this copy of the app came from. Each store gets its own minimum
/// version on the dashboard because version and build numbers can differ
/// between stores.
enum AppStore {
  googlePlay('android'),
  huawei('huawei'),
  appStore('ios');

  const AppStore(this.key);

  /// The key under `platforms` in `GET /v1/app-update`.
  final String key;
}

/// Android installer package names (`PackageManager.getInstallerPackageName`).
const String _googlePlayInstaller = 'com.android.vending';
const String _huaweiInstaller = 'com.huawei.appmarket';

/// Which store an Android install belongs to. The installer is the truth; an
/// app installed some other way (side-loaded, a debug build) on a Huawei
/// phone is sent to AppGallery, since those phones have no Google Play.
AppStore androidStoreFor({String? installer, String? manufacturer}) {
  if (installer == _huaweiInstaller) return AppStore.huawei;
  if (installer == _googlePlayInstaller) return AppStore.googlePlay;
  if (manufacturer?.trim().toLowerCase() == 'huawei') return AppStore.huawei;
  return AppStore.googlePlay;
}

/// An app version such as `1.0.3+12`: the dotted version name and an
/// optional build number. Compared number by number, so `1.0.10` is newer
/// than `1.0.3`.
@immutable
class AppVersion implements Comparable<AppVersion> {
  const AppVersion(this.parts, [this.build]);

  /// Version name parts: `1.0.3` → `[1, 0, 3]`.
  final List<int> parts;

  /// Build number (`+12`), or null when not given.
  final int? build;

  static final RegExp _pattern = RegExp(r'^(\d+(?:\.\d+)*)(?:\+(\d+))?$');

  /// Null when [value] is not a version (the check then does not block).
  static AppVersion? tryParse(String? value) {
    final match = _pattern.firstMatch(value?.trim() ?? '');
    if (match == null) return null;
    final parts = match.group(1)!.split('.').map(int.parse).toList();
    final build = match.group(2);
    return AppVersion(parts, build == null ? null : int.parse(build));
  }

  /// Compares version names first (missing parts count as 0, so `1.0` equals
  /// `1.0.0`), then build numbers. A missing build number counts as 0.
  @override
  int compareTo(AppVersion other) {
    final length = parts.length > other.parts.length
        ? parts.length
        : other.parts.length;
    for (var i = 0; i < length; i++) {
      final a = i < parts.length ? parts[i] : 0;
      final b = i < other.parts.length ? other.parts[i] : 0;
      if (a != b) return a.compareTo(b);
    }
    return (build ?? 0).compareTo(other.build ?? 0);
  }

  /// Whether the installed version is older than [minimum]. A minimum
  /// without a build number (`1.0.3`) allows every build of that version.
  bool isBelow(AppVersion minimum) {
    if (minimum.build == null) {
      return AppVersion(parts).compareTo(AppVersion(minimum.parts)) < 0;
    }
    return compareTo(minimum) < 0;
  }

  @override
  String toString() =>
      build == null ? parts.join('.') : '${parts.join('.')}+$build';
}

/// The result of one check.
@immutable
class AppUpdateStatus {
  const AppUpdateStatus._(this.kind, [this.storeUrl]);

  /// This version may open.
  static const AppUpdateStatus allowed = AppUpdateStatus._(
    AppUpdateStatusKind.allowed,
  );

  /// The server could not be asked (offline, timeout, error answer).
  static const AppUpdateStatus unknown = AppUpdateStatus._(
    AppUpdateStatusKind.unknown,
  );

  /// This version is below the minimum; [storeUrl] is where to update.
  const AppUpdateStatus.required(String storeUrl)
    : this._(AppUpdateStatusKind.required, storeUrl);

  final AppUpdateStatusKind kind;
  final String? storeUrl;

  bool get isRequired => kind == AppUpdateStatusKind.required;

  @override
  bool operator ==(Object other) =>
      other is AppUpdateStatus &&
      other.kind == kind &&
      other.storeUrl == storeUrl;

  @override
  int get hashCode => Object.hash(kind, storeUrl);

  @override
  String toString() =>
      'AppUpdateStatus($kind${storeUrl == null ? '' : ', $storeUrl'})';
}

enum AppUpdateStatusKind { allowed, required, unknown }

/// Decides from the `data` of `GET /v1/app-update` whether [installed],
/// from [store], must update first.
AppUpdateStatus decideAppUpdate(
  Map<String, dynamic> data, {
  required AppVersion installed,
  required AppStore store,
}) {
  if (data['enabled'] != true) return AppUpdateStatus.allowed;
  final platforms = data['platforms'];
  final platform = platforms is Map ? platforms[store.key] : null;
  if (platform is! Map) return AppUpdateStatus.allowed;

  final minimum = AppVersion.tryParse(platform['min_version']?.toString());
  final storeUrl = platform['store_url']?.toString().trim() ?? '';
  if (minimum == null || storeUrl.isEmpty) return AppUpdateStatus.allowed;

  return installed.isBelow(minimum)
      ? AppUpdateStatus.required(storeUrl)
      : AppUpdateStatus.allowed;
}

/// Asks the server (no sign-in needed) whether this installed version may
/// open. Any failure is [AppUpdateStatus.unknown], so students are never
/// locked out because the server could not be reached.
class AppUpdateService {
  AppUpdateService({
    http.Client? client,
    Future<AppVersion> Function()? installedVersion,
    Future<AppStore> Function()? store,
    this.timeout = const Duration(seconds: 10),
  }) : _client = client,
       _installedVersion = installedVersion ?? _readInstalledVersion,
       _store = store ?? _detectStore;

  final http.Client? _client;
  final Future<AppVersion> Function() _installedVersion;
  final Future<AppStore> Function() _store;
  final Duration timeout;

  Future<AppUpdateStatus> check() async {
    try {
      final uri = Uri.parse('${ApiConstants.baseUrl}${ApiConstants.appUpdate}');
      final headers = {'Accept': 'application/json'};
      final client = _client;
      final response =
          await (client == null
                  ? http.get(uri, headers: headers)
                  : client.get(uri, headers: headers))
              .timeout(timeout);
      if (response.statusCode != 200) return AppUpdateStatus.unknown;

      final body = jsonDecode(response.body);
      final data = body is Map ? body['data'] : null;
      if (data is! Map<String, dynamic>) return AppUpdateStatus.unknown;

      return decideAppUpdate(
        data,
        installed: await _installedVersion(),
        store: await _store(),
      );
    } catch (error) {
      debugPrint('App update check skipped: $error');
      return AppUpdateStatus.unknown;
    }
  }

  static Future<AppVersion> _readInstalledVersion() async {
    final info = await PackageInfo.fromPlatform();
    final version = AppVersion.tryParse(info.version) ?? const AppVersion([0]);
    return AppVersion(version.parts, int.tryParse(info.buildNumber));
  }

  static Future<AppStore> _detectStore() async {
    if (Platform.isIOS) return AppStore.appStore;
    final info = await PackageInfo.fromPlatform();
    final installer = info.installerStore;
    final knownStore =
        installer == _googlePlayInstaller || installer == _huaweiInstaller;
    final manufacturer = knownStore
        ? null
        : (await DeviceInfoPlugin().androidInfo).manufacturer;
    return androidStoreFor(installer: installer, manufacturer: manufacturer);
  }
}
