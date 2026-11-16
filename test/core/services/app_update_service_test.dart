import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:learnoo/core/network/api_constants.dart';
import 'package:learnoo/core/services/app_update_service.dart';

AppVersion v(String value) => AppVersion.tryParse(value)!;

Map<String, dynamic> settings({
  bool enabled = true,
  String? android,
  String? huawei,
  String? ios,
}) => {
  'enabled': enabled,
  'platforms': {
    'android': {
      'min_version': android,
      'store_url':
          'https://play.google.com/store/apps/details?id=com.sunmed.learnoo',
    },
    'huawei': {
      'min_version': huawei,
      'store_url': 'https://appgallery.huawei.com/app/C119233749',
    },
    'ios': {
      'min_version': ios,
      'store_url': 'https://apps.apple.com/app/id6825859916',
    },
  },
};

void main() {
  group('version comparison', () {
    test('numbers are compared as numbers, not text', () {
      expect(v('1.0.3+12').isBelow(v('1.0.10')), isTrue);
      expect(v('1.0.10').isBelow(v('1.0.3+12')), isFalse);
      expect(v('1.0.9').isBelow(v('1.0.10')), isTrue);
      expect(v('1.2').isBelow(v('1.10')), isTrue);
      expect(v('2.0.0').isBelow(v('1.99.99')), isFalse);
    });

    test(
      'a minimum without a build number allows every build of that version',
      () {
        expect(v('1.0.3+12').isBelow(v('1.0.3')), isFalse);
        expect(v('1.0.3+1').isBelow(v('1.0.3')), isFalse);
        expect(v('1.0.2+99').isBelow(v('1.0.3')), isTrue);
      },
    );

    test('a minimum with a build number also checks the build', () {
      expect(v('1.0.3+12').isBelow(v('1.0.3+13')), isTrue);
      expect(v('1.0.3+12').isBelow(v('1.0.3+12')), isFalse);
      expect(v('1.0.3+13').isBelow(v('1.0.3+12')), isFalse);
      expect(v('1.0.4+1').isBelow(v('1.0.3+12')), isFalse);
    });

    test('missing parts count as zero', () {
      expect(v('1.0').isBelow(v('1.0.0')), isFalse);
      expect(v('1.0.0').isBelow(v('1.0.1')), isTrue);
      expect(v('1').compareTo(v('1.0.0')), 0);
    });

    test('anything that is not a version is not read as one', () {
      for (final bad in [
        '',
        ' ',
        'v1.0.3',
        '1.0.3+',
        '+12',
        '1..0',
        'latest',
        null,
      ]) {
        expect(AppVersion.tryParse(bad), isNull, reason: '$bad');
      }
      expect(v(' 1.0.3+12 ').toString(), '1.0.3+12');
    });
  });

  group('decision', () {
    test(
      'blocks only the store whose minimum is above the installed version',
      () {
        final data = settings(
          android: '1.0.3+12',
          huawei: '1.0.4',
          ios: '1.0.10',
        );
        final installed = v('1.0.3+12');

        expect(
          decideAppUpdate(
            data,
            installed: installed,
            store: AppStore.googlePlay,
          ),
          AppUpdateStatus.allowed,
        );
        expect(
          decideAppUpdate(data, installed: installed, store: AppStore.huawei),
          const AppUpdateStatus.required(
            'https://appgallery.huawei.com/app/C119233749',
          ),
        );
        expect(
          decideAppUpdate(data, installed: installed, store: AppStore.appStore),
          const AppUpdateStatus.required(
            'https://apps.apple.com/app/id6825859916',
          ),
        );
      },
    );

    test(
      'switched off, no minimum, or an unreadable minimum lets the app open',
      () {
        final installed = v('1.0.0+1');
        expect(
          decideAppUpdate(
            settings(enabled: false, ios: '9.0.0'),
            installed: installed,
            store: AppStore.appStore,
          ),
          AppUpdateStatus.allowed,
        );
        expect(
          decideAppUpdate(
            settings(),
            installed: installed,
            store: AppStore.appStore,
          ),
          AppUpdateStatus.allowed,
        );
        expect(
          decideAppUpdate(
            settings(ios: 'latest'),
            installed: installed,
            store: AppStore.appStore,
          ),
          AppUpdateStatus.allowed,
        );
        expect(
          decideAppUpdate(
            {'enabled': true},
            installed: installed,
            store: AppStore.appStore,
          ),
          AppUpdateStatus.allowed,
        );
      },
    );
  });

  group('which store', () {
    test(
      'the installer decides; a Huawei phone without a store installer goes to AppGallery',
      () {
        expect(
          androidStoreFor(
            installer: 'com.android.vending',
            manufacturer: 'HUAWEI',
          ),
          AppStore.googlePlay,
        );
        expect(
          androidStoreFor(
            installer: 'com.huawei.appmarket',
            manufacturer: 'samsung',
          ),
          AppStore.huawei,
        );
        expect(
          androidStoreFor(installer: null, manufacturer: 'HUAWEI'),
          AppStore.huawei,
        );
        expect(
          androidStoreFor(
            installer: 'com.google.android.packageinstaller',
            manufacturer: 'HONOR',
          ),
          AppStore.googlePlay,
        );
        expect(androidStoreFor(), AppStore.googlePlay);
      },
    );
  });

  group('server check', () {
    AppUpdateService service(
      http.Client client, {
      String installed = '1.0.3+12',
    }) => AppUpdateService(
      client: client,
      installedVersion: () async => v(installed),
      store: () async => AppStore.appStore,
      timeout: const Duration(milliseconds: 200),
    );

    test(
      'reads the public endpoint without a token and blocks below the minimum',
      () async {
        late http.Request seen;
        final client = MockClient((request) async {
          seen = request;
          return http.Response(
            jsonEncode({'data': settings(ios: '1.0.10')}),
            200,
          );
        });

        expect(
          await service(client).check(),
          const AppUpdateStatus.required(
            'https://apps.apple.com/app/id6825859916',
          ),
        );
        expect(seen.method, 'GET');
        expect(seen.url.toString(), '${ApiConstants.baseUrl}/v1/app-update');
        expect(seen.headers.containsKey('Authorization'), isFalse);
      },
    );

    test('allows when the installed version meets the minimum', () async {
      final client = MockClient(
        (_) async =>
            http.Response(jsonEncode({'data': settings(ios: '1.0.3')}), 200),
      );
      expect(await service(client).check(), AppUpdateStatus.allowed);
    });

    test(
      'server down, error answer, bad body or no answer in time → unknown, never blocked',
      () async {
        final failures = <MockClient>[
          MockClient((_) async => throw const SocketExceptionLike()),
          MockClient((_) async => http.Response('oops', 500)),
          MockClient((_) async => http.Response('<html>', 200)),
          MockClient(
            (_) async => http.Response(jsonEncode({'message': 'x'}), 200),
          ),
          MockClient((_) => Completer<http.Response>().future),
        ];
        for (final client in failures) {
          expect(await service(client).check(), AppUpdateStatus.unknown);
        }
      },
    );
  });
}

class SocketExceptionLike implements Exception {
  const SocketExceptionLike();
}
