/// Talks to the phone's notification system (via `flutter_local_notifications`).
///
/// This is the only file that knows about that plugin. Planning lives in
/// `domain/reminder_plan.dart` and synchronisation in `reminder_scheduler.dart`.
///
/// Privacy: notification text never contains habit names or notes, because
/// lock screens are public. It only says "a commitment is waiting".
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import '../domain/reminder_plan.dart';
import 'reminder_scheduler.dart';

/// What the user tapped: which attempt and day to open.
typedef ReminderTap = ({String attemptId, String date});

/// Wrapper around the local-notification plugin; also the [ReminderBackend]
/// used by the scheduler.
class NotificationService implements ReminderBackend {
  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  final StreamController<ReminderTap> _taps = StreamController<ReminderTap>.broadcast();
  bool _initialised = false;

  static const _channelId = 'lockin-reminders';
  static const _channelName = 'Commitment reminders';

  /// Notifications the user taps while the app is running.
  Stream<ReminderTap> get taps => _taps.stream;

  /// Call once at start-up.
  Future<void> initialize() async {
    if (_initialised) return;
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        // Permission is requested later, when the user turns reminders on.
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: (response) => _emit(response.payload),
    );
    _initialised = true;
  }

  /// The tap that cold-started the app, if any.
  Future<ReminderTap?> launchTap() async {
    final details = await _plugin.getNotificationAppLaunchDetails();
    if (details?.didNotificationLaunchApp != true) return null;
    return _parse(details?.notificationResponse?.payload);
  }

  void _emit(String? payload) {
    final tap = _parse(payload);
    if (tap != null) _taps.add(tap);
  }

  ReminderTap? _parse(String? payload) {
    if (payload == null) return null;
    try {
      final data = jsonDecode(payload) as Map<String, dynamic>;
      return (attemptId: data['attemptId'] as String, date: data['date'] as String);
    } catch (_) {
      return null;
    }
  }

  /// Whether notifications are allowed. With [request] it asks the user first.
  Future<bool> permission({bool request = false}) async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      if (request) {
        final granted = await android.requestNotificationsPermission();
        if (granted != null) return granted;
      }
      return await android.areNotificationsEnabled() ?? false;
    }
    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    if (ios != null) {
      if (request) {
        final granted = await ios.requestPermissions(alert: true);
        if (granted != null) return granted;
      }
      return (await ios.checkPermissions())?.isEnabled ?? false;
    }
    return false;
  }

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      _channelId,
      _channelName,
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      playSound: false,
      enableVibration: false,
      visibility: NotificationVisibility.private,
    ),
    iOS: DarwinNotificationDetails(presentAlert: true, presentSound: false, presentBadge: false),
  );

  static const _title = 'A moment to LockIn';
  static const _body = 'Your commitment is waiting. Open LockIn to check in.';

  /// A stable 31-bit id for a reminder key (notifications need integer ids).
  static int idFor(String key) {
    var hash = 0x811C9DC5; // FNV-1a
    for (final unit in key.codeUnits) {
      hash = ((hash ^ unit) * 0x01000193) & 0x7FFFFFFF;
    }
    return hash;
  }

  @override
  Future<List<({String id, String? key})>> list() async {
    final pending = await _plugin.pendingNotificationRequests();
    return [
      for (final p in pending)
        (id: '${p.id}', key: _keyOf(p.payload)),
    ];
  }

  String? _keyOf(String? payload) {
    if (payload == null) return null;
    try {
      return (jsonDecode(payload) as Map<String, dynamic>)['key'] as String?;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> cancel(String id) => _plugin.cancel(id: int.parse(id));

  @override
  Future<void> schedule(Reminder reminder) => _plugin.zonedSchedule(
        id: idFor(reminder.key),
        title: _title,
        body: _body,
        scheduledDate: tz.TZDateTime.fromMillisecondsSinceEpoch(tz.UTC, reminder.at),
        notificationDetails: _details,
        // Inexact scheduling needs no special Android permission; delivery may
        // be a few minutes late, which is fine for a gentle nudge.
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        payload: jsonEncode({
          'key': reminder.key,
          'attemptId': reminder.attemptId,
          'date': reminder.date,
        }),
      );

  /// Schedules a notification five seconds from now to prove delivery works.
  Future<void> sendTest() => _plugin.zonedSchedule(
        id: idFor('lockin:test'),
        title: _title,
        body: _body,
        scheduledDate: tz.TZDateTime.now(tz.UTC).add(const Duration(seconds: 5)),
        notificationDetails: _details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        payload: jsonEncode({'key': 'lockin:test'}),
      );

  /// Removes every LockIn reminder (used on sign-out).
  Future<void> clearAll() async {
    final pending = await _plugin.pendingNotificationRequests();
    for (final p in pending) {
      final key = _keyOf(p.payload);
      if (key != null && key.startsWith('lockin:')) await _plugin.cancel(id: p.id);
    }
  }
}
