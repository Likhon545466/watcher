import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

Map<String, dynamic>? _decodeTmdbBody(String body) {
  try {
    final decoded = jsonDecode(body);

    if (decoded is Map<String, dynamic>) {
      return decoded;
    }

    if (decoded is Map) {
      return Map<String, dynamic>.from(decoded);
    }

    return null;
  } catch (_) {
    return null;
  }
}

enum TmdbDiscoverSection { trending, newReleases, upcoming }

enum TmdbMediaType { movie, tv }

class TmdbDiscoverItem {
  final String id;
  final String title;
  final String? posterPath;
  final String? backdropPath;
  final String mediaType;
  final String releaseDate;
  final double voteAverage;
  final String overview;

  /// Extra metadata used only to diversify Discover results.
  /// Existing UI/data flows do not depend on these fields.
  final String originalLanguage;
  final List<int> genreIds;

  TmdbDiscoverItem({
    required this.id,
    required this.title,
    this.posterPath,
    this.backdropPath,
    required this.mediaType,
    required this.releaseDate,
    required this.voteAverage,
    required this.overview,
    this.originalLanguage = '',
    this.genreIds = const <int>[],
  });

  factory TmdbDiscoverItem.fromJson(
    Map<String, dynamic> json, {
    String? defaultType,
  }) {
    final rawType = (json['media_type'] ?? defaultType ?? 'movie').toString();

    final isMovie = rawType == 'movie';

    final title = isMovie
        ? (json['title'] ?? '').toString()
        : (json['name'] ?? '').toString();

    final date = isMovie
        ? (json['release_date'] ?? '').toString()
        : (json['first_air_date'] ?? '').toString();

    return TmdbDiscoverItem(
      id: json['id'].toString(),
      title: title,
      posterPath: json['poster_path']?.toString(),
      backdropPath: json['backdrop_path']?.toString(),
      mediaType: isMovie ? 'movie' : 'tv',
      releaseDate: date,
      voteAverage: (json['vote_average'] as num?)?.toDouble() ?? 0.0,
      overview: (json['overview'] ?? '').toString(),
      originalLanguage: (json['original_language'] ?? '').toString(),
      genreIds: (json['genre_ids'] is List)
          ? (json['genre_ids'] as List)
                .whereType<num>()
                .map((value) => value.toInt())
                .toList(growable: false)
          : const <int>[],
    );
  }

  String? get posterUrl {
    if (posterPath == null || posterPath!.isEmpty) {
      return null;
    }

    return 'https://image.tmdb.org/t/p/w500$posterPath';
  }

  String? get backdropUrl {
    if (backdropPath == null || backdropPath!.isEmpty) {
      return null;
    }

    return 'https://image.tmdb.org/t/p/w1280$backdropPath';
  }

  String get year {
    if (releaseDate.length < 4) {
      return 'N/A';
    }

    return releaseDate.substring(0, 4);
  }

  String get uniqueKey => '${mediaType}_$id';
}

class TmdbMediaData {
  final String? backdropUrl;
  final String? hdPosterUrl;

  /// Original quality TMDB backdrop URLs.
  ///
  /// First item is usually the matched title's primary backdrop.
  final List<String> backdropUrls;

  /// Original quality TMDB poster URLs.
  ///
  /// First item is usually the matched title's primary poster.
  /// Details screen should place the saved/current app poster first,
  /// then use this list as swipeable alternates.
  final List<String> posterUrls;

  const TmdbMediaData({
    this.backdropUrl,
    this.hdPosterUrl,
    this.backdropUrls = const <String>[],
    this.posterUrls = const <String>[],
  });
}

class TmdbPersonSummary {
  final String id;
  final String name;
  final String knownForDepartment;
  final String? profilePath;
  final double popularity;

  const TmdbPersonSummary({
    required this.id,
    required this.name,
    required this.knownForDepartment,
    this.profilePath,
    required this.popularity,
  });

  String? get profileUrl {
    final path = profilePath?.trim();

    if (path == null || path.isEmpty) {
      return null;
    }

    return 'https://image.tmdb.org/t/p/w500$path';
  }
}

class TmdbPersonDetails {
  final String id;
  final String name;
  final String knownForDepartment;
  final String biography;
  final String birthday;
  final String deathday;
  final String placeOfBirth;
  final String? profilePath;
  final double popularity;
  final List<TmdbDiscoverItem> knownFor;

  const TmdbPersonDetails({
    required this.id,
    required this.name,
    required this.knownForDepartment,
    required this.biography,
    required this.birthday,
    required this.deathday,
    required this.placeOfBirth,
    this.profilePath,
    required this.popularity,
    this.knownFor = const <TmdbDiscoverItem>[],
  });

  String? get profileUrl {
    final path = profilePath?.trim();

    if (path == null || path.isEmpty) {
      return null;
    }

    return 'https://image.tmdb.org/t/p/h632$path';
  }
}

class TmdbSeriesInfo {
  final int seasonNumber;
  final bool hasUpcomingEpisode;

  const TmdbSeriesInfo({
    required this.seasonNumber,
    required this.hasUpcomingEpisode,
  });

  String get label => 'Season $seasonNumber';
}

class TmdbSeasonProgressInfo {
  final String tmdbId;
  final int seasonNumber;
  final int totalSeasons;
  final int knownEpisodeCount;
  final int lastAiredEpisode;
  final int? nextEpisode;

  final int? upcomingSeason;
  final int? upcomingEpisode;
  final DateTime? upcomingAirDate;

  final bool isFinal;
  final bool hasUpcomingEpisode;
  final bool seriesEnded;

  const TmdbSeasonProgressInfo({
    required this.tmdbId,
    required this.seasonNumber,
    required this.totalSeasons,
    required this.knownEpisodeCount,
    required this.lastAiredEpisode,
    required this.nextEpisode,
    this.upcomingSeason,
    this.upcomingEpisode,
    this.upcomingAirDate,
    required this.isFinal,
    required this.hasUpcomingEpisode,
    required this.seriesEnded,
  });
}

class TmdbPageResult {
  final List<TmdbDiscoverItem> items;
  final int page;
  final bool hasMore;

  const TmdbPageResult({
    required this.items,
    required this.page,
    required this.hasMore,
  });
}

class TmdbServiceException implements Exception {
  final String message;

  const TmdbServiceException(this.message);

  @override
  String toString() => message;
}

class _TmdbPageCacheEntry {
  final TmdbPageResult result;
  final DateTime createdAt;

  const _TmdbPageCacheEntry({required this.result, required this.createdAt});
}

class _TmdbSeriesInfoCacheEntry {
  final TmdbSeriesInfo? info;
  final DateTime createdAt;

  const _TmdbSeriesInfoCacheEntry({
    required this.info,
    required this.createdAt,
  });
}

class _TmdbSeasonProgressCacheEntry {
  final TmdbSeasonProgressInfo? info;
  final DateTime createdAt;

  const _TmdbSeasonProgressCacheEntry({
    required this.info,
    required this.createdAt,
  });
}

class _TmdbRecommendationsCacheEntry {
  final List<TmdbDiscoverItem> items;
  final DateTime createdAt;

  const _TmdbRecommendationsCacheEntry({
    required this.items,
    required this.createdAt,
  });
}

class _TmdbPersonDetailsCacheEntry {
  final TmdbPersonDetails details;
  final DateTime createdAt;

  const _TmdbPersonDetailsCacheEntry({
    required this.details,
    required this.createdAt,
  });
}

class TmdbService {
  static const String _apiKey = '5331a80da5ce7a5845447038f4ae1c06';

  static const String _baseUrl = 'https://api.themoviedb.org/3';

  static const String _imageBaseUrl = 'https://image.tmdb.org/t/p';

  static const Duration _requestTimeout = Duration(seconds: 12);

  static const Duration _cacheLifetime = Duration(minutes: 10);

  static const int _backgroundDecodeThreshold = 35000;

  // ==========================================================
  // DIVERSE DISCOVER ROTATION
  // ==========================================================
  //
  // Page 1 stays broad/global.
  // Later pages alternate between industry/language spotlights
  // and genre spotlights. This keeps Discover globally useful
  // without increasing the number of requests per loaded page.
  //
  // Upcoming date range remains unchanged at 90 days.
  //
  // ==========================================================

  static const List<String> _industryLanguageRotation = <String>[
    'en', // Hollywood / English-language
    'hi', // Hindi / Bollywood
    'bn', // Bengali
    'ko', // Korean
    'ja', // Japanese
    'zh', // Chinese
    'ta', // Tamil
    'te', // Telugu
    'ml', // Malayalam
    'kn', // Kannada
    'es', // Spanish
    'fr', // French
    'de', // German
    'it', // Italian
    'tr', // Turkish
    'th', // Thai
    'id', // Indonesian
    'ar', // Arabic
    'ur', // Urdu
    'pt', // Portuguese
  ];

  static const List<int> _genreRotation = <int>[
    28, // Action
    18, // Drama
    35, // Comedy
    53, // Thriller
    27, // Horror
    10749, // Romance
    80, // Crime
    878, // Science Fiction
    14, // Fantasy
    16, // Animation
    10751, // Family
    99, // Documentary
    9648, // Mystery
    12, // Adventure
  ];

  static final http.Client _client = http.Client();

  static final Map<String, _TmdbPageCacheEntry> _pageCache =
      <String, _TmdbPageCacheEntry>{};

  static final Map<String, Future<TmdbPageResult>> _inFlightRequests =
      <String, Future<TmdbPageResult>>{};

  static Future<void>? _prefetchFuture;

  static const Duration _seriesInfoCacheLifetime = Duration(minutes: 30);

  static final Map<String, _TmdbSeriesInfoCacheEntry> _seriesInfoCache =
      <String, _TmdbSeriesInfoCacheEntry>{};

  static final Map<String, Future<TmdbSeriesInfo?>> _seriesInfoInFlight =
      <String, Future<TmdbSeriesInfo?>>{};

  static const int _maxSeriesInfoConcurrentRequests = 2;

  static int _activeSeriesInfoRequests = 0;

  static final List<Completer<void>> _seriesInfoWaiters = <Completer<void>>[];

  static const Duration _externalIdCacheLifetime = Duration(hours: 24);

  static final Map<String, ({String tmdbId, DateTime createdAt})>
  _imdbToTmdbTvIdCache = <String, ({String tmdbId, DateTime createdAt})>{};

  static const Duration _seasonProgressCacheLifetime = Duration(minutes: 30);

  static final Map<String, _TmdbSeasonProgressCacheEntry> _seasonProgressCache =
      <String, _TmdbSeasonProgressCacheEntry>{};

  static final Map<String, Future<TmdbSeasonProgressInfo?>>
  _seasonProgressInFlight = <String, Future<TmdbSeasonProgressInfo?>>{};

  static const Duration _recommendationsCacheLifetime = Duration(minutes: 30);

  static final Map<String, _TmdbRecommendationsCacheEntry>
  _recommendationsCache = <String, _TmdbRecommendationsCacheEntry>{};

  static final Map<String, Future<List<TmdbDiscoverItem>>>
  _recommendationsInFlight = <String, Future<List<TmdbDiscoverItem>>>{};

  static const Duration _personCacheLifetime = Duration(hours: 6);

  static final Map<String, _TmdbPersonDetailsCacheEntry> _personDetailsCache =
      <String, _TmdbPersonDetailsCacheEntry>{};

  static final Map<String, Future<TmdbPersonDetails?>> _personDetailsInFlight =
      <String, Future<TmdbPersonDetails?>>{};

  static String _cacheKey(
    TmdbDiscoverSection section,
    TmdbMediaType mediaType,
    int page,
  ) {
    return '${section.name}_${mediaType.name}_$page';
  }

  static TmdbPageResult? getCachedDiscoverPage({
    required TmdbDiscoverSection section,
    required TmdbMediaType mediaType,
    int page = 1,
  }) {
    final key = _cacheKey(section, mediaType, page);

    final entry = _pageCache[key];

    if (entry == null) {
      return null;
    }

    final age = DateTime.now().difference(entry.createdAt);

    if (age > _cacheLifetime) {
      _pageCache.remove(key);
      return null;
    }

    return entry.result;
  }

  static void _writeCache(String key, TmdbPageResult result) {
    if (result.items.isEmpty) {
      return;
    }

    _pageCache[key] = _TmdbPageCacheEntry(
      result: TmdbPageResult(
        items: List<TmdbDiscoverItem>.unmodifiable(result.items),
        page: result.page,
        hasMore: result.hasMore,
      ),
      createdAt: DateTime.now(),
    );
  }

  static void clearDiscoverCache() {
    _pageCache.clear();
  }

  static void clearDiscoverCombination({
    required TmdbDiscoverSection section,
    required TmdbMediaType mediaType,
  }) {
    final prefix = '${section.name}_${mediaType.name}_';

    _pageCache.removeWhere((key, _) => key.startsWith(prefix));
  }

  static Future<Map<String, dynamic>> _getJson(Uri url) async {
    http.Response response;

    try {
      response = await _client.get(url).timeout(_requestTimeout);
    } on TimeoutException {
      throw const TmdbServiceException('TMDB request timed out.');
    } catch (_) {
      throw const TmdbServiceException('Could not connect to TMDB.');
    }

    if (response.statusCode != 200) {
      throw TmdbServiceException(
        'TMDB request failed with status '
        '${response.statusCode}.',
      );
    }

    final body = response.body;

    if (body.isEmpty) {
      throw const TmdbServiceException('TMDB returned an empty response.');
    }

    Map<String, dynamic>? decoded;

    if (body.length >= _backgroundDecodeThreshold) {
      try {
        decoded = await compute(_decodeTmdbBody, body);
      } catch (_) {
        decoded = _decodeTmdbBody(body);
      }
    } else {
      decoded = _decodeTmdbBody(body);
    }

    if (decoded == null) {
      throw const TmdbServiceException('Could not decode TMDB response.');
    }

    return decoded;
  }

  static String _formatDate(DateTime date) {
    return '${date.year}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }

  static DateTime? _parseDateOnly(dynamic raw) {
    final parsed = DateTime.tryParse(raw?.toString() ?? '');

    if (parsed == null) {
      return null;
    }

    return DateTime(parsed.year, parsed.month, parsed.day);
  }

  static DateTime _dateOnly(DateTime value) {
    return DateTime(value.year, value.month, value.day);
  }

  static String _mediaPath(TmdbMediaType mediaType) {
    return mediaType == TmdbMediaType.movie ? 'movie' : 'tv';
  }

  static String? _tmdbImageUrl(String? path, {String size = 'original'}) {
    final cleanPath = path?.trim();

    if (cleanPath == null || cleanPath.isEmpty) {
      return null;
    }

    if (cleanPath.startsWith('http://') || cleanPath.startsWith('https://')) {
      return cleanPath;
    }

    return '$_imageBaseUrl/$size$cleanPath';
  }

  static String _posterIdentity(String url) {
    var clean = url.trim();

    clean = clean.replaceAll(RegExp(r'https://image\.tmdb\.org/t/p/[^/]+'), '');

    clean = clean.replaceAll(RegExp(r'_SX\d+_|_SY\d+_'), '');

    clean = clean.replaceAll(RegExp(r'SX\d+'), 'SX');

    return clean.toLowerCase();
  }

  static void _addUniquePosterUrl(List<String> urls, String? url) {
    final clean = url?.trim();

    if (clean == null || clean.isEmpty) {
      return;
    }

    final identity = _posterIdentity(clean);

    final exists = urls.any((item) => _posterIdentity(item) == identity);

    if (exists) {
      return;
    }

    urls.add(clean);
  }

  static Future<TmdbPageResult> fetchDiscoverPage({
    required TmdbDiscoverSection section,
    required TmdbMediaType mediaType,
    int page = 1,
    bool forceRefresh = false,
  }) {
    if (page < 1) {
      page = 1;
    }

    final key = _cacheKey(section, mediaType, page);

    if (!forceRefresh) {
      final cached = getCachedDiscoverPage(
        section: section,
        mediaType: mediaType,
        page: page,
      );

      if (cached != null) {
        return Future<TmdbPageResult>.value(cached);
      }
    }

    final existing = _inFlightRequests[key];

    if (existing != null) {
      return existing;
    }

    late final Future<TmdbPageResult> request;

    request = (() async {
      try {
        final result = await _fetchDiscoverPageFromNetwork(
          section: section,
          mediaType: mediaType,
          page: page,
        );

        if (result.items.isNotEmpty) {
          _writeCache(key, result);
        }

        return result;
      } catch (_) {
        final cached = getCachedDiscoverPage(
          section: section,
          mediaType: mediaType,
          page: page,
        );

        if (cached != null) {
          return cached;
        }

        rethrow;
      } finally {
        _inFlightRequests.remove(key);
      }
    })();

    _inFlightRequests[key] = request;

    return request;
  }

  static Future<TmdbPageResult> _fetchDiscoverPageFromNetwork({
    required TmdbDiscoverSection section,
    required TmdbMediaType mediaType,
    required int page,
  }) async {
    switch (section) {
      case TmdbDiscoverSection.trending:
        return _fetchTrendingPage(mediaType: mediaType, page: page);

      case TmdbDiscoverSection.newReleases:
        return _fetchDateDiscoverPage(
          section: section,
          mediaType: mediaType,
          page: page,
        );

      case TmdbDiscoverSection.upcoming:
        return _fetchDateDiscoverPage(
          section: section,
          mediaType: mediaType,
          page: page,
        );
    }
  }

  static Future<TmdbPageResult> _fetchTrendingPage({
    required TmdbMediaType mediaType,
    required int page,
  }) async {
    final media = _mediaPath(mediaType);

    final url = Uri.parse('$_baseUrl/trending/$media/day').replace(
      queryParameters: <String, String>{
        'api_key': _apiKey,
        'page': page.toString(),
        'language': 'en-US',
      },
    );

    final data = await _getJson(url);

    final rawResults = data['results'];

    final items = <TmdbDiscoverItem>[];

    if (rawResults is List) {
      for (final raw in rawResults) {
        if (raw is! Map) {
          continue;
        }

        final item = TmdbDiscoverItem.fromJson(
          Map<String, dynamic>.from(raw),
          defaultType: media,
        );

        if (item.title.trim().isEmpty) {
          continue;
        }

        items.add(item);
      }
    }

    final totalPages = (data['total_pages'] as num?)?.toInt() ?? 1;

    return TmdbPageResult(
      items: _removeDuplicates(items),
      page: page,
      hasMore: page < totalPages,
    );
  }

  static ({String? language, int? genre, int sourcePage})
  _discoverDiversityLane(int requestedPage) {
    if (requestedPage <= 1) {
      return (language: null, genre: null, sourcePage: 1);
    }

    final lanePosition = requestedPage - 2;

    // Even lane positions: rotate industries/languages.
    if (lanePosition.isEven) {
      final sequence = lanePosition ~/ 2;

      final language =
          _industryLanguageRotation[sequence %
              _industryLanguageRotation.length];

      final sourcePage = 1 + (sequence ~/ _industryLanguageRotation.length);

      return (language: language, genre: null, sourcePage: sourcePage);
    }

    // Odd lane positions: rotate genres.
    final sequence = lanePosition ~/ 2;

    final genre = _genreRotation[sequence % _genreRotation.length];

    final sourcePage = 1 + (sequence ~/ _genreRotation.length);

    return (language: null, genre: genre, sourcePage: sourcePage);
  }

  static Future<TmdbPageResult> _fetchDateDiscoverPage({
    required TmdbDiscoverSection section,
    required TmdbMediaType mediaType,
    required int page,
  }) async {
    final now = DateTime.now();

    late final DateTime startDate;
    late final DateTime endDate;

    if (section == TmdbDiscoverSection.newReleases) {
      startDate = now.subtract(const Duration(days: 90));

      endDate = now;
    } else {
      startDate = now;

      endDate = now.add(const Duration(days: 90));
    }

    final media = _mediaPath(mediaType);

    final diversityLane = _discoverDiversityLane(page);

    final parameters = <String, String>{
      'api_key': _apiKey,
      'page': diversityLane.sourcePage.toString(),
      'language': 'en-US',
      'sort_by': 'popularity.desc',
      'include_adult': 'false',
    };

    if (diversityLane.language != null) {
      parameters['with_original_language'] = diversityLane.language!;
    }

    if (diversityLane.genre != null) {
      parameters['with_genres'] = diversityLane.genre!.toString();
    }

    if (mediaType == TmdbMediaType.movie) {
      parameters['primary_release_date.gte'] = _formatDate(startDate);

      parameters['primary_release_date.lte'] = _formatDate(endDate);

      parameters['include_video'] = 'false';
    } else {
      parameters['first_air_date.gte'] = _formatDate(startDate);

      parameters['first_air_date.lte'] = _formatDate(endDate);

      parameters['include_null_first_air_dates'] = 'false';
    }

    final url = Uri.parse(
      '$_baseUrl/discover/$media',
    ).replace(queryParameters: parameters);

    final data = await _getJson(url);

    final rawResults = data['results'];

    final items = <TmdbDiscoverItem>[];

    if (rawResults is List) {
      for (final raw in rawResults) {
        if (raw is! Map) {
          continue;
        }

        final item = TmdbDiscoverItem.fromJson(
          Map<String, dynamic>.from(raw),
          defaultType: media,
        );

        if (item.title.trim().isEmpty || item.releaseDate.isEmpty) {
          continue;
        }

        items.add(item);
      }
    }

    final uniqueItems = _removeDuplicates(items);

    if (section == TmdbDiscoverSection.newReleases) {
      uniqueItems.sort((a, b) => b.releaseDate.compareTo(a.releaseDate));
    } else {
      uniqueItems.sort((a, b) => a.releaseDate.compareTo(b.releaseDate));
    }

    final totalPages = (data['total_pages'] as num?)?.toInt() ?? 1;

    final laneHasMore = diversityLane.sourcePage < totalPages;

    // There are many independent language/genre lanes after page 1.
    // Keep app pagination available while the current lane returns data.
    final hasMore =
        uniqueItems.isNotEmpty && (page == 1 || laneHasMore || page < 80);

    return TmdbPageResult(items: uniqueItems, page: page, hasMore: hasMore);
  }

  static List<TmdbDiscoverItem> _removeDuplicates(
    Iterable<TmdbDiscoverItem> items,
  ) {
    final map = <String, TmdbDiscoverItem>{};

    for (final item in items) {
      if (item.title.trim().isEmpty) {
        continue;
      }

      map[item.uniqueKey] = item;
    }

    return map.values.toList();
  }

  static Future<void> prefetchDiscoverData() {
    return _prefetchFuture ??= _performDiscoverPrefetch();
  }

  static Future<void> _performDiscoverPrefetch() async {
    final jobs = <Future<void> Function()>[
      () async {
        await fetchDiscoverPage(
          section: TmdbDiscoverSection.trending,
          mediaType: TmdbMediaType.movie,
          page: 1,
        );
      },
      () async {
        await fetchDiscoverPage(
          section: TmdbDiscoverSection.trending,
          mediaType: TmdbMediaType.tv,
          page: 1,
        );
      },
      () async {
        await fetchDiscoverPage(
          section: TmdbDiscoverSection.newReleases,
          mediaType: TmdbMediaType.movie,
          page: 1,
        );
      },
      () async {
        await fetchDiscoverPage(
          section: TmdbDiscoverSection.newReleases,
          mediaType: TmdbMediaType.tv,
          page: 1,
        );
      },
      () async {
        await fetchDiscoverPage(
          section: TmdbDiscoverSection.upcoming,
          mediaType: TmdbMediaType.movie,
          page: 1,
        );
      },
      () async {
        await fetchDiscoverPage(
          section: TmdbDiscoverSection.upcoming,
          mediaType: TmdbMediaType.tv,
          page: 1,
        );
      },
    ];

    for (int i = 0; i < jobs.length; i += 2) {
      final batch = jobs.skip(i).take(2);

      await Future.wait(
        batch.map((job) async {
          try {
            await job();
          } catch (_) {}
        }),
      );

      if (i + 2 < jobs.length) {
        await Future<void>.delayed(const Duration(milliseconds: 120));
      }
    }
  }

  static TmdbSeriesInfo? getCachedSeriesSeasonInfo(String tmdbId) {
    final entry = _seriesInfoCache[tmdbId];

    if (entry == null) {
      return null;
    }

    final age = DateTime.now().difference(entry.createdAt);

    if (age > _seriesInfoCacheLifetime) {
      _seriesInfoCache.remove(tmdbId);

      return null;
    }

    return entry.info;
  }

  static Future<T> _withSeriesInfoPermit<T>(Future<T> Function() task) async {
    if (_activeSeriesInfoRequests >= _maxSeriesInfoConcurrentRequests) {
      final waiter = Completer<void>();

      _seriesInfoWaiters.add(waiter);

      await waiter.future;
    }

    _activeSeriesInfoRequests++;

    try {
      return await task();
    } finally {
      _activeSeriesInfoRequests--;

      if (_seriesInfoWaiters.isNotEmpty) {
        final next = _seriesInfoWaiters.removeAt(0);

        if (!next.isCompleted) {
          next.complete();
        }
      }
    }
  }

  static Future<TmdbSeriesInfo?> fetchSeriesSeasonInfo(
    String tmdbId, {
    bool forceRefresh = false,
  }) {
    if (!forceRefresh) {
      final cached = getCachedSeriesSeasonInfo(tmdbId);

      if (cached != null) {
        return Future<TmdbSeriesInfo?>.value(cached);
      }
    }

    final existing = _seriesInfoInFlight[tmdbId];

    if (existing != null) {
      return existing;
    }

    late final Future<TmdbSeriesInfo?> request;

    request =
        _withSeriesInfoPermit<TmdbSeriesInfo?>(() async {
          try {
            final url = Uri.parse('$_baseUrl/tv/$tmdbId').replace(
              queryParameters: const <String, String>{
                'api_key': _apiKey,
                'language': 'en-US',
              },
            );

            final data = await _getJson(url);

            int? seasonNumber;
            bool hasUpcomingEpisode = false;

            final nextEpisode = data['next_episode_to_air'];

            if (nextEpisode is Map) {
              final nextSeason = (nextEpisode['season_number'] as num?)
                  ?.toInt();

              if (nextSeason != null && nextSeason > 0) {
                seasonNumber = nextSeason;

                hasUpcomingEpisode = true;
              }
            }

            if (seasonNumber == null) {
              final lastEpisode = data['last_episode_to_air'];

              if (lastEpisode is Map) {
                final lastSeason = (lastEpisode['season_number'] as num?)
                    ?.toInt();

                if (lastSeason != null && lastSeason > 0) {
                  seasonNumber = lastSeason;
                }
              }
            }

            seasonNumber ??= (data['number_of_seasons'] as num?)?.toInt();

            TmdbSeriesInfo? info;

            if (seasonNumber != null && seasonNumber > 0) {
              info = TmdbSeriesInfo(
                seasonNumber: seasonNumber,
                hasUpcomingEpisode: hasUpcomingEpisode,
              );
            }

            _seriesInfoCache[tmdbId] = _TmdbSeriesInfoCacheEntry(
              info: info,
              createdAt: DateTime.now(),
            );

            return info;
          } catch (_) {
            return null;
          }
        }).whenComplete(() {
          _seriesInfoInFlight.remove(tmdbId);
        });

    _seriesInfoInFlight[tmdbId] = request;

    return request;
  }

  static TmdbSeasonProgressInfo? _readSeasonProgressCache(String key) {
    final entry = _seasonProgressCache[key];

    if (entry == null) {
      return null;
    }

    if (DateTime.now().difference(entry.createdAt) >
        _seasonProgressCacheLifetime) {
      _seasonProgressCache.remove(key);

      return null;
    }

    return entry.info;
  }

  static TmdbSeasonProgressInfo? getCachedSeasonProgressByImdbId(
    String imdbId,
    int season,
  ) {
    return _readSeasonProgressCache('imdb:${imdbId.trim()}:$season');
  }

  static TmdbSeasonProgressInfo? getCachedSeasonProgressByTmdbId(
    String tmdbId,
    int season,
  ) {
    return _readSeasonProgressCache('tmdb:${tmdbId.trim()}:$season');
  }

  static Future<String?> _findTmdbTvIdByImdbId(String imdbId) async {
    final cleanId = imdbId.trim();

    if (!cleanId.startsWith('tt')) {
      return null;
    }

    final cached = _imdbToTmdbTvIdCache[cleanId];

    if (cached != null &&
        DateTime.now().difference(cached.createdAt) <=
            _externalIdCacheLifetime) {
      return cached.tmdbId;
    }

    try {
      final url = Uri.parse('$_baseUrl/find/$cleanId').replace(
        queryParameters: const <String, String>{
          'api_key': _apiKey,
          'external_source': 'imdb_id',
          'language': 'en-US',
        },
      );

      final data = await _getJson(url);

      final rawResults = data['tv_results'];

      if (rawResults is! List || rawResults.isEmpty) {
        return null;
      }

      for (final raw in rawResults) {
        if (raw is! Map) {
          continue;
        }

        final id = raw['id']?.toString();

        if (id == null || id.isEmpty) {
          continue;
        }

        _imdbToTmdbTvIdCache[cleanId] = (tmdbId: id, createdAt: DateTime.now());

        return id;
      }
    } catch (_) {
      return null;
    }

    return null;
  }

  static Future<TmdbSeasonProgressInfo?> fetchSeasonProgressByImdbId(
    String imdbId,
    int season, {
    bool forceRefresh = false,
  }) async {
    final cleanId = imdbId.trim();

    if (season < 1 || !cleanId.startsWith('tt')) {
      return null;
    }

    final key = 'imdb:$cleanId:$season';

    if (!forceRefresh) {
      final cached = _readSeasonProgressCache(key);

      if (cached != null) {
        return cached;
      }
    }

    final existing = _seasonProgressInFlight[key];

    if (existing != null) {
      return existing;
    }

    late final Future<TmdbSeasonProgressInfo?> request;

    request =
        _withSeriesInfoPermit<TmdbSeasonProgressInfo?>(() async {
              final tmdbId = await _findTmdbTvIdByImdbId(cleanId);

              if (tmdbId == null) {
                return null;
              }

              return _fetchSeasonProgressFromTmdbId(tmdbId, season);
            })
            .then((info) {
              if (info != null) {
                _seasonProgressCache[key] = _TmdbSeasonProgressCacheEntry(
                  info: info,
                  createdAt: DateTime.now(),
                );
              }

              return info;
            })
            .whenComplete(() {
              _seasonProgressInFlight.remove(key);
            });

    _seasonProgressInFlight[key] = request;

    return request;
  }

  static Future<TmdbSeasonProgressInfo?> fetchSeasonProgressByTmdbId(
    String tmdbId,
    int season, {
    bool forceRefresh = false,
  }) {
    final cleanId = tmdbId.trim();

    if (season < 1 || cleanId.isEmpty) {
      return Future<TmdbSeasonProgressInfo?>.value(null);
    }

    final key = 'tmdb:$cleanId:$season';

    if (!forceRefresh) {
      final cached = _readSeasonProgressCache(key);

      if (cached != null) {
        return Future<TmdbSeasonProgressInfo?>.value(cached);
      }
    }

    final existing = _seasonProgressInFlight[key];

    if (existing != null) {
      return existing;
    }

    late final Future<TmdbSeasonProgressInfo?> request;

    request =
        _withSeriesInfoPermit<TmdbSeasonProgressInfo?>(() async {
              return _fetchSeasonProgressFromTmdbId(cleanId, season);
            })
            .then((info) {
              if (info != null) {
                _seasonProgressCache[key] = _TmdbSeasonProgressCacheEntry(
                  info: info,
                  createdAt: DateTime.now(),
                );
              }

              return info;
            })
            .whenComplete(() {
              _seasonProgressInFlight.remove(key);
            });

    _seasonProgressInFlight[key] = request;

    return request;
  }

  static Future<TmdbSeasonProgressInfo?> _fetchSeasonProgressFromTmdbId(
    String tmdbId,
    int season,
  ) async {
    try {
      final tvUrl = Uri.parse('$_baseUrl/tv/$tmdbId').replace(
        queryParameters: const <String, String>{
          'api_key': _apiKey,
          'language': 'en-US',
        },
      );

      final tvData = await _getJson(tvUrl);

      final seasonUrl = Uri.parse('$_baseUrl/tv/$tmdbId/season/$season')
          .replace(
            queryParameters: const <String, String>{
              'api_key': _apiKey,
              'language': 'en-US',
            },
          );

      Map<String, dynamic>? seasonData;

      try {
        seasonData = await _getJson(seasonUrl);
      } catch (_) {
        seasonData = null;
      }

      final now = DateTime.now();

      final today = _dateOnly(now);

      int knownEpisodeCount = 0;

      int lastAiredEpisode = 0;

      int? nextEpisode;

      bool hasFutureEpisodeInSeason = false;

      final rawSeasons = tvData['seasons'];

      if (rawSeasons is List) {
        for (final raw in rawSeasons) {
          if (raw is! Map) {
            continue;
          }

          final seasonNumber = (raw['season_number'] as num?)?.toInt();

          if (seasonNumber != season) {
            continue;
          }

          final episodeCount = (raw['episode_count'] as num?)?.toInt();

          if (episodeCount != null &&
              episodeCount > 0 &&
              episodeCount > knownEpisodeCount) {
            knownEpisodeCount = episodeCount;
          }

          break;
        }
      }

      int? upcomingSeason;
      int? upcomingEpisode;
      DateTime? upcomingAirDate;

      final rawEpisodes = seasonData?['episodes'];

      if (rawEpisodes is List) {
        for (final raw in rawEpisodes) {
          if (raw is! Map) {
            continue;
          }

          final episodeNumber = (raw['episode_number'] as num?)?.toInt();

          if (episodeNumber == null || episodeNumber < 1) {
            continue;
          }

          if (episodeNumber > knownEpisodeCount) {
            knownEpisodeCount = episodeNumber;
          }

          final airDate = _parseDateOnly(raw['air_date']);

          if (airDate == null) {
            continue;
          }

          if (!airDate.isAfter(today)) {
            if (episodeNumber > lastAiredEpisode) {
              lastAiredEpisode = episodeNumber;
            }
          } else {
            hasFutureEpisodeInSeason = true;

            final shouldReplace =
                upcomingAirDate == null ||
                airDate.isBefore(upcomingAirDate) ||
                (airDate == upcomingAirDate &&
                    (upcomingEpisode == null ||
                        episodeNumber < upcomingEpisode));

            if (shouldReplace) {
              upcomingSeason = season;

              upcomingEpisode = episodeNumber;

              upcomingAirDate = airDate;
            }

            if (nextEpisode == null || episodeNumber < nextEpisode) {
              nextEpisode = episodeNumber;
            }
          }
        }
      }

      final lastEpisodeToAir = tvData['last_episode_to_air'];

      int lastOverallSeason = 0;

      if (lastEpisodeToAir is Map) {
        final lastSeason = (lastEpisodeToAir['season_number'] as num?)?.toInt();

        final lastEpisode = (lastEpisodeToAir['episode_number'] as num?)
            ?.toInt();

        if (lastSeason != null) {
          lastOverallSeason = lastSeason;
        }

        if (lastSeason == season && lastEpisode != null && lastEpisode > 0) {
          if (lastEpisode > lastAiredEpisode) {
            lastAiredEpisode = lastEpisode;
          }

          if (lastEpisode > knownEpisodeCount) {
            knownEpisodeCount = lastEpisode;
          }
        }
      }

      final nextEpisodeToAir = tvData['next_episode_to_air'];

      int nextOverallSeason = 0;

      if (nextEpisodeToAir is Map) {
        final nextSeason = (nextEpisodeToAir['season_number'] as num?)?.toInt();

        final nextNumber = (nextEpisodeToAir['episode_number'] as num?)
            ?.toInt();

        final nextAirDate = _parseDateOnly(nextEpisodeToAir['air_date']);

        if (nextSeason != null) {
          nextOverallSeason = nextSeason;
        }

        if (nextSeason != null &&
            nextSeason > 0 &&
            nextNumber != null &&
            nextNumber > 0) {
          upcomingSeason = nextSeason;

          upcomingEpisode = nextNumber;

          upcomingAirDate = nextAirDate;
        }

        if (nextSeason == season && nextNumber != null && nextNumber > 0) {
          nextEpisode = nextNumber;

          hasFutureEpisodeInSeason = true;

          if (nextNumber > knownEpisodeCount) {
            knownEpisodeCount = nextNumber;
          }
        }
      }

      final numberOfSeasons =
          ((tvData['number_of_seasons'] as num?)?.toInt() ?? season).clamp(
            1,
            9999,
          );

      final status = tvData['status']?.toString().trim().toLowerCase() ?? '';

      final inProduction = tvData['in_production'] == true;

      final seriesEnded =
          status == 'ended' || status == 'canceled' || status == 'cancelled';

      bool isFinal = false;

      if (season < numberOfSeasons ||
          lastOverallSeason > season ||
          nextOverallSeason > season) {
        isFinal = knownEpisodeCount > 0;
      }

      if (!isFinal &&
          seriesEnded &&
          !hasFutureEpisodeInSeason &&
          knownEpisodeCount > 0) {
        isFinal = true;
      }

      if (!isFinal &&
          !inProduction &&
          !hasFutureEpisodeInSeason &&
          nextEpisode == null &&
          knownEpisodeCount > 0 &&
          lastAiredEpisode >= knownEpisodeCount) {
        isFinal = true;
      }

      if (lastAiredEpisode > knownEpisodeCount) {
        knownEpisodeCount = lastAiredEpisode;
      }

      final requestedNextEpisode = nextEpisode;

      if (requestedNextEpisode != null &&
          requestedNextEpisode > knownEpisodeCount) {
        knownEpisodeCount = requestedNextEpisode;
      }

      final globalUpcomingDate = upcomingAirDate;

      if (globalUpcomingDate != null && globalUpcomingDate.isBefore(today)) {
        upcomingSeason = null;

        upcomingEpisode = null;

        upcomingAirDate = null;
      }

      final hasUpcoming = upcomingSeason != null && upcomingEpisode != null;

      return TmdbSeasonProgressInfo(
        tmdbId: tmdbId,
        seasonNumber: season,
        totalSeasons: numberOfSeasons,
        knownEpisodeCount: knownEpisodeCount,
        lastAiredEpisode: lastAiredEpisode,
        nextEpisode: nextEpisode,
        upcomingSeason: upcomingSeason,
        upcomingEpisode: upcomingEpisode,
        upcomingAirDate: upcomingAirDate,
        isFinal: isFinal,
        hasUpcomingEpisode: hasUpcoming,
        seriesEnded: seriesEnded,
      );
    } catch (_) {
      return null;
    }
  }

  // ==========================================================
  // PERSON SEARCH + DETAILS + CREDITS
  // ==========================================================

  static Future<TmdbPersonSummary?> searchPerson(
    String name, {
    String? departmentHint,
  }) async {
    final cleanName = name.trim();

    if (cleanName.isEmpty || cleanName == 'N/A') {
      return null;
    }

    try {
      final url = Uri.parse('$_baseUrl/search/person').replace(
        queryParameters: <String, String>{
          'api_key': _apiKey,
          'query': cleanName,
          'include_adult': 'false',
          'language': 'en-US',
          'page': '1',
        },
      );

      final data = await _getJson(url);
      final rawResults = data['results'];

      if (rawResults is! List || rawResults.isEmpty) {
        return null;
      }

      final normalizedHint = departmentHint?.trim().toLowerCase() ?? '';
      TmdbPersonSummary? fallback;

      for (final raw in rawResults) {
        if (raw is! Map) {
          continue;
        }

        final map = Map<String, dynamic>.from(raw);
        final id = map['id']?.toString().trim() ?? '';
        final personName = map['name']?.toString().trim() ?? '';

        if (id.isEmpty || personName.isEmpty) {
          continue;
        }

        final department = map['known_for_department']?.toString().trim() ?? '';

        final summary = TmdbPersonSummary(
          id: id,
          name: personName,
          knownForDepartment: department,
          profilePath: map['profile_path']?.toString(),
          popularity: (map['popularity'] as num?)?.toDouble() ?? 0.0,
        );

        fallback ??= summary;

        final exactName = personName.toLowerCase() == cleanName.toLowerCase();

        final departmentMatches =
            normalizedHint.isEmpty ||
            department.toLowerCase().contains(normalizedHint) ||
            (normalizedHint == 'director' &&
                department.toLowerCase().contains('directing')) ||
            (normalizedHint == 'actor' &&
                department.toLowerCase().contains('acting'));

        if (exactName && departmentMatches) {
          return summary;
        }
      }

      return fallback;
    } catch (_) {
      return null;
    }
  }

  static Future<TmdbPersonDetails?> fetchPersonDetails(
    String personId, {
    bool forceRefresh = false,
  }) {
    final cleanId = personId.trim();

    if (cleanId.isEmpty) {
      return Future<TmdbPersonDetails?>.value(null);
    }

    if (!forceRefresh) {
      final cached = _personDetailsCache[cleanId];

      if (cached != null &&
          DateTime.now().difference(cached.createdAt) <= _personCacheLifetime) {
        return Future<TmdbPersonDetails?>.value(cached.details);
      }
    }

    final existing = _personDetailsInFlight[cleanId];

    if (existing != null) {
      return existing;
    }

    late final Future<TmdbPersonDetails?> request;

    request = (() async {
      try {
        final detailsUrl = Uri.parse('$_baseUrl/person/$cleanId').replace(
          queryParameters: const <String, String>{
            'api_key': _apiKey,
            'language': 'en-US',
          },
        );

        final creditsUrl =
            Uri.parse('$_baseUrl/person/$cleanId/combined_credits').replace(
              queryParameters: const <String, String>{
                'api_key': _apiKey,
                'language': 'en-US',
              },
            );

        final responses = await Future.wait<Map<String, dynamic>?>([
          _getJson(
            detailsUrl,
          ).then<Map<String, dynamic>?>((value) => value, onError: (_) => null),
          _getJson(
            creditsUrl,
          ).then<Map<String, dynamic>?>((value) => value, onError: (_) => null),
        ]);

        final detailsData = responses[0];

        if (detailsData == null) {
          return null;
        }

        final knownForDepartment =
            detailsData['known_for_department']?.toString().trim() ?? '';

        final credits = _parsePersonCredits(
          responses[1],
          knownForDepartment: knownForDepartment,
          limit: 20,
        );

        final details = TmdbPersonDetails(
          id: cleanId,
          name: detailsData['name']?.toString().trim() ?? '',
          knownForDepartment: knownForDepartment,
          biography: detailsData['biography']?.toString().trim() ?? '',
          birthday: detailsData['birthday']?.toString().trim() ?? '',
          deathday: detailsData['deathday']?.toString().trim() ?? '',
          placeOfBirth: detailsData['place_of_birth']?.toString().trim() ?? '',
          profilePath: detailsData['profile_path']?.toString(),
          popularity: (detailsData['popularity'] as num?)?.toDouble() ?? 0.0,
          knownFor: List<TmdbDiscoverItem>.unmodifiable(credits),
        );

        _personDetailsCache[cleanId] = _TmdbPersonDetailsCacheEntry(
          details: details,
          createdAt: DateTime.now(),
        );

        return details;
      } catch (_) {
        return null;
      } finally {
        _personDetailsInFlight.remove(cleanId);
      }
    })();

    _personDetailsInFlight[cleanId] = request;

    return request;
  }

  static List<TmdbDiscoverItem> _parsePersonCredits(
    Map<String, dynamic>? data, {
    required String knownForDepartment,
    int limit = 20,
  }) {
    if (data == null) {
      return const <TmdbDiscoverItem>[];
    }

    final combined = <Map<String, dynamic>>[];

    void addRaw(dynamic rawList, String source) {
      if (rawList is! List) {
        return;
      }

      for (final raw in rawList) {
        if (raw is! Map) {
          continue;
        }

        final map = Map<String, dynamic>.from(raw);

        if (map['adult'] == true) {
          continue;
        }

        final mediaType =
            map['media_type']?.toString().trim().toLowerCase() ?? '';

        if (mediaType != 'movie' && mediaType != 'tv') {
          continue;
        }

        if (map['poster_path'] == null ||
            map['poster_path'].toString().trim().isEmpty) {
          continue;
        }

        map['_credit_source'] = source;
        combined.add(map);
      }
    }

    addRaw(data['cast'], 'cast');
    addRaw(data['crew'], 'crew');

    final department = knownForDepartment.toLowerCase();

    combined.sort((a, b) {
      int priority(Map<String, dynamic> item) {
        final source = item['_credit_source']?.toString() ?? '';
        final job = item['job']?.toString().toLowerCase() ?? '';

        if (department.contains('acting')) {
          return source == 'cast' ? 0 : 2;
        }

        if (department.contains('directing')) {
          if (job == 'director') {
            return 0;
          }

          return source == 'crew' ? 1 : 2;
        }

        return 1;
      }

      final p = priority(a).compareTo(priority(b));

      if (p != 0) {
        return p;
      }

      final bPopularity = (b['popularity'] as num?)?.toDouble() ?? 0.0;
      final aPopularity = (a['popularity'] as num?)?.toDouble() ?? 0.0;

      final popularityCompare = bPopularity.compareTo(aPopularity);

      if (popularityCompare != 0) {
        return popularityCompare;
      }

      final bVotes = (b['vote_count'] as num?)?.toInt() ?? 0;
      final aVotes = (a['vote_count'] as num?)?.toInt() ?? 0;

      return bVotes.compareTo(aVotes);
    });

    final unique = <String, TmdbDiscoverItem>{};

    for (final map in combined) {
      final mediaType =
          map['media_type']?.toString().trim().toLowerCase() ?? '';

      final item = TmdbDiscoverItem.fromJson(map, defaultType: mediaType);

      if (item.id.trim().isEmpty || item.title.trim().isEmpty) {
        continue;
      }

      unique[item.uniqueKey] = item;

      if (unique.length >= limit) {
        break;
      }
    }

    return unique.values.toList(growable: false);
  }

  // ==========================================================
  // SIMILAR + RECOMMENDED TITLES
  // ==========================================================

  static Future<List<TmdbDiscoverItem>> fetchSimilarAndRecommended({
    required String showId,
    required String title,
    required String type,
    int limit = 12,
    bool forceRefresh = false,
  }) {
    final cleanId = showId.trim();
    final cleanTitle = title.trim();
    final isMovie = type.trim().toLowerCase().contains('movie');
    final mediaPath = isMovie ? 'movie' : 'tv';
    final safeLimit = limit.clamp(1, 20).toInt();

    final cacheKey =
        '${mediaPath}_${cleanId.isNotEmpty ? cleanId : cleanTitle.toLowerCase()}';

    if (!forceRefresh) {
      final cached = _recommendationsCache[cacheKey];

      if (cached != null &&
          DateTime.now().difference(cached.createdAt) <=
              _recommendationsCacheLifetime) {
        return Future<List<TmdbDiscoverItem>>.value(cached.items);
      }
    }

    final existing = _recommendationsInFlight[cacheKey];

    if (existing != null) {
      return existing;
    }

    late final Future<List<TmdbDiscoverItem>> request;

    request = (() async {
      try {
        final tmdbId = await _resolveTmdbIdForSavedTitle(
          showId: cleanId,
          title: cleanTitle,
          mediaPath: mediaPath,
        );

        if (tmdbId == null || tmdbId.isEmpty) {
          return const <TmdbDiscoverItem>[];
        }

        final recommendationUrl =
            Uri.parse('$_baseUrl/$mediaPath/$tmdbId/recommendations').replace(
              queryParameters: const <String, String>{
                'api_key': _apiKey,
                'language': 'en-US',
                'page': '1',
              },
            );

        final similarUrl = Uri.parse('$_baseUrl/$mediaPath/$tmdbId/similar')
            .replace(
              queryParameters: const <String, String>{
                'api_key': _apiKey,
                'language': 'en-US',
                'page': '1',
              },
            );

        final responses = await Future.wait<Map<String, dynamic>?>([
          _getJson(
            recommendationUrl,
          ).then<Map<String, dynamic>?>((value) => value, onError: (_) => null),
          _getJson(
            similarUrl,
          ).then<Map<String, dynamic>?>((value) => value, onError: (_) => null),
        ]);

        final combined = <TmdbDiscoverItem>[];

        void addResults(Map<String, dynamic>? data) {
          final rawResults = data?['results'];

          if (rawResults is! List) {
            return;
          }

          for (final raw in rawResults) {
            if (raw is! Map) {
              continue;
            }

            final map = Map<String, dynamic>.from(raw);

            if (map['adult'] == true) {
              continue;
            }

            final item = TmdbDiscoverItem.fromJson(map, defaultType: mediaPath);

            if (item.id == tmdbId ||
                item.title.trim().isEmpty ||
                item.posterPath == null ||
                item.posterPath!.trim().isEmpty) {
              continue;
            }

            combined.add(item);
          }
        }

        addResults(responses[0]);
        addResults(responses[1]);

        final unique = _removeDuplicates(
          combined,
        ).take(safeLimit).toList(growable: false);

        final result = List<TmdbDiscoverItem>.unmodifiable(unique);

        _recommendationsCache[cacheKey] = _TmdbRecommendationsCacheEntry(
          items: result,
          createdAt: DateTime.now(),
        );

        return result;
      } catch (_) {
        return const <TmdbDiscoverItem>[];
      } finally {
        _recommendationsInFlight.remove(cacheKey);
      }
    })();

    _recommendationsInFlight[cacheKey] = request;
    return request;
  }

  static Future<String?> _resolveTmdbIdForSavedTitle({
    required String showId,
    required String title,
    required String mediaPath,
  }) async {
    if (mediaPath == 'tv' && showId.startsWith('tmdb_tv_')) {
      final value = showId.substring('tmdb_tv_'.length).trim();
      if (value.isNotEmpty) return value;
    }

    if (mediaPath == 'movie' && showId.startsWith('tmdb_movie_')) {
      final value = showId.substring('tmdb_movie_'.length).trim();
      if (value.isNotEmpty) return value;
    }

    if (showId.startsWith('tt')) {
      try {
        final url = Uri.parse('$_baseUrl/find/$showId').replace(
          queryParameters: const <String, String>{
            'api_key': _apiKey,
            'external_source': 'imdb_id',
            'language': 'en-US',
          },
        );

        final data = await _getJson(url);
        final rawResults = mediaPath == 'movie'
            ? data['movie_results']
            : data['tv_results'];

        if (rawResults is List) {
          for (final raw in rawResults) {
            if (raw is! Map) continue;
            final id = raw['id']?.toString().trim();
            if (id != null && id.isNotEmpty) return id;
          }
        }
      } catch (_) {}
    }

    if (title.trim().isEmpty) {
      return null;
    }

    try {
      final endpoint = mediaPath == 'movie' ? 'search/movie' : 'search/tv';

      final url = Uri.parse('$_baseUrl/$endpoint').replace(
        queryParameters: <String, String>{
          'api_key': _apiKey,
          'query': title.trim(),
          'include_adult': 'false',
          'language': 'en-US',
          'page': '1',
        },
      );

      final data = await _getJson(url);
      final rawResults = data['results'];

      if (rawResults is List) {
        for (final raw in rawResults) {
          if (raw is! Map) continue;
          final id = raw['id']?.toString().trim();
          if (id != null && id.isNotEmpty) return id;
        }
      }
    } catch (_) {}

    return null;
  }

  // ==========================================================
  // MEDIA DETAILS + POSTER GALLERY
  // ==========================================================
  //
  // Used by Details screen for:
  // - backdrop image
  // - alternate TMDB backdrops for swipe gallery
  // - high-resolution primary poster
  // - alternate TMDB posters for swipe gallery
  //
  // ==========================================================

  static Future<TmdbMediaData?> fetchMediaDetails(
    String title,
    String type,
  ) async {
    try {
      final isMovie = type.toLowerCase().contains('movie');

      final endpoint = isMovie ? 'search/movie' : 'search/tv';

      final mediaPath = isMovie ? 'movie' : 'tv';

      final url = Uri.parse('$_baseUrl/$endpoint').replace(
        queryParameters: <String, String>{
          'api_key': _apiKey,
          'query': title,
          'include_adult': 'false',
          'language': 'en-US',
        },
      );

      final data = await _getJson(url);

      final rawResults = data['results'];

      if (rawResults is! List || rawResults.isEmpty) {
        return null;
      }

      final results = rawResults
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();

      if (results.isEmpty) {
        return null;
      }

      final match = results.firstWhere(
        (item) => item['poster_path'] != null || item['backdrop_path'] != null,
        orElse: () => results.first,
      );

      final tmdbId = match['id']?.toString();

      final backdropPath = match['backdrop_path']?.toString();

      final posterPath = match['poster_path']?.toString();

      final backdropUrl = _tmdbImageUrl(backdropPath, size: 'w1280');

      final hdBackdropUrl = _tmdbImageUrl(backdropPath, size: 'original');

      final hdPosterUrl = _tmdbImageUrl(posterPath, size: 'original');

      final backdropUrls = <String>[];
      final posterUrls = <String>[];

      _addUniquePosterUrl(backdropUrls, hdBackdropUrl);
      _addUniquePosterUrl(posterUrls, hdPosterUrl);

      if (tmdbId != null && tmdbId.trim().isNotEmpty) {
        final mediaImages = await _fetchMediaImageUrlsForTmdbId(
          tmdbId.trim(),
          mediaPath,
        );

        for (final backdrop in mediaImages.backdrops) {
          _addUniquePosterUrl(backdropUrls, backdrop);

          if (backdropUrls.length >= 10) {
            break;
          }
        }

        for (final posterUrl in mediaImages.posters) {
          _addUniquePosterUrl(posterUrls, posterUrl);

          if (posterUrls.length >= 12) {
            break;
          }
        }
      }

      return TmdbMediaData(
        backdropUrl: backdropUrl,
        hdPosterUrl: hdPosterUrl,
        backdropUrls: List<String>.unmodifiable(backdropUrls),
        posterUrls: List<String>.unmodifiable(posterUrls),
      );
    } catch (_) {
      return null;
    }
  }

  static Future<({List<String> backdrops, List<String> posters})>
  _fetchMediaImageUrlsForTmdbId(String tmdbId, String mediaPath) async {
    try {
      final url = Uri.parse('$_baseUrl/$mediaPath/$tmdbId/images').replace(
        queryParameters: const <String, String>{
          'api_key': _apiKey,
          'include_image_language': 'en,null',
        },
      );

      final data = await _getJson(url);

      List<Map<String, dynamic>> normalizeImages(dynamic rawImages) {
        if (rawImages is! List || rawImages.isEmpty) {
          return <Map<String, dynamic>>[];
        }

        final images = rawImages
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList();

        images.sort((a, b) {
          final bVote = (b['vote_average'] as num?)?.toDouble() ?? 0.0;
          final aVote = (a['vote_average'] as num?)?.toDouble() ?? 0.0;

          final voteCompare = bVote.compareTo(aVote);

          if (voteCompare != 0) {
            return voteCompare;
          }

          final bCount = (b['vote_count'] as num?)?.toInt() ?? 0;
          final aCount = (a['vote_count'] as num?)?.toInt() ?? 0;

          return bCount.compareTo(aCount);
        });

        return images;
      }

      final backdropMaps = normalizeImages(data['backdrops']);
      final posterMaps = normalizeImages(data['posters']);

      final backdropUrls = <String>[];
      final posterUrls = <String>[];

      for (final backdrop in backdropMaps) {
        final filePath = backdrop['file_path']?.toString();
        final imageUrl = _tmdbImageUrl(filePath, size: 'original');

        _addUniquePosterUrl(backdropUrls, imageUrl);

        if (backdropUrls.length >= 10) {
          break;
        }
      }

      for (final poster in posterMaps) {
        final filePath = poster['file_path']?.toString();
        final imageUrl = _tmdbImageUrl(filePath, size: 'original');

        _addUniquePosterUrl(posterUrls, imageUrl);

        if (posterUrls.length >= 12) {
          break;
        }
      }

      return (
        backdrops: List<String>.unmodifiable(backdropUrls),
        posters: List<String>.unmodifiable(posterUrls),
      );
    } catch (_) {
      return (backdrops: const <String>[], posters: const <String>[]);
    }
  }

  static Future<String?> getImdbId(String tmdbId, String mediaType) async {
    try {
      final endpoint = mediaType == 'tv'
          ? 'tv/$tmdbId/external_ids'
          : 'movie/$tmdbId/external_ids';

      final url = Uri.parse(
        '$_baseUrl/$endpoint',
      ).replace(queryParameters: const <String, String>{'api_key': _apiKey});

      final data = await _getJson(url);

      final imdbId = data['imdb_id']?.toString();

      if (imdbId == null || imdbId.trim().isEmpty) {
        return null;
      }

      return imdbId;
    } catch (_) {
      return null;
    }
  }

  // ==========================================================
  // SEARCH MOVIES + SERIES
  // ==========================================================

  static Future<List<TmdbDiscoverItem>> searchTitles(
    String query, {
    int page = 1,
  }) async {
    final cleanQuery = query.trim();

    if (cleanQuery.length < 2) {
      return const <TmdbDiscoverItem>[];
    }

    final safePage = page < 1 ? 1 : page;

    final url = Uri.parse('$_baseUrl/search/multi').replace(
      queryParameters: <String, String>{
        'api_key': _apiKey,
        'query': cleanQuery,
        'page': safePage.toString(),
        'include_adult': 'false',
        'language': 'en-US',
      },
    );

    final data = await _getJson(url);
    final rawResults = data['results'];

    if (rawResults is! List) {
      return const <TmdbDiscoverItem>[];
    }

    final items = <TmdbDiscoverItem>[];

    for (final raw in rawResults) {
      if (raw is! Map) {
        continue;
      }

      final map = Map<String, dynamic>.from(raw);
      final mediaType = map['media_type']?.toString().trim().toLowerCase();

      if (mediaType != 'movie' && mediaType != 'tv') {
        continue;
      }

      final item = TmdbDiscoverItem.fromJson(map);

      if (item.title.trim().isEmpty || item.id.trim().isEmpty) {
        continue;
      }

      items.add(item);
    }

    return _removeDuplicates(items);
  }

  static Future<List<TmdbDiscoverItem>> fetchTrending({
    bool forceRefresh = false,
  }) async {
    try {
      final results =
          await Future.wait<TmdbPageResult>(<Future<TmdbPageResult>>[
            fetchDiscoverPage(
              section: TmdbDiscoverSection.trending,
              mediaType: TmdbMediaType.movie,
              page: 1,
              forceRefresh: forceRefresh,
            ),
            fetchDiscoverPage(
              section: TmdbDiscoverSection.trending,
              mediaType: TmdbMediaType.tv,
              page: 1,
              forceRefresh: forceRefresh,
            ),
          ]);

      return _removeDuplicates(<TmdbDiscoverItem>[
        ...results[0].items,
        ...results[1].items,
      ]);
    } catch (_) {
      return <TmdbDiscoverItem>[];
    }
  }

  static Future<List<TmdbDiscoverItem>> fetchNowPlaying({
    bool forceRefresh = false,
  }) async {
    try {
      final page1 = await fetchDiscoverPage(
        section: TmdbDiscoverSection.newReleases,
        mediaType: TmdbMediaType.movie,
        page: 1,
        forceRefresh: forceRefresh,
      );

      final page2 = await fetchDiscoverPage(
        section: TmdbDiscoverSection.newReleases,
        mediaType: TmdbMediaType.movie,
        page: 2,
        forceRefresh: forceRefresh,
      );

      final items = _removeDuplicates(<TmdbDiscoverItem>[
        ...page1.items,
        ...page2.items,
      ]);

      items.sort((a, b) => b.releaseDate.compareTo(a.releaseDate));

      return items;
    } catch (_) {
      return <TmdbDiscoverItem>[];
    }
  }

  static Future<List<TmdbDiscoverItem>> fetchUpcoming({
    bool forceRefresh = false,
  }) async {
    try {
      final page1 = await fetchDiscoverPage(
        section: TmdbDiscoverSection.upcoming,
        mediaType: TmdbMediaType.movie,
        page: 1,
        forceRefresh: forceRefresh,
      );

      final page2 = await fetchDiscoverPage(
        section: TmdbDiscoverSection.upcoming,
        mediaType: TmdbMediaType.movie,
        page: 2,
        forceRefresh: forceRefresh,
      );

      final items = _removeDuplicates(<TmdbDiscoverItem>[
        ...page1.items,
        ...page2.items,
      ]);

      items.sort((a, b) => a.releaseDate.compareTo(b.releaseDate));

      return items;
    } catch (_) {
      return <TmdbDiscoverItem>[];
    }
  }
}
