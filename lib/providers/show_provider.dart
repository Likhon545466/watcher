import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/show.dart';
import '../services/notification_service.dart';
import '../services/storage_service.dart';
import '../services/tmdb_service.dart';

// ============================================================
// SERIES SYNC RESULT
// ============================================================

class _SeriesSyncResult {
  final bool changed;
  final bool success;

  const _SeriesSyncResult({required this.changed, required this.success});
}

// ============================================================
// EPISODE REMINDER RESULT
// ============================================================
//
// Used by the Details screen so it can show the correct message
// after the user enables or disables episode reminders.
//
// ============================================================

enum EpisodeReminderResult {
  scheduled,
  enabledWaitingForEpisode,
  disabled,
  permissionDenied,
  showNotFound,
  notSeries,
  statusNotEligible,
}

// ============================================================
// SHOW PROVIDER
// ============================================================

class ShowProvider with ChangeNotifier {
  static const String _seriesMetadataSyncKey =
      'watcher_series_metadata_sync_v1';

  static const Duration _seriesMetadataSyncInterval = Duration(hours: 6);

  List<Show> _shows = <Show>[];

  String _selectedCategory = 'All';
  String _searchQuery = '';

  bool _loading = true;

  bool _backgroundSeriesSyncRunning = false;

  final Map<String, Future<_SeriesSyncResult>> _seriesSyncInFlight =
      <String, Future<_SeriesSyncResult>>{};

  ShowProvider() {
    loadShows();
  }

  // ==========================================================
  // GETTERS
  // ==========================================================

  List<Show> get allShows => List<Show>.unmodifiable(_shows);

  String get selectedCategory => _selectedCategory;

  String get searchQuery => _searchQuery;

  bool get loading => _loading;

  // ==========================================================
  // FILTERED SHOWS
  // ==========================================================

  List<Show> get shows {
    Iterable<Show> filtered = _shows;

    if (_selectedCategory != 'All') {
      filtered = filtered.where((show) => show.status == _selectedCategory);
    }

    final query = _searchQuery.trim().toLowerCase();

    if (query.isNotEmpty) {
      filtered = filtered.where(
        (show) => show.title.toLowerCase().contains(query),
      );
    }

    final list = filtered.toList();

    list.sort((a, b) {
      final activity = b.recentActivityAt.compareTo(a.recentActivityAt);

      if (activity != 0) {
        return activity;
      }

      return b.createdAt.compareTo(a.createdAt);
    });

    return list;
  }

  // ==========================================================
  // FIND BY INTERNAL ID
  // ==========================================================

  Show? byId(String id) {
    for (final show in _shows) {
      if (show.id == id) {
        return show;
      }
    }

    return null;
  }

  // ==========================================================
  // PHASE 2
  // LIBRARY MATCHING
  // ==========================================================

  /// Finds an already-saved title using the safest information
  /// available.
  ///
  /// Priority:
  ///
  /// 1. Exact IMDb/internal ID
  /// 2. Exact TMDB fallback ID
  /// 3. Normalized Title + Type + Release Year
  /// 4. Title + Type only when the match is unambiguous
  Show? findLibraryMatch({
    required String title,
    required String type,
    String? yearText,
    String? exactId,
    String? tmdbId,
    String? tmdbMediaType,
  }) {
    // ========================================================
    // 1. EXACT INTERNAL / IMDB ID
    // ========================================================

    final cleanExactId = exactId?.trim() ?? '';

    if (cleanExactId.isNotEmpty) {
      for (final show in _shows) {
        if (show.id == cleanExactId) {
          return show;
        }
      }
    }

    // ========================================================
    // 2. EXACT TMDB FALLBACK ID
    // ========================================================

    final cleanTmdbId = tmdbId?.trim() ?? '';

    if (cleanTmdbId.isNotEmpty) {
      final media = _normalizeTmdbMediaType(tmdbMediaType, fallbackType: type);

      final fallbackId = 'tmdb_${media}_$cleanTmdbId';

      for (final show in _shows) {
        if (show.id == fallbackId) {
          return show;
        }
      }
    }

    // ========================================================
    // 3. TITLE + TYPE
    // ========================================================

    final normalizedTitle = _normalizeLibraryTitle(title);

    final normalizedType = _normalizeLibraryType(type);

    if (normalizedTitle.isEmpty) {
      return null;
    }

    final titleTypeMatches = _shows
        .where((show) {
          return _normalizeLibraryTitle(show.title) == normalizedTitle &&
              _normalizeLibraryType(show.type) == normalizedType;
        })
        .toList(growable: false);

    if (titleTypeMatches.isEmpty) {
      return null;
    }

    // ========================================================
    // 4. RELEASE YEAR
    // ========================================================

    final targetYear = _extractLibraryYear(yearText);

    if (targetYear != null) {
      for (final show in titleTypeMatches) {
        final showYear = _extractLibraryYear(show.yearText);

        if (showYear == targetYear) {
          return show;
        }
      }

      final unknownYearMatches = titleTypeMatches
          .where((show) => _extractLibraryYear(show.yearText) == null)
          .toList(growable: false);

      if (unknownYearMatches.length == 1) {
        return unknownYearMatches.first;
      }

      return null;
    }

    if (titleTypeMatches.length == 1) {
      return titleTypeMatches.first;
    }

    return null;
  }

  // ==========================================================
  // FIND IMDB SEARCH RESULT
  // ==========================================================

  Show? findLibraryMatchForImdb({
    required String imdbId,
    required String title,
    required String type,
    String? yearText,
  }) {
    return findLibraryMatch(
      exactId: imdbId,
      title: title,
      type: type,
      yearText: yearText,
    );
  }

  // ==========================================================
  // FIND TMDB DISCOVER RESULT
  // ==========================================================

  Show? findLibraryMatchForTmdb({
    required String tmdbId,
    required String mediaType,
    required String title,
    String? yearText,
  }) {
    final showType = mediaType.trim().toLowerCase() == 'tv'
        ? 'Series'
        : 'Movie';

    return findLibraryMatch(
      tmdbId: tmdbId,
      tmdbMediaType: mediaType,
      title: title,
      type: showType,
      yearText: yearText,
    );
  }

  // ==========================================================
  // SIMPLE LIBRARY BOOLEAN
  // ==========================================================

  bool isInLibrary({
    required String title,
    required String type,
    String? yearText,
    String? exactId,
    String? tmdbId,
    String? tmdbMediaType,
  }) {
    return findLibraryMatch(
          title: title,
          type: type,
          yearText: yearText,
          exactId: exactId,
          tmdbId: tmdbId,
          tmdbMediaType: tmdbMediaType,
        ) !=
        null;
  }

  // ==========================================================
  // NORMALIZE TITLE
  // ==========================================================

  String _normalizeLibraryTitle(String value) {
    var result = value.trim().toLowerCase();

    const punctuation = <String>[
      '-',
      '_',
      ':',
      ';',
      '.',
      ',',
      '!',
      '?',
      '\'',
      '"',
      '(',
      ')',
      '[',
      ']',
      '{',
      '}',
      '/',
      '\\',
      '&',
      '+',
    ];

    for (final character in punctuation) {
      result = result.replaceAll(character, ' ');
    }

    result = result.replaceAll(RegExp(r'\s+'), ' ');

    return result.trim();
  }

  // ==========================================================
  // NORMALIZE SHOW TYPE
  // ==========================================================

  String _normalizeLibraryType(String value) {
    final normalized = value.trim().toLowerCase();

    if (normalized == 'tv' ||
        normalized == 'series' ||
        normalized.contains('series')) {
      return 'Series';
    }

    return 'Movie';
  }

  // ==========================================================
  // NORMALIZE TMDB TYPE
  // ==========================================================

  String _normalizeTmdbMediaType(
    String? mediaType, {
    required String fallbackType,
  }) {
    final normalized = mediaType?.trim().toLowerCase();

    if (normalized == 'tv') {
      return 'tv';
    }

    if (normalized == 'movie') {
      return 'movie';
    }

    return _normalizeLibraryType(fallbackType) == 'Series' ? 'tv' : 'movie';
  }

  // ==========================================================
  // EXTRACT RELEASE YEAR
  // ==========================================================

  int? _extractLibraryYear(String? value) {
    final text = value?.trim() ?? '';

    final match = RegExp(r'(?:19|20)\d{2}').firstMatch(text);

    if (match == null) {
      return null;
    }

    return int.tryParse(match.group(0) ?? '');
  }

  // ==========================================================
  // LOAD
  // ==========================================================

  Future<void> loadShows() async {
    _loading = true;

    notifyListeners();

    final prefs = await SharedPreferences.getInstance();

    final raw = prefs.getString(StorageService.showsKey);

    if (raw == null || raw.trim().isEmpty) {
      _shows = <Show>[];
    } else {
      try {
        final decoded = jsonDecode(raw);

        if (decoded is List) {
          _shows = decoded
              .whereType<Map>()
              .map((item) => Show.fromJson(Map<String, dynamic>.from(item)))
              .toList();
        } else {
          _shows = <Show>[];
        }
      } catch (_) {
        _shows = <Show>[];
      }
    }

    _loading = false;

    notifyListeners();

    // ========================================================
    // PHASE 3
    // RECONCILE SAVED REMINDERS AFTER STARTUP
    // ========================================================
    //
    // No permission popup happens here.
    //
    // This only restores / validates reminders when permission
    // already exists.
    // ========================================================

    unawaited(_reconcileLoadedEpisodeReminders());
  }

  // ==========================================================
  // CATEGORY
  // ==========================================================

  void setCategory(String category) {
    if (_selectedCategory == category) {
      return;
    }

    _selectedCategory = category;

    notifyListeners();
  }

  // ==========================================================
  // SEARCH
  // ==========================================================

  void setSearchQuery(String query) {
    if (_searchQuery == query) {
      return;
    }

    _searchQuery = query;

    notifyListeners();
  }

  // ==========================================================
  // ADD
  // ==========================================================

  Future<bool> addShow(Show show) async {
    final duplicate = findLibraryMatch(
      exactId: show.id,
      title: show.title,
      type: show.type,
      yearText: show.yearText,
    );

    if (duplicate != null) {
      return false;
    }

    _shows.add(show.copyWith(updatedAt: DateTime.now()));

    await _save();

    notifyListeners();

    return true;
  }

  // ==========================================================
  // UPDATE
  // ==========================================================

  Future<void> updateShow(Show updatedShow) async {
    final index = _shows.indexWhere((show) => show.id == updatedShow.id);

    if (index == -1) {
      return;
    }

    final previous = _shows[index];

    final safeLastWatchedAt =
        updatedShow.lastWatchedAt ?? previous.lastWatchedAt;

    var safeUpdated = updatedShow.copyWith(
      lastWatchedAt: safeLastWatchedAt,
      updatedAt: DateTime.now(),
    );

    // ========================================================
    // PHASE 3
    // COMPLETED / DROPPED TITLES MUST NOT KEEP A REMINDER
    // ========================================================

    if (safeUpdated.isSeries &&
        (safeUpdated.status == 'Completed' ||
            safeUpdated.status == 'Dropped')) {
      safeUpdated = await _disableReminderForShow(safeUpdated);
    }

    _shows[index] = safeUpdated;

    await _save();

    notifyListeners();
  }

  // ==========================================================
  // APPLY REFRESHED DESCRIPTIVE METADATA
  // ==========================================================

  Future<bool> applyRefreshedMetadata(String id, Show metadataShow) async {
    final index = _shows.indexWhere((show) => show.id == id);

    if (index == -1) {
      return false;
    }

    final current = _shows[index];

    final now = DateTime.now();

    final merged = current.copyWith(
      title: metadataShow.title.isNotEmpty ? metadataShow.title : current.title,

      type: metadataShow.type,

      posterUrl: metadataShow.posterUrl.isNotEmpty
          ? metadataShow.posterUrl
          : current.posterUrl,

      yearText: metadataShow.yearText.isNotEmpty
          ? metadataShow.yearText
          : current.yearText,

      genre: metadataShow.genre.isNotEmpty ? metadataShow.genre : current.genre,

      plot: metadataShow.plot.isNotEmpty ? metadataShow.plot : current.plot,

      director: metadataShow.director.isNotEmpty
          ? metadataShow.director
          : current.director,

      writer: metadataShow.writer.isNotEmpty
          ? metadataShow.writer
          : current.writer,

      actors: metadataShow.actors.isNotEmpty
          ? metadataShow.actors
          : current.actors,

      language: metadataShow.language.isNotEmpty
          ? metadataShow.language
          : current.language,

      awards: metadataShow.awards.isNotEmpty
          ? metadataShow.awards
          : current.awards,

      runtimeMinutes: metadataShow.runtimeMinutes > 0
          ? metadataShow.runtimeMinutes
          : current.runtimeMinutes,

      rating: metadataShow.rating > 0 ? metadataShow.rating : current.rating,

      totalSeasons: metadataShow.totalSeasons > current.totalSeasons
          ? metadataShow.totalSeasons
          : current.totalSeasons,

      status: current.status,

      personalNote: current.personalNote,

      currentSeason: current.currentSeason,

      currentEpisode: current.currentEpisode,

      seasonProgress: current.seasonProgress,

      seasonEpisodeCounts: current.seasonEpisodeCounts,

      seasonEpisodeCountFinalized: current.seasonEpisodeCountFinalized,

      seasonLastAiredEpisodes: current.seasonLastAiredEpisodes,

      seasonNextEpisodes: current.seasonNextEpisodes,

      lastWatchedAt: current.lastWatchedAt,

      metadataUpdatedAt: now,

      nextEpisodeSeason: current.nextEpisodeSeason,

      nextEpisodeNumber: current.nextEpisodeNumber,

      nextEpisodeAirDate: current.nextEpisodeAirDate,

      seriesEnded: current.seriesEnded,

      episodeReminderEnabled: current.episodeReminderEnabled,

      reminderSeason: current.reminderSeason,

      reminderEpisode: current.reminderEpisode,

      reminderAirDate: current.reminderAirDate,

      createdAt: current.createdAt,

      updatedAt: current.updatedAt,
    );

    _shows[index] = merged;

    await _save();

    notifyListeners();

    return true;
  }

  // ==========================================================
  // DELETE
  // ==========================================================

  Future<void> deleteShow(String id) async {
    final existing = byId(id);

    if (existing != null && existing.isSeries) {
      await NotificationService.cancelEpisodeReminder(existing.id);
    }

    _shows.removeWhere((show) => show.id == id);

    await _save();

    notifyListeners();
  }

  // ==========================================================
  // STATUS
  // ==========================================================

  Future<void> setStatus(String id, String status) async {
    final show = byId(id);

    if (show == null || show.status == status) {
      return;
    }

    final shouldMarkAsWatched = status == 'Watching' || status == 'Completed';

    await updateShow(
      show.copyWith(
        status: status,

        lastWatchedAt: shouldMarkAsWatched
            ? DateTime.now()
            : show.lastWatchedAt,
      ),
    );
  }

  // ==========================================================
  // PHASE 3
  // SET EPISODE REMINDER
  // ==========================================================

  Future<EpisodeReminderResult> setEpisodeReminderEnabled(
    String id,
    bool enabled,
  ) async {
    final original = byId(id);

    if (original == null) {
      return EpisodeReminderResult.showNotFound;
    }

    if (!original.isSeries) {
      return EpisodeReminderResult.notSeries;
    }

    // ========================================================
    // TURN OFF
    // ========================================================

    if (!enabled) {
      final index = _shows.indexWhere((show) => show.id == id);

      if (index == -1) {
        return EpisodeReminderResult.showNotFound;
      }

      final updated = await _disableReminderForShow(_shows[index]);

      _shows[index] = updated.copyWith(updatedAt: DateTime.now());

      await _save();

      notifyListeners();

      return EpisodeReminderResult.disabled;
    }

    // ========================================================
    // BLOCK COMPLETED / DROPPED
    // ========================================================

    if (original.status == 'Completed' || original.status == 'Dropped') {
      return EpisodeReminderResult.statusNotEligible;
    }

    // ========================================================
    // ASK PERMISSION ONLY HERE
    // ========================================================

    final permission =
        await NotificationService.requestNotificationPermission();

    if (!permission) {
      return EpisodeReminderResult.permissionDenied;
    }

    // ========================================================
    // GET FRESHEST TMDB DATA POSSIBLE
    // ========================================================
    //
    // Reminder is still OFF during this refresh, so the sync
    // itself will not schedule anything yet.
    // ========================================================

    if (_canResolveSeries(original)) {
      await forceRefreshSeriesMetadata(original.id);
    }

    final refreshed = byId(id);

    if (refreshed == null) {
      return EpisodeReminderResult.showNotFound;
    }

    // TMDB refresh may have safely auto-completed the series.
    if (refreshed.status == 'Completed' || refreshed.status == 'Dropped') {
      return EpisodeReminderResult.statusNotEligible;
    }

    // ========================================================
    // SAVE USER PREFERENCE AS ON
    // ========================================================

    var enabledShow = refreshed.copyWith(
      episodeReminderEnabled: true,

      reminderSeason: null,

      reminderEpisode: null,

      reminderAirDate: null,

      updatedAt: DateTime.now(),
    );

    // ========================================================
    // SCHEDULE IF UPCOMING EPISODE EXISTS
    // ========================================================

    enabledShow = await _reconcileReminderForShow(
      enabledShow,
      forceSchedule: true,
    );

    final index = _shows.indexWhere((show) => show.id == id);

    if (index == -1) {
      return EpisodeReminderResult.showNotFound;
    }

    _shows[index] = enabledShow;

    await _save();

    notifyListeners();

    if (enabledShow.hasScheduledEpisodeReminder) {
      return EpisodeReminderResult.scheduled;
    }

    // Reminder preference remains ON.
    //
    // If TMDB does not know the next episode yet, a future
    // metadata refresh can schedule it automatically.
    return EpisodeReminderResult.enabledWaitingForEpisode;
  }

  // ==========================================================
  // PHASE 3
  // RECONCILE ONE REMINDER
  // ==========================================================

  Future<Show> _reconcileReminderForShow(
    Show show, {
    bool forceSchedule = false,
  }) async {
    // ========================================================
    // REMINDER OFF
    // ========================================================

    if (!show.episodeReminderEnabled) {
      if (show.reminderSeason != null ||
          show.reminderEpisode != null ||
          show.reminderAirDate != null) {
        await NotificationService.cancelEpisodeReminder(show.id);

        return show.copyWith(
          reminderSeason: null,
          reminderEpisode: null,
          reminderAirDate: null,
          updatedAt: show.updatedAt,
        );
      }

      return show;
    }

    // ========================================================
    // INVALID TYPE
    // ========================================================

    if (!show.isSeries) {
      return _disableReminderForShow(show);
    }

    // ========================================================
    // STATUS CANCEL
    // ========================================================

    if (show.status == 'Completed' || show.status == 'Dropped') {
      return _disableReminderForShow(show);
    }

    // ========================================================
    // SERIES DEFINITELY ENDED WITH NOTHING UPCOMING
    // ========================================================

    if (show.seriesEnded && !show.hasReminderTarget) {
      return _disableReminderForShow(show);
    }

    // ========================================================
    // NO UPCOMING TARGET YET
    // ========================================================

    if (!show.hasReminderTarget) {
      await NotificationService.cancelEpisodeReminder(show.id);

      return show.copyWith(
        reminderSeason: null,
        reminderEpisode: null,
        reminderAirDate: null,
        updatedAt: show.updatedAt,
      );
    }

    // ========================================================
    // ALREADY MATCHES CURRENT NEXT EPISODE
    // ========================================================

    if (!forceSchedule && show.reminderMatchesNextEpisode) {
      return show;
    }

    // ========================================================
    // TARGET CHANGED
    // ========================================================
    //
    // Cancel the old target first. This also prevents a stale
    // notification from surviving if Android permission has
    // been disabled after the previous reminder was scheduled.
    // ========================================================

    await NotificationService.cancelEpisodeReminder(show.id);

    final nextSeason = show.nextEpisodeSeason!;

    final nextEpisode = show.nextEpisodeNumber!;

    final nextAirDate = show.nextEpisodeAirDate!;

    final scheduled = await NotificationService.scheduleEpisodeReminder(
      showId: show.id,

      showTitle: show.title,

      season: nextSeason,

      episode: nextEpisode,

      airDate: nextAirDate,
    );

    if (!scheduled) {
      // Keep preference ON.
      //
      // The next metadata sync can try again later.
      return show.copyWith(
        reminderSeason: null,
        reminderEpisode: null,
        reminderAirDate: null,
        updatedAt: show.updatedAt,
      );
    }

    return show.copyWith(
      episodeReminderEnabled: true,

      reminderSeason: nextSeason,

      reminderEpisode: nextEpisode,

      reminderAirDate: nextAirDate,

      updatedAt: show.updatedAt,
    );
  }

  // ==========================================================
  // PHASE 3
  // DISABLE ONE REMINDER
  // ==========================================================

  Future<Show> _disableReminderForShow(Show show) async {
    await NotificationService.cancelEpisodeReminder(show.id);

    return show.copyWith(
      episodeReminderEnabled: false,

      reminderSeason: null,

      reminderEpisode: null,

      reminderAirDate: null,

      updatedAt: show.updatedAt,
    );
  }

  // ==========================================================
  // PHASE 3
  // RECONCILE REMINDERS AFTER APP LOAD
  // ==========================================================

  Future<void> _reconcileLoadedEpisodeReminders() async {
    if (_shows.isEmpty) {
      return;
    }

    bool changed = false;

    for (int i = 0; i < _shows.length; i++) {
      final show = _shows[i];

      if (!show.isSeries) {
        continue;
      }

      if (!show.episodeReminderEnabled &&
          show.reminderSeason == null &&
          show.reminderEpisode == null &&
          show.reminderAirDate == null) {
        continue;
      }

      final updated = await _reconcileReminderForShow(show);

      if (!_sameReminderState(show, updated)) {
        _shows[i] = updated;

        changed = true;
      }
    }

    if (!changed) {
      return;
    }

    await _save();

    notifyListeners();
  }

  // ==========================================================
  // PHASE 3
  // REMINDER STATE COMPARISON
  // ==========================================================

  bool _sameReminderState(Show first, Show second) {
    return first.episodeReminderEnabled == second.episodeReminderEnabled &&
        first.reminderSeason == second.reminderSeason &&
        first.reminderEpisode == second.reminderEpisode &&
        _sameNullableDate(first.reminderAirDate, second.reminderAirDate);
  }

  bool _sameNullableDate(DateTime? first, DateTime? second) {
    if (first == null && second == null) {
      return true;
    }

    if (first == null || second == null) {
      return false;
    }

    return first.year == second.year &&
        first.month == second.month &&
        first.day == second.day;
  }

  // ==========================================================
  // SEASON
  // ==========================================================

  Future<void> setSeason(String id, int season) async {
    final show = byId(id);

    if (show == null || !show.isSeries) {
      return;
    }

    final newSeason = season < 1 ? 1 : season;

    final newTotalSeasons = newSeason > show.totalSeasons
        ? newSeason
        : show.totalSeasons;

    final progress = show.seasonProgress[newSeason] ?? 0;

    var newStatus = show.status;

    if (newSeason != show.currentSeason && show.status == 'Completed') {
      newStatus = 'Watching';
    }

    await updateShow(
      show.copyWith(
        totalSeasons: newTotalSeasons,

        currentSeason: newSeason,

        currentEpisode: progress,

        status: newStatus,
      ),
    );
  }

  // ==========================================================
  // SET EPISODE METADATA
  // ==========================================================

  Future<void> setSeasonEpisodeCount(
    String id,
    int season,
    int count, {
    bool isFinal = false,
    int? lastAiredEpisode,
    int? nextEpisode,
    int? upcomingSeason,
    int? upcomingEpisode,
    DateTime? upcomingAirDate,
    int? totalSeasons,
    bool? seriesEnded,
    bool markMetadataUpdated = true,
  }) async {
    if (season < 1 || count <= 0) {
      return;
    }

    final show = byId(id);

    if (show == null || !show.isSeries) {
      return;
    }

    final counts = Map<int, int>.from(show.seasonEpisodeCounts);

    final finalized = Map<int, bool>.from(show.seasonEpisodeCountFinalized);

    final lastAired = Map<int, int>.from(show.seasonLastAiredEpisodes);

    final nextEpisodes = Map<int, int>.from(show.seasonNextEpisodes);

    final storedProgress = show.seasonProgress[season] ?? 0;

    final currentProgress = show.currentSeason == season
        ? show.currentEpisode
        : storedProgress;

    final existingCount = counts[season] ?? 0;

    final existingLastAired = lastAired[season] ?? 0;

    var safeCount = count;

    if (existingCount > safeCount) {
      safeCount = existingCount;
    }

    if (storedProgress > safeCount) {
      safeCount = storedProgress;
    }

    if (currentProgress > safeCount) {
      safeCount = currentProgress;
    }

    final safeLastAired = lastAiredEpisode ?? 0;

    if (safeLastAired > safeCount) {
      safeCount = safeLastAired;
    }

    final safeNextEpisode = nextEpisode ?? 0;

    if (safeNextEpisode > safeCount) {
      safeCount = safeNextEpisode;
    }

    counts[season] = safeCount;

    finalized[season] = (finalized[season] ?? false) || isFinal;

    if (safeLastAired > 0 || existingLastAired > 0) {
      lastAired[season] = safeLastAired > existingLastAired
          ? safeLastAired
          : existingLastAired;
    }

    if (safeNextEpisode > 0) {
      nextEpisodes[season] = safeNextEpisode;
    } else if (isFinal) {
      nextEpisodes.remove(season);
    }

    var newTotalSeasons = show.totalSeasons;

    if (totalSeasons != null && totalSeasons > 0) {
      newTotalSeasons = totalSeasons;
    }

    if (season > newTotalSeasons) {
      newTotalSeasons = season;
    }

    if ((upcomingSeason ?? 0) > newTotalSeasons) {
      newTotalSeasons = upcomingSeason!;
    }

    final now = DateTime.now();

    final index = _shows.indexWhere((item) => item.id == id);

    if (index == -1) {
      return;
    }

    var updated = show.copyWith(
      totalSeasons: newTotalSeasons,

      seasonEpisodeCounts: counts,

      seasonEpisodeCountFinalized: finalized,

      seasonLastAiredEpisodes: lastAired,

      seasonNextEpisodes: nextEpisodes,

      metadataUpdatedAt: markMetadataUpdated ? now : show.metadataUpdatedAt,

      nextEpisodeSeason: upcomingSeason ?? show.nextEpisodeSeason,

      nextEpisodeNumber: upcomingEpisode ?? show.nextEpisodeNumber,

      nextEpisodeAirDate: upcomingAirDate ?? show.nextEpisodeAirDate,

      seriesEnded: seriesEnded ?? show.seriesEnded,

      lastWatchedAt: show.lastWatchedAt,

      updatedAt: show.updatedAt,
    );

    if (updated.isSeriesFullyWatched && updated.status != 'Completed') {
      updated = updated.copyWith(
        status: 'Completed',

        lastWatchedAt: show.lastWatchedAt,

        updatedAt: show.updatedAt,
      );
    }

    // ========================================================
    // PHASE 3
    // METADATA CHANGED, SO RECHECK REMINDER
    // ========================================================

    updated = await _reconcileReminderForShow(updated);

    _shows[index] = updated;

    await _save();

    notifyListeners();
  }

  // ==========================================================
  // MARK SEASON COMPLETE
  // ==========================================================

  Future<bool> markSeasonComplete(String id, {int? season}) async {
    final show = byId(id);

    if (show == null || !show.isSeries) {
      return false;
    }

    final targetSeason = season ?? show.currentSeason;

    if (targetSeason < 1) {
      return false;
    }

    final count = show.seasonEpisodeCounts[targetSeason] ?? 0;

    final isFinal = show.isSeasonEpisodeCountFinal(targetSeason);

    if (!isFinal || count <= 0) {
      return false;
    }

    final progress = Map<int, int>.from(show.seasonProgress);

    progress[targetSeason] = count;

    final now = DateTime.now();

    final isCurrentSeason = targetSeason == show.currentSeason;

    var updated = show.copyWith(
      currentEpisode: isCurrentSeason ? count : show.currentEpisode,

      seasonProgress: progress,

      status: show.status == 'Plan to Watch' ? 'Watching' : show.status,

      lastWatchedAt: now,
    );

    if (updated.isSeriesFullyWatched) {
      updated = updated.copyWith(status: 'Completed', lastWatchedAt: now);
    }

    await updateShow(updated);

    return true;
  }

  // ==========================================================
  // EPISODE +
  // ==========================================================

  Future<void> incrementEpisode(String id) async {
    final show = byId(id);

    if (show == null || !show.isSeries) {
      return;
    }

    var season = show.currentSeason;

    var episode = show.currentEpisode;

    final progress = Map<int, int>.from(show.seasonProgress);

    final counts = Map<int, int>.from(show.seasonEpisodeCounts);

    final limit = counts[season] ?? 0;

    final limitIsFinal = show.isSeasonEpisodeCountFinal(season);

    if (limitIsFinal && limit > 0 && episode >= limit) {
      if (show.canAutoCompleteSeries) {
        var completed = show.copyWith(
          currentEpisode: limit,

          status: 'Completed',

          lastWatchedAt: DateTime.now(),
        );

        final completedProgress = Map<int, int>.from(completed.seasonProgress);

        completedProgress[season] = limit;

        completed = completed.copyWith(seasonProgress: completedProgress);

        await updateShow(completed);

        return;
      }

      season += 1;

      episode = progress[season] ?? 0;
    } else {
      episode += 1;

      final currentKnownCount = counts[season] ?? 0;

      if (!show.isSeasonEpisodeCountFinal(season) &&
          episode > currentKnownCount) {
        counts[season] = episode;
      }
    }

    progress[season] = episode;

    final newTotal = season > show.totalSeasons ? season : show.totalSeasons;

    var status = show.status;

    if (status == 'Plan to Watch' || status == 'Completed') {
      status = 'Watching';
    }

    var updated = show.copyWith(
      totalSeasons: newTotal,

      currentSeason: season,

      currentEpisode: episode,

      seasonProgress: progress,

      seasonEpisodeCounts: counts,

      status: status,

      lastWatchedAt: DateTime.now(),
    );

    if (updated.isSeriesFullyWatched) {
      updated = updated.copyWith(
        status: 'Completed',

        lastWatchedAt: DateTime.now(),
      );
    }

    await updateShow(updated);
  }

  // ==========================================================
  // EPISODE -
  // ==========================================================

  Future<void> decrementEpisode(String id) async {
    final show = byId(id);

    if (show == null || !show.isSeries) {
      return;
    }

    var season = show.currentSeason;

    var episode = show.currentEpisode;

    final progress = Map<int, int>.from(show.seasonProgress);

    if (episode > 0) {
      episode -= 1;
    } else if (season > 1) {
      season -= 1;

      episode = progress[season] ?? 0;
    } else {
      return;
    }

    progress[season] = episode;

    var updated = show.copyWith(
      currentSeason: season,

      currentEpisode: episode,

      seasonProgress: progress,
    );

    if (show.status == 'Completed' &&
        show.seriesEnded &&
        !updated.isSeriesFullyWatched) {
      updated = updated.copyWith(status: 'Watching');
    }

    await updateShow(updated);
  }

  // ==========================================================
  // HOME SILENT SERIES SYNC
  // ==========================================================

  Future<void> syncSeriesMetadataInBackground({bool force = false}) async {
    if (_loading || _backgroundSeriesSyncRunning) {
      return;
    }

    final candidates = _shows.where(_shouldSyncSeries).toList();

    if (candidates.isEmpty) {
      return;
    }

    _backgroundSeriesSyncRunning = true;

    try {
      final prefs = await SharedPreferences.getInstance();

      final syncTimes = _readSyncTimes(prefs);

      final now = DateTime.now();

      final pending = candidates.where((show) {
        if (force) {
          return true;
        }

        final key = _syncKey(show.id, show.currentSeason);

        final timestamp = syncTimes[key];

        if (timestamp == null) {
          return true;
        }

        final lastSync = DateTime.fromMillisecondsSinceEpoch(timestamp);

        return now.difference(lastSync) >= _seriesMetadataSyncInterval;
      }).toList();

      if (pending.isEmpty) {
        return;
      }

      pending.sort((a, b) {
        final priority = _syncPriority(a).compareTo(_syncPriority(b));

        if (priority != 0) {
          return priority;
        }

        return b.recentActivityAt.compareTo(a.recentActivityAt);
      });

      bool anyChanged = false;

      bool syncTimesChanged = false;

      for (int i = 0; i < pending.length; i += 2) {
        final batch = pending.skip(i).take(2).toList(growable: false);

        final results = await Future.wait(
          batch.map(
            (show) => _syncOneSeries(
              show.id,
              show.currentSeason,
              forceRefresh: force,
            ),
          ),
        );

        for (int j = 0; j < results.length; j++) {
          final result = results[j];

          final show = batch[j];

          if (result.changed) {
            anyChanged = true;
          }

          if (result.success) {
            syncTimes[_syncKey(show.id, show.currentSeason)] =
                DateTime.now().millisecondsSinceEpoch;

            syncTimesChanged = true;
          }
        }

        if (i + 2 < pending.length) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
      }

      if (anyChanged) {
        await _save();

        notifyListeners();
      }

      if (syncTimesChanged) {
        await prefs.setString(_seriesMetadataSyncKey, jsonEncode(syncTimes));
      }
    } finally {
      _backgroundSeriesSyncRunning = false;
    }
  }

  // ==========================================================
  // NORMAL SINGLE-SERIES SYNC
  // ==========================================================

  Future<void> syncSeriesMetadataForShow(
    String id, {
    bool force = false,
  }) async {
    final show = byId(id);

    if (show == null || !_shouldSyncSeries(show)) {
      return;
    }

    final prefs = await SharedPreferences.getInstance();

    final syncTimes = _readSyncTimes(prefs);

    final key = _syncKey(show.id, show.currentSeason);

    if (!force) {
      final timestamp = syncTimes[key];

      if (timestamp != null) {
        final lastSync = DateTime.fromMillisecondsSinceEpoch(timestamp);

        if (DateTime.now().difference(lastSync) < _seriesMetadataSyncInterval) {
          return;
        }
      }
    }

    final result = await _syncOneSeries(
      show.id,
      show.currentSeason,
      forceRefresh: force,
    );

    if (result.changed) {
      await _save();

      notifyListeners();
    }

    if (result.success) {
      syncTimes[key] = DateTime.now().millisecondsSinceEpoch;

      await prefs.setString(_seriesMetadataSyncKey, jsonEncode(syncTimes));
    }
  }

  // ==========================================================
  // MANUAL FORCE REFRESH
  // ==========================================================

  Future<bool> forceRefreshSeriesMetadata(String id) async {
    final show = byId(id);

    if (show == null || !show.isSeries || !_canResolveSeries(show)) {
      return false;
    }

    final result = await _syncOneSeries(
      show.id,
      show.currentSeason,
      forceRefresh: true,
    );

    if (result.changed) {
      await _save();

      notifyListeners();
    }

    if (result.success) {
      final prefs = await SharedPreferences.getInstance();

      final syncTimes = _readSyncTimes(prefs);

      syncTimes[_syncKey(show.id, show.currentSeason)] =
          DateTime.now().millisecondsSinceEpoch;

      await prefs.setString(_seriesMetadataSyncKey, jsonEncode(syncTimes));
    }

    return result.success;
  }

  // ==========================================================
  // SHOULD SYNC SERIES
  // ==========================================================

  bool _shouldSyncSeries(Show show) {
    if (!show.isSeries) {
      return false;
    }

    if (show.status == 'Dropped') {
      return false;
    }

    if (show.status == 'Completed' &&
        show.seriesEnded &&
        show.currentSeasonEpisodeCountIsFinal &&
        !show.hasUpcomingEpisode) {
      return false;
    }

    return _canResolveSeries(show);
  }

  // ==========================================================
  // CAN RESOLVE SERIES
  // ==========================================================

  bool _canResolveSeries(Show show) {
    return show.id.startsWith('tt') || show.id.startsWith('tmdb_tv_');
  }

  // ==========================================================
  // SYNC PRIORITY
  // ==========================================================

  int _syncPriority(Show show) {
    switch (show.status) {
      case 'Watching':
        return 0;

      case 'Plan to Watch':
        return 1;

      case 'On Hold':
        return 2;

      case 'Completed':
        return 3;

      default:
        return 4;
    }
  }

  // ==========================================================
  // SYNC ONE SHOW
  // ==========================================================

  Future<_SeriesSyncResult> _syncOneSeries(
    String showId,
    int season, {
    required bool forceRefresh,
  }) {
    final requestKey = '$showId:$season';

    final existing = _seriesSyncInFlight[requestKey];

    if (existing != null) {
      return existing;
    }

    late final Future<_SeriesSyncResult> request;

    request = _performOneSeriesSync(showId, season, forceRefresh: forceRefresh)
        .whenComplete(() {
          _seriesSyncInFlight.remove(requestKey);
        });

    _seriesSyncInFlight[requestKey] = request;

    return request;
  }

  // ==========================================================
  // PERFORM ONE SERIES SYNC
  // ==========================================================

  Future<_SeriesSyncResult> _performOneSeriesSync(
    String showId,
    int season, {
    required bool forceRefresh,
  }) async {
    final originalShow = byId(showId);

    if (originalShow == null || !originalShow.isSeries || season < 1) {
      return const _SeriesSyncResult(changed: false, success: false);
    }

    TmdbSeasonProgressInfo? info;

    try {
      if (originalShow.id.startsWith('tt')) {
        info = await TmdbService.fetchSeasonProgressByImdbId(
          originalShow.id,
          season,
          forceRefresh: forceRefresh,
        );
      } else if (originalShow.id.startsWith('tmdb_tv_')) {
        final tmdbId = originalShow.id.substring('tmdb_tv_'.length);

        info = await TmdbService.fetchSeasonProgressByTmdbId(
          tmdbId,
          season,
          forceRefresh: forceRefresh,
        );
      }
    } catch (_) {
      info = null;
    }

    if (info == null || info.knownEpisodeCount <= 0) {
      return const _SeriesSyncResult(changed: false, success: false);
    }

    final currentShow = byId(showId);

    if (currentShow == null) {
      return const _SeriesSyncResult(changed: false, success: true);
    }

    var updated = _applyTmdbMetadata(currentShow, info);

    if (updated == null) {
      return const _SeriesSyncResult(changed: false, success: true);
    }

    // ========================================================
    // PHASE 3
    // NEXT EPISODE MAY HAVE CHANGED
    // ========================================================

    updated = await _reconcileReminderForShow(updated);

    final index = _shows.indexWhere((show) => show.id == showId);

    if (index == -1) {
      return const _SeriesSyncResult(changed: false, success: true);
    }

    _shows[index] = updated;

    return const _SeriesSyncResult(changed: true, success: true);
  }

  // ==========================================================
  // APPLY TMDB METADATA
  // ==========================================================

  Show? _applyTmdbMetadata(Show show, TmdbSeasonProgressInfo info) {
    final season = info.seasonNumber;

    if (season < 1) {
      return null;
    }

    final counts = Map<int, int>.from(show.seasonEpisodeCounts);

    final finalized = Map<int, bool>.from(show.seasonEpisodeCountFinalized);

    final lastAired = Map<int, int>.from(show.seasonLastAiredEpisodes);

    final nextEpisodes = Map<int, int>.from(show.seasonNextEpisodes);

    final storedProgress = show.seasonProgress[season] ?? 0;

    final currentProgress = show.currentSeason == season
        ? show.currentEpisode
        : storedProgress;

    var safeCount = info.knownEpisodeCount;

    if (storedProgress > safeCount) {
      safeCount = storedProgress;
    }

    if (currentProgress > safeCount) {
      safeCount = currentProgress;
    }

    if (info.lastAiredEpisode > safeCount) {
      safeCount = info.lastAiredEpisode;
    }

    if ((info.nextEpisode ?? 0) > safeCount) {
      safeCount = info.nextEpisode!;
    }

    counts[season] = safeCount;

    finalized[season] = info.isFinal;

    if (info.lastAiredEpisode > 0) {
      lastAired[season] = info.lastAiredEpisode;
    } else {
      lastAired.remove(season);
    }

    if (info.nextEpisode != null && info.nextEpisode! > 0) {
      nextEpisodes[season] = info.nextEpisode!;
    } else {
      nextEpisodes.remove(season);
    }

    var totalSeasons = info.totalSeasons > 0
        ? info.totalSeasons
        : show.totalSeasons;

    if (show.currentSeason > totalSeasons) {
      totalSeasons = show.currentSeason;
    }

    if ((info.upcomingSeason ?? 0) > totalSeasons) {
      totalSeasons = info.upcomingSeason!;
    }

    final now = DateTime.now();

    var updated = show.copyWith(
      totalSeasons: totalSeasons,

      seasonEpisodeCounts: counts,

      seasonEpisodeCountFinalized: finalized,

      seasonLastAiredEpisodes: lastAired,

      seasonNextEpisodes: nextEpisodes,

      metadataUpdatedAt: now,

      // These values are authoritative from the latest TMDB
      // progress response. Passing null intentionally clears
      // stale previous next-episode metadata.
      nextEpisodeSeason: info.upcomingSeason,

      nextEpisodeNumber: info.upcomingEpisode,

      nextEpisodeAirDate: info.upcomingAirDate,

      seriesEnded: info.seriesEnded,

      lastWatchedAt: show.lastWatchedAt,

      updatedAt: show.updatedAt,
    );

    if (updated.isSeriesFullyWatched && updated.status != 'Completed') {
      updated = updated.copyWith(
        status: 'Completed',

        lastWatchedAt: show.lastWatchedAt,

        updatedAt: show.updatedAt,
      );
    }

    return updated;
  }

  // ==========================================================
  // BACKUP / RESTORE
  // ==========================================================

  Future<void> replaceAll(List<Show> shows) async {
    // Cancel reminders belonging to the previous library.
    for (final show in _shows) {
      if (show.isSeries) {
        await NotificationService.cancelEpisodeReminder(show.id);
      }
    }

    _shows = List<Show>.from(shows);

    // Recreate valid reminders from the restored library.
    for (int i = 0; i < _shows.length; i++) {
      final show = _shows[i];

      if (!show.isSeries || !show.episodeReminderEnabled) {
        continue;
      }

      _shows[i] = await _reconcileReminderForShow(show, forceSchedule: true);
    }

    await _save();

    notifyListeners();
  }

  Future<int> mergeShows(List<Show> newShows) async {
    int addedCount = 0;

    bool reminderStateChanged = false;

    for (final newShow in newShows) {
      final existing = findLibraryMatch(
        exactId: newShow.id,
        title: newShow.title,
        type: newShow.type,
        yearText: newShow.yearText,
      );

      if (existing == null) {
        var showToAdd = newShow;

        if (showToAdd.isSeries && showToAdd.episodeReminderEnabled) {
          final reconciled = await _reconcileReminderForShow(
            showToAdd,
            forceSchedule: true,
          );

          reminderStateChanged = !_sameReminderState(showToAdd, reconciled);

          showToAdd = reconciled;
        }

        _shows.add(showToAdd);

        addedCount++;
      }
    }

    if (addedCount > 0 || reminderStateChanged) {
      await _save();

      notifyListeners();
    }

    return addedCount;
  }

  // ==========================================================
  // SYNC CACHE KEY
  // ==========================================================

  String _syncKey(String id, int season) {
    return '$id:$season';
  }

  // ==========================================================
  // READ SYNC TIMES
  // ==========================================================

  Map<String, int> _readSyncTimes(SharedPreferences prefs) {
    final raw = prefs.getString(_seriesMetadataSyncKey);

    if (raw == null || raw.trim().isEmpty) {
      return <String, int>{};
    }

    try {
      final decoded = jsonDecode(raw);

      if (decoded is! Map) {
        return <String, int>{};
      }

      final result = <String, int>{};

      decoded.forEach((key, value) {
        final parsed = value is int
            ? value
            : int.tryParse(value?.toString() ?? '');

        if (parsed != null && parsed > 0) {
          result[key.toString()] = parsed;
        }
      });

      return result;
    } catch (_) {
      return <String, int>{};
    }
  }

  // ==========================================================
  // SAVE
  // ==========================================================

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString(
      StorageService.showsKey,
      jsonEncode(_shows.map((show) => show.toJson()).toList()),
    );
  }
}
