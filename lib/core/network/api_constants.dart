class ApiConstants {
  static const String baseUrl = 'https://api.learnoo.app';
  static const String register = '/v1/auth/register';
  static const String login = '/v1/auth/login';
  static const String emailVerificationNotification = '/v1/auth/email/verification-notification';
  static const String phoneVerificationNotification = '/v1/auth/phone/verification-notification';
  static const String verifyEmail = '/v1/auth/email/verify';
  static const String verifyPhone = '/v1/auth/phone/verify';
  static const String passwordForgot = '/v1/auth/password/forgot';
  static const String passwordReset = '/v1/auth/password/reset';
  static const String universities = '/v1/university';
  static const String centers = '/v1/center';
  static const String faculties = '/v1/faculty';
  static const String departments = '/v1/department';
  static const String courses = '/v1/course';
  static const String updateProfile = '/v1/auth/update';
  static const String me = '/v1/auth/me';
  static const String logout = '/v1/auth/logout';
  static const String lectures = '/v1/lecture';
  static const String chapters = '/v1/chapter';
  static const String codeActivate = '/v1/code/activate';
  static const String studentCourseActivate = '/v1/student/courses/activate';
  static const String categories = '/v1/department';
  static const String discussion = '/v1/discussion';

  // Quiz/Exam endpoints
  static const String quiz = '/v1/quiz';
  static const String quizQuestion = '/v1/quiz-question';
  static const String quizAnswer = '/v1/quiz-answer';
  static const String quizAttempt = '/v1/quiz-attempt';

  /// Per-question answer rows. POST creates, PUT updates by row id.
  /// Without these the backend never sees individual answers, so short-answer
  /// questions cannot be graded by an instructor.
  static const String quizUserAnswer = '/v1/quiz-user-answer';

  /// Full review payload for one attempt: `/v1/quiz-attempts/{id}/result`.
  static String quizAttemptResult(Object attemptId) =>
      '/v1/quiz-attempts/$attemptId/result';

  // -------------------------------------------------------------------------
  // Parent portal — mirrors `parentApi` in `src/lib/api.ts`.
  // -------------------------------------------------------------------------

  /// Linked children. `GET` lists them, `POST` links one by student code.
  static const String parentStudents = '/v1/parent/students';

  static String parentStudentDashboard(Object id) =>
      '/v1/parent/students/$id/dashboard';
  static String parentStudentProgress(Object id) =>
      '/v1/parent/students/$id/progress';
  static String parentStudentWeeklyStats(Object id) =>
      '/v1/parent/students/$id/weekly-stats';
  static String parentStudentAlerts(Object id) =>
      '/v1/parent/students/$id/alerts';
  static String parentStudentFeedback(Object id) =>
      '/v1/parent/students/$id/feedback';
  static String parentStudentActivity(Object id) =>
      '/v1/parent/students/$id/activity';

  // Notes endpoints
  static const String notes = '/v1/note';

  // Library endpoints
  static const String libraries = '/v1/library';

  // Posts endpoints
  static const String posts = '/v1/post';

  /// Reactions on a post.
  static String postReact(Object postId) => '/v1/post/$postId/react';

  // User progress endpoint
  static const String userProgress = '/v1/user-progress';

  // Live room endpoints
  static const String liveRooms = '/v1/live-room';

  // OTA (Over-The-Air) update endpoint
  static const String otaLatest = '/v1/ota/latest';

  // Social links endpoint
  static const String socialLinks = '/v1/social-link';

  // Feature flags endpoint
  static const String features = '/v1/feature';

  // Global search
  static const String search = '/v1/search';

  /// Support tickets (student "Contact support" form).
  static const String issues = '/v1/issues';

  // Chapter view count endpoint
  static const String chapterViewCount = '/v1/chapter-view-count';

  /// Registers one view against the student's per-chapter limit.
  static String chapterView(Object chapterId) => '/v1/chapter/$chapterId/view';

  /// Encrypted HLS playlist served by the API for a chapter.
  static String chapterHlsPlaylist(Object chapterId) =>
      '$baseUrl/hls/chapter/$chapterId/playlist';

  // Notifications endpoints
  static const String notifications = '/v1/notifications';
  static const String notificationsUnread = '/v1/notifications/unread';
  static const String notificationsRead = '/v1/notifications/{id}/read';
  static const String notificationsReadAll = '/v1/notifications/read-all';
  static const String notificationsDelete = '/v1/notifications/{id}';
  static const String notificationsCount = '/v1/notifications/count';

  // -------------------------------------------------------------------------
  // Realtime (Laravel Reverb) — must match `src/lib/echo.ts` on the web.
  // -------------------------------------------------------------------------

  /// Reverb app key.
  static const String reverbKey = 'ecnn3pfvurlo73fkabhm';
  static const String reverbHost = 'api.learnoo.app';
  static const int reverbPort = 8090;
  static const bool reverbUseTls = true;

  /// Private-channel authorizer. Takes the same bearer token as the REST API.
  static const String broadcastingAuth = '$baseUrl/broadcasting/auth';

  /// Private channel that carries the login OTP. `{id}` is the user id.
  static String otpChannel(Object userId) => 'private-auto-otp.$userId';

  /// Event name broadcast on [otpChannel].
  static const String otpEvent = 'SendOtpEvent';

  /// Public channel used for notification fan-out.
  static const String globalChannel = 'global';

  // -------------------------------------------------------------------------
  // Live sessions (Jitsi) — must match `src/lib/jitsi.ts` on the web.
  // -------------------------------------------------------------------------

  static const String jitsiDomain = 'meet.learnoo.app';
  static const String jitsiServerUrl = 'https://$jitsiDomain';

  /// Room name shared with the web client. Strips every non-alphanumeric
  /// character then prefixes `learnooroom`, so live room 58 is
  /// `learnooroom58` on both platforms — students in the app and on the web
  /// land in the same conference.
  static String jitsiRoomName(Object roomId) {
    final clean = roomId.toString().replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
    return 'learnooroom$clean';
  }
}
