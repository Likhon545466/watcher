import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/omdb_search_item.dart';
import '../models/season_info.dart';
import '../models/show.dart';

class OmdbException implements Exception {
  final String message;
  const OmdbException(this.message);

  @override
  String toString() => message;
}

class OmdbService {
  static const String _apiKey = String.fromEnvironment(
    'OMDB_API_KEY',
    defaultValue: 'b6f5c12a',
  );
  static const String _host = 'www.omdbapi.com';

  static Future<List<OmdbSearchItem>> search(
    String query, {
    int page = 1,
  }) async {
    final cleanQuery = query.trim();
    if (cleanQuery.length < 2) return const <OmdbSearchItem>[];

    final data = await _get(<String, String>{
      'apikey': _apiKey,
      's': cleanQuery,
      'page': '$page',
    });

    if (data['Response'] != 'True') {
      final error = data['Error']?.toString() ?? 'No results found.';
      if (error.toLowerCase().contains('not found')) {
        return const <OmdbSearchItem>[];
      }
      throw OmdbException(error);
    }

    final raw = data['Search'];
    if (raw is! List) return const <OmdbSearchItem>[];

    return raw
        .whereType<Map>()
        .map((item) => OmdbSearchItem.fromJson(Map<String, dynamic>.from(item)))
        .where((item) => item.imdbId.isNotEmpty && item.title.isNotEmpty)
        .toList(growable: false);
  }

  static Future<Show> getDetails(
    String imdbId, {
    String status = 'Plan to Watch',
  }) async {
    final data = await _get(<String, String>{
      'apikey': _apiKey,
      'i': imdbId,
      'plot': 'full',
    });

    if (data['Response'] != 'True') {
      throw OmdbException(data['Error']?.toString() ?? 'Details not found.');
    }

    return Show.fromOmdb(data, status: status);
  }

  static Future<SeasonInfo> getSeason(String imdbId, int season) async {
    final data = await _get(<String, String>{
      'apikey': _apiKey,
      'i': imdbId,
      'Season': '$season',
    });

    if (data['Response'] != 'True') {
      throw OmdbException(
        data['Error']?.toString() ?? 'Season information not found.',
      );
    }

    return SeasonInfo.fromJson(data);
  }

  static Future<Map<String, dynamic>> _get(Map<String, String> query) async {
    if (_apiKey.trim().isEmpty) {
      throw const OmdbException('OMDb API key is missing.');
    }

    final uri = Uri.https(_host, '/', query);

    try {
      final response = await http.get(uri).timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) {
        throw OmdbException('Server error: ${response.statusCode}');
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map) {
        throw const OmdbException('Invalid response from OMDb.');
      }
      return Map<String, dynamic>.from(decoded);
    } on SocketException {
      throw const OmdbException('No internet connection.');
    } on FormatException {
      throw const OmdbException('OMDb returned invalid data.');
    } on OmdbException {
      rethrow;
    } catch (_) {
      throw const OmdbException('Could not connect to OMDb. Please try again.');
    }
  }
}
