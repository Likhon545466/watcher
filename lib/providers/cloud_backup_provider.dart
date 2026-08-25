import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/google_drive_backup_service.dart';

class CloudBackupProvider extends ChangeNotifier {
  CloudBackupProvider();

  static const String _autoBackupEnabledKey = 'cloud_backup_auto_enabled';

  static const String _autoSyncEnabledKey = 'cloud_backup_auto_sync_enabled';

  static const String _backupOnboardingHandledKey =
      'cloud_backup_onboarding_handled';

  static const String _googleAccountWasConnectedKey =
      'cloud_backup_google_account_was_connected';

  static const String _lastCloudBackupAtKey = 'cloud_backup_last_backup_at';

  static const String _lastCloudRestoreAtKey = 'cloud_backup_last_restore_at';

  static const String _lastCloudSyncAtKey = 'cloud_backup_last_sync_at';

  final GoogleDriveBackupService _driveService =
      GoogleDriveBackupService.instance;

  bool _initialized = false;
  bool _loading = false;
  bool _connecting = false;

  bool _autoBackupEnabled = false;
  bool _autoSyncEnabled = false;
  bool _backupOnboardingHandled = false;

  bool _hasCloudBackup = false;
  bool _checkingCloudBackup = false;

  DateTime? _lastCloudBackupAt;
  DateTime? _lastCloudRestoreAt;
  DateTime? _lastCloudSyncAt;

  GoogleDriveBackupInfo? _cloudBackupInfo;

  String? _lastError;

  // ==========================================================
  // GETTERS
  // ==========================================================

  bool get initialized => _initialized;

  bool get loading => _loading;

  bool get connecting => _connecting;

  bool get isConnected => _driveService.isConnected;

  String? get email => _driveService.email;

  String? get displayName => _driveService.displayName;

  String? get photoUrl => _driveService.photoUrl;

  bool get autoBackupEnabled => _autoBackupEnabled;

  bool get autoSyncEnabled => _autoSyncEnabled;

  bool get backupOnboardingHandled => _backupOnboardingHandled;

  bool get shouldShowBackupOnboarding =>
      _initialized && !_backupOnboardingHandled && !_driveService.isConnected;

  bool get hasCloudBackup => _hasCloudBackup;

  bool get checkingCloudBackup => _checkingCloudBackup;

  DateTime? get lastCloudBackupAt => _lastCloudBackupAt;

  DateTime? get lastCloudRestoreAt => _lastCloudRestoreAt;

  DateTime? get lastCloudSyncAt => _lastCloudSyncAt;

  GoogleDriveBackupInfo? get cloudBackupInfo => _cloudBackupInfo;

  DateTime? get cloudModifiedTime => _cloudBackupInfo?.modifiedTime;

  String? get lastError => _lastError;

  // ==========================================================
  // INITIALIZE
  // ==========================================================

  Future<void> initialize() async {
    if (_initialized || _loading) {
      return;
    }

    _loading = true;
    _lastError = null;

    notifyListeners();

    try {
      final preferences = await SharedPreferences.getInstance();

      _autoBackupEnabled = preferences.getBool(_autoBackupEnabledKey) ?? false;

      final storedAutoSync = preferences.getBool(_autoSyncEnabledKey);
      _autoSyncEnabled = storedAutoSync ?? _autoBackupEnabled;

      if (storedAutoSync == null && _autoSyncEnabled) {
        await preferences.setBool(_autoSyncEnabledKey, true);
      }

      _backupOnboardingHandled =
          preferences.getBool(_backupOnboardingHandledKey) ?? false;

      final lastBackupRaw = preferences.getString(_lastCloudBackupAtKey);

      final lastRestoreRaw = preferences.getString(_lastCloudRestoreAtKey);

      final lastSyncRaw = preferences.getString(_lastCloudSyncAtKey);

      _lastCloudBackupAt = _parseStoredDateTime(lastBackupRaw);

      _lastCloudRestoreAt = _parseStoredDateTime(lastRestoreRaw);

      _lastCloudSyncAt = _parseStoredDateTime(lastSyncRaw);

      /*
       * Initialize the Google Sign-In SDK first.
       *
       * Only users who explicitly connected Google before are eligible for
       * silent session restore. Guest/Skip users never trigger Google auth
       * during normal app startup.
       */
      await _driveService.initialize();

      final googleAccountWasConnected =
          preferences.getBool(_googleAccountWasConnectedKey) ?? false;

      if (googleAccountWasConnected) {
        final restored = await _driveService.restorePreviousSession();

        if (_driveService.isConnected) {
          if (!_backupOnboardingHandled) {
            _backupOnboardingHandled = true;
            await preferences.setBool(_backupOnboardingHandledKey, true);
          }

          final authorized = await _driveService.hasDriveAuthorization();

          if (authorized) {
            await _refreshCloudBackupInfoInternal();
          } else {
            // Keep the user's Auto Backup preference unchanged.
            // A restored Google account can become usable moments later,
            // and the auto-backup controller will retry failed uploads.
            debugPrint(
              'Google account restored, but Drive authorization is not ready yet.',
            );
          }
        } else if (!restored) {
          /*
           * Google no longer has a restorable account for this app.
           * Stop retrying on every launch. The user can reconnect manually
           * from Data & Backup later.
           */
          await preferences.setBool(_googleAccountWasConnectedKey, false);

          if (_autoBackupEnabled) {
            _autoBackupEnabled = false;
            await preferences.setBool(_autoBackupEnabledKey, false);
          }

          if (_autoSyncEnabled) {
            _autoSyncEnabled = false;
            await preferences.setBool(_autoSyncEnabledKey, false);
          }
        }
      } else if (_autoBackupEnabled || _autoSyncEnabled) {
        /*
         * Guest/Skip state: never open Google UI automatically.
         */
        _autoBackupEnabled = false;
        _autoSyncEnabled = false;
        await preferences.setBool(_autoBackupEnabledKey, false);
        await preferences.setBool(_autoSyncEnabledKey, false);
      }

      _initialized = true;
    } catch (error) {
      _lastError = 'Could not initialize Google backup.';

      debugPrint('CloudBackupProvider initialize error: $error');

      _initialized = true;
    } finally {
      _loading = false;

      notifyListeners();
    }
  }

  // ==========================================================
  // CONNECT GOOGLE
  // ==========================================================

  Future<bool> connectGoogle() async {
    if (_connecting) {
      return false;
    }

    _connecting = true;
    _lastError = null;

    notifyListeners();

    try {
      await _driveService.connect();

      final authorized = await _driveService.hasDriveAuthorization();

      if (!authorized) {
        _lastError = 'Google Drive permission was not granted.';

        return false;
      }

      final preferences = await SharedPreferences.getInstance();

      _backupOnboardingHandled = true;

      await preferences.setBool(_backupOnboardingHandledKey, true);

      await preferences.setBool(_googleAccountWasConnectedKey, true);

      _autoBackupEnabled = true;
      _autoSyncEnabled = true;

      await preferences.setBool(_autoBackupEnabledKey, true);
      await preferences.setBool(_autoSyncEnabledKey, true);

      await _refreshCloudBackupInfoInternal();

      return true;
    } catch (error) {
      _lastError = 'Could not connect your Google account.';

      debugPrint('CloudBackupProvider connect error: $error');

      return false;
    } finally {
      _connecting = false;

      notifyListeners();
    }
  }

  // ==========================================================
  // SKIP FIRST-RUN BACKUP ONBOARDING
  // ==========================================================

  Future<void> skipBackupOnboarding() async {
    final preferences = await SharedPreferences.getInstance();

    _backupOnboardingHandled = true;

    _autoBackupEnabled = false;
    _autoSyncEnabled = false;

    await preferences.setBool(_backupOnboardingHandledKey, true);

    await preferences.setBool(_googleAccountWasConnectedKey, false);

    await preferences.setBool(_autoBackupEnabledKey, false);
    await preferences.setBool(_autoSyncEnabledKey, false);

    notifyListeners();
  }

  // ==========================================================
  // RESET ONBOARDING
  // ==========================================================

  Future<void> resetBackupOnboarding() async {
    final preferences = await SharedPreferences.getInstance();

    _backupOnboardingHandled = false;

    await preferences.setBool(_backupOnboardingHandledKey, false);

    notifyListeners();
  }

  // ==========================================================
  // BACKUP & SYNC MASTER TOGGLE
  // ==========================================================

  Future<bool> setBackupAndSyncEnabled(bool enabled) async {
    _lastError = null;

    if (!enabled) {
      _autoBackupEnabled = false;
      _autoSyncEnabled = false;
      final preferences = await SharedPreferences.getInstance();
      await preferences.setBool(_autoBackupEnabledKey, false);
      await preferences.setBool(_autoSyncEnabledKey, false);
      notifyListeners();
      return true;
    }

    if (!_driveService.isConnected) {
      final connected = await connectGoogle();
      if (!connected) return false;
    }

    final authorized = await _driveService.hasDriveAuthorization();
    if (!authorized) {
      _lastError = 'Google Drive permission is required.';
      notifyListeners();
      return false;
    }

    _autoBackupEnabled = true;
    _autoSyncEnabled = true;
    _backupOnboardingHandled = true;

    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_autoBackupEnabledKey, true);
    await preferences.setBool(_autoSyncEnabledKey, true);
    await preferences.setBool(_backupOnboardingHandledKey, true);
    notifyListeners();
    return true;
  }

  Future<bool> setAutoBackupEnabled(bool enabled) async {
    return setBackupAndSyncEnabled(enabled);
  }

  Future<bool> setAutoSyncEnabled(bool enabled) async {
    return setBackupAndSyncEnabled(enabled);
  }

  // ==========================================================
  // REFRESH CLOUD BACKUP INFO
  // ==========================================================

  Future<void> refreshCloudBackupInfo() async {
    if (_checkingCloudBackup) {
      return;
    }

    _checkingCloudBackup = true;
    _lastError = null;

    notifyListeners();

    try {
      if (!_driveService.isConnected) {
        _clearCloudInfo();

        return;
      }

      final authorized = await _driveService.hasDriveAuthorization();

      if (!authorized) {
        _clearCloudInfo();

        return;
      }

      await _refreshCloudBackupInfoInternal();
    } catch (error) {
      _lastError = 'Could not check Google Drive backup.';

      debugPrint('Cloud backup refresh error: $error');
    } finally {
      _checkingCloudBackup = false;

      notifyListeners();
    }
  }

  Future<void> _refreshCloudBackupInfoInternal() async {
    final info = await _driveService.getBackupInfo();

    _cloudBackupInfo = info;

    _hasCloudBackup = info != null;
  }

  // ==========================================================
  // CLOUD BACKUP COMPLETED
  // ==========================================================

  Future<void> markCloudBackupCompleted({
    GoogleDriveBackupInfo? info,
    DateTime? completedAt,
  }) async {
    final now = completedAt ?? info?.modifiedTime ?? DateTime.now();

    _lastCloudBackupAt = now;

    _cloudBackupInfo = info ?? _cloudBackupInfo;

    _hasCloudBackup = true;

    final preferences = await SharedPreferences.getInstance();

    await preferences.setString(_lastCloudBackupAtKey, now.toIso8601String());

    notifyListeners();
  }

  // ==========================================================
  // CLOUD RESTORE COMPLETED
  // ==========================================================

  Future<void> markCloudRestoreCompleted({DateTime? completedAt}) async {
    final now = completedAt ?? DateTime.now();

    _lastCloudRestoreAt = now;

    final preferences = await SharedPreferences.getInstance();

    await preferences.setString(_lastCloudRestoreAtKey, now.toIso8601String());

    notifyListeners();
  }

  // ==========================================================
  // CLOUD SYNC COMPLETED
  // ==========================================================

  Future<void> markCloudSyncCompleted({DateTime? completedAt}) async {
    final now = completedAt ?? DateTime.now();
    _lastCloudSyncAt = now;

    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_lastCloudSyncAtKey, now.toIso8601String());

    notifyListeners();
  }

  // ==========================================================
  // SIGN OUT
  // ==========================================================

  Future<void> signOut() async {
    _lastError = null;

    try {
      await _driveService.signOut();
    } catch (error) {
      debugPrint('Google sign out error: $error');
    }

    final preferences = await SharedPreferences.getInstance();

    _autoBackupEnabled = false;
    _autoSyncEnabled = false;

    await preferences.setBool(_autoBackupEnabledKey, false);
    await preferences.setBool(_autoSyncEnabledKey, false);

    await preferences.setBool(_googleAccountWasConnectedKey, false);

    _clearCloudInfo();

    notifyListeners();
  }

  // ==========================================================
  // DISCONNECT GOOGLE ACCESS
  // ==========================================================

  Future<void> disconnectGoogle() async {
    _lastError = null;

    try {
      await _driveService.disconnect();
    } catch (error) {
      debugPrint('Google disconnect error: $error');
    }

    final preferences = await SharedPreferences.getInstance();

    _autoBackupEnabled = false;
    _autoSyncEnabled = false;

    await preferences.setBool(_autoBackupEnabledKey, false);
    await preferences.setBool(_autoSyncEnabledKey, false);

    await preferences.setBool(_googleAccountWasConnectedKey, false);

    _clearCloudInfo();

    notifyListeners();
  }

  // ==========================================================
  // ERROR
  // ==========================================================

  void clearError() {
    if (_lastError == null) {
      return;
    }

    _lastError = null;

    notifyListeners();
  }

  // ==========================================================
  // HELPERS
  // ==========================================================

  void _clearCloudInfo() {
    _cloudBackupInfo = null;

    _hasCloudBackup = false;
  }

  DateTime? _parseStoredDateTime(String? value) {
    if (value == null || value.trim().isEmpty) {
      return null;
    }

    return DateTime.tryParse(value);
  }
}
