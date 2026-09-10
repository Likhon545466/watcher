import 'package:flutter_test/flutter_test.dart';
import 'package:watcher/services/app_update_service.dart';

void main() {
  group('AppReleaseInfo Version Comparison Tests', () {
    test('Detects newer semantic patch version', () {
      const release = AppReleaseInfo(
        tagName: 'v4.2.8',
        version: '4.2.8',
        title: 'Watcher v4.2.8',
        releaseNotes: 'Bug fixes',
        htmlUrl: 'https://github.com/Likhon545466/watcher/releases/tag/v4.2.8',
      );

      expect(release.isNewerThan('v4.2.7'), isTrue);
      expect(release.isNewerThan('4.2.7'), isTrue);
      expect(release.isNewerThan('4.2.8'), isFalse);
      expect(release.isNewerThan('4.2.9'), isFalse);
    });

    test('Detects newer semantic minor and major versions', () {
      const releaseMinor = AppReleaseInfo(
        tagName: 'v4.3.0',
        version: '4.3.0',
        title: 'Watcher v4.3.0',
        releaseNotes: 'New features',
        htmlUrl: 'https://github.com/Likhon545466/watcher/releases/tag/v4.3.0',
      );
      expect(releaseMinor.isNewerThan('4.2.9'), isTrue);

      const releaseMajor = AppReleaseInfo(
        tagName: 'v5.0.0',
        version: '5.0.0',
        title: 'Watcher v5.0.0',
        releaseNotes: 'Major redesign',
        htmlUrl: 'https://github.com/Likhon545466/watcher/releases/tag/v5.0.0',
      );
      expect(releaseMajor.isNewerThan('4.9.9'), isTrue);
    });

    test('Handles build numbers comparison when versions match', () {
      const release = AppReleaseInfo(
        tagName: 'v4.2.7+22',
        version: '4.2.7+22',
        title: 'Watcher v4.2.7 (Build 22)',
        releaseNotes: 'Maintenance update',
        htmlUrl: 'https://github.com/Likhon545466/watcher/releases/tag/v4.2.7',
      );

      expect(release.isNewerThan('4.2.7', '21'), isTrue);
      expect(release.isNewerThan('4.2.7', '22'), isFalse);
      expect(release.isNewerThan('4.2.7', '23'), isFalse);
    });

    test('Formats APK file size correctly', () {
      const release = AppReleaseInfo(
        tagName: 'v4.2.7',
        version: '4.2.7',
        title: 'Watcher v4.2.7',
        releaseNotes: 'Release',
        htmlUrl: 'https://github.com/Likhon545466/watcher/releases/tag/v4.2.7',
        apkSize: 36700160, // ~35.0 MB
      );

      expect(release.formattedApkSize, '35.0 MB');
    });

    test('AppUpdateService.getLatestRelease retrieves release info with fallback', () async {
      final release = await AppUpdateService.getLatestRelease();
      expect(release, isNotNull);
      expect(release!.tagName.isNotEmpty, isTrue);
      expect(release.title.isNotEmpty, isTrue);
    });

    test('AppUpdateService.checkForNewVersion returns null when on latest version', () async {
      // Testing with a future version higher than the repo latest
      final release = await AppUpdateService.checkForNewVersion(
        currentVersion: '99.0.0',
        buildNumber: '999',
      );
      expect(release, isNull);
    });

    test('AppUpdateService.checkForNewVersion returns release when older version provided', () async {
      // Testing with older version 1.0.0
      final release = await AppUpdateService.checkForNewVersion(
        currentVersion: '1.0.0',
        buildNumber: '1',
      );
      expect(release, isNotNull);
      expect(release!.tagName.isNotEmpty, isTrue);
    });
  });
}
