import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ============================================================
// POSTER CACHE SERVICE
// ============================================================
//
// Persistent poster storage for Watcher.
//
// Posters are stored inside Application Support instead of
// the temporary cache directory.
//
// This means posters remain available offline across normal
// app restarts.
//
// They are removed only when:
// 1. Watcher app data is cleared
// 2. Watcher is uninstalled
// 3. clearCache() is called manually
// 4. Auto Clean trims the oldest cached posters after the
//    user-selected storage limit is crossed
//
// ============================================================

class PosterCacheService {
  PosterCacheService._();

  // ==========================================================
  // CACHE VERSION
  // ==========================================================

  static const String _cacheFolderName = 'watcher_poster_cache_v1';

  // ==========================================================
  // AUTO CLEAN SETTINGS
  // ==========================================================

  static const String _autoCleanLimitKey = 'poster_cache_auto_clean_limit_v1';

  static const int cacheLimitOffBytes = 0;

  static const List<int> autoCleanLimitOptionsBytes = <int>[
    cacheLimitOffBytes,
    100 * 1024 * 1024,
    250 * 1024 * 1024,
    500 * 1024 * 1024,
    1024 * 1024 * 1024,
  ];

  static const Duration _autoCleanThrottle = Duration(minutes: 5);

  static DateTime? _lastAutoCleanCheck;

  static bool _autoCleanRunning = false;

  // ==========================================================
  // NETWORK TIMEOUT
  // ==========================================================

  static const Duration _networkTimeout = Duration(seconds: 15);

  // ==========================================================
  // MEMORY LOOKUP
  // ==========================================================
  //
  // This does NOT hold image bytes in memory.
  //
  // It only remembers:
  //
  // poster URL -> local file path
  //
  // so repeated filesystem lookups are avoided.
  // ==========================================================

  static final Map<String, String> _resolvedPaths = <String, String>{};

  // ==========================================================
  // IN-FLIGHT DOWNLOADS
  // ==========================================================
  //
  // Home + Discover + Details can request the same poster
  // at the same time.
  //
  // This prevents duplicate downloads.
  // ==========================================================

  static final Map<String, Future<File?>> _inFlight = <String, Future<File?>>{};

  // ==========================================================
  // CACHE DIRECTORY
  // ==========================================================

  static Future<Directory> _getCacheDirectory() async {
    final supportDirectory = await getApplicationSupportDirectory();

    final directory = Directory(
      '${supportDirectory.path}${Platform.pathSeparator}$_cacheFolderName',
    );

    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }

    return directory;
  }

  // ==========================================================
  // AUTO CLEAN LIMIT
  // ==========================================================

  static Future<int> getAutoCleanLimitBytes() async {
    try {
      final preferences = await SharedPreferences.getInstance();

      final value = preferences.getInt(_autoCleanLimitKey);

      if (value == null || value <= 0) {
        return cacheLimitOffBytes;
      }

      return value;
    } catch (_) {
      return cacheLimitOffBytes;
    }
  }

  static Future<void> setAutoCleanLimitBytes(int bytes) async {
    final safeValue = bytes <= 0 ? cacheLimitOffBytes : bytes;

    final preferences = await SharedPreferences.getInstance();

    await preferences.setInt(_autoCleanLimitKey, safeValue);
  }

  static Future<void> enforceAutoCleanLimit({bool force = false}) async {
    if (_autoCleanRunning) {
      return;
    }

    final now = DateTime.now();

    if (!force && _lastAutoCleanCheck != null) {
      final sinceLastCheck = now.difference(_lastAutoCleanCheck!);

      if (sinceLastCheck < _autoCleanThrottle) {
        return;
      }
    }

    _lastAutoCleanCheck = now;

    final limitBytes = await getAutoCleanLimitBytes();

    if (limitBytes <= 0) {
      return;
    }

    _autoCleanRunning = true;

    try {
      await trimCacheToLimitBytes(limitBytes);
    } finally {
      _autoCleanRunning = false;
    }
  }

  static Future<void> trimCacheToLimitBytes(int limitBytes) async {
    if (limitBytes <= 0) {
      return;
    }

    try {
      final directory = await _getCacheDirectory();

      final files = <({File file, int size, DateTime modified})>[];

      int totalBytes = 0;

      await for (final entity in directory.list(recursive: false)) {
        if (entity is! File || entity.path.endsWith('.part')) {
          continue;
        }

        try {
          final size = await entity.length();

          final stat = await entity.stat();

          if (size <= 0) {
            continue;
          }

          files.add((file: entity, size: size, modified: stat.modified));

          totalBytes += size;
        } catch (_) {}
      }

      if (totalBytes <= limitBytes) {
        return;
      }

      files.sort((a, b) => a.modified.compareTo(b.modified));

      for (final item in files) {
        if (totalBytes <= limitBytes) {
          break;
        }

        try {
          await item.file.delete();

          totalBytes -= item.size;

          _resolvedPaths.removeWhere((_, path) => path == item.file.path);
        } catch (_) {}
      }
    } catch (_) {
      // Auto cleanup should never crash Watcher.
    }
  }

  // ==========================================================
  // GET POSTER
  // ==========================================================
  //
  // Behavior:
  //
  // 1. Check memory path map
  // 2. Check persistent disk
  // 3. Download from internet
  // 4. Save to disk
  // 5. Return local File
  //
  // If internet is unavailable and no cached file exists,
  // null is returned.
  // ==========================================================

  static Future<File?> getPosterFile(String rawUrl) async {
    final url = rawUrl.trim();

    if (url.isEmpty) {
      return null;
    }

    // ========================================================
    // FAST MEMORY PATH CHECK
    // ========================================================

    final rememberedPath = _resolvedPaths[url];

    if (rememberedPath != null) {
      final rememberedFile = File(rememberedPath);

      if (await _isValidFile(rememberedFile)) {
        unawaited(enforceAutoCleanLimit());

        return rememberedFile;
      }

      _resolvedPaths.remove(url);
    }

    // ========================================================
    // DEDUPLICATE SAME DOWNLOAD
    // ========================================================

    final existingRequest = _inFlight[url];

    if (existingRequest != null) {
      return existingRequest;
    }

    late final Future<File?> request;

    request = _resolvePoster(url).whenComplete(() {
      _inFlight.remove(url);
    });

    _inFlight[url] = request;

    final file = await request;

    if (file != null) {
      unawaited(enforceAutoCleanLimit());
    }

    return file;
  }

  // ==========================================================
  // RESOLVE POSTER
  // ==========================================================

  static Future<File?> _resolvePoster(String url) async {
    try {
      final directory = await _getCacheDirectory();

      final filename = _buildFileName(url);

      final file = File('${directory.path}${Platform.pathSeparator}$filename');

      // ======================================================
      // DISK HIT
      // ======================================================

      if (await _isValidFile(file)) {
        _resolvedPaths[url] = file.path;

        return file;
      }

      // ======================================================
      // REMOVE BROKEN FILE
      // ======================================================

      if (await file.exists()) {
        try {
          await file.delete();
        } catch (_) {
          // Continue and try network.
        }
      }

      // ======================================================
      // NETWORK DOWNLOAD
      // ======================================================

      final response = await http.get(Uri.parse(url)).timeout(_networkTimeout);

      if (response.statusCode != 200 || response.bodyBytes.isEmpty) {
        return null;
      }

      // ======================================================
      // BASIC IMAGE RESPONSE VALIDATION
      // ======================================================

      final contentType = response.headers['content-type'];

      if (contentType != null &&
          contentType.isNotEmpty &&
          !contentType.toLowerCase().contains('image')) {
        return null;
      }

      // ======================================================
      // ATOMIC WRITE
      // ======================================================
      //
      // Save into .part first.
      //
      // This prevents a half-downloaded image from being
      // treated as a valid cached poster.
      // ======================================================

      final partFile = File('${file.path}.part');

      try {
        if (await partFile.exists()) {
          await partFile.delete();
        }

        await partFile.writeAsBytes(response.bodyBytes, flush: true);

        if (!await _isValidFile(partFile)) {
          try {
            await partFile.delete();
          } catch (_) {}

          return null;
        }

        // Another request normally cannot reach this point
        // because of _inFlight, but this keeps the write safe.
        if (await file.exists()) {
          try {
            await file.delete();
          } catch (_) {}
        }

        await partFile.rename(file.path);
      } catch (_) {
        try {
          if (await partFile.exists()) {
            await partFile.delete();
          }
        } catch (_) {}

        return null;
      }

      if (!await _isValidFile(file)) {
        return null;
      }

      _resolvedPaths[url] = file.path;

      return file;
    } on TimeoutException {
      return null;
    } on SocketException {
      return null;
    } on HttpException {
      return null;
    } on FormatException {
      return null;
    } catch (_) {
      return null;
    }
  }

  // ==========================================================
  // VALID FILE
  // ==========================================================

  static Future<bool> _isValidFile(File file) async {
    try {
      if (!await file.exists()) {
        return false;
      }

      final size = await file.length();

      // Extremely tiny files are usually failed responses,
      // HTML/error files, or incomplete downloads.
      return size > 100;
    } catch (_) {
      return false;
    }
  }

  // ==========================================================
  // STABLE FILE NAME
  // ==========================================================
  //
  // We intentionally do not use Dart's String.hashCode as a
  // persistent file identifier.
  //
  // Instead two deterministic hashes + URL length are used.
  // ==========================================================

  static String _buildFileName(String url) {
    final firstHash = _fnv1a32(url);

    final secondHash = _djb2_32(url);

    final extension = _detectExtension(url);

    return 'poster_'
        '${firstHash.toRadixString(16).padLeft(8, '0')}_'
        '${secondHash.toRadixString(16).padLeft(8, '0')}_'
        '${url.length}'
        '$extension';
  }

  // ==========================================================
  // FNV-1A 32 BIT
  // ==========================================================

  static int _fnv1a32(String value) {
    int hash = 0x811C9DC5;

    for (final unit in value.codeUnits) {
      hash ^= unit;

      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }

    return hash;
  }

  // ==========================================================
  // DJB2 32 BIT
  // ==========================================================

  static int _djb2_32(String value) {
    int hash = 5381;

    for (final unit in value.codeUnits) {
      hash = ((hash << 5) + hash + unit) & 0xFFFFFFFF;
    }

    return hash;
  }

  // ==========================================================
  // FILE EXTENSION
  // ==========================================================

  static String _detectExtension(String url) {
    try {
      final uri = Uri.parse(url);

      final path = uri.path.toLowerCase();

      if (path.endsWith('.png')) {
        return '.png';
      }

      if (path.endsWith('.webp')) {
        return '.webp';
      }

      if (path.endsWith('.jpeg')) {
        return '.jpeg';
      }

      if (path.endsWith('.jpg')) {
        return '.jpg';
      }
    } catch (_) {
      // Default below.
    }

    return '.img';
  }

  // ==========================================================
  // CACHE SIZE
  // ==========================================================

  static Future<int> getCacheSizeBytes() async {
    try {
      final directory = await _getCacheDirectory();

      int total = 0;

      await for (final entity in directory.list(recursive: false)) {
        if (entity is! File) {
          continue;
        }

        if (entity.path.endsWith('.part')) {
          continue;
        }

        try {
          total += await entity.length();
        } catch (_) {}
      }

      return total;
    } catch (_) {
      return 0;
    }
  }

  // ==========================================================
  // CACHED POSTER COUNT
  // ==========================================================

  static Future<int> getCachedPosterCount() async {
    try {
      final directory = await _getCacheDirectory();

      int count = 0;

      await for (final entity in directory.list(recursive: false)) {
        if (entity is File && !entity.path.endsWith('.part')) {
          count++;
        }
      }

      return count;
    } catch (_) {
      return 0;
    }
  }

  // ==========================================================
  // CLEAR POSTER CACHE
  // ==========================================================

  static Future<void> clearCache() async {
    _resolvedPaths.clear();

    try {
      final directory = await _getCacheDirectory();

      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    } catch (_) {
      // Cache cleanup should never crash Watcher.
    }
  }
}
