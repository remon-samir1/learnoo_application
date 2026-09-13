import 'package:flutter_test/flutter_test.dart';
import 'package:learnoo/features/auth/domain/splash_router.dart';

/// Builds a router whose collaborators are all stubs, so the decision is
/// exercised without a token store, a socket or an API.
SplashRouter buildRouter({
  String? token = 'session-token',
  bool online = true,
  Map<String, dynamic> profile = const {'success': false},
  void Function()? onClearToken,
}) {
  return SplashRouter(
    readToken: () async => token,
    hasConnection: () async => online,
    fetchProfile: () async => profile,
    clearToken: () async => onClearToken?.call(),
  );
}

Map<String, dynamic> profileResponse({
  String? role,
  String? universityId,
  String? facultyId,
  List<int>? centers,
}) {
  return {
    'success': true,
    'data': {
      'attributes': {
        if (role != null) 'role': role,
        if (universityId != null) 'university_id': universityId,
        if (facultyId != null) 'faculty_id': facultyId,
        if (centers != null) 'centers': centers,
      },
    },
  };
}

void main() {
  group('unauthenticated', () {
    test('a null token goes to login', () async {
      final router = buildRouter(token: null);
      expect(await router.resolve(), SplashDestination.login);
    });

    test('an empty token goes to login', () async {
      final router = buildRouter(token: '');
      expect(await router.resolve(), SplashDestination.login);
    });

    test('no profile call is made without a token', () async {
      var profileCalls = 0;
      final router = SplashRouter(
        readToken: () async => null,
        hasConnection: () async => true,
        fetchProfile: () async {
          profileCalls++;
          return const {'success': false};
        },
        clearToken: () async {},
      );

      await router.resolve();
      expect(profileCalls, 0);
    });
  });

  group('student', () {
    test('a complete academic profile goes to the student app', () async {
      final router = buildRouter(
        profile: profileResponse(
          role: 'Student',
          universityId: '3',
          facultyId: '12',
          centers: [7],
        ),
      );

      expect(await router.resolve(), SplashDestination.studentHome);
    });

    test('an incomplete academic profile goes to onboarding', () async {
      final router = buildRouter(profile: profileResponse(role: 'Student'));
      expect(await router.resolve(), SplashDestination.onboarding);
    });
  });

  group('parent', () {
    test('a parent goes to the parent dashboard', () async {
      final router = buildRouter(profile: profileResponse(role: 'Parent'));
      expect(await router.resolve(), SplashDestination.parentDashboard);
    });

    test('the role check ignores case and surrounding space', () async {
      final router = buildRouter(profile: profileResponse(role: '  parent '));
      expect(await router.resolve(), SplashDestination.parentDashboard);
    });

    test('a parent never falls into onboarding despite no academic ids',
        () async {
      // A parent account has no university or faculty; the completeness gate
      // must not see it first.
      final router = buildRouter(profile: profileResponse(role: 'Parent'));
      expect(await router.resolve(), isNot(SplashDestination.onboarding));
    });
  });

  group('offline and errors', () {
    test('offline with a stored session opens the cached app', () async {
      var profileCalls = 0;
      final router = SplashRouter(
        readToken: () async => 'session-token',
        hasConnection: () async => false,
        fetchProfile: () async {
          profileCalls++;
          return const {'success': false};
        },
        clearToken: () async {},
      );

      expect(await router.resolve(), SplashDestination.studentHome);
      expect(profileCalls, 0, reason: 'offline must not attempt a request');
    });

    test('a 401 clears the token and goes to login', () async {
      var cleared = false;
      final router = buildRouter(
        profile: const {'success': false, 'statusCode': 401},
        onClearToken: () => cleared = true,
      );

      expect(await router.resolve(), SplashDestination.login);
      expect(cleared, isTrue);
    });

    test('a 403 clears the token and goes to login', () async {
      var cleared = false;
      final router = buildRouter(
        profile: const {'success': false, 'statusCode': 403},
        onClearToken: () => cleared = true,
      );

      expect(await router.resolve(), SplashDestination.login);
      expect(cleared, isTrue);
    });

    test('a server error keeps the session and opens the cached app', () async {
      var cleared = false;
      final router = buildRouter(
        profile: const {'success': false, 'statusCode': 500},
        onClearToken: () => cleared = true,
      );

      expect(await router.resolve(), SplashDestination.studentHome);
      expect(cleared, isFalse, reason: 'a hiccup must not sign the user out');
    });
  });
}
