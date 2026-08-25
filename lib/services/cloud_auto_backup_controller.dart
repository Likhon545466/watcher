import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../providers/cloud_backup_provider.dart';
import '../providers/show_provider.dart';
import 'google_drive_backup_service.dart';
import 'storage_service.dart';

class CloudAutoBackupController {
  CloudAutoBackupController({
    required this.showProvider,
    required this.cloudProvider,
  }) {
    active = this;
    showProvider.addListener(_onShowProviderChanged);
    cloudProvider.addListener(_onCloudProviderChanged);
    unawaited(_initialize());
  }

  static CloudAutoBackupController? active;

  static const Duration _changeDetectionDelay = Duration(milliseconds: 500);
  static const Duration _uploadDebounce = Duration(seconds: 6);
  static const Duration _retryDelay = Duration(seconds: 15);
  static const Duration _resumeThrottle = Duration(seconds: 8);

  static const String _uploadedSignatureKey =
      'cloud_auto_backup_last_uploaded_signature_v2';

  final ShowProvider showProvider;
  final CloudBackupProvider cloudProvider;

  Timer? _changeDetectionTimer;
  Timer? _syncTimer;

  bool _initialized = false;
  bool _disposed = false;
  bool _syncing = false;
  bool _syncAgain = false;

  String? _lastObservedSignature;
  String? _lastUploadedSignature;
  DateTime? _lastSyncAttemptAt;

  Future<void> _initialize() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      _lastUploadedSignature = preferences.getString(_uploadedSignatureKey);

      if (!showProvider.loading) {
        _lastObservedSignature = _createCurrentStateSignature();
      }
    } catch (error) {
      debugPrint('Cloud sync controller initialize error: $error');
    } finally {
      _initialized = true;
      _maybeScheduleStartupSync();
    }
  }

  void _onShowProviderChanged() {
    if (_disposed || !_initialized || showProvider.loading || _syncing) {
      return;
    }

    _changeDetectionTimer?.cancel();
    _changeDetectionTimer = Timer(
      _changeDetectionDelay,
      _detectActualLibraryChange,
    );
  }

  void _detectActualLibraryChange() {
    if (_disposed || showProvider.loading || _syncing) {
      return;
    }

    final signature = _createCurrentStateSignature();
    final previous = _lastObservedSignature;

    if (previous == null) {
      _lastObservedSignature = signature;
      _maybeScheduleStartupSync();
      return;
    }

    if (previous == signature) {
      return;
    }

    _lastObservedSignature = signature;

    if (cloudProvider.autoSyncEnabled && _canUseCloud()) {
      _scheduleSync(_uploadDebounce);
      return;
    }

    if (cloudProvider.autoBackupEnabled && _canUseCloud()) {
      _scheduleBackupOnly(_uploadDebounce);
    }
  }

  void _onCloudProviderChanged() {
    if (_disposed || !_initialized) {
      return;
    }

    if (!_canUseCloud()) {
      _syncTimer?.cancel();
      _syncTimer = null;
      return;
    }

    _maybeScheduleStartupSync();
  }

  bool _canUseCloud() {
    return !_disposed && cloudProvider.initialized && cloudProvider.isConnected;
  }

  void _maybeScheduleStartupSync() {
    if (!_canUseCloud() || showProvider.loading) {
      return;
    }

    if (cloudProvider.autoSyncEnabled) {
      _scheduleSync(const Duration(milliseconds: 700));
    }
  }

  void onAppResumed() {
    if (!_canUseCloud() || !cloudProvider.autoSyncEnabled) {
      return;
    }

    final now = DateTime.now();

    if (_lastSyncAttemptAt != null &&
        now.difference(_lastSyncAttemptAt!) < _resumeThrottle) {
      return;
    }

    _scheduleSync(const Duration(milliseconds: 350));
  }

  Future<bool> syncNow() async {
    if (!_canUseCloud() || showProvider.loading) {
      return false;
    }

    return _performTwoWaySync(manual: true);
  }

  void _scheduleSync(Duration delay) {
    _syncTimer?.cancel();
    _syncTimer = Timer(delay, () {
      unawaited(_performTwoWaySync());
    });
  }

  void _scheduleBackupOnly(Duration delay) {
    _syncTimer?.cancel();
    _syncTimer = Timer(delay, () {
      unawaited(_performBackupOnly());
    });
  }

  Future<bool> _performTwoWaySync({bool manual = false}) async {
    if (_disposed || !_canUseCloud() || showProvider.loading) {
      return false;
    }

    if (_syncing) {
      _syncAgain = true;
      return false;
    }

    _syncing = true;
    _syncAgain = false;
    _lastSyncAttemptAt = DateTime.now();

    try {
      final drive = GoogleDriveBackupService.instance;
      var snapshot = await drive.downloadBackupSnapshot();

      if (snapshot != null) {
        final cloudState = StorageService.decodeSyncBackup(snapshot.jsonData);
        await showProvider.mergeCloudSyncState(
          cloudState.shows,
          cloudState.deletedShows,
        );
      }

      // Optimistic re-check. If another device updated Drive while we were
      // merging, pull that newer snapshot once more before our upload.
      if (snapshot != null) {
        final newestInfo = await drive.getBackupInfo();
        final firstModified = snapshot.info.modifiedTime?.toUtc();
        final newestModified = newestInfo?.modifiedTime?.toUtc();

        if (firstModified != null &&
            newestModified != null &&
            newestModified.isAfter(firstModified)) {
          final newerSnapshot = await drive.downloadBackupSnapshot();

          if (newerSnapshot != null) {
            final newerState = StorageService.decodeSyncBackup(
              newerSnapshot.jsonData,
            );
            await showProvider.mergeCloudSyncState(
              newerState.shows,
              newerState.deletedShows,
            );
            snapshot = newerSnapshot;
          }
        }
      }

      final localSignature = _createCurrentStateSignature();
      final cloudSignature = snapshot == null
          ? null
          : _createDecodedCloudSignature(snapshot.jsonData);

      GoogleDriveBackupInfo? uploadedInfo;

      if (snapshot == null || cloudSignature != localSignature) {
        final jsonData = await StorageService.encodeSyncBackup(
          showProvider.allShows,
          showProvider.deletedShowTombstones,
        );

        uploadedInfo = await drive.uploadBackupJson(jsonData);
        await cloudProvider.markCloudBackupCompleted(info: uploadedInfo);
      }

      _lastObservedSignature = _createCurrentStateSignature();
      _lastUploadedSignature = _lastObservedSignature;
      await _persistUploadedSignature(_lastObservedSignature!);

      await cloudProvider.markCloudSyncCompleted(
        completedAt: uploadedInfo?.modifiedTime ?? DateTime.now(),
      );

      return true;
    } on GoogleDriveAuthorizationRequiredException catch (error) {
      debugPrint('Watcher Auto Sync authorization required: $error');
      return false;
    } catch (error) {
      debugPrint('Watcher Auto Sync failed: $error');

      if (!manual && !_disposed && _canUseCloud()) {
        _scheduleSync(_retryDelay);
      }

      return false;
    } finally {
      _syncing = false;

      if (_syncAgain && !_disposed && _canUseCloud()) {
        _syncAgain = false;
        _scheduleSync(const Duration(seconds: 2));
      }
    }
  }

  Future<void> _performBackupOnly() async {
    if (_disposed || !_canUseCloud() || !cloudProvider.autoBackupEnabled) {
      return;
    }

    if (_syncing) {
      _syncAgain = true;
      return;
    }

    _syncing = true;

    try {
      final signature = _createCurrentStateSignature();

      if (signature == _lastUploadedSignature) {
        return;
      }

      final jsonData = await StorageService.encodeSyncBackup(
        showProvider.allShows,
        showProvider.deletedShowTombstones,
      );

      final info = await GoogleDriveBackupService.instance.uploadBackupJson(
        jsonData,
      );

      _lastUploadedSignature = signature;
      _lastObservedSignature = signature;
      await _persistUploadedSignature(signature);
      await cloudProvider.markCloudBackupCompleted(info: info);
    } catch (error) {
      debugPrint('Watcher Auto Backup failed: $error');
      _scheduleBackupOnly(_retryDelay);
    } finally {
      _syncing = false;
    }
  }

  String _createDecodedCloudSignature(String raw) {
    final state = StorageService.decodeSyncBackup(raw);
    return _createStateSignature(state.shows, state.deletedShows);
  }

  String _createCurrentStateSignature() {
    return _createStateSignature(
      showProvider.allShows,
      showProvider.deletedShowTombstones,
    );
  }

  String _createStateSignature(
    List<dynamic> shows,
    Map<String, DateTime> deletions,
  ) {
    final showJson =
        shows
            .map((item) {
              if (item is Map<String, dynamic>) {
                return item;
              }
              return (item as dynamic).toJson() as Map<String, dynamic>;
            })
            .toList(growable: false)
          ..sort(
            (a, b) => (a['id'] ?? '').toString().compareTo(
              (b['id'] ?? '').toString(),
            ),
          );

    final deletionJson = deletions.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    return _fnv1a32(
      jsonEncode(<String, dynamic>{
        'shows': showJson,
        'deletedShows': <String, String>{
          for (final entry in deletionJson)
            entry.key: entry.value.toUtc().toIso8601String(),
        },
      }),
    );
  }

  String _fnv1a32(String raw) {
    int hash = 0x811C9DC5;

    for (final unit in raw.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }

    return hash.toRadixString(16).padLeft(8, '0');
  }

  Future<void> _persistUploadedSignature(String signature) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(_uploadedSignatureKey, signature);
    } catch (_) {}
  }

  void dispose() {
    if (_disposed) {
      return;
    }

    _disposed = true;
    _changeDetectionTimer?.cancel();
    _syncTimer?.cancel();
    showProvider.removeListener(_onShowProviderChanged);
    cloudProvider.removeListener(_onCloudProviderChanged);

    if (identical(active, this)) {
      active = null;
    }
  }
}
