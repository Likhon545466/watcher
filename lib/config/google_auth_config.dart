class GoogleAuthConfig {
  GoogleAuthConfig._();

  static const String serverClientId =
      '879746739863-b2hoe45i8voflfn1l8ut07i9rbsun515.apps.googleusercontent.com';

  static const List<String> driveScopes = <String>[
    'https://www.googleapis.com/auth/drive.appdata',
  ];

  static const String backupFileName = 'watcher_backup.json';
}