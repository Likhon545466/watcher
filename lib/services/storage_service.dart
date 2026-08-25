import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/show.dart';

class WatcherSyncBackup {
  final List<Show> shows;
  final Map<String, DateTime> deletedShows;
  final DateTime? exportedAt;

  const WatcherSyncBackup({
    required this.shows,
    required this.deletedShows,
    this.exportedAt,
  });
}

class StorageService {
  static const String showsKey = 'watcher_shows_json_key';

  static Future<String> encodeBackup(List<Show> shows) async {
    /*
     * Backup safety:
     *
     * This backup stores Watcher metadata only.
     * It does not include poster image files, offline poster cache,
     * base64 images, thumbnails, or any other large binary data.
     *
     * show.toJson() may include posterUrl as a normal string.
     * That is intentionally kept so restored titles can load posters again.
     */
    final payload = <String, dynamic>{
      'app': 'Watcher',
      'version': 2,
      'exportedAt': DateTime.now().toIso8601String(),
      'shows': shows.map((show) => show.toJson()).toList(),
    };

    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  static List<Show> decodeBackup(String raw) {
    final decoded = jsonDecode(raw);

    List<dynamic> items;

    if (decoded is List) {
      items = decoded;
    } else if (decoded is Map && decoded['shows'] is List) {
      items = decoded['shows'] as List<dynamic>;
    } else {
      throw const FormatException('This is not a valid Watcher backup.');
    }

    return items
        .whereType<Map>()
        .map((item) => Show.fromJson(Map<String, dynamic>.from(item)))
        .toList(growable: false);
  }

  static Future<String> encodeSyncBackup(
    List<Show> shows,
    Map<String, DateTime> deletedShows,
  ) async {
    final payload = <String, dynamic>{
      'app': 'Watcher',
      'version': 3,
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'shows': shows.map((show) => show.toJson()).toList(),
      'deletedShows': deletedShows.map(
        (id, deletedAt) => MapEntry(id, deletedAt.toUtc().toIso8601String()),
      ),
    };

    return jsonEncode(payload);
  }

  static WatcherSyncBackup decodeSyncBackup(String raw) {
    final decoded = jsonDecode(raw);

    if (decoded is List) {
      return WatcherSyncBackup(
        shows: decoded
            .whereType<Map>()
            .map((item) => Show.fromJson(Map<String, dynamic>.from(item)))
            .toList(growable: false),
        deletedShows: const <String, DateTime>{},
      );
    }

    if (decoded is! Map || decoded['shows'] is! List) {
      throw const FormatException('This is not a valid Watcher backup.');
    }

    final shows = (decoded['shows'] as List<dynamic>)
        .whereType<Map>()
        .map((item) => Show.fromJson(Map<String, dynamic>.from(item)))
        .toList(growable: false);

    final deletedShows = <String, DateTime>{};
    final rawDeleted = decoded['deletedShows'];

    if (rawDeleted is Map) {
      rawDeleted.forEach((key, value) {
        final id = key.toString().trim();
        final date = DateTime.tryParse(value?.toString() ?? '');

        if (id.isNotEmpty && date != null) {
          deletedShows[id] = date.toUtc();
        }
      });
    }

    return WatcherSyncBackup(
      shows: shows,
      deletedShows: deletedShows,
      exportedAt: DateTime.tryParse(decoded['exportedAt']?.toString() ?? ''),
    );
  }

  static Future<File> createBackupFile(List<Show> shows) async {
    final directory = await getTemporaryDirectory();

    final stamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');

    final file = File('${directory.path}/watcher_backup_$stamp.txt');

    await file.writeAsString(await encodeBackup(shows), flush: true);

    return file;
  }

  /// Generates a clean CSV file compatible with Excel / Google Sheets.
  static Future<File> createCsvFile(List<Show> shows) async {
    final directory = await getTemporaryDirectory();

    final stamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');

    final file = File('${directory.path}/watcher_export_$stamp.csv');

    final buffer = StringBuffer();

    buffer.writeln(
      'Title,Type,Status,Rating,Release Year,Runtime (mins),Current Season,Watched Episodes,Genre',
    );

    for (final show in shows) {
      final cleanTitle = '"${show.title.replaceAll('"', '""')}"';

      final cleanGenre = '"${show.genre.replaceAll('"', '""')}"';

      buffer.writeln(
        '$cleanTitle,${show.type},${show.status},${show.rating},${show.yearText},${show.runtimeMinutes},${show.currentSeason},${show.watchedEpisodes},$cleanGenre',
      );
    }

    await file.writeAsString(buffer.toString(), flush: true);

    return file;
  }
}
