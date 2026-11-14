import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../domain/coaching_plan.dart';
import '../domain/notification_planner.dart';
import '../state/providers.dart';

/// Plant die täglichen Coaching-Nachrichten (0 bis 10 pro Tag) lokal auf
/// dem Gerät. Funktioniert offline; Server-Push kann später ergänzt werden.
class NotificationService {
  NotificationService(this._ref);

  final Ref _ref;
  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  /// Wird beim Antippen einer Nachricht aufgerufen (Payload z. B. `content:123`).
  void Function(String payload)? onOpen;

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'coaching',
      'Coaching',
      channelDescription: 'Tägliche Schritte, Rezepte und Motivation',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      icon: 'ic_stat_vibono',
      color: Color(0xFF9CC536),
    ),
    iOS: DarwinNotificationDetails(threadIdentifier: 'coaching'),
  );

  Future<void> init() async {
    if (kIsWeb) return;
    try {
      tzdata.initializeTimeZones();
      try {
        final info = await FlutterTimezone.getLocalTimezone();
        tz.setLocalLocation(tz.getLocation(info.identifier));
      } catch (_) {
        tz.setLocalLocation(tz.getLocation('Europe/Berlin'));
      }
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('ic_stat_vibono'),
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
        ),
        onDidReceiveNotificationResponse: (r) {
          final p = r.payload;
          if (p != null) onOpen?.call(p);
        },
      );
      _ready = true;
      final launch = await _plugin.getNotificationAppLaunchDetails();
      final p = launch?.notificationResponse?.payload;
      if (launch?.didNotificationLaunchApp == true && p != null) {
        Future<void>.delayed(const Duration(milliseconds: 800), () => onOpen?.call(p));
      }
    } catch (e) {
      debugPrint('Benachrichtigungen nicht verfügbar: $e');
    }
  }

  Future<bool> requestPermission() async {
    if (!_ready) return false;
    final ios = _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
    if (ios != null) return await ios.requestPermissions(alert: true, badge: true, sound: true) ?? false;
    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) return await android.requestNotificationsPermission() ?? false;
    return false;
  }

  /// Plant heute (Rest) und morgen neu. Aufruf nach Onboarding, beim
  /// App-Start und nach geänderten Einstellungen.
  Future<void> reschedule() async {
    if (!_ready) return;
    final profile = _ref.read(sessionProvider).profile;
    await _plugin.cancelAll();
    if (profile.notificationsPerDay == 0 || !profile.completed) return;
    final api = _ref.read(apiProvider);
    final today = CoachingPlan.dateOnly(DateTime.now());
    for (var offset = 0; offset < 2; offset++) {
      try {
        final day = await api.coachingDay(today.add(Duration(days: offset)));
        final plans = NotificationPlanner.plan(day, profile);
        for (var i = 0; i < plans.length; i++) {
          final n = plans[i];
          await _plugin.zonedSchedule(
            id: offset * 100 + i,
            title: n.title,
            body: n.body,
            payload: n.payload,
            scheduledDate: tz.TZDateTime.from(n.at, tz.local),
            notificationDetails: _details,
            androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          );
        }
      } catch (e) {
        debugPrint('Nachrichten für Tag +$offset nicht geplant: $e');
      }
    }
  }
}

final notificationServiceProvider = Provider<NotificationService>((ref) => NotificationService(ref));
