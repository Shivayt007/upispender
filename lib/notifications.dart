import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'data.dart';
import 'analytics.dart';

class SpendNotifications {
  SpendNotifications._();
  static final instance = SpendNotifications._();
  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  static const _threshold = NotificationDetails(
    android: AndroidNotificationDetails(
      'spend_alerts', 'Budget alerts',
      channelDescription: 'Notifications when daily spending approaches the target',
      importance: Importance.high, priority: Priority.high,
    ),
  );
  static const _smart = NotificationDetails(
    android: AndroidNotificationDetails(
      'smart_spend', 'Smart spending warnings',
      channelDescription: 'Category budget and unusually large debit alerts',
      importance: Importance.high, priority: Priority.high,
    ),
  );
  static const _report = NotificationDetails(
    android: AndroidNotificationDetails(
      'daily_reports', 'Daily reports',
      channelDescription: 'A reminder to view your on-device daily spending report',
      importance: Importance.defaultImportance, priority: Priority.defaultPriority,
    ),
  );

  Future<void> init() async {
    if (_initialized) return;
    if (kIsWeb) return;
    try {
      tzdata.initializeTimeZones();
      final zone = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(zone));
    } catch (_) {
      tz.setLocalLocation(tz.getLocation('Asia/Kolkata'));
    }
    try {
      await _plugin.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
      );
      _initialized = true;
    } catch (e) {
      debugPrint('Notification initialization skipped: $e');
    }
  }

  Future<void> requestPermission() async {
    if (!_initialized) await init();
    if (!_initialized) return;
    try {
      await _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()?.requestNotificationsPermission();
    } catch (e) {
      debugPrint('Notification permission request: $e');
    }
  }

  bool isQuiet(SpendStore store) {
    final now = DateTime.now().hour;
    final start = store.number('quietStart');
    final end = store.number('quietEnd');
    if (start == end) return false;
    return start < end ? now >= start && now < end : now >= start || now < end;
  }

  Future<void> spendingChanged(SpendStore store, int oldSpent) async {
    if (!_initialized || !store.flag('notifications') || isQuiet(store)) return;
    final hidden = store.flag('privacyMode');
    final target = store.todayTarget;
    if (target > 0) {
      final before = oldSpent / target;
      final after = store.todaySpent / target;
      int? crossed;
      for (final percentage in [50, 80, 100]) {
        final level = percentage / 100;
        if (before < level && after >= level) crossed = percentage;
      }
      if (crossed != null) {
        final message = crossed == 100
            ? 'You reached your daily target. Consider pausing extra purchases.'
            : 'You have used ' + crossed.toString() + '% of your daily target.';
        try {
          await _plugin.show(
            DateTime.now().millisecondsSinceEpoch.remainder(1000000),
            hidden ? 'Daily budget update' : 'Budget update • ' + rupees(store.todaySpent),
            message, _threshold,
          );
        } catch (e) {
          debugPrint('Budget warning could not be shown: $e');
        }
      }
    }
    final saved = store.lastAddedEntry;
    if (saved == null || !sameDay(saved.at, DateTime.now())) return;
    final cap = store.limitForCategory(saved.category);
    if (cap != null && cap > 0) {
      final nowInCategory = store.spentInCategoryOn(saved.category, DateTime.now());
      final previousInCategory = nowInCategory - saved.paise;
      int? crossed;
      for (final percentage in [80, 100]) {
        final boundary = cap * percentage / 100;
        if (previousInCategory < boundary && nowInCategory >= boundary) crossed = percentage;
      }
      if (crossed != null) {
        try {
          await _plugin.show(
            9201, saved.category + ' budget warning',
            'You have reached ' + crossed.toString() + '% of your daily ' +
              saved.category + ' limit.', _smart,
          );
        } catch (e) {
          debugPrint('Category warning could not be shown: $e');
        }
      }
    }
    if (SpendAnalytics.isUnusual(saved, store.entries)) {
      try {
        await _plugin.show(
          9202, 'Unusually large payment recorded',
          hidden ? 'This payment is much larger than your recent average.'
            : rupees(saved.paise) + ' is at least 3× your recent payment average.',
          _smart,
        );
      } catch (e) {
        debugPrint('Unusual spending notification failed: $e');
      }
    }
  }

  Future<void> scheduleReport(SpendStore store) async {
    if (!_initialized) await init();
    if (!_initialized) return;
    try {
      await _plugin.cancel(9001);
      if (!store.flag('notifications')) return;
      final now = tz.TZDateTime.now(tz.local);
      var scheduled = tz.TZDateTime(
        tz.local, now.year, now.month, now.day,
        store.number('reportHour'), store.number('reportMinute'),
      );
      if (!scheduled.isAfter(now)) scheduled = scheduled.add(const Duration(days: 1));
      await _plugin.zonedSchedule(
        9001, 'Your daily spending report is ready',
        'Open UPI Spend Tracker to see your spending and insights.',
        scheduled, _report,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
      );
    } catch (e) {
      debugPrint('Report reminder could not be scheduled: $e');
    }
  }

  Future<void> scheduleEveningReminder(SpendStore store) async {
    if (!_initialized) return;
    try {
      await _plugin.cancel(9002);
      if (!store.flag('notifications') || !store.flag('reminder')) return;
      final now = tz.TZDateTime.now(tz.local);
      var scheduled = tz.TZDateTime(tz.local, now.year, now.month, now.day, 19, 30);
      if (!scheduled.isAfter(now)) scheduled = scheduled.add(const Duration(days: 1));
      await _plugin.zonedSchedule(
        9002, 'Have you logged today’s expenses?',
        'A quick check-in helps keep your budget accurate.',
        scheduled, _report,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
      );
    } catch (e) {
      debugPrint('Evening reminder could not be scheduled: $e');
    }
  }
}
