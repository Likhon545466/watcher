import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/show.dart';
import '../providers/show_provider.dart';
import '../services/omdb_service.dart';
import '../services/tmdb_service.dart';
import '../utils/status_style.dart';
import '../widgets/ambient_background.dart';
import '../widgets/glass_container.dart';
import '../widgets/poster_image.dart';
import '../widgets/round_step_button.dart';
import 'add_edit_show_screen.dart';

class ShowDetailScreen extends StatefulWidget {
  final String showId;

  const ShowDetailScreen({super.key, required this.showId});

  @override
  State<ShowDetailScreen> createState() => _ShowDetailScreenState();
}

class _ShowDetailScreenState extends State<ShowDetailScreen> {
  int? _loadingSeason;
  String? _seasonError;
  int? _seasonErrorSeason;
  final Set<int> _seasonMetadataAttempted = <int>{};

  bool _fetchingDetails = false;
  bool _refreshingMetadata = false;

  // ==========================================================
  // TMDB MEDIA
  // ==========================================================

  TmdbMediaData? _tmdbData;
  bool _loadingTmdb = false;
  bool _hasFetchedTmdb = false;

  // ==========================================================
  // PERSONAL NOTE
  // ==========================================================

  final TextEditingController _noteController = TextEditingController();
  bool _isEditingNote = false;

  // ==========================================================
  // PHASE 3 - REMINDER
  // ==========================================================

  bool _changingReminder = false;
  final Set<String> _autoDisabledReminderIds = <String>{};

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  // ==========================================================
  // FETCH TMDB MEDIA
  // ==========================================================

  Future<void> _fetchTmdbMediaIfNeeded(Show show) async {
    if (_hasFetchedTmdb || _loadingTmdb) {
      return;
    }

    setState(() {
      _loadingTmdb = true;
    });

    try {
      final mediaData = await TmdbService.fetchMediaDetails(
        show.title,
        show.type,
      );

      if (mounted) {
        setState(() {
          _tmdbData = mediaData;
          _hasFetchedTmdb = true;
        });
      }
    } catch (_) {
    } finally {
      if (mounted) {
        setState(() {
          _loadingTmdb = false;
        });
      }
    }
  }

  // ==========================================================
  // FETCH FULL OMDB DETAILS
  // ==========================================================

  Future<void> _fetchFullDetailsIfNeeded(Show show) async {
    if (!show.id.startsWith('tt') || _fetchingDetails) {
      return;
    }

    if (show.director.isNotEmpty || show.actors.isNotEmpty) {
      return;
    }

    setState(() {
      _fetchingDetails = true;
    });

    try {
      final fullShow = await OmdbService.getDetails(
        show.id,
        status: show.status,
      );

      if (!mounted) {
        return;
      }

      final updated = fullShow.copyWith(
        createdAt: show.createdAt,
        currentSeason: show.currentSeason,
        currentEpisode: show.currentEpisode,
        seasonProgress: show.seasonProgress,
        seasonEpisodeCounts: show.seasonEpisodeCounts,
        seasonEpisodeCountFinalized: show.seasonEpisodeCountFinalized,
        seasonLastAiredEpisodes: show.seasonLastAiredEpisodes,
        seasonNextEpisodes: show.seasonNextEpisodes,
        personalNote: show.personalNote,
        totalSeasons: show.totalSeasons > fullShow.totalSeasons
            ? show.totalSeasons
            : fullShow.totalSeasons,
        status: show.status,
        lastWatchedAt: show.lastWatchedAt,
        metadataUpdatedAt: show.metadataUpdatedAt,
        nextEpisodeSeason: show.nextEpisodeSeason,
        nextEpisodeNumber: show.nextEpisodeNumber,
        nextEpisodeAirDate: show.nextEpisodeAirDate,
        seriesEnded: show.seriesEnded,
        episodeReminderEnabled: show.episodeReminderEnabled,
        reminderSeason: show.reminderSeason,
        reminderEpisode: show.reminderEpisode,
        reminderAirDate: show.reminderAirDate,
        updatedAt: show.updatedAt,
      );

      await context.read<ShowProvider>().updateShow(updated);
    } catch (_) {
    } finally {
      if (mounted) {
        setState(() {
          _fetchingDetails = false;
        });
      }
    }
  }

  // ==========================================================
  // MANUAL METADATA REFRESH
  // ==========================================================

  Future<void> _refreshMetadata(Show show) async {
    if (_refreshingMetadata) {
      return;
    }

    setState(() {
      _refreshingMetadata = true;
      _seasonError = null;
      _seasonErrorSeason = null;
    });

    final messenger = ScaffoldMessenger.of(context);

    bool descriptiveUpdated = false;
    bool seriesUpdated = false;

    try {
      final provider = context.read<ShowProvider>();

      if (show.id.startsWith('tt')) {
        final metadataShow = await OmdbService.getDetails(
          show.id,
          status: show.status,
        );

        if (!mounted) {
          return;
        }

        descriptiveUpdated = await provider.applyRefreshedMetadata(
          show.id,
          metadataShow,
        );
      }

      final latestAfterOmdb = provider.byId(show.id) ?? show;

      if (latestAfterOmdb.isSeries &&
          (latestAfterOmdb.id.startsWith('tt') ||
              latestAfterOmdb.id.startsWith('tmdb_tv_'))) {
        seriesUpdated = await provider.forceRefreshSeriesMetadata(
          latestAfterOmdb.id,
        );
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _hasFetchedTmdb = false;
        _tmdbData = null;
        _seasonMetadataAttempted.clear();
      });

      final latest = provider.byId(show.id) ?? latestAfterOmdb;

      await _fetchTmdbMediaIfNeeded(latest);

      if (!mounted) {
        return;
      }

      if (descriptiveUpdated || seriesUpdated) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Metadata refreshed successfully.')),
        );
      } else {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('No new metadata was available right now.'),
          ),
        );
      }
    } on OmdbException catch (error) {
      if (!mounted) {
        return;
      }

      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    } catch (_) {
      if (!mounted) {
        return;
      }

      messenger.showSnackBar(
        const SnackBar(content: Text('Could not refresh metadata.')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _refreshingMetadata = false;
        });
      }
    }
  }

  // ==========================================================
  // LOAD SEASON INFO
  // ==========================================================

  Future<void> _loadSeasonInfo(Show show) async {
    if (!show.isSeries) {
      return;
    }

    final isImdbSeries = show.id.startsWith('tt');
    final isTmdbFallbackSeries = show.id.startsWith('tmdb_tv_');

    if (!isImdbSeries && !isTmdbFallbackSeries) {
      return;
    }

    final requestedSeason = show.currentSeason;

    if (_loadingSeason == requestedSeason ||
        _seasonMetadataAttempted.contains(requestedSeason)) {
      return;
    }

    _seasonMetadataAttempted.add(requestedSeason);

    setState(() {
      _loadingSeason = requestedSeason;
      _seasonError = null;
      _seasonErrorSeason = null;
    });

    bool metadataUpdated = false;

    try {
      metadataUpdated = await context
          .read<ShowProvider>()
          .forceRefreshSeriesMetadata(show.id);

      if (!mounted) {
        return;
      }

      if (!metadataUpdated && isImdbSeries) {
        final omdbInfo = await OmdbService.getSeason(show.id, requestedSeason);

        if (!mounted) {
          return;
        }

        if (omdbInfo.episodeCount > 0) {
          await context.read<ShowProvider>().setSeasonEpisodeCount(
            show.id,
            requestedSeason,
            omdbInfo.episodeCount,
            isFinal: false,
          );

          metadataUpdated = true;
        }
      }

      if (!metadataUpdated && mounted) {
        setState(() {
          _seasonError = 'Season information is not available yet.';
          _seasonErrorSeason = requestedSeason;
        });
      }
    } on OmdbException catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _seasonError = error.message;
        _seasonErrorSeason = requestedSeason;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _seasonError = 'Season information is not available yet.';
        _seasonErrorSeason = requestedSeason;
      });
    } finally {
      if (mounted) {
        setState(() {
          _loadingSeason = null;
        });
      }
    }
  }

  // ==========================================================
  // CHANGE SEASON
  // ==========================================================

  Future<void> _changeSeason(Show show, int delta) async {
    final next = (show.currentSeason + delta) < 1
        ? 1
        : show.currentSeason + delta;

    if (next == show.currentSeason) {
      return;
    }

    await context.read<ShowProvider>().setSeason(show.id, next);

    if (!mounted) {
      return;
    }

    final updated = context.read<ShowProvider>().byId(show.id);

    if (updated != null) {
      await _loadSeasonInfo(updated);
    }
  }

  // ==========================================================
  // PERSONAL NOTE
  // ==========================================================

  Future<void> _savePersonalNote(Show show) async {
    final updated = show.copyWith(personalNote: _noteController.text.trim());
    await context.read<ShowProvider>().updateShow(updated);

    if (!mounted) {
      return;
    }

    setState(() {
      _isEditingNote = false;
    });
  }

  // ==========================================================
  // EDIT & DELETE
  // ==========================================================

  Future<void> _edit(Show show) async {
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => AddEditShowScreen(initialShow: show)),
    );
  }

  Future<void> _delete(Show show) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete from Watcher?'),
        content: Text('"${show.title}" and its progress will be removed.'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) {
      return;
    }

    await context.read<ShowProvider>().deleteShow(show.id);

    if (mounted) {
      Navigator.pop(context);
    }
  }

  // ==========================================================
  // TOGGLE EPISODE REMINDER
  // ==========================================================

  Future<void> _toggleEpisodeReminder(Show show, bool enabled) async {
    if (_changingReminder) {
      return;
    }

    setState(() {
      _changingReminder = true;
    });

    final messenger = ScaffoldMessenger.of(context);

    try {
      final result = await context
          .read<ShowProvider>()
          .setEpisodeReminderEnabled(show.id, enabled);

      if (!mounted) {
        return;
      }

      switch (result) {
        case EpisodeReminderResult.scheduled:
          final updated = context.read<ShowProvider>().byId(show.id);
          final date = updated?.reminderAirDate;

          messenger.showSnackBar(
            SnackBar(
              content: Text(
                date != null
                    ? 'Episode reminder scheduled for ${_formatEpisodeDate(date)}.'
                    : 'Episode reminder scheduled.',
              ),
            ),
          );
          break;

        case EpisodeReminderResult.enabledWaitingForEpisode:
          messenger.showSnackBar(
            const SnackBar(
              content: Text(
                'Reminder is on. Watcher will schedule it when the next episode date becomes available.',
              ),
            ),
          );
          break;

        case EpisodeReminderResult.disabled:
          messenger.showSnackBar(
            const SnackBar(content: Text('Episode reminder turned off.')),
          );
          break;

        case EpisodeReminderResult.permissionDenied:
          messenger.showSnackBar(
            const SnackBar(
              content: Text('Notification permission was not allowed.'),
            ),
          );
          break;

        case EpisodeReminderResult.statusNotEligible:
          messenger.showSnackBar(
            const SnackBar(
              content: Text(
                'Episode reminders are unavailable for Completed or Dropped titles.',
              ),
            ),
          );
          break;

        case EpisodeReminderResult.notSeries:
          messenger.showSnackBar(
            const SnackBar(
              content: Text('Episode reminders are only available for series.'),
            ),
          );
          break;

        case EpisodeReminderResult.showNotFound:
          messenger.showSnackBar(
            const SnackBar(content: Text('This title is no longer available.')),
          );
          break;
      }
    } finally {
      if (mounted) {
        setState(() {
          _changingReminder = false;
        });
      }
    }
  }

  // ==========================================================
  // DATE FORMAT
  // ==========================================================

  String _formatEpisodeDate(DateTime date) {
    const months = <String>[
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  String _formatMetadataSync(DateTime? date) {
    if (date == null) {
      return 'Never synced';
    }

    final local = date.toLocal();
    const months = <String>[
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];

    final hour12 = local.hour == 0
        ? 12
        : local.hour > 12
        ? local.hour - 12
        : local.hour;

    final minute = local.minute.toString().padLeft(2, '0');
    final period = local.hour >= 12 ? 'PM' : 'AM';

    return '${months[local.month - 1]} ${local.day}, ${local.year} • '
        '$hour12:$minute $period';
  }

  bool _isReminderBlockedBySeriesState(Show show) {
    return show.isSeries &&
        show.seriesEnded &&
        !show.hasUpcomingEpisode &&
        show.nextEpisodeAirDate == null;
  }

  Future<void> _autoDisableEndedSeriesReminderIfNeeded(Show show) async {
    if (!show.isSeries || !show.episodeReminderEnabled) {
      return;
    }

    if (!_isReminderBlockedBySeriesState(show)) {
      return;
    }

    if (_autoDisabledReminderIds.contains(show.id)) {
      return;
    }

    _autoDisabledReminderIds.add(show.id);

    try {
      await context.read<ShowProvider>().setEpisodeReminderEnabled(
        show.id,
        false,
      );
    } catch (_) {
      _autoDisabledReminderIds.remove(show.id);
    }
  }

  Future<void> _markSeasonComplete(Show show) async {
    if (!show.isSeries) {
      return;
    }

    final episodeCount = show.currentSeasonEpisodeCount;

    if (episodeCount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Episode count is not available for this season yet.'),
        ),
      );
      return;
    }

    if (show.currentEpisode >= episodeCount) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Season ${show.currentSeason} is already complete.'),
        ),
      );
      return;
    }

    final progress = Map<int, int>.from(show.seasonProgress);
    final counts = Map<int, int>.from(show.seasonEpisodeCounts);

    progress[show.currentSeason] = episodeCount;
    counts[show.currentSeason] = episodeCount;

    final updated = show.copyWith(
      currentEpisode: episodeCount,
      seasonProgress: progress,
      seasonEpisodeCounts: counts,
      status: show.status == 'Plan to Watch' ? 'Watching' : show.status,
      lastWatchedAt: DateTime.now(),
    );

    await context.read<ShowProvider>().updateShow(updated);

    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Season ${show.currentSeason} marked complete.')),
    );
  }

  void _showMetadataInfo(Show show) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final theme = Theme.of(context);
        final colors = theme.colorScheme;
        final bottom = MediaQuery.of(context).padding.bottom;
        final posterCount = _buildPosterGalleryUrls(show).length;

        return Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + bottom),
          child: GlassContainer(
            borderRadius: 24,
            padding: const EdgeInsets.all(20),
            opacity: 0.95,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: colors.onSurfaceVariant.withOpacity(0.28),
                      borderRadius: BorderRadius.circular(100),
                    ),
                  ),
                ),
                Row(
                  children: <Widget>[
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: colors.primary.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.auto_awesome_rounded,
                        color: colors.primary,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          const Text(
                            'Official Info Details',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Aggregated metadata sources.',
                            style: TextStyle(
                              fontSize: 12,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _SourceInfoRow(
                  icon: Icons.movie_filter_outlined,
                  title: 'OMDb',
                  value: 'Title, year, runtime, rating, plot, cast and crew.',
                ),
                const SizedBox(height: 10),
                _SourceInfoRow(
                  icon: Icons.image_outlined,
                  title: 'TMDB',
                  value: show.isSeries
                      ? 'Backdrop, HD posters, season totals and next episode.'
                      : 'Backdrop and HD poster alternatives.',
                ),
                const SizedBox(height: 10),
                _SourceInfoRow(
                  icon: Icons.collections_bookmark_outlined,
                  title: 'Posters',
                  value: posterCount > 1
                      ? '$posterCount posters available.'
                      : 'Saved poster stays first.',
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: FilledButton.icon(
                    onPressed: _refreshingMetadata
                        ? null
                        : () {
                            Navigator.pop(context);
                            _refreshMetadata(show);
                          },
                    icon: _refreshingMetadata
                        ? const SizedBox(
                            width: 17,
                            height: 17,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh_rounded, size: 18),
                    label: Text(
                      _refreshingMetadata
                          ? 'Refreshing Metadata'
                          : 'Refresh Metadata',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ==========================================================
  // POSTER GALLERY LOGIC
  // ==========================================================

  String _upgradePosterUrl(String url) {
    final clean = url.trim();
    if (clean.isEmpty) return clean;

    if (clean.contains('image.tmdb.org/t/p/')) {
      return clean.replaceAll(
        RegExp(r'https://image\.tmdb\.org/t/p/[^/]+'),
        'https://image.tmdb.org/t/p/original',
      );
    }
    return clean.replaceAll(RegExp(r'SX\d+'), 'SX1080');
  }

  String _posterIdentity(String url) {
    var clean = url.trim().toLowerCase();
    clean = clean.replaceAll(RegExp(r'https://image\.tmdb\.org/t/p/[^/]+'), '');
    clean = clean.replaceAll(
      RegExp(r'_SX\d+_|_SY\d+_|_CR\d+,\d+,\d+,\d+_'),
      '',
    );
    return clean.replaceAll(RegExp(r'SX\d+'), 'SX');
  }

  void _addUniquePoster(List<String> posters, String? url) {
    final clean = url?.trim();
    if (clean == null || clean.isEmpty) return;

    final upgraded = _upgradePosterUrl(clean);
    final identity = _posterIdentity(upgraded);
    final exists = posters.any((item) => _posterIdentity(item) == identity);

    if (!exists) posters.add(upgraded);
  }

  List<String> _buildPosterGalleryUrls(Show show) {
    final posters = <String>[];
    _addUniquePoster(posters, show.posterUrl);

    final dynamic tmdbData = _tmdbData;
    final dynamic rawPosterUrls = tmdbData?.posterUrls;

    if (rawPosterUrls is Iterable) {
      for (final url in rawPosterUrls) {
        _addUniquePoster(posters, url?.toString());
        if (posters.length >= 6) break;
      }
    }

    _addUniquePoster(posters, _tmdbData?.hdPosterUrl);
    return posters;
  }

  void _openHdPoster(Show show) {
    final posters = _buildPosterGalleryUrls(show);
    if (posters.isEmpty) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _HdPosterScreen(title: show.title, posterUrls: posters),
      ),
    );
  }

  // ==========================================================
  // BUILD
  // ==========================================================

  @override
  Widget build(BuildContext context) {
    final show = context.watch<ShowProvider>().byId(widget.showId);

    if (show == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('This item is no longer available.')),
      );
    }

    if (_isReminderBlockedBySeriesState(show) && show.episodeReminderEnabled) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _autoDisableEndedSeriesReminderIfNeeded(show),
      );
    }

    if (!_hasFetchedTmdb && !_loadingTmdb) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _fetchTmdbMediaIfNeeded(show),
      );
    }

    if (show.id.startsWith('tt') &&
        (show.director.isEmpty || show.actors.isEmpty) &&
        !_fetchingDetails) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _fetchFullDetailsIfNeeded(show),
      );
    }

    if (show.isSeries &&
        (show.id.startsWith('tt') || show.id.startsWith('tmdb_tv_')) &&
        _loadingSeason != show.currentSeason &&
        !_seasonMetadataAttempted.contains(show.currentSeason)) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _loadSeasonInfo(show),
      );
    }

    final theme = Theme.of(context);

    return AmbientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text(
            show.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
          ),
          actions: <Widget>[
            if (_fetchingDetails || _loadingTmdb || _refreshingMetadata)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 22),
              onPressed: () => _edit(show),
            ),
            IconButton(
              icon: const Icon(
                Icons.delete_outline_rounded,
                color: Colors.red,
                size: 22,
              ),
              onPressed: () => _delete(show),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: <Widget>[
            // BACKDROP
            if (_tmdbData?.backdropUrl != null) ...<Widget>[
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: CachedNetworkImage(
                  imageUrl: _tmdbData!.backdropUrl!,
                  height: 180,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorWidget: (context, url, error) => const SizedBox.shrink(),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // HERO INFO
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                GestureDetector(
                  onTap: () => _openHdPoster(show),
                  child: Hero(
                    tag: 'poster-${show.id}',
                    child: Stack(
                      children: <Widget>[
                        PosterImage(
                          url: show.posterUrl,
                          width: 110,
                          height: 160,
                          radius: 14,
                        ),
                        Positioned(
                          bottom: 6,
                          right: 6,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(.65),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.zoom_in_rounded,
                              color: Colors.white,
                              size: 16,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        show.title,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          fontSize: 20,
                          height: 1.15,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${show.type} • ${show.yearText}',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (show.rating > 0) ...<Widget>[
                        const SizedBox(height: 6),
                        Row(
                          children: <Widget>[
                            const Icon(
                              Icons.star_rounded,
                              color: Color(0xFFFFC400),
                              size: 20,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              show.rating.toStringAsFixed(1),
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 15,
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (show.genre.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 6),
                        Text(
                          'Genre: ${show.genre}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontSize: 12.5,
                          ),
                        ),
                      ],
                      if (show.runtimeMinutes > 0) ...<Widget>[
                        const SizedBox(height: 4),
                        Text(
                          'Runtime: ${show.runtimeMinutes} min',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontSize: 12.5,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // OFFICIAL INFO PANEL (CLEAN DATE & TIME ONLY)
            _SmartMetadataPanel(
              show: show,
              posterCount: _buildPosterGalleryUrls(show).length,
              lastSyncText: _formatMetadataSync(show.metadataUpdatedAt),
              refreshing: _refreshingMetadata,
              loading: _fetchingDetails || _loadingTmdb,
              onRefresh: () => _refreshMetadata(show),
              onInfoTap: () => _showMetadataInfo(show),
            ),
            const SizedBox(height: 20),

            // STATUS PANEL
            Text(
              'Status',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: StatusStyle.statuses.map((status) {
                return _StatusChoice(
                  status: status,
                  selected: show.status == status,
                  onTap: () =>
                      context.read<ShowProvider>().setStatus(show.id, status),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),

            // PERSONAL NOTES PANEL
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'My Notes & Review',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
                TextButton.icon(
                  onPressed: () {
                    if (_isEditingNote) {
                      _savePersonalNote(show);
                    } else {
                      _noteController.text = show.personalNote;
                      setState(() {
                        _isEditingNote = true;
                      });
                    }
                  },
                  icon: Icon(
                    _isEditingNote
                        ? Icons.check_circle_rounded
                        : Icons.edit_note_rounded,
                    size: 18,
                  ),
                  label: Text(_isEditingNote ? 'Save' : 'Edit Note'),
                ),
              ],
            ),
            const SizedBox(height: 6),
            GlassContainer(
              padding: const EdgeInsets.all(14),
              borderRadius: 14,
              child: _isEditingNote
                  ? TextField(
                      controller: _noteController,
                      maxLines: 3,
                      style: const TextStyle(fontSize: 13.5),
                      decoration: const InputDecoration(
                        hintText: 'Write your thoughts or review...',
                        border: InputBorder.none,
                      ),
                    )
                  : Text(
                      show.personalNote.isNotEmpty
                          ? show.personalNote
                          : 'No personal notes added yet. Tap edit to write your thoughts!',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontStyle: show.personalNote.isEmpty
                            ? FontStyle.italic
                            : FontStyle.normal,
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 13.5,
                      ),
                    ),
            ),

            // UNIFIED WATCH PANEL (REMINDER + PROGRESS TRACKER)
            if (show.isSeries) ...<Widget>[
              const SizedBox(height: 20),
              Text(
                'Watch Panel',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 8),
              GlassContainer(
                borderRadius: 18,
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _EpisodeReminderContent(
                      show: show,
                      busy: _changingReminder,
                      formatDate: _formatEpisodeDate,
                      onChanged: (enabled) =>
                          _toggleEpisodeReminder(show, enabled),
                    ),
                    const Divider(height: 28),
                    _ProgressTrackerContent(
                      show: show,
                      loadingSeason: _loadingSeason == show.currentSeason,
                      seasonError: _seasonErrorSeason == show.currentSeason
                          ? _seasonError
                          : null,
                      onSeasonMinus: show.currentSeason > 1
                          ? () => _changeSeason(show, -1)
                          : null,
                      onSeasonPlus: () => _changeSeason(show, 1),
                      onEpisodeMinus:
                          show.currentSeason == 1 && show.currentEpisode == 0
                          ? null
                          : () => context.read<ShowProvider>().decrementEpisode(
                              show.id,
                            ),
                      onEpisodePlus: () => context
                          .read<ShowProvider>()
                          .incrementEpisode(show.id),
                      onMarkSeasonComplete: () => _markSeasonComplete(show),
                    ),
                  ],
                ),
              ),
            ],

            // UNIFIED ABOUT PANEL (PLOT, CAST, CREW, AWARDS)
            const SizedBox(height: 20),
            Text(
              'About',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 8),
            _AboutUnifiedPanel(show: show),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// SMART METADATA PANEL (STRICTLY CLEAN - ONLY DATE & TIME)
// ============================================================

class _SmartMetadataPanel extends StatelessWidget {
  final Show show;
  final int posterCount;
  final String lastSyncText;
  final bool refreshing;
  final bool loading;
  final VoidCallback onRefresh;
  final VoidCallback onInfoTap;

  const _SmartMetadataPanel({
    required this.show,
    required this.posterCount,
    required this.lastSyncText,
    required this.refreshing,
    required this.loading,
    required this.onRefresh,
    required this.onInfoTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final primary = colors.primary;

    final totalKnownEpisodes = show.seasonEpisodeCounts.values.fold<int>(
      0,
      (sum, count) => sum + (count > 0 ? count : 0),
    );

    final currentSeasonCount = show.currentSeasonEpisodeCount;

    final progressText = show.isSeries
        ? 'S${show.currentSeason} • EP${show.currentEpisode}'
        : show.status;

    final nextText =
        show.nextEpisodeSeason != null && show.nextEpisodeNumber != null
        ? 'Next S${show.nextEpisodeSeason} EP${show.nextEpisodeNumber}'
        : show.seriesEnded
        ? 'No Upcoming'
        : 'Next Unknown';

    final stateText = show.isSeries
        ? show.seriesEnded
              ? 'Series Ended'
              : show.hasUpcomingEpisode
              ? 'Ongoing'
              : 'Series'
        : 'Movie';

    final firstRow = show.isSeries
        ? <Widget>[
            _MetadataPill(
              icon: Icons.video_library_outlined,
              label:
                  '${show.totalSeasons} Season${show.totalSeasons == 1 ? '' : 's'}',
              accent: primary,
            ),
            _MetadataPill(
              icon: Icons.format_list_numbered_rounded,
              label: totalKnownEpisodes > 0
                  ? '$totalKnownEpisodes Episodes'
                  : currentSeasonCount > 0
                  ? 'S${show.currentSeason}: $currentSeasonCount EP'
                  : 'Episodes N/A',
              accent: Colors.indigo,
            ),
            _MetadataPill(
              icon: show.seriesEnded
                  ? Icons.flag_circle_outlined
                  : Icons.sensors_rounded,
              label: stateText,
              accent: show.seriesEnded ? Colors.orange : Colors.green,
            ),
            _MetadataPill(
              icon: Icons.play_circle_outline_rounded,
              label: progressText,
              accent: Colors.teal,
            ),
            _MetadataPill(
              icon: Icons.notifications_none_rounded,
              label: nextText,
              accent: show.seriesEnded ? Colors.grey : Colors.deepPurple,
            ),
          ]
        : <Widget>[
            _MetadataPill(
              icon: Icons.movie_creation_outlined,
              label: 'Movie',
              accent: primary,
            ),
            if (show.runtimeMinutes > 0)
              _MetadataPill(
                icon: Icons.schedule_rounded,
                label: '${show.runtimeMinutes} min',
                accent: Colors.teal,
              ),
            if (show.rating > 0)
              _MetadataPill(
                icon: Icons.star_border_rounded,
                label: 'IMDb ${show.rating.toStringAsFixed(1)}',
                accent: Colors.amber.shade800,
              ),
            _MetadataPill(
              icon: Icons.calendar_month_outlined,
              label: show.yearText,
              accent: Colors.indigo,
            ),
          ];

    return GlassContainer(
      borderRadius: 18,
      padding: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onInfoTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 11, 10, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: primary.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Icon(
                      Icons.auto_awesome_rounded,
                      color: primary,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const Text(
                          'Official Info',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        // STRICT REQUIREMENT: Only date & time here
                        Text(
                          loading
                              ? 'Loading metadata...'
                              : 'Last synced: $lastSyncText',
                          style: TextStyle(
                            fontSize: 11.2,
                            height: 1.3,
                            color: colors.onSurfaceVariant,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 38,
                    height: 38,
                    child: IconButton.filledTonal(
                      padding: EdgeInsets.zero,
                      tooltip: 'Refresh Metadata',
                      onPressed: refreshing ? null : onRefresh,
                      icon: refreshing
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh_rounded, size: 18),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 7,
                runSpacing: 7,
                children: <Widget>[
                  ...firstRow,
                  _MetadataPill(
                    icon: Icons.photo_library_outlined,
                    label: posterCount > 1
                        ? '$posterCount Posters'
                        : 'HD Poster',
                    accent: Colors.pinkAccent,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetadataPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color accent;

  const _MetadataPill({
    required this.icon,
    required this.label,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: accent.withOpacity(isDark ? 0.16 : 0.10),
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: accent.withOpacity(isDark ? 0.30 : 0.20)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 13.5, color: accent),
          const SizedBox(width: 4.5),
          Text(
            label,
            style: TextStyle(
              color: accent,
              fontSize: 11.2,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.1,
            ),
          ),
        ],
      ),
    );
  }
}

class _SourceInfoRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;

  const _SourceInfoRow({
    required this.icon,
    required this.title,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.onSurface.withOpacity(0.03),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.outline.withOpacity(0.08)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: colors.primary.withOpacity(0.10),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, size: 17, color: colors.primary),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 12.8,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 11.7,
                    height: 1.35,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// STATUS CHOICE
// ============================================================

class _StatusChoice extends StatelessWidget {
  final String status;
  final bool selected;
  final VoidCallback onTap;

  const _StatusChoice({
    required this.status,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = StatusStyle.color(status);
    final icon = StatusStyle.icon(status);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GlassContainer(
      borderRadius: 22,
      opacity: selected ? (isDark ? 0.28 : 0.20) : (isDark ? 0.08 : 0.04),
      borderColor: selected
          ? color.withOpacity(0.85)
          : (isDark
                ? Colors.white.withOpacity(0.18)
                : Colors.black.withOpacity(0.12)),
      boxShadow: selected
          ? [
              BoxShadow(
                color: color.withOpacity(0.30),
                blurRadius: 12,
                spreadRadius: 1,
              ),
            ]
          : null,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              icon,
              size: 15,
              color: selected
                  ? color
                  : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Text(
              status,
              style: TextStyle(
                color: selected
                    ? color
                    : Theme.of(context).colorScheme.onSurface,
                fontSize: 13,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// EPISODE REMINDER CONTENT (IN WATCH PANEL)
// ============================================================

class _EpisodeReminderContent extends StatelessWidget {
  final Show show;
  final bool busy;
  final String Function(DateTime date) formatDate;
  final ValueChanged<bool> onChanged;

  const _EpisodeReminderContent({
    required this.show,
    required this.busy,
    required this.formatDate,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;

    final endedBlocked =
        show.seriesEnded &&
        !show.hasUpcomingEpisode &&
        show.nextEpisodeAirDate == null;

    final statusEligible =
        show.status != 'Completed' && show.status != 'Dropped' && !endedBlocked;

    final nextSeason = show.nextEpisodeSeason;
    final nextEpisode = show.nextEpisodeNumber;
    final nextAirDate = show.nextEpisodeAirDate;

    String nextEpisodeText;

    if (endedBlocked) {
      nextEpisodeText = 'Series Ended';
    } else if (nextSeason != null && nextEpisode != null) {
      nextEpisodeText = 'S$nextSeason • EP$nextEpisode';
    } else {
      nextEpisodeText = 'Not announced yet';
    }

    String subtitle;

    if (endedBlocked) {
      subtitle = 'No upcoming episodes for this title.';
    } else if (!statusEligible) {
      subtitle = 'Reminders disabled while ${show.status}.';
    } else if (show.hasScheduledEpisodeReminder) {
      final reminderDate = show.reminderAirDate;
      subtitle = reminderDate != null
          ? 'Scheduled for ${formatDate(reminderDate)} at 10:00 AM.'
          : 'Episode reminder scheduled.';
    } else if (show.episodeReminderEnabled) {
      subtitle = nextAirDate == null
          ? 'Reminder on. Waiting for next air date.'
          : 'Reminder on. Automatically kept updated.';
    } else if (nextAirDate != null) {
      subtitle = 'Airs ${formatDate(nextAirDate)}';
    } else {
      subtitle = 'Turn on to get notified when new episodes release.';
    }

    final effectiveReminderOn = statusEligible && show.episodeReminderEnabled;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: primary.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                effectiveReminderOn
                    ? Icons.notifications_active_rounded
                    : endedBlocked
                    ? Icons.notifications_off_outlined
                    : Icons.notifications_none_rounded,
                color: primary,
                size: 19,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    endedBlocked ? 'Episode Reminder Off' : 'Next Episode',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    nextEpisodeText,
                    style: TextStyle(
                      color: endedBlocked
                          ? theme.colorScheme.onSurfaceVariant
                          : primary,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            if (busy)
              const SizedBox(
                width: 32,
                height: 32,
                child: Padding(
                  padding: EdgeInsets.all(6),
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else
              Switch(
                value: effectiveReminderOn,
                onChanged: statusEligible ? onChanged : null,
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          style: theme.textTheme.bodySmall?.copyWith(
            height: 1.3,
            fontSize: 11.8,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

// ============================================================
// PROGRESS TRACKER CONTENT (IN WATCH PANEL)
// ============================================================

class _ProgressTrackerContent extends StatelessWidget {
  final Show show;
  final bool loadingSeason;
  final String? seasonError;
  final VoidCallback? onSeasonMinus;
  final VoidCallback? onSeasonPlus;
  final VoidCallback? onEpisodeMinus;
  final VoidCallback? onEpisodePlus;
  final VoidCallback? onMarkSeasonComplete;

  const _ProgressTrackerContent({
    required this.show,
    required this.loadingSeason,
    required this.seasonError,
    required this.onSeasonMinus,
    required this.onSeasonPlus,
    required this.onEpisodeMinus,
    required this.onEpisodePlus,
    required this.onMarkSeasonComplete,
  });

  @override
  Widget build(BuildContext context) {
    final knownEpisodeCount = show.currentSeasonEpisodeCount;
    final episodeLimit = show.currentSeasonEpisodeCountIsFinal
        ? knownEpisodeCount
        : 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Progress Tracker',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 10),
        _ProgressRow(
          label: 'Season ${show.currentSeason}',
          minus: onSeasonMinus,
          plus: onSeasonPlus,
        ),
        const Divider(height: 18),
        _ProgressRow(
          label: episodeLimit > 0
              ? 'Episode ${show.currentEpisode} / $episodeLimit'
              : 'Episode ${show.currentEpisode}',
          minus: onEpisodeMinus,
          plus: onEpisodePlus,
        ),
        if (episodeLimit > 0 && show.currentEpisode < episodeLimit) ...<Widget>[
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 38,
            child: FilledButton.tonalIcon(
              onPressed: onMarkSeasonComplete,
              icon: const Icon(Icons.done_all_rounded, size: 16),
              label: Text(
                'Mark Season ${show.currentSeason} Complete',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ],
        if (loadingSeason) ...<Widget>[
          const SizedBox(height: 8),
          const LinearProgressIndicator(minHeight: 2),
        ],
        if (seasonError != null) ...<Widget>[
          const SizedBox(height: 6),
          Text(
            'Episode limit unavailable: $seasonError',
            style: TextStyle(
              color: Theme.of(context).colorScheme.error,
              fontSize: 11,
            ),
          ),
        ],
      ],
    );
  }
}

class _ProgressRow extends StatelessWidget {
  final String label;
  final VoidCallback? minus;
  final VoidCallback? plus;

  const _ProgressRow({
    required this.label,
    required this.minus,
    required this.plus,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: Text(
            label,
            style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600),
          ),
        ),
        RoundStepButton(isAdd: false, onPressed: minus, size: 34),
        const SizedBox(width: 8),
        RoundStepButton(isAdd: true, onPressed: plus, size: 34),
      ],
    );
  }
}

// ============================================================
// UNIFIED ABOUT PANEL (PLOT, CAST, CREW, AWARDS)
// ============================================================

class _AboutUnifiedPanel extends StatelessWidget {
  final Show show;

  const _AboutUnifiedPanel({required this.show});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final castList = show.actors
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    return GlassContainer(
      borderRadius: 18,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // PLOT SECTION
          if (show.plot.isNotEmpty) ...[
            Text(
              'Plot Overview',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.primary,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              show.plot,
              style: theme.textTheme.bodyMedium?.copyWith(
                height: 1.4,
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 13,
              ),
            ),
            const Divider(height: 24),
          ],

          // CAST SECTION
          if (castList.isNotEmpty) ...[
            Text(
              'Cast',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.primary,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: castList.map((actor) {
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.onSurface.withOpacity(0.04),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: theme.colorScheme.outline.withOpacity(0.08),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(
                        Icons.person_outline_rounded,
                        size: 14,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        actor,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
            const Divider(height: 24),
          ],

          // CREW SECTION
          _CrewTile(
            icon: Icons.movie_creation_outlined,
            title: 'Director',
            value: show.director.isNotEmpty ? show.director : 'N/A',
          ),
          if (show.writer.isNotEmpty) ...[
            const SizedBox(height: 8),
            _CrewTile(
              icon: Icons.edit_note_rounded,
              title: 'Writer',
              value: show.writer,
            ),
          ],
          if (show.language.isNotEmpty) ...[
            const SizedBox(height: 8),
            _CrewTile(
              icon: Icons.translate_rounded,
              title: 'Language',
              value: show.language,
            ),
          ],

          // AWARDS SECTION
          if (show.awards.isNotEmpty) ...[
            const Divider(height: 24),
            Row(
              children: <Widget>[
                const Icon(
                  Icons.emoji_events_rounded,
                  color: Color(0xFFFFA000),
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    show.awards,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFFB45309),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _CrewTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;

  const _CrewTile({
    required this.icon,
    required this.title,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(icon, size: 16, color: theme.colorScheme.primary),
        const SizedBox(width: 8),
        SizedBox(
          width: 70,
          child: Text(
            title,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

// ============================================================
// HD POSTER SCREEN
// ============================================================

class _HdPosterScreen extends StatefulWidget {
  final String title;
  final List<String> posterUrls;

  const _HdPosterScreen({required this.title, required this.posterUrls});

  @override
  State<_HdPosterScreen> createState() => _HdPosterScreenState();
}

class _HdPosterScreenState extends State<_HdPosterScreen> {
  late final PageController _pageController;
  int _index = 0;
  bool _downloading = false;

  String get _currentPosterUrl {
    if (widget.posterUrls.isEmpty) {
      return '';
    }
    return widget.posterUrls[_index.clamp(0, widget.posterUrls.length - 1)];
  }

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _shareOrSave() async {
    if (_downloading) {
      return;
    }

    final posterUrl = _currentPosterUrl;

    if (posterUrl.isEmpty) {
      return;
    }

    setState(() {
      _downloading = true;
    });

    final messenger = ScaffoldMessenger.of(context);

    try {
      final response = await http.get(Uri.parse(posterUrl));

      if (response.statusCode != 200) {
        throw Exception();
      }

      final tempDir = await getTemporaryDirectory();
      final cleanTitle = widget.title.replaceAll(RegExp(r'[^\w\s]+'), '_');
      final file = File(
        '${tempDir.path}/${cleanTitle}_poster_${_index + 1}.jpg',
      );

      await file.writeAsBytes(response.bodyBytes);

      await Share.shareXFiles(
        <XFile>[XFile(file.path, mimeType: 'image/jpeg')],
        subject: widget.title,
        text: widget.title,
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Could not download or share the poster.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _downloading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.posterUrls.length;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: Text(
          widget.title,
          style: const TextStyle(color: Colors.white, fontSize: 16),
        ),
        actions: <Widget>[
          IconButton(
            icon: _downloading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : const Icon(Icons.share_rounded, color: Colors.white),
            onPressed: _shareOrSave,
          ),
        ],
      ),
      body: Stack(
        children: <Widget>[
          PageView.builder(
            controller: _pageController,
            itemCount: total,
            onPageChanged: (value) {
              setState(() {
                _index = value;
              });
            },
            itemBuilder: (context, index) {
              final posterUrl = widget.posterUrls[index];

              return Center(
                child: InteractiveViewer(
                  minScale: 0.8,
                  maxScale: 4.0,
                  child: CachedNetworkImage(
                    imageUrl: posterUrl,
                    fit: BoxFit.contain,
                    placeholder: (context, url) => const Center(
                      child: CircularProgressIndicator(color: Colors.white24),
                    ),
                    errorWidget: (context, url, error) => const Text(
                      'Could not load HD poster.',
                      style: TextStyle(color: Colors.white70),
                    ),
                  ),
                ),
              );
            },
          ),
          if (total > 1)
            Positioned(
              bottom: 28,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.55),
                    borderRadius: BorderRadius.circular(100),
                    border: Border.all(color: Colors.white.withOpacity(0.18)),
                  ),
                  child: Text(
                    '${_index + 1} / $total',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
