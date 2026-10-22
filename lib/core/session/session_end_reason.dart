/// Backend error key for "this device is not the one this account may use".
///
/// `app/(auth)/login/page.tsx` on the web keys the whole flow off it:
/// ```ts
/// if (err instanceof ApiError && err.code === 'device_transfer_required')
///   setTransferToken(err.transferToken || '');
/// ```
const String kDeviceTransferRequiredCode = 'device_transfer_required';

/// Backend error key on a 401 after the account was moved to another device.
const String kDeviceSessionRevokedCode = 'device_session_revoked';

/// Why the student was sent back to the sign-in screen.
///
/// The web redirects through `/api/auth/session-end?reason=…`, which lands on
/// `/login?session=device-changed|expired` and shows the matching notice.
enum SessionEndReason {
  /// Any other 401: the token simply stopped being valid.
  expired,

  /// `code: device_session_revoked` — staff approved a different device.
  deviceChanged;

  static SessionEndReason fromErrorCode(String? code) =>
      code == kDeviceSessionRevokedCode
          ? SessionEndReason.deviceChanged
          : SessionEndReason.expired;
}
