// SMOKE TEST: opens every main screen with realistic seeded data and fails if
// Flutter reports ANY error (layout, semantics, assertion...). This is the
// safety net that catches "red screen" bugs before you do.
//
// Optionally it also saves pictures to test/visual/goldens/ so screens can be
// compared with the original `design-context/*.png`:
//
//   flutter test test/visual --update-goldens --dart-define=GOLDENS=true
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/widgets.dart' show SizedBox;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lockin/app/app.dart';
import 'package:lockin/app/router.dart';
import 'package:lockin/core/providers.dart';
import 'package:lockin/core/utils/calendar_date.dart';
import 'package:lockin/features/auth/application/session_controller.dart';
import 'package:lockin/features/auth/data/disabled_auth_gateway.dart';
import 'package:lockin/features/reminders/application/reminder_providers.dart';
import 'package:lockin/features/reminders/data/notification_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tzdata;

/// The "current time" for every screenshot: 15 June 2026, 10:00 UTC.
final _now = DateTime.parse('2026-06-15T10:00:00Z');

Future<void> _loadFont(String family, List<String> files) async {
  final loader = FontLoader(family);
  for (final f in files) {
    loader.addFont(
      Future.value(ByteData.sublistView(File(f).readAsBytesSync())),
    );
  }
  await loader.load();
}

/// A realistic account: one building habit going well, one paused, one quit
/// habit that broke, and one weekly quota.
Map<String, dynamic> _seed() {
  Map<String, dynamic> commitment(
    String id,
    String name,
    String path,
    String start,
    int duration,
    Map<String, dynamic> pace,
    String status, {
    String description = '',
    String reward = 'A Good Coffee',
    List<Map<String, dynamic>> pauses = const [],
    String? failureDate,
    String? failureReason,
    List<Map<String, dynamic>> events = const [],
  }) => {
    'id': id,
    'attemptId': id,
    'path': path,
    'name': name,
    'description': description,
    'startDate': start,
    'duration': duration,
    'pace': pace,
    'reward': reward,
    'timeZone': 'UTC',
    'status': status,
    'createdAt': '${start}T08:00:00Z',
    'pauses': pauses,
    'failureDate': ?failureDate,
    'failureReason': ?failureReason,
    'events': events,
  };

  Map<String, dynamic> log(String id, String date, int count) => {
    'attemptId': id,
    'date': date,
    'count': count,
    'updatedAt': '${date}T09:00:00Z',
    'outcome': 'success',
  };

  return {
    'commitments': [
      commitment(
        'yoga',
        'Daily Yoga Practice',
        'build',
        '2026-06-01',
        30,
        {'kind': 'daily', 'count': 1},
        'active',
        description: 'Twenty minutes every morning.',
        events: [
          {
            'type': 'locked',
            'at': '2026-06-01T08:00:00Z',
            'date': '2026-06-01',
          },
        ],
      ),
      commitment(
        'water',
        'Drink Water',
        'build',
        '2026-06-10',
        14,
        {'kind': 'daily', 'count': 8},
        'active',
        reward: 'Favorite Meal',
      ),
      commitment(
        'run',
        'Run 3 Times a Week',
        'build',
        '2026-06-08',
        28,
        {'kind': 'weekly', 'count': 3},
        'active',
        reward: 'Watch a movie',
      ),
      commitment(
        'sugar',
        'No Sugar',
        'quit',
        '2026-06-03',
        21,
        {'kind': 'daily', 'count': 1},
        'paused',
        pauses: [
          {'start': '2026-06-13'},
        ],
        reward: 'Take a Nap',
      ),
      commitment(
        'phone',
        'No Phone in Bed',
        'quit',
        '2026-06-01',
        30,
        {'kind': 'daily', 'count': 1},
        'broken',
        failureDate: '2026-06-09',
        failureReason: 'explicit',
        events: [
          {
            'type': 'locked',
            'at': '2026-06-01T08:00:00Z',
            'date': '2026-06-01',
          },
          {
            'type': 'broken',
            'at': '2026-06-09T20:00:00Z',
            'date': '2026-06-09',
          },
        ],
      ),
    ],
    'checkIns': [
      for (var d = 1; d <= 14; d++)
        log('yoga', '2026-06-${d.toString().padLeft(2, '0')}', 1),
      log('water', '2026-06-15', 5),
      log('run', '2026-06-09', 1),
      log('run', '2026-06-11', 1),
      for (var d = 3; d <= 8; d++)
        log('phone', '2026-06-${d.toString().padLeft(2, '0')}', 1),
    ],
  };
}

/// The real notification plugin needs a phone; tests use this do-nothing stand-in.
class _FakeNotifications extends NotificationService {
  @override
  Future<bool> permission({bool request = false}) async => false;
  @override
  Future<List<({String id, String? key})>> list() async => [];
  @override
  Future<void> cancel(String id) async {}
  @override
  Future<void> clearAll() async {}
  @override
  Future<ReminderTap?> launchTap() async => null;
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    tzdata.initializeTimeZones();
    DeviceZone.current = 'UTC';
    await _loadFont('Inter', [
      'assets/fonts/Inter_400Regular.ttf',
      'assets/fonts/Inter_500Medium.ttf',
      'assets/fonts/Inter_600SemiBold.ttf',
      'assets/fonts/Inter_700Bold.ttf',
    ]);
    await _loadFont('Feather', ['assets/fonts/Feather.ttf']);
  });

  late SemanticsHandle semanticsHandle;

  Future<GoRouter> boot(
    WidgetTester tester, {
    bool seeded = true,
    bool signedIn = true,
  }) async {
    // Turn accessibility on: several past bugs only appeared with semantics active.
    semanticsHandle = tester.ensureSemantics();
    SharedPreferences.setMockInitialValues({
      if (signedIn) 'lockin.device-session.v1': true,
      if (seeded && signedIn) 'lockin.data.v1.device': jsonEncode(_seed()),
    });
    final prefs = await SharedPreferences.getInstance();
    binding.platformDispatcher.views.first.physicalSize = const Size(
      390 * 3,
      844 * 3,
    );
    binding.platformDispatcher.views.first.devicePixelRatio = 3;
    addTearDown(binding.platformDispatcher.views.first.resetPhysicalSize);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          clockProvider.overrideWithValue(() => _now),
          authGatewayProvider.overrideWith(
            (ref) async => DisabledAuthGateway(),
          ),
          notificationServiceProvider.overrideWithValue(_FakeNotifications()),
        ],
        child: const LockInApp(),
      ),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    return ProviderScope.containerOf(
      tester.element(find.byType(LockInApp)),
    ).read(routerProvider);
  }

  Future<void> shot(WidgetTester tester, String name) async {
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    // Fail on any error Flutter swallowed while building/laying out.
    final problem = tester.takeException();
    if (const bool.fromEnvironment('GOLDENS')) {
      await expectLater(
        find.byType(LockInApp),
        matchesGoldenFile('goldens/$name.png'),
      );
    }
    // Remove the app so its timers (30 s data refresh) are cancelled.
    await tester.pumpWidget(const SizedBox.shrink());
    semanticsHandle.dispose();
    expect(problem, isNull, reason: 'screen "$name" threw');
  }

  testWidgets('sign in', (tester) async {
    await boot(tester, signedIn: false);
    await shot(tester, '01_sign_in');
  });

  testWidgets('focus (populated)', (tester) async {
    await boot(tester);
    await shot(tester, '02_focus');
  });

  testWidgets('focus (empty account)', (tester) async {
    await boot(tester, seeded: false);
    await shot(tester, '03_focus_empty');
  });

  testWidgets('wizard steps', (tester) async {
    final router = await boot(tester, seeded: false);
    unawaited(router.push('/commitment/new'));
    await shot(tester, '04_wizard_1');
  });

  testWidgets('detail active', (tester) async {
    final router = await boot(tester);
    unawaited(router.push('/commitment/yoga'));
    await shot(tester, '05_detail_active');
  });

  testWidgets('detail broken', (tester) async {
    final router = await boot(tester);
    unawaited(router.push('/commitment/phone'));
    await shot(tester, '06_detail_broken');
  });

  testWidgets('reflection', (tester) async {
    final router = await boot(tester);
    unawaited(router.push('/commitment/phone/reflect'));
    await shot(tester, '07_reflection');
  });

  testWidgets('history', (tester) async {
    final router = await boot(tester);
    router.go('/history');
    await shot(tester, '08_history');
  });

  testWidgets('settings', (tester) async {
    final router = await boot(tester);
    router.go('/settings');
    await shot(tester, '09_settings');
  });
}
