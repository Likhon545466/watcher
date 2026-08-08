import 'dart:async';
import 'dart:convert';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

// ============================================================
// NOTIFICATION SERVICE
// ============================================================

class NotificationService {
  NotificationService._();

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static bool _initialized = false;

  static Future<void>? _initializationFuture;

  static bool get isInitialized => _initialized;

  static String _timezoneName = 'UTC';

  static String get timezoneName => _timezoneName;

  static String? _pendingPayload;

  static String? get pendingPayload => _pendingPayload;

  // ==========================================================
  // CHANNEL
  // ==========================================================

  static const String episodeChannelId = 'watcher_episode_reminders';

  static const String episodeChannelName = 'Episode Reminders';

  static const String episodeChannelDescription =
      'Notifications for upcoming series episodes';

  // ==========================================================
  // REMINDER TIME
  // ==========================================================

  static const int reminderHour = 10;

  static const int reminderMinute = 0;

  // ==========================================================
  // INITIALIZE
  // ==========================================================

  static Future<void> initialize() {
    if (_initialized) {
      return Future<void>.value();
    }

    final existing = _initializationFuture;

    if (existing != null) {
      return existing;
    }

    final future = _initializeSafely();

    _initializationFuture = future;

    return future;
  }

  static Future<void> _initializeSafely() async {
    try {
      await _performInitialization();
    } catch (_) {
      _initialized = false;
    } finally {
      _initializationFuture = null;
    }
  }

  static Future<void> _performInitialization() async {
    if (_initialized) {
      return;
    }

    // ========================================================
    // TIMEZONE
    // ========================================================

    tz.initializeTimeZones();

    await _configureLocalTimezone();

    // ========================================================
    // PLUGIN SETTINGS
    // ========================================================

    const androidSettings = AndroidInitializationSettings(
      'ic_watcher_notification',
    );

    const darwinSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    const initializationSettings = InitializationSettings(
      android: androidSettings,
      iOS: darwinSettings,
      macOS: darwinSettings,
    );

    // ========================================================
    // INITIALIZE PLUGIN
    // ========================================================

    await _plugin.initialize(
      settings: initializationSettings,
      onDidReceiveNotificationResponse: _onNotificationResponse,
    );

    // ========================================================
    // CREATE ANDROID CHANNEL
    // ========================================================

    await _createAndroidChannel();

    // ========================================================
    // NOTIFICATION LAUNCH PAYLOAD
    // ========================================================

    try {
      final launchDetails = await _plugin.getNotificationAppLaunchDetails();

      if (launchDetails != null && launchDetails.didNotificationLaunchApp) {
        final payload = launchDetails.notificationResponse?.payload;

        if (payload != null && payload.trim().isNotEmpty) {
          _pendingPayload = payload;
        }
      }
    } catch (_) {
      // Launch payload is optional.
    }

    _initialized = true;
  }

  // ==========================================================
  // TIMEZONE
  // ==========================================================

  static Future<void> _configureLocalTimezone() async {
    try {
      final timezoneInfo = await FlutterTimezone.getLocalTimezone().timeout(
        const Duration(seconds: 3),
      );

      final identifier = timezoneInfo.identifier.trim();

      if (identifier.isEmpty) {
        _useUtcTimezone();
        return;
      }

      final location = tz.getLocation(identifier);

      tz.setLocalLocation(location);

      _timezoneName = identifier;
    } catch (_) {
      _useUtcTimezone();
    }
  }

  static void _useUtcTimezone() {
    try {
      final utc = tz.getLocation('UTC');

      tz.setLocalLocation(utc);
    } catch (_) {
      // UTC is bundled with timezone data.
    }

    _timezoneName = 'UTC';
  }

  // ==========================================================
  // ANDROID CHANNEL
  // ==========================================================

  static Future<void> _createAndroidChannel() async {
    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();

    if (androidPlugin == null) {
      return;
    }

    const channel = AndroidNotificationChannel(
      episodeChannelId,
      episodeChannelName,
      description: episodeChannelDescription,
      importance: Importance.high,
      playSound: true,
      enableVibration: true,
      showBadge: true,
    );

    await androidPlugin.createNotificationChannel(channel);
  }

  // ==========================================================
  // NOTIFICATION TAP
  // ==========================================================

  static void _onNotificationResponse(NotificationResponse response) {
    final payload = response.payload;

    if (payload == null || payload.trim().isEmpty) {
      return;
    }

    _pendingPayload = payload;
  }

  static String? consumePendingPayload() {
    final value = _pendingPayload;

    _pendingPayload = null;

    return value;
  }

  // ==========================================================
  // PERMISSION
  // ==========================================================

  static Future<bool> requestNotificationPermission() async {
    try {
      final androidPlugin = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();

      // Non-Android platforms are handled by their own
      // notification permission systems.
      if (androidPlugin == null) {
        await initialize();
        return true;
      }

      // ======================================================
      // ALREADY GRANTED
      // ======================================================

      final alreadyEnabled = await androidPlugin.areNotificationsEnabled();

      if (alreadyEnabled == true) {
        await initialize();

        return true;
      }

      // ======================================================
      // REQUEST ANDROID 13+ PERMISSION
      // ======================================================

      final result = await androidPlugin.requestNotificationsPermission();

      if (result == true) {
        await initialize();

        return true;
      }

      // Some Android versions/devices may return null.
      // Verify the final OS state directly.
      final enabledAfterRequest = await androidPlugin.areNotificationsEnabled();

      final granted = enabledAfterRequest == true;

      if (granted) {
        await initialize();
      }

      return granted;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> areNotificationsEnabled() async {
    try {
      final androidPlugin = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();

      if (androidPlugin == null) {
        return true;
      }

      final enabled = await androidPlugin.areNotificationsEnabled();

      return enabled ?? false;
    } catch (_) {
      return false;
    }
  }

  // ==========================================================
  // SCHEDULE EPISODE REMINDER
  // ==========================================================

  static Future<bool> scheduleEpisodeReminder({
    required String showId,
    required String showTitle,
    required int season,
    required int episode,
    required DateTime airDate,
  }) async {
    try {
      await initialize();

      if (!_initialized) {
        return false;
      }

      if (showId.trim().isEmpty ||
          showTitle.trim().isEmpty ||
          season <= 0 ||
          episode <= 0) {
        return false;
      }

      final notificationsEnabled = await areNotificationsEnabled();

      if (!notificationsEnabled) {
        return false;
      }

      // Reminder fires at 10:00 AM local time
      // on the episode air date.
      final scheduledDate = tz.TZDateTime(
        tz.local,
        airDate.year,
        airDate.month,
        airDate.day,
        reminderHour,
        reminderMinute,
      );

      final now = tz.TZDateTime.now(tz.local);

      // Never schedule a reminder in the past.
      if (!scheduledDate.isAfter(now)) {
        return false;
      }

      final notificationId = notificationIdForShow(showId);

      final payload = jsonEncode(<String, dynamic>{
        'type': 'episode_reminder',
        'showId': showId,
        'season': season,
        'episode': episode,
      });

      final title = 'New episode today';

      final body = '$showTitle • S$season E$episode airs today.';

      const androidDetails = AndroidNotificationDetails(
        episodeChannelId,
        episodeChannelName,
        channelDescription: episodeChannelDescription,
        icon: 'ic_watcher_notification',
        importance: Importance.high,
        priority: Priority.high,
        playSound: true,
        enableVibration: true,
        autoCancel: true,
        onlyAlertOnce: true,
        category: AndroidNotificationCategory.reminder,
        visibility: NotificationVisibility.public,
      );

      const darwinDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );

      const notificationDetails = NotificationDetails(
        android: androidDetails,
        iOS: darwinDetails,
        macOS: darwinDetails,
      );

      // One active upcoming-episode notification per show.
      // Existing reminder is replaced safely.
      await _plugin.cancel(id: notificationId);

      await _plugin.zonedSchedule(
        id: notificationId,
        title: title,
        body: body,
        scheduledDate: scheduledDate,
        notificationDetails: notificationDetails,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        payload: payload,
      );

      return true;
    } catch (_) {
      return false;
    }
  }

  // ==========================================================
  // CANCEL ONE REMINDER
  // ==========================================================

  static Future<void> cancelEpisodeReminder(String showId) async {
    if (showId.trim().isEmpty) {
      return;
    }

    try {
      await initialize();

      if (!_initialized) {
        return;
      }

      await _plugin.cancel(id: notificationIdForShow(showId));
    } catch (_) {
      // Cancellation failure should not crash the app.
    }
  }

  // ==========================================================
  // CANCEL ALL
  // ==========================================================

  static Future<void> cancelAllNotifications() async {
    try {
      await initialize();

      if (!_initialized) {
        return;
      }

      await _plugin.cancelAll();
    } catch (_) {
      // Cancellation failure should not crash the app.
    }
  }

  // ==========================================================
  // PENDING NOTIFICATIONS
  // ==========================================================

  static Future<List<PendingNotificationRequest>>
  getPendingNotifications() async {
    try {
      await initialize();

      if (!_initialized) {
        return const <PendingNotificationRequest>[];
      }

      return await _plugin.pendingNotificationRequests();
    } catch (_) {
      return const <PendingNotificationRequest>[];
    }
  }

  static Future<int> getPendingReminderCount() async {
    final pending = await getPendingNotifications();

    return pending.where((notification) {
      final payload = notification.payload;

      if (payload == null || payload.isEmpty) {
        return false;
      }

      try {
        final decoded = jsonDecode(payload);

        return decoded is Map && decoded['type'] == 'episode_reminder';
      } catch (_) {
        return false;
      }
    }).length;
  }

  // ==========================================================
  // STABLE NOTIFICATION ID
  // ==========================================================

  static int notificationIdForShow(String showId) {
    final input = 'watcher_episode_$showId';

    int hash = 0x811C9DC5;

    for (final unit in input.codeUnits) {
      hash ^= unit;

      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }

    final positive = hash & 0x7FFFFFFF;

    return positive == 0 ? 1 : positive;
  }
}
