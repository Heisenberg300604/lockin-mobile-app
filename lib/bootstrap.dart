/// Everything that must happen *before* the first frame.
///
/// Flutter apps start in `main()`. Anything asynchronous that the UI needs
/// immediately (stored preferences, the time-zone database, the notification
/// plugin) is prepared here, then handed to the widget tree through Riverpod
/// overrides. That way widgets can read those values synchronously.
library;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'app/app.dart';
import 'core/providers.dart';
import 'core/utils/calendar_date.dart';
import 'features/reminders/application/reminder_providers.dart';
import 'features/reminders/data/notification_service.dart';

/// Prepares services and starts the app.
Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();

  // The app is portrait-only (see the original app.json).
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  // 1. Time zones: load the IANA database, then ask the OS which zone we are in.
  tzdata.initializeTimeZones();
  DeviceZone.current = await _resolveDeviceZone();

  // 2. Preferences and local data live in SharedPreferences.
  final prefs = await SharedPreferences.getInstance();
  await _removeLegacyCommitmentData(prefs);

  // 3. Notifications.
  final notifications = NotificationService();
  try {
    await notifications.initialize();
  } catch (_) {
    // The app works without notifications; Settings will report the problem.
  }

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        notificationServiceProvider.overrideWithValue(notifications),
      ],
      child: const LockInApp(),
    ),
  );
}

/// The API is now the source of truth. Remove only the old on-device
/// commitment snapshots and saved creation drafts once; Clerk's secure session
/// and unrelated app preferences are deliberately left intact.
Future<void> _removeLegacyCommitmentData(SharedPreferences prefs) async {
  const migrationKey = 'lockin.remote-data-reset.v1';
  if (prefs.getBool(migrationKey) ?? false) return;

  final oldKeys = prefs.getKeys().where(
    (key) =>
        key.startsWith('lockin.data.v1.') || key.startsWith('lockin.draft.'),
  );
  for (final key in oldKeys) {
    await prefs.remove(key);
  }
  await prefs.setBool(migrationKey, true);
}

Future<String> _resolveDeviceZone() async {
  try {
    final info = await FlutterTimezone.getLocalTimezone();
    final id = info.identifier;
    if (id == 'UTC' || id == 'Etc/UTC' || id == 'GMT') return 'UTC';
    tz.getLocation(id); // throws if unknown to our database
    return id;
  } catch (_) {
    return 'UTC';
  }
}
