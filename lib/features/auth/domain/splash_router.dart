import '../domain/student_profile.dart';

/// Where the splash screen sends the user once it knows who they are.
enum SplashDestination {
  /// No usable session.
  login,

  /// Signed in, but the academic selection is incomplete.
  onboarding,

  /// Signed-in student.
  studentHome,

  /// Signed-in parent.
  parentDashboard,
}

/// Decides the entry screen.
///
/// The rule used to live inside the splash widget's state, tangled with
/// `Navigator` calls, so it could only be exercised by driving the real screen
/// against the real API. It is a pure decision over three inputs, so it lives
/// here and the widget just renders the answer.
///
/// Order matters and mirrors the web's `getPostAuthHref`: role is resolved
/// before the profile-completeness gate, because a parent account has no
/// academic selection to complete and must never land in the student app.
class SplashRouter {
  SplashRouter({
    required this.readToken,
    required this.hasConnection,
    required this.fetchProfile,
    required this.clearToken,
  });

  /// The stored session token, or `null` when signed out.
  final Future<String?> Function() readToken;

  final Future<bool> Function() hasConnection;

  /// `GET /v1/auth/me`, in the repository's `{success, data, statusCode}` shape.
  final Future<Map<String, dynamic>> Function() fetchProfile;

  /// Drops a token the server has rejected.
  final Future<void> Function() clearToken;

  /// `/v1/auth/me` reports the role as a display name; the web compares it to
  /// the literal "Parent".
  static bool isParentRole(String? role) =>
      role != null && role.trim().toLowerCase() == 'parent';

  Future<SplashDestination> resolve() async {
    final token = await readToken();
    if (token == null || token.isEmpty) {
      return SplashDestination.login;
    }

    // Offline with a stored session: let the student into the cached app
    // rather than bouncing them to a login they cannot complete.
    if (!await hasConnection()) {
      return SplashDestination.studentHome;
    }

    final result = await fetchProfile();

    if (result['success'] == true) {
      final data = result['data'];
      final profile = StudentProfile.fromData(
        data is Map ? Map<String, dynamic>.from(data) : null,
      );

      if (isParentRole(profile.role)) {
        return SplashDestination.parentDashboard;
      }

      return profile.isAcademicProfileComplete
          ? SplashDestination.studentHome
          : SplashDestination.onboarding;
    }

    // The server rejected the token — drop it and start over.
    final statusCode = result['statusCode'];
    if (statusCode == 401 || statusCode == 403) {
      await clearToken();
      return SplashDestination.login;
    }

    // Any other failure is probably a server hiccup, so the session is kept
    // and the cached app is shown instead of signing the student out.
    return SplashDestination.studentHome;
  }
}
