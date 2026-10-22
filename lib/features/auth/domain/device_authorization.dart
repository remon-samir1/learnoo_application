import '../../../core/network/api_exception.dart';
import '../../../core/session/session_end_reason.dart';

export '../../../core/session/session_end_reason.dart'
    show SessionEndReason, kDeviceSessionRevokedCode, kDeviceTransferRequiredCode;

/// A login refused because this device is not authorized for the account.
///
/// Holds the backend's own message (already localised by the `lang` header)
/// and the single-use `transfer_token` that identifies this device to the
/// approval endpoint. The web shows the request button only when that token is
/// present — an empty token leaves the student with the message alone — and
/// this type mirrors that through [canRequestAuthorization].
class DeviceAuthorizationChallenge {
  const DeviceAuthorizationChallenge({
    required this.message,
    required this.transferToken,
  });

  /// Message the backend returned for the refused login.
  final String message;

  /// `transfer_token` from the error body; empty when the backend omitted it.
  final String transferToken;

  /// Whether the "ask staff to authorize this device" action can be offered.
  bool get canRequestAuthorization => transferToken.isNotEmpty;

  /// Reads a challenge off a failed `POST /v1/auth/login`, or returns `null`
  /// when the failure was something else (wrong number, validation, network).
  static DeviceAuthorizationChallenge? fromApiException(
    ApiException error, {
    String? fallbackMessage,
  }) {
    if (error.code != kDeviceTransferRequiredCode) return null;
    return DeviceAuthorizationChallenge(
      message: error.display(fallbackMessage),
      transferToken: error.transferToken ?? '',
    );
  }

  /// Same, from the `{success, message, code, transferToken}` map the
  /// repositories hand to the screens.
  static DeviceAuthorizationChallenge? fromResult(
    Map<String, dynamic> result, {
    String? fallbackMessage,
  }) {
    if (result['code']?.toString() != kDeviceTransferRequiredCode) return null;
    final message = result['message']?.toString().trim();
    return DeviceAuthorizationChallenge(
      message: (message != null && message.isNotEmpty)
          ? message
          : (fallbackMessage ?? ''),
      transferToken: result['transferToken']?.toString().trim() ?? '',
    );
  }
}
