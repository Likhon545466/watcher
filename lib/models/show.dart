class Show {
  final String id;
  final String title;
  final String type; // Movie or Series
  final String posterUrl;
  final String yearText;
  final String genre;
  final String plot;
  final String director;
  final String writer;
  final String actors;
  final String language;
  final String awards;
  final int runtimeMinutes;
  final double rating;
  final String status;
  final String personalNote;
  final int totalSeasons;
  final int currentSeason;
  final int currentEpisode;

  final Map<int, int> seasonProgress;
  final Map<int, int> seasonEpisodeCounts;

  /// Whether this season's episode count is safe to use
  /// as a final/hard episode limit.
  final Map<int, bool> seasonEpisodeCountFinalized;

  /// Highest confirmed aired episode.
  final Map<int, int> seasonLastAiredEpisodes;

  /// Next scheduled episode number for each known season.
  final Map<int, int> seasonNextEpisodes;

  /// Only changes when the user actually starts/continues watching.
  final DateTime? lastWatchedAt;

  /// Last successful metadata refresh time.
  final DateTime? metadataUpdatedAt;

  /// Global next scheduled episode for the title.
  ///
  /// This can belong to a later season than [currentSeason].
  final int? nextEpisodeSeason;
  final int? nextEpisodeNumber;
  final DateTime? nextEpisodeAirDate;

  /// True only when TMDB confirms that the TV series itself
  /// has ended or been cancelled.
  ///
  /// A finished season alone does NOT make this true.
  final bool seriesEnded;

  // ==========================================================
  // PHASE 3 - EPISODE REMINDER
  // ==========================================================

  /// User preference for this title.
  ///
  /// When true, Watcher should keep the next known episode
  /// reminder synchronized with the latest TMDB metadata.
  final bool episodeReminderEnabled;

  /// Episode information for the reminder that was most
  /// recently scheduled successfully.
  ///
  /// These are intentionally separate from nextEpisode*.
  /// TMDB metadata may change before the notification service
  /// successfully reschedules the reminder.
  final int? reminderSeason;
  final int? reminderEpisode;
  final DateTime? reminderAirDate;

  final DateTime createdAt;
  final DateTime updatedAt;

  const Show({
    required this.id,
    required this.title,
    required this.type,
    required this.posterUrl,
    required this.yearText,
    required this.genre,
    required this.plot,
    required this.director,
    required this.writer,
    required this.actors,
    required this.language,
    required this.awards,
    required this.runtimeMinutes,
    required this.rating,
    required this.status,
    this.personalNote = '',
    required this.totalSeasons,
    required this.currentSeason,
    required this.currentEpisode,
    required this.seasonProgress,
    required this.seasonEpisodeCounts,
    this.seasonEpisodeCountFinalized = const <int, bool>{},
    this.seasonLastAiredEpisodes = const <int, int>{},
    this.seasonNextEpisodes = const <int, int>{},
    this.lastWatchedAt,
    this.metadataUpdatedAt,
    this.nextEpisodeSeason,
    this.nextEpisodeNumber,
    this.nextEpisodeAirDate,
    this.seriesEnded = false,
    this.episodeReminderEnabled = false,
    this.reminderSeason,
    this.reminderEpisode,
    this.reminderAirDate,
    required this.createdAt,
    required this.updatedAt,
  });

  // ==========================================================
  // BASIC GETTERS
  // ==========================================================

  bool get isSeries => type.toLowerCase() == 'series';

  bool get isMovie => !isSeries;

  int get releaseYear {
    final match = RegExp(r'\d{4}').firstMatch(yearText);

    return int.tryParse(match?.group(0) ?? '') ?? DateTime.now().year;
  }

  // ==========================================================
  // WATCH PROGRESS
  // ==========================================================

  int get watchedEpisodes {
    if (!isSeries) {
      return 0;
    }

    return seasonProgress.values.fold<int>(0, (sum, value) => sum + value);
  }

  int get currentSeasonEpisodeCount {
    return seasonEpisodeCounts[currentSeason] ?? 0;
  }

  bool get currentSeasonEpisodeCountIsFinal {
    return seasonEpisodeCountFinalized[currentSeason] ?? false;
  }

  int get currentSeasonLastAiredEpisode {
    return seasonLastAiredEpisodes[currentSeason] ?? 0;
  }

  int? get currentSeasonNextEpisode {
    final value = seasonNextEpisodes[currentSeason];

    if (value != null && value > 0) {
      return value;
    }

    if (nextEpisodeSeason == currentSeason &&
        nextEpisodeNumber != null &&
        nextEpisodeNumber! > 0) {
      return nextEpisodeNumber;
    }

    return null;
  }

  bool get hasUpcomingEpisode {
    return nextEpisodeNumber != null && nextEpisodeNumber! > 0;
  }

  bool isSeasonEpisodeCountFinal(int season) {
    return seasonEpisodeCountFinalized[season] ?? false;
  }

  // ==========================================================
  // EPISODE REMINDER GETTERS
  // ==========================================================

  /// True when Watcher currently has enough saved information
  /// to represent a successfully scheduled reminder.
  bool get hasScheduledEpisodeReminder {
    return episodeReminderEnabled &&
        reminderSeason != null &&
        reminderSeason! > 0 &&
        reminderEpisode != null &&
        reminderEpisode! > 0 &&
        reminderAirDate != null;
  }

  /// True when the currently scheduled reminder still matches
  /// the latest known TMDB next episode.
  ///
  /// Provider sync can use this to avoid unnecessary
  /// notification rescheduling.
  bool get reminderMatchesNextEpisode {
    if (!hasScheduledEpisodeReminder) {
      return false;
    }

    if (nextEpisodeSeason == null ||
        nextEpisodeNumber == null ||
        nextEpisodeAirDate == null) {
      return false;
    }

    return reminderSeason == nextEpisodeSeason &&
        reminderEpisode == nextEpisodeNumber &&
        _sameCalendarDate(reminderAirDate!, nextEpisodeAirDate!);
  }

  /// Watcher can attempt scheduling only when all required
  /// upcoming episode fields are present.
  bool get hasReminderTarget {
    return isSeries &&
        nextEpisodeSeason != null &&
        nextEpisodeSeason! > 0 &&
        nextEpisodeNumber != null &&
        nextEpisodeNumber! > 0 &&
        nextEpisodeAirDate != null;
  }

  // ==========================================================
  // SERIES COMPLETION
  // ==========================================================

  /// True only when Watcher has enough trusted information to
  /// decide that the entire series can be automatically completed.
  ///
  /// Important:
  /// A finished season is not enough.
  bool get canAutoCompleteSeries {
    if (!isSeries || !seriesEnded) {
      return false;
    }

    final count = currentSeasonEpisodeCount;

    if (count <= 0) {
      return false;
    }

    if (!currentSeasonEpisodeCountIsFinal) {
      return false;
    }

    if (currentSeason < totalSeasons) {
      return false;
    }

    if (hasUpcomingEpisode) {
      return false;
    }

    return true;
  }

  /// True when the whole series is confirmed ended and the user
  /// has reached the final known episode.
  bool get isSeriesFullyWatched {
    if (!canAutoCompleteSeries) {
      return false;
    }

    return currentEpisode >= currentSeasonEpisodeCount;
  }

  // ==========================================================
  // RECENT ACTIVITY
  // ==========================================================

  DateTime get recentActivityAt {
    return lastWatchedAt ?? createdAt;
  }

  // ==========================================================
  // WATCH TIME
  // ==========================================================

  int get watchTimeMinutes {
    if (isSeries) {
      final minutesPerEpisode = runtimeMinutes > 0 ? runtimeMinutes : 45;

      return watchedEpisodes * minutesPerEpisode;
    }

    return status == 'Completed' ? runtimeMinutes : 0;
  }

  // ==========================================================
  // OMDB
  // ==========================================================

  factory Show.fromOmdb(
    Map<String, dynamic> json, {
    String status = 'Plan to Watch',
  }) {
    final type = _normalizeType(json['Type']?.toString());

    final now = DateTime.now();

    final totalSeasons =
        int.tryParse(json['totalSeasons']?.toString() ?? '') ?? 1;

    return Show(
      id: json['imdbID']?.toString().trim().isNotEmpty == true
          ? json['imdbID'].toString()
          : 'local-${now.microsecondsSinceEpoch}',
      title: _clean(json['Title'], fallback: 'Untitled'),
      type: type,
      posterUrl: _clean(json['Poster']),
      yearText: _clean(json['Year'], fallback: '${now.year}'),
      genre: _clean(json['Genre']),
      plot: _clean(json['Plot']),
      director: _clean(json['Director']),
      writer: _clean(json['Writer']),
      actors: _clean(json['Actors']),
      language: _clean(json['Language']),
      awards: _clean(json['Awards']),
      runtimeMinutes: _parseRuntime(json['Runtime']?.toString()),
      rating: double.tryParse(json['imdbRating']?.toString() ?? '') ?? 0,
      status: status,
      personalNote: '',
      totalSeasons: type == 'Series'
          ? (totalSeasons < 1 ? 1 : totalSeasons)
          : 1,
      currentSeason: 1,
      currentEpisode: 0,
      seasonProgress: const <int, int>{},
      seasonEpisodeCounts: const <int, int>{},
      seasonEpisodeCountFinalized: const <int, bool>{},
      seasonLastAiredEpisodes: const <int, int>{},
      seasonNextEpisodes: const <int, int>{},
      lastWatchedAt: null,
      metadataUpdatedAt: null,
      nextEpisodeSeason: null,
      nextEpisodeNumber: null,
      nextEpisodeAirDate: null,
      seriesEnded: false,
      episodeReminderEnabled: false,
      reminderSeason: null,
      reminderEpisode: null,
      reminderAirDate: null,
      createdAt: now,
      updatedAt: now,
    );
  }

  // ==========================================================
  // SEARCH RESULT
  // ==========================================================

  factory Show.fromSearchResult(Map<String, dynamic> json) {
    final now = DateTime.now();

    final type = _normalizeType(json['Type']?.toString());

    return Show(
      id: json['imdbID']?.toString() ?? 'local-${now.microsecondsSinceEpoch}',
      title: _clean(json['Title'], fallback: 'Untitled'),
      type: type,
      posterUrl: _clean(json['Poster']),
      yearText: _clean(json['Year'], fallback: '${now.year}'),
      genre: '',
      plot: '',
      director: '',
      writer: '',
      actors: '',
      language: '',
      awards: '',
      runtimeMinutes: type == 'Series' ? 45 : 0,
      rating: 0,
      status: 'Plan to Watch',
      personalNote: '',
      totalSeasons: 1,
      currentSeason: 1,
      currentEpisode: 0,
      seasonProgress: const <int, int>{},
      seasonEpisodeCounts: const <int, int>{},
      seasonEpisodeCountFinalized: const <int, bool>{},
      seasonLastAiredEpisodes: const <int, int>{},
      seasonNextEpisodes: const <int, int>{},
      lastWatchedAt: null,
      metadataUpdatedAt: null,
      nextEpisodeSeason: null,
      nextEpisodeNumber: null,
      nextEpisodeAirDate: null,
      seriesEnded: false,
      episodeReminderEnabled: false,
      reminderSeason: null,
      reminderEpisode: null,
      reminderAirDate: null,
      createdAt: now,
      updatedAt: now,
    );
  }

  // ==========================================================
  // JSON
  // ==========================================================

  factory Show.fromJson(Map<String, dynamic> json) {
    final type = _normalizeType(json['type']?.toString());

    final oldWatchedEpisodes = _toInt(json['watchedEpisodes']);

    final currentSeason = _toInt(
      json['currentSeason'],
      fallback: 1,
    ).clamp(1, 9999).toInt();

    final currentEpisode = _toInt(
      json['currentEpisode'],
      fallback: type == 'Series' ? oldWatchedEpisodes : 0,
    ).clamp(0, 999999).toInt();

    final progress = _intMap(json['seasonProgress']);

    if (type == 'Series' && progress.isEmpty && currentEpisode > 0) {
      progress[currentSeason] = currentEpisode;
    }

    final now = DateTime.now();

    final oldReleaseYear = _toInt(json['releaseYear'], fallback: now.year);

    return Show(
      id: json['id']?.toString() ?? 'local-${now.microsecondsSinceEpoch}',
      title: _clean(json['title'], fallback: 'Untitled'),
      type: type,
      posterUrl: _clean(json['posterUrl']),
      yearText: _clean(json['yearText'], fallback: '$oldReleaseYear'),
      genre: _clean(json['genre']),
      plot: _clean(json['plot']),
      director: _clean(json['director']),
      writer: _clean(json['writer']),
      actors: _clean(json['actors']),
      language: _clean(json['language']),
      awards: _clean(json['awards']),
      runtimeMinutes: _toInt(
        json['runtimeMinutes'],
        fallback: type == 'Series' ? 45 : 0,
      ),
      rating: _toDouble(json['rating']),
      status: _normalizeStatus(json['status']?.toString()),
      personalNote: _clean(json['personalNote']),
      totalSeasons: _toInt(
        json['totalSeasons'],
        fallback: 1,
      ).clamp(1, 9999).toInt(),
      currentSeason: currentSeason,
      currentEpisode: currentEpisode,
      seasonProgress: progress,
      seasonEpisodeCounts: _intMap(json['seasonEpisodeCounts']),
      seasonEpisodeCountFinalized: _boolMap(
        json['seasonEpisodeCountFinalized'],
      ),
      seasonLastAiredEpisodes: _intMap(json['seasonLastAiredEpisodes']),
      seasonNextEpisodes: _intMap(json['seasonNextEpisodes']),
      lastWatchedAt: DateTime.tryParse(json['lastWatchedAt']?.toString() ?? ''),
      metadataUpdatedAt: DateTime.tryParse(
        json['metadataUpdatedAt']?.toString() ?? '',
      ),
      nextEpisodeSeason: _nullablePositiveInt(json['nextEpisodeSeason']),
      nextEpisodeNumber: _nullablePositiveInt(json['nextEpisodeNumber']),
      nextEpisodeAirDate: DateTime.tryParse(
        json['nextEpisodeAirDate']?.toString() ?? '',
      ),

      // Old saved Watcher libraries don't have this field,
      // so they safely default to false until TMDB refreshes them.
      seriesEnded: _toBool(json['seriesEnded'], fallback: false),

      // ======================================================
      // PHASE 3 - OLD LIBRARIES SAFELY DEFAULT TO OFF
      // ======================================================
      episodeReminderEnabled: _toBool(
        json['episodeReminderEnabled'],
        fallback: false,
      ),

      reminderSeason: _nullablePositiveInt(json['reminderSeason']),

      reminderEpisode: _nullablePositiveInt(json['reminderEpisode']),

      reminderAirDate: DateTime.tryParse(
        json['reminderAirDate']?.toString() ?? '',
      ),

      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ?? now,

      updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? '') ?? now,
    );
  }

  // ==========================================================
  // TO JSON
  // ==========================================================

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'title': title,
      'type': type,
      'posterUrl': posterUrl,
      'yearText': yearText,
      'releaseYear': releaseYear,
      'genre': genre,
      'plot': plot,
      'director': director,
      'writer': writer,
      'actors': actors,
      'language': language,
      'awards': awards,
      'runtimeMinutes': runtimeMinutes,
      'rating': rating,
      'status': status,
      'personalNote': personalNote,
      'totalSeasons': totalSeasons,
      'currentSeason': currentSeason,
      'currentEpisode': currentEpisode,
      'watchedEpisodes': watchedEpisodes,

      'seasonProgress': seasonProgress.map(
        (key, value) => MapEntry('$key', value),
      ),

      'seasonEpisodeCounts': seasonEpisodeCounts.map(
        (key, value) => MapEntry('$key', value),
      ),

      'seasonEpisodeCountFinalized': seasonEpisodeCountFinalized.map(
        (key, value) => MapEntry('$key', value),
      ),

      'seasonLastAiredEpisodes': seasonLastAiredEpisodes.map(
        (key, value) => MapEntry('$key', value),
      ),

      'seasonNextEpisodes': seasonNextEpisodes.map(
        (key, value) => MapEntry('$key', value),
      ),

      'lastWatchedAt': lastWatchedAt?.toIso8601String(),

      'metadataUpdatedAt': metadataUpdatedAt?.toIso8601String(),

      'nextEpisodeSeason': nextEpisodeSeason,

      'nextEpisodeNumber': nextEpisodeNumber,

      'nextEpisodeAirDate': nextEpisodeAirDate?.toIso8601String(),

      'seriesEnded': seriesEnded,

      // ======================================================
      // PHASE 3 - REMINDER STATE
      // ======================================================
      'episodeReminderEnabled': episodeReminderEnabled,

      'reminderSeason': reminderSeason,

      'reminderEpisode': reminderEpisode,

      'reminderAirDate': reminderAirDate?.toIso8601String(),

      'createdAt': createdAt.toIso8601String(),

      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  // ==========================================================
  // COPY WITH
  // ==========================================================

  static const Object _unset = Object();

  Show copyWith({
    String? id,
    String? title,
    String? type,
    String? posterUrl,
    String? yearText,
    String? genre,
    String? plot,
    String? director,
    String? writer,
    String? actors,
    String? language,
    String? awards,
    int? runtimeMinutes,
    double? rating,
    String? status,
    String? personalNote,
    int? totalSeasons,
    int? currentSeason,
    int? currentEpisode,
    Map<int, int>? seasonProgress,
    Map<int, int>? seasonEpisodeCounts,
    Map<int, bool>? seasonEpisodeCountFinalized,
    Map<int, int>? seasonLastAiredEpisodes,
    Map<int, int>? seasonNextEpisodes,
    DateTime? lastWatchedAt,
    Object? metadataUpdatedAt = _unset,
    Object? nextEpisodeSeason = _unset,
    Object? nextEpisodeNumber = _unset,
    Object? nextEpisodeAirDate = _unset,
    bool? seriesEnded,

    // ========================================================
    // PHASE 3 - REMINDER
    // ========================================================
    bool? episodeReminderEnabled,
    Object? reminderSeason = _unset,
    Object? reminderEpisode = _unset,
    Object? reminderAirDate = _unset,

    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Show(
      id: id ?? this.id,
      title: title ?? this.title,
      type: type ?? this.type,
      posterUrl: posterUrl ?? this.posterUrl,
      yearText: yearText ?? this.yearText,
      genre: genre ?? this.genre,
      plot: plot ?? this.plot,
      director: director ?? this.director,
      writer: writer ?? this.writer,
      actors: actors ?? this.actors,
      language: language ?? this.language,
      awards: awards ?? this.awards,
      runtimeMinutes: runtimeMinutes ?? this.runtimeMinutes,
      rating: rating ?? this.rating,
      status: status ?? this.status,
      personalNote: personalNote ?? this.personalNote,
      totalSeasons: totalSeasons ?? this.totalSeasons,
      currentSeason: currentSeason ?? this.currentSeason,
      currentEpisode: currentEpisode ?? this.currentEpisode,
      seasonProgress: seasonProgress ?? this.seasonProgress,
      seasonEpisodeCounts: seasonEpisodeCounts ?? this.seasonEpisodeCounts,
      seasonEpisodeCountFinalized:
          seasonEpisodeCountFinalized ?? this.seasonEpisodeCountFinalized,
      seasonLastAiredEpisodes:
          seasonLastAiredEpisodes ?? this.seasonLastAiredEpisodes,
      seasonNextEpisodes: seasonNextEpisodes ?? this.seasonNextEpisodes,

      lastWatchedAt: lastWatchedAt ?? this.lastWatchedAt,

      metadataUpdatedAt: identical(metadataUpdatedAt, _unset)
          ? this.metadataUpdatedAt
          : metadataUpdatedAt as DateTime?,

      nextEpisodeSeason: identical(nextEpisodeSeason, _unset)
          ? this.nextEpisodeSeason
          : nextEpisodeSeason as int?,

      nextEpisodeNumber: identical(nextEpisodeNumber, _unset)
          ? this.nextEpisodeNumber
          : nextEpisodeNumber as int?,

      nextEpisodeAirDate: identical(nextEpisodeAirDate, _unset)
          ? this.nextEpisodeAirDate
          : nextEpisodeAirDate as DateTime?,

      seriesEnded: seriesEnded ?? this.seriesEnded,

      episodeReminderEnabled:
          episodeReminderEnabled ?? this.episodeReminderEnabled,

      reminderSeason: identical(reminderSeason, _unset)
          ? this.reminderSeason
          : reminderSeason as int?,

      reminderEpisode: identical(reminderEpisode, _unset)
          ? this.reminderEpisode
          : reminderEpisode as int?,

      reminderAirDate: identical(reminderAirDate, _unset)
          ? this.reminderAirDate
          : reminderAirDate as DateTime?,

      createdAt: createdAt ?? this.createdAt,

      updatedAt: updatedAt ?? DateTime.now(),
    );
  }

  // ==========================================================
  // HELPERS
  // ==========================================================

  static bool _sameCalendarDate(DateTime first, DateTime second) {
    return first.year == second.year &&
        first.month == second.month &&
        first.day == second.day;
  }

  static String _clean(dynamic value, {String fallback = ''}) {
    final text = value?.toString().trim() ?? '';

    if (text.isEmpty || text == 'N/A' || text == 'null') {
      return fallback;
    }

    if (text.contains('media-amazon.com/images/M/')) {
      return text.replaceAll(
        RegExp(r'_SX\d+_|_SY\d+_|_CR\d+,\d+,\d+,\d+_'),
        '',
      );
    }

    return text;
  }

  static String _normalizeType(String? value) {
    return value?.toLowerCase() == 'series' ? 'Series' : 'Movie';
  }

  static String _normalizeStatus(String? value) {
    const statuses = <String>{
      'Watching',
      'Completed',
      'Plan to Watch',
      'On Hold',
      'Dropped',
    };

    return statuses.contains(value) ? value! : 'Plan to Watch';
  }

  static int _parseRuntime(String? value) {
    final match = RegExp(r'\d+').firstMatch(value ?? '');

    return int.tryParse(match?.group(0) ?? '') ?? 0;
  }

  static int? _nullablePositiveInt(dynamic value) {
    final parsed = _toInt(value);

    return parsed > 0 ? parsed : null;
  }

  static int _toInt(dynamic value, {int fallback = 0}) {
    if (value is int) {
      return value;
    }

    if (value is num) {
      return value.toInt();
    }

    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  static double _toDouble(dynamic value) {
    if (value is double) {
      return value;
    }

    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  static bool _toBool(dynamic value, {bool fallback = false}) {
    if (value is bool) {
      return value;
    }

    final text = value?.toString().trim().toLowerCase();

    if (text == 'true' || text == '1') {
      return true;
    }

    if (text == 'false' || text == '0') {
      return false;
    }

    return fallback;
  }

  static Map<int, int> _intMap(dynamic value) {
    if (value is! Map) {
      return <int, int>{};
    }

    final result = <int, int>{};

    value.forEach((dynamic key, dynamic item) {
      final parsedKey = int.tryParse(key.toString());

      final parsedValue = _toInt(item);

      if (parsedKey != null && parsedKey > 0 && parsedValue >= 0) {
        result[parsedKey] = parsedValue;
      }
    });

    return result;
  }

  static Map<int, bool> _boolMap(dynamic value) {
    if (value is! Map) {
      return <int, bool>{};
    }

    final result = <int, bool>{};

    value.forEach((dynamic key, dynamic item) {
      final parsedKey = int.tryParse(key.toString());

      bool? parsedValue;

      if (item is bool) {
        parsedValue = item;
      } else {
        final text = item?.toString().toLowerCase();

        if (text == 'true') {
          parsedValue = true;
        }

        if (text == 'false') {
          parsedValue = false;
        }
      }

      if (parsedKey != null && parsedKey > 0 && parsedValue != null) {
        result[parsedKey] = parsedValue;
      }
    });

    return result;
  }
}
