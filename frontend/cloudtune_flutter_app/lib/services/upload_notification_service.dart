import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class UploadNotificationService {
  UploadNotificationService._();

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _initialized = false;
  static final Set<String> _activeSyncKeys = <String>{};
  static const String _uploadChannelId = 'cloudtune_playlist_uploads';

  static Future<void> initialize() async {
    if (_initialized) return;

    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
      macOS: DarwinInitializationSettings(),
    );
    await _plugin.initialize(settings);
    _initialized = true;
  }

  static bool get _supportsNotifications {
    if (kIsWeb) return false;
    return Platform.isAndroid || Platform.isIOS || Platform.isMacOS;
  }

  static int _notificationId(String syncKey) {
    return 43000 + (syncKey.hashCode & 0x7FF);
  }

  static Future<void> showPlaylistUploadProgress({
    required String syncKey,
    required String playlistName,
    required int uploadedTracks,
    required int totalTracks,
  }) async {
    if (!_supportsNotifications || totalTracks <= 0) return;
    await initialize();

    final uploaded = uploadedTracks.clamp(0, totalTracks);
    final id = _notificationId(syncKey);
    _activeSyncKeys.add(syncKey);

    if (Platform.isAndroid) {
      final androidDetails = AndroidNotificationDetails(
        _uploadChannelId,
        'CloudTune uploads',
        channelDescription: 'Playlist upload progress',
        importance: Importance.low,
        priority: Priority.low,
        onlyAlertOnce: true,
        ongoing: true,
        autoCancel: false,
        showProgress: true,
        maxProgress: totalTracks,
        progress: uploaded,
        playSound: false,
        enableVibration: false,
      );
      final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.startForegroundService(
        id,
        'Загрузка плейлиста',
        '$playlistName: $uploaded/$totalTracks',
        notificationDetails: androidDetails,
        startType: AndroidServiceStartType.startSticky,
        foregroundServiceTypes: <AndroidServiceForegroundType>{
          AndroidServiceForegroundType.foregroundServiceTypeDataSync,
        },
      );
      return;
    }

    final details = NotificationDetails(
      iOS: const DarwinNotificationDetails(presentSound: false),
      macOS: const DarwinNotificationDetails(presentSound: false),
    );

    await _plugin.show(
      id,
      'Загрузка плейлиста',
      '$playlistName: $uploaded/$totalTracks',
      details,
    );
  }

  static Future<void> showPlaylistUploadFinished({
    required String syncKey,
    required String playlistName,
    required int uploadedTracks,
    required int totalTracks,
  }) async {
    if (!_supportsNotifications) return;
    await initialize();

    final id = _notificationId(syncKey);
    final success = totalTracks > 0 && uploadedTracks >= totalTracks;
    _activeSyncKeys.remove(syncKey);

    if (Platform.isAndroid && _activeSyncKeys.isEmpty) {
      final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.stopForegroundService();
    }

    final title = success
        ? 'Плейлист загружен'
        : 'Загрузка завершена частично';
    final details = NotificationDetails(
      android: const AndroidNotificationDetails(
        _uploadChannelId,
        'CloudTune uploads',
        channelDescription: 'Playlist upload progress',
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
        ongoing: false,
        autoCancel: true,
        showProgress: false,
      ),
      iOS: const DarwinNotificationDetails(),
      macOS: const DarwinNotificationDetails(),
    );
    await _plugin.show(
      id,
      title,
      '$playlistName: $uploadedTracks/$totalTracks',
      details,
    );
  }
}
