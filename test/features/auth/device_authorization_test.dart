import 'package:flutter_test/flutter_test.dart';
import 'package:learnoo/core/network/api_exception.dart';
import 'package:learnoo/core/services/device_service.dart';
import 'package:learnoo/features/auth/domain/device_authorization.dart';

/// The shape the backend answers with when the account is bound to another
/// device, mirroring `ApiError(status, message, errors, code, transfer_token)`
/// on the web.
Map<String, dynamic> refusalBody({
  String? transferToken = 'transfer-token-value',
  String code = kDeviceTransferRequiredCode,
  String message = 'This device is not authorized for your account.',
}) {
  return {
    'message': message,
    'code': code,
    'transfer_token': ?transferToken,
  };
}

void main() {
  group('ApiException.fromBody', () {
    test('reads the device refusal code and transfer token', () {
      final error = ApiException.fromBody(403, refusalBody(), fallback: 'x');

      expect(error.status, 403);
      expect(error.code, 'device_transfer_required');
      expect(error.transferToken, 'transfer-token-value');
      expect(error.message, 'This device is not authorized for your account.');
    });

    test('leaves code and token null when the body omits them', () {
      final error = ApiException.fromBody(
        422,
        {'message': 'The given data was invalid.'},
        fallback: 'x',
      );

      expect(error.code, isNull);
      expect(error.transferToken, isNull);
    });

    test('treats blank code and token as absent', () {
      final error = ApiException.fromBody(
        403,
        {'message': 'nope', 'code': '  ', 'transfer_token': ''},
        fallback: 'x',
      );

      expect(error.code, isNull);
      expect(error.transferToken, isNull);
    });
  });

  group('DeviceAuthorizationChallenge.fromApiException', () {
    test('recognises a device_transfer_required refusal', () {
      final error = ApiException.fromBody(403, refusalBody(), fallback: 'x');
      final challenge = DeviceAuthorizationChallenge.fromApiException(error);

      expect(challenge, isNotNull);
      expect(challenge!.transferToken, 'transfer-token-value');
      expect(challenge.canRequestAuthorization, isTrue);
      expect(challenge.message,
          'This device is not authorized for your account.');
    });

    test('offers no request action when the token is missing', () {
      final error = ApiException.fromBody(
        403,
        refusalBody(transferToken: null),
        fallback: 'x',
      );
      final challenge = DeviceAuthorizationChallenge.fromApiException(error);

      expect(challenge, isNotNull);
      expect(challenge!.transferToken, isEmpty);
      expect(challenge.canRequestAuthorization, isFalse);
    });

    test('ignores any other failure', () {
      final wrongCode = ApiException.fromBody(
        403,
        refusalBody(code: 'course_not_activated'),
        fallback: 'x',
      );
      final noCode = ApiException(422, 'The given data was invalid.');

      expect(
          DeviceAuthorizationChallenge.fromApiException(wrongCode), isNull);
      expect(DeviceAuthorizationChallenge.fromApiException(noCode), isNull);
    });

    test('falls back to the caller message when the body has none', () {
      final error = ApiException(
        403,
        '',
        null,
        kDeviceTransferRequiredCode,
        'tok',
      );

      final challenge = DeviceAuthorizationChallenge.fromApiException(
        error,
        fallbackMessage: 'Login failed',
      );

      expect(challenge!.message, 'Login failed');
    });
  });

  group('DeviceAuthorizationChallenge.fromResult', () {
    test('reads the repository result map', () {
      final challenge = DeviceAuthorizationChallenge.fromResult({
        'success': false,
        'message': 'Not your device',
        'code': kDeviceTransferRequiredCode,
        'transferToken': 'tok-1',
      });

      expect(challenge!.message, 'Not your device');
      expect(challenge.transferToken, 'tok-1');
      expect(challenge.canRequestAuthorization, isTrue);
    });

    test('returns null for an ordinary login failure', () {
      expect(
        DeviceAuthorizationChallenge.fromResult({
          'success': false,
          'message': 'Login failed',
          'statusCode': 422,
        }),
        isNull,
      );
    });

    test('uses the fallback message and tolerates a missing token', () {
      final challenge = DeviceAuthorizationChallenge.fromResult(
        {'success': false, 'code': kDeviceTransferRequiredCode},
        fallbackMessage: 'Login failed',
      );

      expect(challenge!.message, 'Login failed');
      expect(challenge.canRequestAuthorization, isFalse);
    });
  });

  group('SessionEndReason', () {
    test('maps device_session_revoked to the device-changed notice', () {
      expect(
        SessionEndReason.fromErrorCode(kDeviceSessionRevokedCode),
        SessionEndReason.deviceChanged,
      );
    });

    test('treats every other 401 as an expired session', () {
      expect(SessionEndReason.fromErrorCode(null), SessionEndReason.expired);
      expect(
        SessionEndReason.fromErrorCode('unauthenticated'),
        SessionEndReason.expired,
      );
    });
  });

  group('DeviceService device id', () {
    test('generates a v4 UUID in the same shape as crypto.randomUUID()', () {
      final id = DeviceService.generateDeviceId();

      expect(
        id,
        matches(RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')),
      );
      expect(id.length, 36);
    });

    test('generates a distinct id each time', () {
      final ids = {for (var i = 0; i < 50; i++) DeviceService.generateDeviceId()};
      expect(ids.length, 50);
    });

    test('accepts stored ids only within the web client length bounds', () {
      expect(DeviceService.isValidDeviceId(DeviceService.generateDeviceId()),
          isTrue);
      expect(DeviceService.isValidDeviceId('a' * 16), isTrue);
      expect(DeviceService.isValidDeviceId('a' * 255), isTrue);
      expect(DeviceService.isValidDeviceId('a' * 15), isFalse);
      expect(DeviceService.isValidDeviceId('a' * 256), isFalse);
      expect(DeviceService.isValidDeviceId(''), isFalse);
      expect(DeviceService.isValidDeviceId(null), isFalse);
    });
  });
}
