import 'dart:convert';
import 'package:http/http.dart' as http;

class AppReleaseInfo {
  final String tagName;
  final String version;
  final String title;
  final String releaseNotes;
  final DateTime? publishedAt;
  final String htmlUrl;
  final String? apkDownloadUrl;
  final String? apkName;
  final int? apkSize;
  final int downloadCount;
  final bool isPrerelease;

  const AppReleaseInfo({
    required this.tagName,
    required this.version,
    required this.title,
    required this.releaseNotes,
    this.publishedAt,
    required this.htmlUrl,
    this.apkDownloadUrl,
    this.apkName,
    this.apkSize,
    this.downloadCount = 0,
    this.isPrerelease = false,
  });

  factory AppReleaseInfo.fromJson(Map<String, dynamic> json) {
    final tagName = (json['tag_name'] as String?)?.trim() ?? '';
    final rawVersion = tagName.startsWith('v') || tagName.startsWith('V')
        ? tagName.substring(1).trim()
        : tagName;

    // Find APK asset if available
    String? apkUrl;
    String? apkFileName;
    int? apkByteSize;
    int totalDownloads = 0;

    final assets = json['assets'] as List<dynamic>?;
    if (assets != null && assets.isNotEmpty) {
      for (final item in assets) {
        if (item is Map<String, dynamic>) {
          final name = (item['name'] as String?) ?? '';
          final dCount = (item['download_count'] as num?)?.toInt() ?? 0;
          totalDownloads += dCount;

          if (name.toLowerCase().endsWith('.apk')) {
            apkUrl = item['browser_download_url'] as String?;
            apkFileName = name;
            apkByteSize = (item['size'] as num?)?.toInt();
          }
        }
      }
    }

    DateTime? publishedDate;
    final publishedStr = json['published_at'] as String?;
    if (publishedStr != null) {
      publishedDate = DateTime.tryParse(publishedStr);
    }

    return AppReleaseInfo(
      tagName: tagName.isNotEmpty ? tagName : rawVersion,
      version: rawVersion,
      title: (json['name'] as String?)?.trim().isNotEmpty == true
          ? (json['name'] as String).trim()
          : (tagName.isNotEmpty ? tagName : 'Latest Release'),
      releaseNotes: (json['body'] as String?)?.trim() ?? '',
      publishedAt: publishedDate,
      htmlUrl: (json['html_url'] as String?) ??
          'https://github.com/Likhon545466/watcher/releases',
      apkDownloadUrl: apkUrl,
      apkName: apkFileName,
      apkSize: apkByteSize,
      downloadCount: totalDownloads,
      isPrerelease: (json['prerelease'] as bool?) ?? false,
    );
  }

  /// Formatted APK size in MB
  String get formattedApkSize {
    if (apkSize == null || apkSize! <= 0) return '';
    final mb = apkSize! / (1024 * 1024);
    return '${mb.toStringAsFixed(1)} MB';
  }

  /// Compares this remote release version with the installed [currentVersion].
  /// Returns `true` if this release is newer.
  bool isNewerThan(String currentVersion, [String? currentBuildNumber]) {
    final cleanCurrent = currentVersion
        .toLowerCase()
        .replaceAll('v', '')
        .trim();
    final cleanRemote = version
        .toLowerCase()
        .replaceAll('v', '')
        .trim();

    // Separate version and build number if current has '+'
    String curVerPart = cleanCurrent;
    int? curBuildNum = int.tryParse(currentBuildNumber ?? '');

    if (cleanCurrent.contains('+')) {
      final parts = cleanCurrent.split('+');
      curVerPart = parts[0];
      if (curBuildNum == null && parts.length > 1) {
        curBuildNum = int.tryParse(parts[1]);
      }
    }

    String remoteVerPart = cleanRemote;
    int? remoteBuildNum;
    if (cleanRemote.contains('+')) {
      final parts = cleanRemote.split('+');
      remoteVerPart = parts[0];
      if (parts.length > 1) {
        remoteBuildNum = int.tryParse(parts[1]);
      }
    }

    final curSegments = _parseSegments(curVerPart);
    final remoteSegments = _parseSegments(remoteVerPart);

    final maxLen = curSegments.length > remoteSegments.length
        ? curSegments.length
        : remoteSegments.length;

    for (int i = 0; i < maxLen; i++) {
      final c = i < curSegments.length ? curSegments[i] : 0;
      final r = i < remoteSegments.length ? remoteSegments[i] : 0;

      if (r > c) {
        return true;
      } else if (r < c) {
        return false;
      }
    }

    // If semantic versions match, compare build numbers if present
    if (remoteBuildNum != null && curBuildNum != null) {
      return remoteBuildNum > curBuildNum;
    }

    return false;
  }

  static List<int> _parseSegments(String v) {
    return v
        .split('.')
        .map((s) => int.tryParse(s.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0)
        .toList();
  }
}

class GithubRepoStats {
  final String repoName;
  final String ownerName;
  final String description;
  final int stars;
  final int forks;
  final int openIssues;
  final int watchers;
  final String? license;
  final String repoUrl;
  final String ownerAvatarUrl;
  final String ownerProfileUrl;
  final String? ownerBio;
  final int ownerPublicRepos;
  final int ownerFollowers;

  const GithubRepoStats({
    required this.repoName,
    required this.ownerName,
    required this.description,
    required this.stars,
    required this.forks,
    required this.openIssues,
    required this.watchers,
    this.license,
    required this.repoUrl,
    required this.ownerAvatarUrl,
    required this.ownerProfileUrl,
    this.ownerBio,
    this.ownerPublicRepos = 0,
    this.ownerFollowers = 0,
  });

  factory GithubRepoStats.fallback() {
    return const GithubRepoStats(
      repoName: 'watcher',
      ownerName: 'Likhon545466',
      description:
          'A clean offline-first movie and series tracker powered by OMDb and TMDB.',
      stars: 0,
      forks: 0,
      openIssues: 0,
      watchers: 0,
      license: 'MIT',
      repoUrl: 'https://github.com/Likhon545466/watcher',
      ownerAvatarUrl: 'https://github.com/Likhon545466.png',
      ownerProfileUrl: 'https://github.com/Likhon545466',
      ownerBio: 'Creator & Maintainer of Watcher',
      ownerPublicRepos: 0,
      ownerFollowers: 0,
    );
  }
}

class AppUpdateService {
  static const String repoOwner = 'Likhon545466';
  static const String repoName = 'watcher';
  static const String repoFullName = '$repoOwner/$repoName';

  static const String githubRepoUrl = 'https://github.com/$repoFullName';
  static const String githubProfileUrl = 'https://github.com/$repoOwner';
  static const String githubReleasesUrl = '$githubRepoUrl/releases';
  static const String githubLatestReleaseUrl = '$githubRepoUrl/releases/latest';
  static const String githubIssuesUrl = '$githubRepoUrl/issues';
  static const String githubNewIssueUrl = '$githubRepoUrl/issues/new';

  static const Map<String, String> _headers = {
    'Accept': 'application/vnd.github.v3+json',
    'User-Agent': 'Watcher-App',
  };

  /// Checks for the latest release on GitHub with multi-tier fallback:
  /// 1. GitHub REST API (`/releases/latest` or `/releases?per_page=1`)
  /// 2. Raw repository files (`.watcher_version` / `CHANGELOG.md`) to bypass rate limits
  static Future<AppReleaseInfo?> getLatestRelease() async {
    // Tier 1: Try GitHub REST API
    try {
      final uri = Uri.parse(
        'https://api.github.com/repos/$repoFullName/releases/latest',
      );
      final response = await http
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 7));

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        return AppReleaseInfo.fromJson(data);
      } else if (response.statusCode == 404) {
        // Try fetching list of releases
        final listUri = Uri.parse(
          'https://api.github.com/repos/$repoFullName/releases?per_page=1',
        );
        final listResponse = await http
            .get(listUri, headers: _headers)
            .timeout(const Duration(seconds: 7));
        if (listResponse.statusCode == 200) {
          final listData = json.decode(listResponse.body) as List<dynamic>;
          if (listData.isNotEmpty && listData[0] is Map<String, dynamic>) {
            return AppReleaseInfo.fromJson(
              listData[0] as Map<String, dynamic>,
            );
          }
        }
      }
    } catch (_) {}

    // Tier 2: Fallback to Raw GitHub content (No API rate limits)
    try {
      final rawRelease = await _fetchFromGithubRaw();
      if (rawRelease != null) {
        return rawRelease;
      }
    } catch (_) {}

    return null;
  }

  /// Fetches latest version and changelog from GitHub raw content
  static Future<AppReleaseInfo?> _fetchFromGithubRaw() async {
    try {
      final versionUri = Uri.parse(
        'https://raw.githubusercontent.com/$repoFullName/main/.watcher_version',
      );
      final changelogUri = Uri.parse(
        'https://raw.githubusercontent.com/$repoFullName/main/CHANGELOG.md',
      );

      final results = await Future.wait([
        http.get(versionUri).timeout(const Duration(seconds: 8)),
        http.get(changelogUri).timeout(const Duration(seconds: 8)),
      ]);

      final versionRes = results[0];
      final changelogRes = results[1];

      String rawVersionText = '';
      if (versionRes.statusCode == 200 && versionRes.body.trim().isNotEmpty) {
        rawVersionText = versionRes.body.trim();
      } else {
        // Fallback: try fetching pubspec.yaml
        final pubspecUri = Uri.parse(
          'https://raw.githubusercontent.com/$repoFullName/main/pubspec.yaml',
        );
        final pubspecRes =
            await http.get(pubspecUri).timeout(const Duration(seconds: 8));
        if (pubspecRes.statusCode == 200) {
          final lines = pubspecRes.body.split('\n');
          for (final line in lines) {
            if (line.trim().startsWith('version:')) {
              rawVersionText = line.replaceAll('version:', '').trim();
              break;
            }
          }
        }
      }

      if (rawVersionText.isEmpty) return null;

      String versionName = rawVersionText;
      String buildNumber = '';
      if (rawVersionText.contains('+')) {
        final parts = rawVersionText.split('+');
        versionName = parts[0].trim();
        if (parts.length > 1) {
          buildNumber = parts[1].trim();
        }
      }

      // Parse changelog for latest version
      String releaseNotes = '';
      if (changelogRes.statusCode == 200) {
        releaseNotes = _extractLatestChangelogSection(changelogRes.body);
      }

      final cleanVer = versionName.startsWith('v') || versionName.startsWith('V')
          ? versionName.substring(1)
          : versionName;
      final tagName = 'v$cleanVer';

      final apkName = buildNumber.isNotEmpty
          ? 'Watcher-v$cleanVer-build$buildNumber.apk'
          : 'Watcher-v$cleanVer.apk';

      final apkDownloadUrl =
          'https://github.com/$repoFullName/releases/download/$tagName/$apkName';

      return AppReleaseInfo(
        tagName: tagName,
        version: rawVersionText,
        title: 'Watcher $tagName',
        releaseNotes: releaseNotes.isNotEmpty
            ? releaseNotes
            : 'Latest release from GitHub repository.',
        publishedAt: DateTime.now(),
        htmlUrl: 'https://github.com/$repoFullName/releases',
        apkDownloadUrl: apkDownloadUrl,
        apkName: apkName,
      );
    } catch (_) {}
    return null;
  }

  /// Extracts the top version block from CHANGELOG.md markdown
  static String _extractLatestChangelogSection(String changelogMarkdown) {
    try {
      final lines = changelogMarkdown.split('\n');
      final buffer = StringBuffer();
      bool sectionStarted = false;

      for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed.startsWith('## [')) {
          if (sectionStarted) {
            break; // Finished first release section
          }
          sectionStarted = true;
          continue;
        }

        if (sectionStarted) {
          if (trimmed == '---') {
            break;
          }
          buffer.writeln(line);
        }
      }

      final result = buffer.toString().trim();
      return result.isNotEmpty ? result : '';
    } catch (_) {
      return '';
    }
  }

  /// Fetches repository stats and developer profile from GitHub API,
  /// falling back gracefully if rate-limited.
  static Future<GithubRepoStats> fetchGithubStats() async {
    try {
      final repoUri = Uri.parse('https://api.github.com/repos/$repoFullName');
      final userUri = Uri.parse('https://api.github.com/users/$repoOwner');

      final results = await Future.wait([
        http.get(repoUri, headers: _headers).timeout(const Duration(seconds: 7)),
        http.get(userUri, headers: _headers).timeout(const Duration(seconds: 7)),
      ]);

      final repoRes = results[0];
      final userRes = results[1];

      Map<String, dynamic>? repoData;
      Map<String, dynamic>? userData;

      if (repoRes.statusCode == 200) {
        repoData = json.decode(repoRes.body) as Map<String, dynamic>;
      }

      if (userRes.statusCode == 200) {
        userData = json.decode(userRes.body) as Map<String, dynamic>;
      }

      if (repoData != null) {
        final owner = repoData['owner'] as Map<String, dynamic>?;
        final licenseObj = repoData['license'] as Map<String, dynamic>?;

        return GithubRepoStats(
          repoName: (repoData['name'] as String?) ?? repoName,
          ownerName: (owner?['login'] as String?) ?? repoOwner,
          description: (repoData['description'] as String?) ??
              'A clean offline-first movie and series tracker powered by OMDb and TMDB.',
          stars: (repoData['stargazers_count'] as num?)?.toInt() ?? 0,
          forks: (repoData['forks_count'] as num?)?.toInt() ?? 0,
          openIssues: (repoData['open_issues_count'] as num?)?.toInt() ?? 0,
          watchers: (repoData['watchers_count'] as num?)?.toInt() ?? 0,
          license: (licenseObj?['spdx_id'] as String?) ??
              (licenseObj?['name'] as String?) ??
              'MIT',
          repoUrl: (repoData['html_url'] as String?) ?? githubRepoUrl,
          ownerAvatarUrl: (owner?['avatar_url'] as String?) ??
              (userData?['avatar_url'] as String?) ??
              'https://github.com/$repoOwner.png',
          ownerProfileUrl: (owner?['html_url'] as String?) ?? githubProfileUrl,
          ownerBio: (userData?['bio'] as String?) ??
              'Creator & Maintainer of Watcher',
          ownerPublicRepos:
              (userData?['public_repos'] as num?)?.toInt() ?? 0,
          ownerFollowers:
              (userData?['followers'] as num?)?.toInt() ?? 0,
        );
      }
    } catch (_) {}

    return GithubRepoStats.fallback();
  }
}
