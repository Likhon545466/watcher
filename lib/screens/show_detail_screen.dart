import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/show.dart';
import '../models/tmdb_episode_detail.dart';
import '../models/tmdb_video.dart';
import '../providers/show_provider.dart';
import '../services/notification_service.dart';
import '../services/omdb_service.dart';
import '../services/tmdb_service.dart';
import '../utils/status_style.dart';
import '../widgets/ambient_background.dart';
import '../widgets/glass_container.dart';
import '../widgets/poster_image.dart';
import '../widgets/round_step_button.dart';
import 'add_edit_show_screen.dart';
import 'discover_detail_screen.dart';
import 'person_detail_screen.dart';

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

  List<TmdbDiscoverItem> _recommendations = const <TmdbDiscoverItem>[];
  bool _loadingRecommendations = false;
  bool _hasFetchedRecommendations = false;

  final Set<String> _addingRecommendationIds = <String>{};

  // ==========================================================
  // TRAILERS & TEASERS
  // ==========================================================

  List<TmdbVideo> _videos = const <TmdbVideo>[];
  bool _loadingVideos = false;
  bool _hasFetchedVideos = false;

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
  // FETCH SIMILAR / RECOMMENDED
  // ==========================================================

  Future<void> _fetchRecommendationsIfNeeded(Show show) async {
    if (_hasFetchedRecommendations || _loadingRecommendations) {
      return;
    }

    setState(() {
      _loadingRecommendations = true;
    });

    try {
      final items = await TmdbService.fetchSimilarAndRecommended(
        showId: show.id,
        title: show.title,
        type: show.type,
        limit: 12,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _recommendations = items;
        _hasFetchedRecommendations = true;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _recommendations = const <TmdbDiscoverItem>[];
          _hasFetchedRecommendations = true;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _loadingRecommendations = false;
        });
      }
    }
  }

  Future<void> _openRecommendation(TmdbDiscoverItem item) async {
    final provider = context.read<ShowProvider>();

    final existing = provider.findLibraryMatchForTmdb(
      tmdbId: item.id,
      mediaType: item.mediaType,
      title: item.title,
      yearText: item.year,
    );

    if (existing != null) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ShowDetailScreen(showId: existing.id),
        ),
      );

      return;
    }

    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => DiscoverDetailScreen(item: item)),
    );
  }

  Future<void> _showRecommendationAddMenu(TmdbDiscoverItem item) async {
    final selectedStatus = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);

        const statuses = <String>[
          'Plan to Watch',
          'Watching',
          'Completed',
          'On Hold',
        ];

        return Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 18),
          child: GlassContainer(
            borderRadius: 22,
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            opacity: 0.96,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.onSurfaceVariant.withOpacity(
                        0.28,
                      ),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
                Text(
                  'Add to Watcher',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 14),
                for (final status in statuses) ...<Widget>[
                  ListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                    leading: Icon(
                      StatusStyle.icon(status),
                      color: StatusStyle.color(status),
                    ),
                    title: Text(
                      status,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    onTap: () => Navigator.pop(sheetContext, status),
                  ),
                  if (status != statuses.last)
                    Divider(
                      height: 1,
                      color: theme.colorScheme.outline.withOpacity(0.08),
                    ),
                ],
              ],
            ),
          ),
        );
      },
    );

    if (selectedStatus == null || !mounted) {
      return;
    }

    await _quickAddRecommendation(item, selectedStatus);
  }

  Future<void> _quickAddRecommendation(
    TmdbDiscoverItem item,
    String status,
  ) async {
    if (_addingRecommendationIds.contains(item.uniqueKey)) {
      return;
    }

    final provider = context.read<ShowProvider>();

    final existingBefore = provider.findLibraryMatchForTmdb(
      tmdbId: item.id,
      mediaType: item.mediaType,
      title: item.title,
      yearText: item.year,
    );

    if (existingBefore != null) {
      await provider.setStatus(existingBefore.id, status);
      return;
    }

    setState(() {
      _addingRecommendationIds.add(item.uniqueKey);
    });

    final messenger = ScaffoldMessenger.of(context);

    try {
      final imdbId = await TmdbService.getImdbId(item.id, item.mediaType);

      Show show;

      if (imdbId != null && imdbId.isNotEmpty) {
        try {
          show = await OmdbService.getDetails(imdbId, status: status);

          if (show.isSeries) {
            try {
              final season = await OmdbService.getSeason(show.id, 1);

              if (season.episodeCount > 0) {
                show = show.copyWith(
                  seasonEpisodeCounts: <int, int>{1: season.episodeCount},
                  seasonEpisodeCountFinalized: const <int, bool>{1: false},
                  updatedAt: show.updatedAt,
                );
              }
            } catch (_) {
              // TMDB background metadata sync can fill this later.
            }
          }
        } catch (_) {
          show = _createRecommendationFallbackShow(item, imdbId, status);
        }
      } else {
        show = _createRecommendationFallbackShow(
          item,
          'tmdb_${item.mediaType}_${item.id}',
          status,
        );
      }

      if (!mounted) {
        return;
      }

      final latestProvider = context.read<ShowProvider>();

      final existingAfter = latestProvider.findLibraryMatch(
        exactId: show.id,
        tmdbId: item.id,
        tmdbMediaType: item.mediaType,
        title: show.title,
        type: show.type,
        yearText: show.yearText,
      );

      if (existingAfter != null) {
        await latestProvider.setStatus(existingAfter.id, status);

        if (mounted) {
          setState(() {});
        }

        return;
      }

      final added = await latestProvider.addShow(show);

      if (!mounted) {
        return;
      }

      if (added) {
        if (show.isSeries) {
          unawaited(
            latestProvider.syncSeriesMetadataForShow(show.id, force: true),
          );
        }

        messenger.showSnackBar(
          SnackBar(content: Text('${item.title} added as $status.')),
        );

        setState(() {});
      } else {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('This title is already in your watchlist.'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _addingRecommendationIds.remove(item.uniqueKey);
        });
      }
    }
  }

  Show _createRecommendationFallbackShow(
    TmdbDiscoverItem item,
    String id,
    String status,
  ) {
    final now = DateTime.now();

    return Show(
      id: id,
      title: item.title,
      type: item.mediaType == 'tv' ? 'Series' : 'Movie',
      yearText: item.year,
      genre: 'N/A',
      director: 'N/A',
      writer: 'N/A',
      actors: 'N/A',
      language: 'N/A',
      awards: 'N/A',
      runtimeMinutes: 0,
      currentSeason: 1,
      currentEpisode: 0,
      totalSeasons: 1,
      seasonProgress: const <int, int>{},
      seasonEpisodeCounts: const <int, int>{},
      seasonEpisodeCountFinalized: const <int, bool>{},
      posterUrl: item.posterUrl ?? '',
      plot: item.overview,
      rating: item.voteAverage > 0
          ? double.parse(item.voteAverage.toStringAsFixed(1))
          : 0.0,
      status: status,
      createdAt: now,
      updatedAt: now,
    );
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
  // FETCH VIDEOS
  // ==========================================================

  Future<void> _fetchVideosIfNeeded(Show show) async {
    if (_hasFetchedVideos || _loadingVideos) return;
    setState(() {
      _loadingVideos = true;
    });

    try {
      final videos = await TmdbService.fetchVideos(
        showId: show.id,
        title: show.title,
        type: show.type,
      );
      if (mounted) {
        setState(() {
          _videos = videos;
          _hasFetchedVideos = true;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _videos = const <TmdbVideo>[];
          _hasFetchedVideos = true;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _loadingVideos = false;
        });
      }
    }
  }

  void _showTrailersModal(Show show) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        final bottom = MediaQuery.of(sheetContext).padding.bottom;

        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.fromLTRB(14, 0, 14, 16 + bottom),
              child: GlassContainer(
                borderRadius: 24,
                padding: const EdgeInsets.all(18),
                opacity: 0.96,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 14),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.onSurfaceVariant.withOpacity(
                            0.28,
                          ),
                          borderRadius: BorderRadius.circular(100),
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        const Icon(
                          Icons.play_circle_fill_rounded,
                          color: Colors.redAccent,
                          size: 26,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Official Trailers & Clips',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              Text(
                                show.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (_loadingVideos)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 32),
                        child: Center(
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    else if (_videos.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Center(
                          child: Text(
                            'No trailers or clips found.',
                            style: TextStyle(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      )
                    else
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight:
                              MediaQuery.of(sheetContext).size.height * 0.55,
                        ),
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: _videos.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 10),
                          itemBuilder: (ctx, i) {
                            final video = _videos[i];
                            return InkWell(
                              onTap: () async {
                                final uri = Uri.parse(video.youtubeUrl);
                                if (await canLaunchUrl(uri)) {
                                  await launchUrl(
                                    uri,
                                    mode: LaunchMode.externalApplication,
                                  );
                                }
                              },
                              borderRadius: BorderRadius.circular(14),
                              child: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: theme
                                      .colorScheme
                                      .surfaceContainerHighest
                                      .withOpacity(0.35),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: theme.colorScheme.outlineVariant
                                        .withOpacity(0.3),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Stack(
                                      alignment: Alignment.center,
                                      children: [
                                        ClipRRect(
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                          child: CachedNetworkImage(
                                            imageUrl: video.thumbnailUrl,
                                            width: 100,
                                            height: 58,
                                            fit: BoxFit.cover,
                                            errorWidget: (_, __, ___) =>
                                                Container(
                                                  width: 100,
                                                  height: 58,
                                                  color: Colors.black26,
                                                  child: const Icon(
                                                    Icons.movie_rounded,
                                                  ),
                                                ),
                                          ),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.all(4),
                                          decoration: BoxDecoration(
                                            color: Colors.black.withOpacity(
                                              0.65,
                                            ),
                                            shape: BoxShape.circle,
                                          ),
                                          child: const Icon(
                                            Icons.play_arrow_rounded,
                                            color: Colors.white,
                                            size: 18,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            video.name,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                              fontSize: 12.5,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 6,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: video.official
                                                  ? theme.colorScheme.primary
                                                        .withOpacity(0.15)
                                                  : theme
                                                        .colorScheme
                                                        .surfaceContainerHighest,
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              video.official
                                                  ? 'Official ${video.type}'
                                                  : video.type,
                                              style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.w700,
                                                color: video.official
                                                    ? theme.colorScheme.primary
                                                    : theme
                                                          .colorScheme
                                                          .onSurfaceVariant,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ==========================================================
  // EPISODE GUIDE & CHECKLIST (FEATURE 4)
  // ==========================================================

  void _showEpisodeGuideModal(Show show) {
    int currentModalSeason = show.currentSeason;
    List<TmdbEpisodeDetail> episodes = const <TmdbEpisodeDetail>[];
    bool loadingEpisodes = true;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        final bottom = MediaQuery.of(sheetContext).padding.bottom;
        final totalSeasons = show.totalSeasons > 0
            ? show.totalSeasons
            : (show.seasonProgress.keys.isNotEmpty
                  ? show.seasonProgress.keys.reduce(
                      (a, b) => a > b ? a : b,
                    )
                  : 1);

        return StatefulBuilder(
          builder: (modalCtx, setModalState) {
            void loadEpisodesForSeason(int s) async {
              setModalState(() {
                loadingEpisodes = true;
                currentModalSeason = s;
              });
              final result = await TmdbService.fetchSeasonEpisodeDetails(
                showId: show.id,
                title: show.title,
                seasonNumber: s,
              );
              setModalState(() {
                episodes = result;
                loadingEpisodes = false;
              });
            }

            if (loadingEpisodes && episodes.isEmpty) {
              loadEpisodesForSeason(currentModalSeason);
            }

            return Padding(
              padding: EdgeInsets.fromLTRB(14, 0, 14, 16 + bottom),
              child: GlassContainer(
                borderRadius: 24,
                padding: const EdgeInsets.all(18),
                opacity: 0.96,
                child: Consumer<ShowProvider>(
                  builder: (context, provider, _) {
                    final currentShow = provider.byId(show.id) ?? show;
                    final watchedUpTo =
                        currentShow.seasonProgress[currentModalSeason] ?? 0;

                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Center(
                          child: Container(
                            width: 36,
                            height: 4,
                            margin: const EdgeInsets.only(bottom: 14),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.onSurfaceVariant
                                  .withOpacity(0.28),
                              borderRadius: BorderRadius.circular(100),
                            ),
                          ),
                        ),
                        Row(
                          children: [
                            const Icon(
                              Icons.checklist_rounded,
                              color: Color(0xFF6C5CE7),
                              size: 26,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Season Episode Guide & Checklist',
                                    style: theme.textTheme.titleMedium
                                        ?.copyWith(fontWeight: FontWeight.w800),
                                  ),
                                  Text(
                                    '${currentShow.title} • Season $currentModalSeason',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        // SEASON CHIPS SELECTOR
                        SizedBox(
                          height: 36,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: totalSeasons,
                            separatorBuilder: (_, __) =>
                                const SizedBox(width: 8),
                            itemBuilder: (ctx, idx) {
                              final s = idx + 1;
                              final isSelected = s == currentModalSeason;
                              return ChoiceChip(
                                label: Text(
                                  'Season $s',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: isSelected
                                        ? FontWeight.w800
                                        : FontWeight.w600,
                                  ),
                                ),
                                selected: isSelected,
                                onSelected: (sel) {
                                  if (sel) loadEpisodesForSeason(s);
                                },
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 14),
                        if (loadingEpisodes)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 36),
                            child: Center(
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        else if (episodes.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 24),
                            child: Center(
                              child: Text(
                                'No detailed episode list available for Season $currentModalSeason.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          )
                        else
                          ConstrainedBox(
                            constraints: BoxConstraints(
                              maxHeight:
                                  MediaQuery.of(sheetContext).size.height *
                                  0.50,
                            ),
                            child: ListView.separated(
                              shrinkWrap: true,
                              itemCount: episodes.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 10),
                              itemBuilder: (ctx, i) {
                                final ep = episodes[i];
                                final isWatched =
                                    ep.episodeNumber <= watchedUpTo;

                                return Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: isWatched
                                        ? theme.colorScheme.primaryContainer
                                              .withOpacity(0.2)
                                        : theme
                                              .colorScheme
                                              .surfaceContainerHighest
                                              .withOpacity(0.35),
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: isWatched
                                          ? theme.colorScheme.primary
                                                .withOpacity(0.4)
                                          : theme.colorScheme.outlineVariant
                                                .withOpacity(0.25),
                                    ),
                                  ),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      if (ep.stillUrl != null &&
                                          ep.stillUrl!.isNotEmpty)
                                        ClipRRect(
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          child: CachedNetworkImage(
                                            imageUrl: ep.stillUrl!,
                                            width: 80,
                                            height: 48,
                                            fit: BoxFit.cover,
                                            errorWidget: (_, __, ___) =>
                                                Container(
                                                  width: 80,
                                                  height: 48,
                                                  color: Colors.black26,
                                                  child: const Icon(
                                                    Icons.tv_rounded,
                                                    size: 20,
                                                  ),
                                                ),
                                          ),
                                        )
                                      else
                                        Container(
                                          width: 44,
                                          height: 44,
                                          decoration: BoxDecoration(
                                            color: theme
                                                .colorScheme
                                                .surfaceContainerHighest,
                                            borderRadius: BorderRadius.circular(
                                              10,
                                            ),
                                          ),
                                          alignment: Alignment.center,
                                          child: Text(
                                            'E${ep.episodeNumber}',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w800,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'E${ep.episodeNumber}: ${ep.name.isNotEmpty ? ep.name : "Episode ${ep.episodeNumber}"}',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontWeight: FontWeight.w700,
                                                fontSize: 13,
                                                color: isWatched
                                                    ? theme.colorScheme.primary
                                                    : null,
                                              ),
                                            ),
                                            if (ep.airDate != null && ep.airDate!.isNotEmpty) ...[
                                              const SizedBox(height: 2),
                                              Text(
                                                'Air date: ${ep.airDate}',
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  color: theme
                                                      .colorScheme
                                                      .onSurfaceVariant,
                                                ),
                                              ),
                                            ],
                                            if (ep.overview.isNotEmpty) ...[
                                              const SizedBox(height: 4),
                                              Text(
                                                ep.overview,
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  fontSize: 11.5,
                                                  color: theme
                                                      .colorScheme
                                                      .onSurfaceVariant
                                                      .withOpacity(0.9),
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      IconButton(
                                        icon: Icon(
                                          isWatched
                                              ? Icons.check_circle_rounded
                                              : Icons
                                                    .radio_button_unchecked_rounded,
                                          color: isWatched
                                              ? theme.colorScheme.primary
                                              : theme
                                                    .colorScheme
                                                    .onSurfaceVariant,
                                          size: 24,
                                        ),
                                        tooltip: isWatched
                                            ? 'Mark as unread'
                                            : 'Mark watched',
                                        onPressed: () {
                                          provider.setEpisodeWatched(
                                            currentShow.id,
                                            currentModalSeason,
                                            ep.episodeNumber,
                                            !isWatched,
                                          );
                                        },
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ==========================================================
  // CUSTOM TAGS DIALOG (FEATURE 7)
  // ==========================================================

  void _showAddTagDialog(Show show) {
    final controller = TextEditingController();
    const suggestions = <String>[
      'Favorites',
      'Rewatch',
      'Anime',
      'Weekend Binge',
      'Netflix',
      'Marvel',
      'Must Watch',
      'Masterpiece',
    ];

    showDialog<void>(
      context: context,
      builder: (dialogCtx) {
        final theme = Theme.of(dialogCtx);
        return AlertDialog(
          title: const Text('Add Custom Tag'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: controller,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Tag Name',
                  hintText: 'e.g. Favorites, Anime, Rewatch',
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Quick Suggestions:',
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: suggestions.map((tag) {
                  return ActionChip(
                    label: Text(tag, style: const TextStyle(fontSize: 11.5)),
                    onPressed: () {
                      context.read<ShowProvider>().addTagToShow(show.id, tag);
                      Navigator.pop(dialogCtx);
                    },
                  );
                }).toList(),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final text = controller.text.trim();
                if (text.isNotEmpty) {
                  context.read<ShowProvider>().addTagToShow(show.id, text);
                }
                Navigator.pop(dialogCtx);
              },
              child: const Text('Add'),
            ),
          ],
        );
      },
    );
  }

  // ==========================================================
  // TOGGLE MOVIE REMINDER (FEATURE 11)
  // ==========================================================

  Future<void> _toggleMovieReminder(Show show, bool enabled) async {
    if (_changingReminder) return;
    setState(() {
      _changingReminder = true;
    });

    final messenger = ScaffoldMessenger.of(context);

    try {
      DateTime? releaseDate = show.movieReleaseDate;
      if (releaseDate == null && show.yearText.isNotEmpty) {
        final parsedYear = int.tryParse(show.yearText.trim());
        if (parsedYear != null && parsedYear >= DateTime.now().year) {
          releaseDate = DateTime(parsedYear, 12, 1);
        }
      }

      final result = await context
          .read<ShowProvider>()
          .setMovieReminderEnabled(show.id, enabled, releaseDate: releaseDate);

      if (!mounted) return;

      switch (result) {
        case EpisodeReminderResult.scheduled:
          messenger.showSnackBar(
            SnackBar(
              content: Text(
                'Movie release reminder scheduled for ${_formatEpisodeDate(show.movieReleaseDate ?? DateTime.now())}.',
              ),
            ),
          );
          break;
        case EpisodeReminderResult.enabledWaitingForEpisode:
          messenger.showSnackBar(
            const SnackBar(
              content: Text(
                'Reminder enabled! You will be alerted when the movie officially releases.',
              ),
            ),
          );
          break;
        case EpisodeReminderResult.disabled:
          messenger.showSnackBar(
            const SnackBar(content: Text('Movie reminder turned off.')),
          );
          break;
        case EpisodeReminderResult.permissionDenied:
          messenger.showSnackBar(
            const SnackBar(
              content: Text('Notification permission was not allowed.'),
            ),
          );
          break;
        default:
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
  // BACKDROP GALLERY + SHARE / SAVE
  // ==========================================================

  String _upgradeBackdropUrl(String url) {
    final clean = url.trim();

    if (clean.isEmpty) {
      return clean;
    }

    if (clean.contains('image.tmdb.org/t/p/')) {
      return clean.replaceAll(
        RegExp(r'https://image\.tmdb\.org/t/p/[^/]+'),
        'https://image.tmdb.org/t/p/original',
      );
    }

    return clean;
  }

  String _backdropIdentity(String url) {
    return url.trim().toLowerCase().replaceAll(
      RegExp(r'https://image\.tmdb\.org/t/p/[^/]+'),
      '',
    );
  }

  void _addUniqueBackdrop(List<String> backdrops, String? url) {
    final clean = url?.trim();

    if (clean == null || clean.isEmpty) {
      return;
    }

    final upgraded = _upgradeBackdropUrl(clean);
    final identity = _backdropIdentity(upgraded);

    final exists = backdrops.any((item) => _backdropIdentity(item) == identity);

    if (!exists) {
      backdrops.add(upgraded);
    }
  }

  List<String> _buildBackdropGalleryUrls() {
    final backdrops = <String>[];

    _addUniqueBackdrop(backdrops, _tmdbData?.backdropUrl);

    final dynamic tmdbData = _tmdbData;
    final dynamic rawBackdropUrls = tmdbData?.backdropUrls;

    if (rawBackdropUrls is Iterable) {
      for (final url in rawBackdropUrls) {
        _addUniqueBackdrop(backdrops, url?.toString());

        if (backdrops.length >= 10) {
          break;
        }
      }
    }

    return backdrops;
  }

  void _openHdBackdrop(Show show) {
    final backdrops = _buildBackdropGalleryUrls();

    if (backdrops.isEmpty) {
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            _HdBackdropScreen(title: show.title, backdropUrls: backdrops),
      ),
    );
  }

  // ==========================================================
  // PERSON DETAILS
  // ==========================================================

  Future<void> _openPerson(String name, {String? departmentHint}) async {
    final cleanName = name.trim();

    if (cleanName.isEmpty || cleanName == 'N/A') {
      return;
    }

    final messenger = ScaffoldMessenger.of(context);

    final person = await TmdbService.searchPerson(
      cleanName,
      departmentHint: departmentHint,
    );

    if (!mounted) {
      return;
    }

    if (person == null) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not find details for $cleanName.')),
      );
      return;
    }

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            PersonDetailScreen(personId: person.id, personName: person.name),
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

    if (!_hasFetchedRecommendations && !_loadingRecommendations) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _fetchRecommendationsIfNeeded(show),
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
              GestureDetector(
                onTap: () => _openHdBackdrop(show),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Stack(
                    children: <Widget>[
                      CachedNetworkImage(
                        imageUrl: _tmdbData!.backdropUrl!,
                        height: 180,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        errorWidget: (context, url, error) =>
                            const SizedBox.shrink(),
                      ),
                      Positioned(
                        bottom: 8,
                        right: 8,
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.62),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.open_in_full_rounded,
                            color: Colors.white,
                            size: 16,
                          ),
                        ),
                      ),
                    ],
                  ),
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
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: [
                          OutlinedButton.icon(
                            onPressed: () {
                              _fetchVideosIfNeeded(show);
                              _showTrailersModal(show);
                            },
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              visualDensity: VisualDensity.compact,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            icon: const Icon(
                              Icons.play_circle_outline_rounded,
                              size: 16,
                              color: Colors.redAccent,
                            ),
                            label: const Text(
                              'Trailers',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
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

            // CUSTOM TAGS & LISTS PANEL (FEATURE 7)
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Tags & Lists',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => _showAddTagDialog(show),
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('Add Tag'),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              GlassContainer(
                padding: const EdgeInsets.all(12),
                borderRadius: 14,
                child: show.customTags.isEmpty
                    ? InkWell(
                        onTap: () => _showAddTagDialog(show),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Row(
                            children: [
                              Icon(
                                Icons.label_outline_rounded,
                                size: 18,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'No tags added yet. Tap here to add custom tags/lists.',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: theme.colorScheme.onSurfaceVariant,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: show.customTags.map((tag) {
                          return InputChip(
                            label: Text(
                              tag,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            deleteIcon: const Icon(
                              Icons.close_rounded,
                              size: 14,
                            ),
                            onDeleted: () => context
                                .read<ShowProvider>()
                                .removeTagFromShow(show.id, tag),
                          );
                        }).toList(),
                      ),
              ),

              // UNIFIED WATCH PANEL (REMINDER + PROGRESS TRACKER + EPISODE GUIDE)
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
                            : () => context
                                  .read<ShowProvider>()
                                  .decrementEpisode(show.id),
                        onEpisodePlus: () => context
                            .read<ShowProvider>()
                            .incrementEpisode(show.id),
                        onMarkSeasonComplete: () => _markSeasonComplete(show),
                      ),
                      const Divider(height: 28),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () => _showEpisodeGuideModal(show),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          icon: const Icon(Icons.checklist_rounded, size: 18),
                          label: const Text(
                            'Episode Guide & Checklist',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ] else ...<Widget>[
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
                  child: Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          show.movieReminderEnabled
                              ? Icons.notifications_active_rounded
                              : Icons.notifications_none_rounded,
                          color: show.movieReminderEnabled
                              ? theme.colorScheme.primary
                              : theme.colorScheme.onSurfaceVariant,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Premiere Release Reminder',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13.5,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              show.movieReleaseDate != null
                                  ? 'Releases ${_formatEpisodeDate(show.movieReleaseDate!)}'
                                  : (show.movieReminderEnabled
                                        ? 'Reminder active for premiere date'
                                        : 'Get notified on movie release day'),
                              style: TextStyle(
                                fontSize: 12,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: show.movieReminderEnabled,
                        onChanged: _changingReminder
                            ? null
                            : (val) => _toggleMovieReminder(show, val),
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
            _AboutUnifiedPanel(
              show: show,
              onPersonTap: (name, departmentHint) =>
                  _openPerson(name, departmentHint: departmentHint),
            ),

            if (_loadingRecommendations ||
                _recommendations.isNotEmpty) ...<Widget>[
              const SizedBox(height: 24),
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      'You May Also Like',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  if (_loadingRecommendations)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              if (_recommendations.isNotEmpty)
                SizedBox(
                  height: 255,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    cacheExtent: 420,
                    itemCount: _recommendations.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 10),
                    itemBuilder: (context, index) {
                      final item = _recommendations[index];

                      final provider = context.watch<ShowProvider>();

                      final existing = provider.findLibraryMatchForTmdb(
                        tmdbId: item.id,
                        mediaType: item.mediaType,
                        title: item.title,
                        yearText: item.year,
                      );

                      final isAdding = _addingRecommendationIds.contains(
                        item.uniqueKey,
                      );

                      return _RecommendationCard(
                        item: item,
                        existingStatus: existing?.status,
                        adding: isAdding,
                        onTap: () => _openRecommendation(item),
                        onAdd: existing == null
                            ? () => _showRecommendationAddMenu(item)
                            : null,
                      );
                    },
                  ),
                )
              else if (_loadingRecommendations)
                const SizedBox(
                  height: 120,
                  child: Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
            ],
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
                  if (!endedBlocked && nextAirDate != null) ...<Widget>[
                    const SizedBox(height: 2),
                    Row(
                      children: <Widget>[
                        Icon(
                          Icons.calendar_month_rounded,
                          size: 12.5,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Airs ${formatDate(nextAirDate)}',
                          style: TextStyle(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
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
  final void Function(String name, String? departmentHint) onPersonTap;

  const _AboutUnifiedPanel({required this.show, required this.onPersonTap});

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
                return Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => onPersonTap(actor, 'Actor'),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
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
                          const SizedBox(width: 3),
                          Icon(
                            Icons.chevron_right_rounded,
                            size: 13,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ],
                      ),
                    ),
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
            onTap: show.director.isNotEmpty && show.director != 'N/A'
                ? () => onPersonTap(show.director, 'Director')
                : null,
          ),
          if (show.writer.isNotEmpty) ...[
            const SizedBox(height: 8),
            _CrewTile(
              icon: Icons.edit_note_rounded,
              title: 'Writer',
              value: show.writer,
              onTap: () => onPersonTap(show.writer, 'Writing'),
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
  final VoidCallback? onTap;

  const _CrewTile({
    required this.icon,
    required this.title,
    required this.value,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final content = Row(
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
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: onTap != null
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurface,
            ),
          ),
        ),
        if (onTap != null)
          Icon(
            Icons.chevron_right_rounded,
            size: 16,
            color: theme.colorScheme.onSurfaceVariant,
          ),
      ],
    );

    if (onTap == null) {
      return content;
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: content,
      ),
    );
  }
}

// ============================================================
// SIMILAR / RECOMMENDED CARD
// ============================================================

class _RecommendationCard extends StatelessWidget {
  final TmdbDiscoverItem item;
  final String? existingStatus;
  final bool adding;
  final VoidCallback onTap;
  final VoidCallback? onAdd;

  const _RecommendationCard({
    required this.item,
    required this.existingStatus,
    required this.adding,
    required this.onTap,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final typeLabel = item.mediaType == 'tv' ? 'Series' : 'Movie';
    final year = item.year == 'N/A' ? '' : item.year;
    final status = existingStatus;
    final statusColor = status != null ? StatusStyle.color(status) : null;

    return SizedBox(
      width: 118,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Stack(
              children: <Widget>[
                PosterImage(
                  url: item.posterUrl ?? '',
                  width: 118,
                  height: 166,
                  radius: 12,
                ),
                if (status != null && statusColor != null)
                  Positioned(
                    left: 6,
                    right: 6,
                    bottom: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.92),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Icon(
                            StatusStyle.icon(status),
                            size: 11,
                            color: Colors.white,
                          ),
                          const SizedBox(width: 3),
                          Flexible(
                            child: Text(
                              status,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 9.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 7),
            Text(
              item.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12.2,
                height: 1.15,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 3),
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    year.isEmpty ? typeLabel : '$typeLabel • $year',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10.2,
                      fontWeight: FontWeight.w600,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ),
                if (item.voteAverage > 0) ...<Widget>[
                  const SizedBox(width: 3),
                  const Icon(
                    Icons.star_rounded,
                    size: 10.5,
                    color: Color(0xFFFFC400),
                  ),
                  const SizedBox(width: 1),
                  Text(
                    item.voteAverage.toStringAsFixed(1),
                    style: TextStyle(
                      fontSize: 9.8,
                      fontWeight: FontWeight.w700,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
            if (status == null) ...<Widget>[
              const SizedBox(height: 6),
              SizedBox(
                width: double.infinity,
                height: 29,
                child: FilledButton.tonalIcon(
                  onPressed: adding ? null : onAdd,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    visualDensity: VisualDensity.compact,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(9),
                    ),
                  ),
                  icon: adding
                      ? const SizedBox(
                          width: 11,
                          height: 11,
                          child: CircularProgressIndicator(strokeWidth: 1.5),
                        )
                      : const Icon(Icons.add_rounded, size: 14),
                  label: Text(
                    adding ? 'Adding' : 'Add',
                    style: const TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ============================================================
// HD BACKDROP SCREEN
// ============================================================

class _HdBackdropScreen extends StatefulWidget {
  final String title;
  final List<String> backdropUrls;

  const _HdBackdropScreen({required this.title, required this.backdropUrls});

  @override
  State<_HdBackdropScreen> createState() => _HdBackdropScreenState();
}

class _HdBackdropScreenState extends State<_HdBackdropScreen> {
  late final PageController _pageController;
  int _index = 0;
  bool _busy = false;

  String get _currentBackdropUrl {
    if (widget.backdropUrls.isEmpty) {
      return '';
    }

    return widget.backdropUrls[_index.clamp(0, widget.backdropUrls.length - 1)];
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

  String _safeFileName(String value) {
    final clean = value
        .replaceAll(RegExp(r'[^\w\s-]+'), '_')
        .replaceAll(RegExp(r'\s+'), '_')
        .trim();

    return clean.isEmpty ? 'watcher_backdrop' : clean;
  }

  Future<File> _downloadCurrentBackdrop({required bool permanent}) async {
    final url = _currentBackdropUrl;

    if (url.isEmpty) {
      throw Exception('Backdrop URL is empty.');
    }

    final response = await http.get(Uri.parse(url));

    if (response.statusCode != 200) {
      throw Exception('Backdrop download failed.');
    }

    final directory = permanent
        ? await getApplicationDocumentsDirectory()
        : await getTemporaryDirectory();

    final file = File(
      '${directory.path}/'
      '${_safeFileName(widget.title)}_backdrop_${_index + 1}.jpg',
    );

    await file.writeAsBytes(response.bodyBytes, flush: true);

    return file;
  }

  Future<void> _shareBackdrop() async {
    if (_busy) {
      return;
    }

    setState(() {
      _busy = true;
    });

    final messenger = ScaffoldMessenger.of(context);

    try {
      final file = await _downloadCurrentBackdrop(permanent: false);

      await Share.shareXFiles(
        <XFile>[XFile(file.path, mimeType: 'image/jpeg')],
        subject: widget.title,
        text: widget.title,
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not share the backdrop.')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _saveBackdrop() async {
    if (_busy) {
      return;
    }

    setState(() {
      _busy = true;
    });

    final messenger = ScaffoldMessenger.of(context);

    try {
      final file = await _downloadCurrentBackdrop(permanent: false);

      var hasAccess = await Gal.hasAccess();

      if (!hasAccess) {
        await Gal.requestAccess();
        hasAccess = await Gal.hasAccess();
      }

      if (!hasAccess) {
        throw Exception('Gallery permission denied.');
      }

      await Gal.putImage(file.path);

      messenger.showSnackBar(
        const SnackBar(content: Text('Backdrop saved to Gallery.')),
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Could not save the backdrop to Gallery.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.backdropUrls.length;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: Text(
          widget.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: <Widget>[
          IconButton(
            tooltip: 'Save',
            onPressed: _busy ? null : _saveBackdrop,
            icon: const Icon(Icons.download_rounded, color: Colors.white),
          ),
          IconButton(
            tooltip: 'Share',
            onPressed: _busy ? null : _shareBackdrop,
            icon: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : const Icon(Icons.share_rounded, color: Colors.white),
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
              final backdropUrl = widget.backdropUrls[index];

              return Center(
                child: InteractiveViewer(
                  minScale: 0.8,
                  maxScale: 4.0,
                  child: CachedNetworkImage(
                    imageUrl: backdropUrl,
                    fit: BoxFit.contain,
                    placeholder: (context, url) => const Center(
                      child: CircularProgressIndicator(color: Colors.white24),
                    ),
                    errorWidget: (context, url, error) => const Text(
                      'Could not load HD backdrop.',
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

  Future<File> _downloadCurrentPoster() async {
    final posterUrl = _currentPosterUrl;

    if (posterUrl.isEmpty) {
      throw Exception('Poster URL is empty.');
    }

    final response = await http.get(Uri.parse(posterUrl));

    if (response.statusCode != 200) {
      throw Exception('Poster download failed.');
    }

    final tempDir = await getTemporaryDirectory();
    final cleanTitle = widget.title.replaceAll(RegExp(r'[^\w\s]+'), '_');
    final file = File('${tempDir.path}/${cleanTitle}_poster_${_index + 1}.jpg');

    await file.writeAsBytes(response.bodyBytes, flush: true);

    return file;
  }

  Future<void> _sharePoster() async {
    if (_downloading) {
      return;
    }

    setState(() {
      _downloading = true;
    });

    final messenger = ScaffoldMessenger.of(context);

    try {
      final file = await _downloadCurrentPoster();

      await Share.shareXFiles(
        <XFile>[XFile(file.path, mimeType: 'image/jpeg')],
        subject: widget.title,
        text: widget.title,
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not share the poster.')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _downloading = false;
        });
      }
    }
  }

  Future<void> _savePoster() async {
    if (_downloading) {
      return;
    }

    setState(() {
      _downloading = true;
    });

    final messenger = ScaffoldMessenger.of(context);

    try {
      final file = await _downloadCurrentPoster();

      var hasAccess = await Gal.hasAccess();

      if (!hasAccess) {
        await Gal.requestAccess();
        hasAccess = await Gal.hasAccess();
      }

      if (!hasAccess) {
        throw Exception('Gallery permission denied.');
      }

      await Gal.putImage(file.path);

      messenger.showSnackBar(
        const SnackBar(content: Text('Poster saved to Gallery.')),
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not save the poster to Gallery.')),
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
            tooltip: 'Save',
            onPressed: _downloading ? null : _savePoster,
            icon: const Icon(Icons.download_rounded, color: Colors.white),
          ),
          IconButton(
            tooltip: 'Share',
            onPressed: _downloading ? null : _sharePoster,
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
