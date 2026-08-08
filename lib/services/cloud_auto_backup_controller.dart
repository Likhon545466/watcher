import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../providers/cloud_backup_provider.dart';
import '../providers/show_provider.dart';
import 'google_drive_backup_service.dart';
import 'storage_service.dart';

// ============================================================
// CLOUD AUTO BACKUP CONTROLLER
// ============================================================

class CloudAutoBackupController {
  CloudAutoBackupController({
    required this.showProvider,
    required this.cloudProvider,
  }) {
    showProvider.addListener(_onShowProviderChanged);

    cloudProvider.addListener(_onCloudProviderChanged);

    unawaited(_initialize());
  }

  // ==========================================================
  // CONFIG
  // ==========================================================

  static const Duration _changeDetectionDelay = Duration(milliseconds: 500);

  /*
   * Auto Backup debounce.
   *
   * Old value was 25 seconds, which felt too slow.
   * 6 seconds is fast enough for the user to feel instant,
   * but still prevents Google Drive upload spam when the user
   * quickly taps episode + / - or changes multiple items.
   */
  static const Duration _uploadDebounce = Duration(seconds: 6);

  static const Duration _retryAfterActiveUpload = Duration(seconds: 3);

  static const String _uploadedSignatureKey =
      'cloud_auto_backup_last_uploaded_signature_v1';

  // ==========================================================
  // PROVIDERS
  // ==========================================================

  final ShowProvider showProvider;

  final CloudBackupProvider cloudProvider;

  // ==========================================================
  // STATE
  // ==========================================================

  Timer? _changeDetectionTimer;

  Timer? _uploadTimer;

  bool _initialized = false;

  bool _disposed = false;

  bool _uploading = false;

  bool _uploadAgain = false;

  String? _lastObservedSignature;

  String? _lastUploadedSignature;

  String? _pendingSignature;

  DateTime? _lastKnownCloudBackupAt;

  // ==========================================================
  // INITIALIZE
  // ==========================================================

  Future<void> _initialize() async {
    try {
      final preferences = await SharedPreferences.getInstance();

      _lastUploadedSignature = preferences.getString(_uploadedSignatureKey);

      _lastKnownCloudBackupAt = cloudProvider.lastCloudBackupAt;

      if (!showProvider.loading) {
        _lastObservedSignature = _createCurrentLibrarySignature();
      }

      _initialized = true;

      _maybeScheduleInitialBackup();
    } catch (error) {
      debugPrint('CloudAutoBackupController initialize error: $error');

      _initialized = true;
    }
  }

  // ==========================================================
  // SHOW PROVIDER CHANGED
  // ==========================================================

  void _onShowProviderChanged() {
    if (_disposed || !_initialized || showProvider.loading) {
      return;
    }

    _changeDetectionTimer?.cancel();

    _changeDetectionTimer = Timer(
      _changeDetectionDelay,
      _detectActualLibraryChange,
    );
  }

  // ==========================================================
  // DETECT REAL LIBRARY CHANGE
  // ==========================================================

  void _detectActualLibraryChange() {
    if (_disposed || showProvider.loading) {
      return;
    }

    final currentSignature = _createCurrentLibrarySignature();

    final previousSignature = _lastObservedSignature;

    // --------------------------------------------------------
    // First completed local load becomes our baseline.
    // It is NOT treated as a new user change.
    // --------------------------------------------------------

    if (previousSignature == null) {
      _lastObservedSignature = currentSignature;

      _maybeScheduleInitialBackup();

      return;
    }

    // --------------------------------------------------------
    // Search/category/filter UI changes may notify ShowProvider,
    // but they do not change the actual library JSON.
    // --------------------------------------------------------

    if (previousSignature == currentSignature) {
      return;
    }

    _lastObservedSignature = currentSignature;

    if (!_canAutoBackup()) {
      return;
    }

    _scheduleAutoBackup(currentSignature);
  }

  // ==========================================================
  // CLOUD PROVIDER CHANGED
  // ==========================================================

  void _onCloudProviderChanged() {
    if (_disposed || !_initialized) {
      return;
    }

    // --------------------------------------------------------
    // If Backup Now was used manually, CloudBackupProvider's
    // lastCloudBackupAt changes.
    //
    // Treat the current local library as the latest
    // successfully uploaded snapshot.
    // --------------------------------------------------------

    final backupAt = cloudProvider.lastCloudBackupAt;

    if (backupAt != null && backupAt != _lastKnownCloudBackupAt) {
      _lastKnownCloudBackupAt = backupAt;

      if (!showProvider.loading) {
        final signature = _createCurrentLibrarySignature();

        _lastUploadedSignature = signature;

        _lastObservedSignature ??= signature;

        unawaited(_persistUploadedSignature(signature));
      }
    }

    if (!cloudProvider.autoBackupEnabled || !cloudProvider.isConnected) {
      _uploadTimer?.cancel();

      _uploadTimer = null;

      _pendingSignature = null;

      return;
    }

    _maybeScheduleInitialBackup();
  }

  // ==========================================================
  // INITIAL BACKUP
  // ==========================================================

  void _maybeScheduleInitialBackup() {
    if (!_canAutoBackup() ||
        showProvider.loading ||
        cloudProvider.checkingCloudBackup ||
        showProvider.allShows.isEmpty) {
      return;
    }

    final currentSignature = _createCurrentLibrarySignature();

    _lastObservedSignature ??= currentSignature;

    if (currentSignature == _lastUploadedSignature) {
      return;
    }

    // --------------------------------------------------------
    // NEW DEVICE / REINSTALL SAFETY
    // --------------------------------------------------------
    //
    // Existing cloud backup + no local uploaded signature
    // usually means:
    //
    // - fresh install
    // - new phone
    // - local app data reset
    //
    // Never automatically overwrite the existing cloud backup.
    // User must Restore from Cloud or manually choose Backup Now.
    // --------------------------------------------------------

    if (cloudProvider.hasCloudBackup && _lastUploadedSignature == null) {
      return;
    }

    _scheduleAutoBackup(currentSignature);
  }

  // ==========================================================
  // CAN AUTO BACKUP?
  // ==========================================================

  bool _canAutoBackup() {
    return !_disposed &&
        cloudProvider.initialized &&
        cloudProvider.isConnected &&
        cloudProvider.autoBackupEnabled;
  }

  // ==========================================================
  // SCHEDULE AUTO BACKUP
  // ==========================================================

  void _scheduleAutoBackup(String signature) {
    if (!_canAutoBackup()) {
      return;
    }

    if (signature == _lastUploadedSignature) {
      return;
    }

    _pendingSignature = signature;

    _uploadTimer?.cancel();

    _uploadTimer = Timer(_uploadDebounce, () {
      unawaited(_performAutoBackup());
    });
  }

  // ==========================================================
  // PERFORM AUTO BACKUP
  // ==========================================================

  Future<void> _performAutoBackup() async {
    if (_disposed || !_canAutoBackup() || showProvider.loading) {
      return;
    }

    if (_uploading) {
      _uploadAgain = true;

      return;
    }

    final currentSignature = _createCurrentLibrarySignature();

    if (currentSignature == _lastUploadedSignature) {
      _pendingSignature = null;

      return;
    }

    // --------------------------------------------------------
    // Fresh-install protection again immediately before upload.
    // --------------------------------------------------------

    if (cloudProvider.hasCloudBackup &&
        _lastUploadedSignature == null &&
        cloudProvider.lastCloudBackupAt == null) {
      return;
    }

    _uploading = true;

    _uploadAgain = false;

    try {
      final shows = showProvider.allShows;

      final snapshotSignature = _createLibrarySignature(
        shows.map((show) => show.toJson()).toList(growable: false),
      );

      if (snapshotSignature == _lastUploadedSignature) {
        return;
      }

      final jsonData = await StorageService.encodeBackup(shows);

      final info = await GoogleDriveBackupService.instance.uploadBackupJson(
        jsonData,
      );

      if (_disposed) {
        return;
      }

      _lastUploadedSignature = snapshotSignature;

      _lastObservedSignature = _createCurrentLibrarySignature();

      _pendingSignature = null;

      await _persistUploadedSignature(snapshotSignature);

      await cloudProvider.markCloudBackupCompleted(info: info);
    } on GoogleDriveAuthorizationRequiredException catch (error) {
      debugPrint('Watcher Auto Backup authorization required: $error');
    } catch (error) {
      debugPrint('Watcher Auto Backup failed: $error');
    } finally {
      _uploading = false;

      if (!_disposed) {
        if (_uploadAgain) {
          // --------------------------------------------------
          // Library changed while previous upload was running.
          // Try again with the newest snapshot shortly.
          // --------------------------------------------------

          _uploadAgain = false;

          _uploadTimer?.cancel();

          _uploadTimer = Timer(_retryAfterActiveUpload, () {
            unawaited(_performAutoBackup());
          });
        } else {
          final newestSignature = _createCurrentLibrarySignature();

          if (_canAutoBackup() &&
              newestSignature != _lastUploadedSignature &&
              newestSignature != _pendingSignature) {
            _scheduleAutoBackup(newestSignature);
          }
        }
      }
    }
  }

  // ==========================================================
  // CURRENT LIBRARY SIGNATURE
  // ==========================================================

  String _createCurrentLibrarySignature() {
    final jsonList = showProvider.allShows
        .map((show) => show.toJson())
        .toList(growable: false);

    return _createLibrarySignature(jsonList);
  }

  // ==========================================================
  // STABLE SIGNATURE
  // ==========================================================

  String _createLibrarySignature(Object data) {
    final raw = jsonEncode(data);

    // --------------------------------------------------------
    // Stable FNV-1a 32-bit hash.
    //
    // String.hashCode is not used because this signature
    // is persisted between app launches.
    // --------------------------------------------------------

    int hash = 0x811C9DC5;

    for (final unit in raw.codeUnits) {
      hash ^= unit;

      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }

    return hash.toRadixString(16).padLeft(8, '0');
  }

  // ==========================================================
  // SAVE UPLOADED SIGNATURE
  // ==========================================================

  Future<void> _persistUploadedSignature(String signature) async {
    try {
      final preferences = await SharedPreferences.getInstance();

      await preferences.setString(_uploadedSignatureKey, signature);
    } catch (error) {
      debugPrint('Could not save cloud backup signature: $error');
    }
  }

  // ==========================================================
  // DISPOSE
  // ==========================================================

  void dispose() {
    if (_disposed) {
      return;
    }

    _disposed = true;

    _changeDetectionTimer?.cancel();

    _uploadTimer?.cancel();

    showProvider.removeListener(_onShowProviderChanged);

    cloudProvider.removeListener(_onCloudProviderChanged);
  }
}
