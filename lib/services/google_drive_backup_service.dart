import 'dart:convert';

import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;

import '../config/google_auth_config.dart';

// ============================================================
// GOOGLE DRIVE BACKUP INFO
// ============================================================

class GoogleDriveBackupInfo {
  final String fileId;
  final String fileName;
  final DateTime? modifiedTime;
  final int? sizeBytes;

  const GoogleDriveBackupInfo({
    required this.fileId,
    required this.fileName,
    required this.modifiedTime,
    required this.sizeBytes,
  });

  factory GoogleDriveBackupInfo.fromDriveFile(drive.File file) {
    return GoogleDriveBackupInfo(
      fileId: file.id ?? '',
      fileName: file.name ?? GoogleAuthConfig.backupFileName,
      modifiedTime: file.modifiedTime,
      sizeBytes: int.tryParse(file.size ?? ''),
    );
  }
}

class GoogleDriveBackupSnapshot {
  final String jsonData;
  final GoogleDriveBackupInfo info;

  const GoogleDriveBackupSnapshot({required this.jsonData, required this.info});
}

// ============================================================
// EXCEPTIONS
// ============================================================

class GoogleDriveBackupException implements Exception {
  final String message;
  final Object? cause;

  const GoogleDriveBackupException(this.message, {this.cause});

  @override
  String toString() {
    return message;
  }
}

class GoogleDriveNotConnectedException extends GoogleDriveBackupException {
  const GoogleDriveNotConnectedException()
    : super('No Google account is connected.');
}

class GoogleDriveAuthorizationRequiredException
    extends GoogleDriveBackupException {
  const GoogleDriveAuthorizationRequiredException()
    : super('Google Drive permission is required.');
}

// ============================================================
// GOOGLE DRIVE BACKUP SERVICE
// ============================================================

class GoogleDriveBackupService {
  GoogleDriveBackupService._();

  static final GoogleDriveBackupService instance = GoogleDriveBackupService._();

  final GoogleSignIn _googleSignIn = GoogleSignIn.instance;

  GoogleSignInAccount? _account;

  bool _initialized = false;

  Future<void>? _initializing;

  // ==========================================================
  // ACCOUNT INFO
  // ==========================================================

  GoogleSignInAccount? get currentAccount => _account;

  bool get isConnected => _account != null;

  String? get email => _account?.email;

  String? get displayName => _account?.displayName;

  String? get photoUrl => _account?.photoUrl;

  // ==========================================================
  // INITIALIZE
  // ==========================================================

  Future<void> initialize() {
    if (_initialized) {
      return Future<void>.value();
    }

    final existing = _initializing;

    if (existing != null) {
      return existing;
    }

    final future = _initializeInternal();

    _initializing = future;

    return future;
  }

  Future<void> _initializeInternal() async {
    try {
      await _googleSignIn.initialize(
        serverClientId: GoogleAuthConfig.serverClientId,
      );

      /*
       * Normal app startup only initializes the SDK.
       *
       * Previous-session restoration is intentionally separated into
       * restorePreviousSession(), so guest/Skip users never trigger Google
       * authentication during startup.
       */
      _account = null;
      _initialized = true;
    } finally {
      _initializing = null;
    }
  }

  // ==========================================================
  // RESTORE PREVIOUS GOOGLE SESSION
  // ==========================================================

  Future<bool> restorePreviousSession() async {
    await initialize();

    if (_account != null) {
      return true;
    }

    try {
      final lightweightAttempt = _googleSignIn
          .attemptLightweightAuthentication();

      if (lightweightAttempt == null) {
        _account = null;
        return false;
      }

      _account = await lightweightAttempt;

      final account = _account;

      if (account == null) {
        return false;
      }

      // The user already chose to connect Google previously.
      // After restoring that account, make sure Drive scopes are usable.
      try {
        var authorization = await account.authorizationClient
            .authorizationForScopes(GoogleAuthConfig.driveScopes);

        authorization ??= await account.authorizationClient.authorizeScopes(
          GoogleAuthConfig.driveScopes,
        );
      } catch (_) {
        // Keep the restored account. Provider/controller can retry later.
      }

      return true;
    } catch (_) {
      _account = null;
      return false;
    }
  }

  // ==========================================================
  // CONNECT GOOGLE ACCOUNT
  // ==========================================================

  Future<GoogleSignInAccount> connect() async {
    await initialize();

    /*
     * This method should ONLY be called from a user action,
     * for example:
     *
     * Continue with Google
     * Connect Google Account
     *
     * because Google may need to show authentication or
     * authorization UI.
     */
    final account = await _googleSignIn.authenticate(
      scopeHint: GoogleAuthConfig.driveScopes,
    );

    _account = account;

    var authorization = await account.authorizationClient
        .authorizationForScopes(GoogleAuthConfig.driveScopes);

    authorization ??= await account.authorizationClient.authorizeScopes(
      GoogleAuthConfig.driveScopes,
    );

    return account;
  }

  // ==========================================================
  // CHECK DRIVE AUTHORIZATION
  // ==========================================================

  Future<bool> hasDriveAuthorization() async {
    await initialize();

    final account = _account;

    if (account == null) {
      return false;
    }

    try {
      final authorization = await account.authorizationClient
          .authorizationForScopes(GoogleAuthConfig.driveScopes);

      return authorization != null;
    } catch (_) {
      return false;
    }
  }

  // ==========================================================
  // AUTHORIZED HTTP CLIENT
  // ==========================================================

  Future<http.Client> _createAuthorizedClient() async {
    await initialize();

    final account = _account;

    if (account == null) {
      throw const GoogleDriveNotConnectedException();
    }

    final authorization = await account.authorizationClient
        .authorizationForScopes(GoogleAuthConfig.driveScopes);

    if (authorization == null) {
      /*
       * Important:
       *
       * Background/auto backup must never suddenly show
       * Google's permission UI.
       *
       * If authorization is missing, UI can ask the user
       * to reconnect manually.
       */
      throw const GoogleDriveAuthorizationRequiredException();
    }

    return authorization.authClient(scopes: GoogleAuthConfig.driveScopes);
  }

  // ==========================================================
  // FIND WATCHER BACKUP FILE
  // ==========================================================

  Future<drive.File?> _findBackupFile(drive.DriveApi driveApi) async {
    final escapedName = GoogleAuthConfig.backupFileName.replaceAll("'", r"\'");

    final result = await driveApi.files.list(
      spaces: 'appDataFolder',
      q: "name = '$escapedName' and trashed = false",
      orderBy: 'modifiedTime desc',
      pageSize: 10,
      $fields: 'files(id,name,mimeType,modifiedTime,size,trashed)',
    );

    final files = result.files;

    if (files == null || files.isEmpty) {
      return null;
    }

    return files.first;
  }

  // ==========================================================
  // GET CLOUD BACKUP INFO
  // ==========================================================

  Future<GoogleDriveBackupInfo?> getBackupInfo() async {
    final client = await _createAuthorizedClient();

    try {
      final driveApi = drive.DriveApi(client);

      final file = await _findBackupFile(driveApi);

      if (file == null || file.id == null || file.id!.isEmpty) {
        return null;
      }

      return GoogleDriveBackupInfo.fromDriveFile(file);
    } finally {
      client.close();
    }
  }

  // ==========================================================
  // CLOUD BACKUP EXISTS
  // ==========================================================

  Future<bool> hasCloudBackup() async {
    final info = await getBackupInfo();

    return info != null;
  }

  // ==========================================================
  // UPLOAD / UPDATE BACKUP
  // ==========================================================

  Future<GoogleDriveBackupInfo> uploadBackupJson(String jsonData) async {
    if (jsonData.trim().isEmpty) {
      throw const GoogleDriveBackupException('Backup data is empty.');
    }

    final client = await _createAuthorizedClient();

    try {
      final driveApi = drive.DriveApi(client);

      final existingFile = await _findBackupFile(driveApi);

      final bytes = utf8.encode(jsonData);

      final media = drive.Media(
        Stream<List<int>>.value(bytes),
        bytes.length,
        contentType: 'application/json',
      );

      late drive.File uploadedFile;

      if (existingFile == null ||
          existingFile.id == null ||
          existingFile.id!.isEmpty) {
        // ----------------------------------------------------
        // FIRST CLOUD BACKUP
        // ----------------------------------------------------

        final metadata = drive.File(
          name: GoogleAuthConfig.backupFileName,
          mimeType: 'application/json',
          parents: const <String>['appDataFolder'],
          appProperties: const <String, String?>{
            'app': 'watcher',
            'type': 'backup',
            'format': '1',
          },
        );

        uploadedFile = await driveApi.files.create(
          metadata,
          uploadMedia: media,
          $fields: 'id,name,mimeType,modifiedTime,size',
        );
      } else {
        // ----------------------------------------------------
        // UPDATE EXISTING CLOUD BACKUP
        // ----------------------------------------------------

        final metadata = drive.File(
          name: GoogleAuthConfig.backupFileName,
          mimeType: 'application/json',
          appProperties: const <String, String?>{
            'app': 'watcher',
            'type': 'backup',
            'format': '1',
          },
        );

        uploadedFile = await driveApi.files.update(
          metadata,
          existingFile.id!,
          uploadMedia: media,
          $fields: 'id,name,mimeType,modifiedTime,size',
        );
      }

      final fileId = uploadedFile.id;

      if (fileId == null || fileId.isEmpty) {
        throw const GoogleDriveBackupException(
          'Google Drive did not return a backup file ID.',
        );
      }

      return GoogleDriveBackupInfo.fromDriveFile(uploadedFile);
    } catch (error) {
      if (error is GoogleDriveBackupException) {
        rethrow;
      }

      throw GoogleDriveBackupException(
        'Could not upload Watcher backup to Google Drive.',
        cause: error,
      );
    } finally {
      client.close();
    }
  }

  Future<GoogleDriveBackupSnapshot?> downloadBackupSnapshot() async {
    final client = await _createAuthorizedClient();

    try {
      final driveApi = drive.DriveApi(client);
      final file = await _findBackupFile(driveApi);
      final fileId = file?.id;

      if (file == null || fileId == null || fileId.isEmpty) {
        return null;
      }

      final response = await driveApi.files.get(
        fileId,
        downloadOptions: drive.DownloadOptions.fullMedia,
      );

      if (response is! drive.Media) {
        throw const GoogleDriveBackupException(
          'Google Drive returned an invalid backup response.',
        );
      }

      final bytes = <int>[];

      await for (final chunk in response.stream) {
        bytes.addAll(chunk);
      }

      if (bytes.isEmpty) {
        throw const GoogleDriveBackupException('Cloud backup file is empty.');
      }

      return GoogleDriveBackupSnapshot(
        jsonData: utf8.decode(bytes),
        info: GoogleDriveBackupInfo.fromDriveFile(file),
      );
    } catch (error) {
      if (error is GoogleDriveBackupException) {
        rethrow;
      }

      throw GoogleDriveBackupException(
        'Could not download Watcher backup from Google Drive.',
        cause: error,
      );
    } finally {
      client.close();
    }
  }

  // ==========================================================
  // DOWNLOAD BACKUP
  // ==========================================================

  Future<String?> downloadBackupJson() async {
    final client = await _createAuthorizedClient();

    try {
      final driveApi = drive.DriveApi(client);

      final file = await _findBackupFile(driveApi);

      final fileId = file?.id;

      if (fileId == null || fileId.isEmpty) {
        return null;
      }

      final response = await driveApi.files.get(
        fileId,
        downloadOptions: drive.DownloadOptions.fullMedia,
      );

      if (response is! drive.Media) {
        throw const GoogleDriveBackupException(
          'Google Drive returned an invalid backup response.',
        );
      }

      final bytes = <int>[];

      await for (final chunk in response.stream) {
        bytes.addAll(chunk);
      }

      if (bytes.isEmpty) {
        throw const GoogleDriveBackupException('Cloud backup file is empty.');
      }

      return utf8.decode(bytes);
    } catch (error) {
      if (error is GoogleDriveBackupException) {
        rethrow;
      }

      throw GoogleDriveBackupException(
        'Could not download Watcher backup from Google Drive.',
        cause: error,
      );
    } finally {
      client.close();
    }
  }

  // ==========================================================
  // DELETE CLOUD BACKUP
  // ==========================================================

  Future<bool> deleteCloudBackup() async {
    final client = await _createAuthorizedClient();

    try {
      final driveApi = drive.DriveApi(client);

      final file = await _findBackupFile(driveApi);

      final fileId = file?.id;

      if (fileId == null || fileId.isEmpty) {
        return false;
      }

      await driveApi.files.delete(fileId);

      return true;
    } catch (error) {
      if (error is GoogleDriveBackupException) {
        rethrow;
      }

      throw GoogleDriveBackupException(
        'Could not delete Watcher cloud backup.',
        cause: error,
      );
    } finally {
      client.close();
    }
  }

  // ==========================================================
  // SIGN OUT
  // ==========================================================

  Future<void> signOut() async {
    await initialize();

    await _googleSignIn.signOut();

    _account = null;
  }

  // ==========================================================
  // DISCONNECT / REVOKE GOOGLE ACCESS
  // ==========================================================

  Future<void> disconnect() async {
    await initialize();

    await _googleSignIn.disconnect();

    _account = null;
  }
}
