import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/show.dart';
import '../providers/show_provider.dart';
import '../services/omdb_service.dart';
import '../services/tmdb_service.dart';
import '../utils/status_style.dart';
import '../widgets/ambient_background.dart';
import '../widgets/glass_container.dart';
import '../widgets/poster_image.dart';
import 'show_detail_screen.dart';

class DiscoverDetailScreen extends StatefulWidget {
  final TmdbDiscoverItem item;

  const DiscoverDetailScreen({super.key, required this.item});

  @override
  State<DiscoverDetailScreen> createState() => _DiscoverDetailScreenState();
}

class _DiscoverDetailScreenState extends State<DiscoverDetailScreen> {
  Show? _fullShowDetails;

  bool _loadingDetails = true;

  bool _addingToWatchlist = false;

  // ==========================================================
  // INIT
  // ==========================================================

  @override
  void initState() {
    super.initState();

    _fetchFullDetails();
  }

  // ==========================================================
  // FETCH FULL DETAILS
  // ==========================================================

  Future<void> _fetchFullDetails() async {
    final item = widget.item;

    final itemIdStr = item.id;

    try {
      final imdbId = await TmdbService.getImdbId(itemIdStr, item.mediaType);

      Show show;

      if (imdbId != null && imdbId.isNotEmpty) {
        try {
          show = await OmdbService.getDetails(imdbId);

          if (show.isSeries) {
            try {
              final season = await OmdbService.getSeason(show.id, 1);

              if (season.episodeCount > 0) {
                show = show.copyWith(
                  seasonEpisodeCounts: <int, int>{1: season.episodeCount},

                  // OMDb season data is only fallback data.
                  // It must not be treated as a verified
                  // final episode limit.
                  seasonEpisodeCountFinalized: const <int, bool>{1: false},

                  updatedAt: show.updatedAt,
                );
              }
            } catch (_) {
              // TMDB sync can update episode metadata later.
            }
          }
        } catch (_) {
          show = _createFallbackShow(item, imdbId);
        }
      } else {
        show = _createFallbackShow(item, _tmdbFallbackId(item));
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _fullShowDetails = show;

        _loadingDetails = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _fullShowDetails = _createFallbackShow(item, _tmdbFallbackId(item));

        _loadingDetails = false;
      });
    }
  }

  // ==========================================================
  // CONSISTENT TMDB FALLBACK ID
  // ==========================================================

  String _tmdbFallbackId(TmdbDiscoverItem item) {
    return 'tmdb_${item.mediaType}_${item.id}';
  }

  // ==========================================================
  // FALLBACK SHOW
  // ==========================================================

  Show _createFallbackShow(TmdbDiscoverItem item, String id) {
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

      status: 'Plan to Watch',

      createdAt: DateTime.now(),

      updatedAt: DateTime.now(),
    );
  }

  // ==========================================================
  // FIND EXISTING LIBRARY ITEM
  // ==========================================================

  Show? _findExisting(ShowProvider provider) {
    final item = widget.item;

    return provider.findLibraryMatchForTmdb(
      tmdbId: item.id,

      mediaType: item.mediaType,

      title: item.title,

      yearText: item.year,
    );
  }

  // ==========================================================
  // OPEN EXISTING LIBRARY DETAILS
  // ==========================================================

  Future<void> _openExisting(Show existing) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ShowDetailScreen(showId: existing.id)),
    );
  }

  // ==========================================================
  // ADD TO WATCHLIST
  // ==========================================================

  Future<void> _openAddStatusSheet() async {
    if (_addingToWatchlist || _fullShowDetails == null) {
      return;
    }

    final provider = context.read<ShowProvider>();

    final existing = _findExisting(provider);

    if (existing != null) {
      await _openExisting(existing);

      return;
    }

    final selectedStatus = await _showSaveStatusSheet(_fullShowDetails!);

    if (selectedStatus == null || !mounted) {
      return;
    }

    await _addToLibraryWithStatus(selectedStatus);
  }

  Future<String?> _showSaveStatusSheet(Show show) {
    final statuses = show.isMovie
        ? const <String>['Plan to Watch', 'Completed', 'On Hold']
        : const <String>['Plan to Watch', 'Watching', 'Completed', 'On Hold'];

    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        final theme = Theme.of(context);

        final colors = theme.colorScheme;

        final bottom = MediaQuery.of(context).padding.bottom;

        return Padding(
          padding: EdgeInsets.fromLTRB(14, 0, 14, 14 + bottom),
          child: GlassContainer(
            borderRadius: 26,
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
            opacity: 0.95,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Center(
                  child: Container(
                    width: 38,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 18),
                    decoration: BoxDecoration(
                      color: colors.onSurfaceVariant.withOpacity(0.25),
                      borderRadius: BorderRadius.circular(100),
                    ),
                  ),
                ),

                Row(
                  children: <Widget>[
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: colors.primary.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(15),
                        border: Border.all(
                          color: colors.primary.withOpacity(0.20),
                        ),
                      ),
                      child: Icon(
                        Icons.playlist_add_check_rounded,
                        color: colors.primary,
                      ),
                    ),

                    const SizedBox(width: 12),

                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            'Save to Library',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Choose the status before adding this title.',
                            style: TextStyle(
                              fontSize: 12.5,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                ...statuses.map((status) {
                  final color = StatusStyle.color(status);

                  final subtitle = switch (status) {
                    'Completed' =>
                      show.isMovie
                          ? 'You have already watched this movie.'
                          : 'Save it as already finished.',
                    'Watching' => 'You are watching this series now.',
                    'On Hold' => 'Save it, but keep it paused for later.',
                    _ => 'Save it for later watching.',
                  };

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 9),
                    child: Material(
                      color: color.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(18),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(18),
                        onTap: () {
                          Navigator.pop(context, status);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: color.withOpacity(0.25)),
                          ),
                          child: Row(
                            children: <Widget>[
                              Container(
                                width: 34,
                                height: 34,
                                decoration: BoxDecoration(
                                  color: color.withOpacity(0.16),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  StatusStyle.icon(status),
                                  color: color,
                                  size: 18,
                                ),
                              ),
                              const SizedBox(width: 11),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: <Widget>[
                                    Text(
                                      status,
                                      style: TextStyle(
                                        color: color,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 13.5,
                                      ),
                                    ),
                                    const SizedBox(height: 1),
                                    Text(
                                      subtitle,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: colors.onSurfaceVariant,
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(
                                Icons.chevron_right_rounded,
                                color: colors.onSurfaceVariant,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }),

                const SizedBox(height: 2),

                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () {
                      Navigator.pop(context);
                    },
                    child: const Text('Cancel'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _addToLibraryWithStatus(String status) async {
    if (_addingToWatchlist || _fullShowDetails == null) {
      return;
    }

    final provider = context.read<ShowProvider>();

    final existing = _findExisting(provider);

    if (existing != null) {
      await _openExisting(existing);

      return;
    }

    setState(() {
      _addingToWatchlist = true;
    });

    final messenger = ScaffoldMessenger.of(context);

    try {
      final baseShow = _fullShowDetails!;

      final shouldMarkActivity = status == 'Watching' || status == 'Completed';

      final show = baseShow.copyWith(
        status: status,
        lastWatchedAt: shouldMarkActivity
            ? DateTime.now()
            : baseShow.lastWatchedAt,
      );

      // ======================================================
      // SECOND DUPLICATE CHECK
      // ======================================================

      final latestExisting = provider.findLibraryMatch(
        exactId: show.id,

        tmdbId: widget.item.id,

        tmdbMediaType: widget.item.mediaType,

        title: show.title,

        type: show.type,

        yearText: show.yearText,
      );

      if (latestExisting != null) {
        if (!mounted) {
          return;
        }

        await _openExisting(latestExisting);

        return;
      }

      final added = await provider.addShow(show);

      if (!mounted) {
        return;
      }

      if (added) {
        messenger.showSnackBar(
          SnackBar(content: Text('${widget.item.title} added as $status.')),
        );

        // ====================================================
        // SERIES METADATA VERIFICATION
        // ====================================================

        if (show.isSeries) {
          unawaited(provider.syncSeriesMetadataForShow(show.id, force: true));
        }
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
          _addingToWatchlist = false;
        });
      }
    }
  }

  // ==========================================================
  // BUILD
  // ==========================================================

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final item = widget.item;

    final show = _fullShowDetails;

    // ========================================================
    // PHASE 2: LIVE LIBRARY STATE
    // ========================================================

    final provider = context.watch<ShowProvider>();

    final existing = _findExisting(provider);

    final alreadyInLibrary = existing != null;

    final libraryStatusColor = existing != null
        ? StatusStyle.color(existing.status)
        : theme.colorScheme.primary;

    final castList = (show?.actors ?? '')
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty && e != 'N/A')
        .toList();

    return AmbientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,

        // ====================================================
        // APP BAR
        // ====================================================
        appBar: AppBar(
          title: Text(
            item.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
          ),
          actions: <Widget>[
            if (_loadingDetails)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
          ],
        ),

        // ====================================================
        // BODY
        // ====================================================
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: <Widget>[
            // =================================================
            // POSTER + BASIC INFORMATION
            // =================================================
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                PosterImage(
                  url: (show?.posterUrl.isNotEmpty ?? false)
                      ? show!.posterUrl
                      : (item.posterUrl ?? ''),
                  width: 115,
                  height: 165,
                  radius: 14,
                ),

                const SizedBox(width: 16),

                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        item.title,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          fontSize: 20,
                          height: 1.15,
                        ),
                      ),

                      const SizedBox(height: 6),

                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          item.mediaType == 'tv' ? 'TV Series' : 'Movie',
                          style: TextStyle(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w700,
                            fontSize: 11.5,
                          ),
                        ),
                      ),

                      const SizedBox(height: 6),

                      Text(
                        'Release: ${item.year.isNotEmpty ? item.year : 'N/A'}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),

                      if (show != null && show.rating > 0) ...<Widget>[
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

                      if (show != null &&
                          show.genre.isNotEmpty &&
                          show.genre != 'N/A') ...<Widget>[
                        const SizedBox(height: 6),
                        Text(
                          'Genre: ${show.genre}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                      ],

                      if (show != null && show.runtimeMinutes > 0) ...<Widget>[
                        const SizedBox(height: 4),
                        Text(
                          'Runtime: ${show.runtimeMinutes} min',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),

            // =================================================
            // WATCHLIST / LIBRARY BUTTON
            // =================================================
            FilledButton.icon(
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),

              onPressed: _addingToWatchlist
                  ? null
                  : alreadyInLibrary
                  ? () => _openExisting(existing)
                  : _loadingDetails
                  ? null
                  : _openAddStatusSheet,

              icon: _addingToWatchlist
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : alreadyInLibrary
                  ? Icon(Icons.check_circle_rounded, color: libraryStatusColor)
                  : const Icon(Icons.add_rounded),

              label: Text(
                _addingToWatchlist
                    ? 'Adding...'
                    : alreadyInLibrary
                    ? 'In Library • ${existing.status}'
                    : _loadingDetails
                    ? 'Loading Details...'
                    : 'Add to Library',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
            ),

            const SizedBox(height: 20),

            // =================================================
            // OVERVIEW
            // =================================================
            Text(
              'Overview',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),

            const SizedBox(height: 8),

            GlassContainer(
              padding: const EdgeInsets.all(14),
              borderRadius: 16,
              child: Text(
                (show?.plot.isNotEmpty ?? false)
                    ? show!.plot
                    : (item.overview.isNotEmpty
                          ? item.overview
                          : 'No plot summary available.'),
                style: theme.textTheme.bodyMedium?.copyWith(
                  height: 1.45,
                  color: theme.colorScheme.onSurfaceVariant,
                  fontSize: 13.5,
                ),
              ),
            ),

            const SizedBox(height: 20),

            // =================================================
            // CAST
            // =================================================
            if (castList.isNotEmpty) ...<Widget>[
              Text(
                'Cast & Crew',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),

              const SizedBox(height: 10),

              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: castList.map((actor) {
                  return GlassContainer(
                    borderRadius: 16,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Icon(
                          Icons.person_outline_rounded,
                          size: 15,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          actor,
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),

              const SizedBox(height: 14),
            ],

            // =================================================
            // CREW
            // =================================================
            if (show != null) ...<Widget>[
              GlassContainer(
                padding: const EdgeInsets.all(14),
                borderRadius: 16,
                child: Column(
                  children: <Widget>[
                    _CrewTile(
                      icon: Icons.movie_creation_outlined,
                      title: 'Director',
                      value: show.director.isNotEmpty ? show.director : 'N/A',
                    ),

                    if (show.writer.isNotEmpty &&
                        show.writer != 'N/A') ...<Widget>[
                      const Divider(height: 16),
                      _CrewTile(
                        icon: Icons.edit_note_rounded,
                        title: 'Writer',
                        value: show.writer,
                      ),
                    ],

                    if (show.language.isNotEmpty &&
                        show.language != 'N/A') ...<Widget>[
                      const Divider(height: 16),
                      _CrewTile(
                        icon: Icons.translate_rounded,
                        title: 'Language',
                        value: show.language,
                      ),
                    ],
                  ],
                ),
              ),

              if (show.awards.isNotEmpty && show.awards != 'N/A') ...<Widget>[
                const SizedBox(height: 12),

                GlassContainer(
                  borderRadius: 14,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  borderColor: const Color(0xFFFFE082),
                  child: Row(
                    children: <Widget>[
                      const Icon(
                        Icons.emoji_events_rounded,
                        color: Color(0xFFFFA000),
                        size: 22,
                      ),

                      const SizedBox(width: 10),

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
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

// ============================================================
// CREW TILE
// ============================================================

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
        Icon(icon, size: 18, color: theme.colorScheme.primary),

        const SizedBox(width: 10),

        SizedBox(
          width: 70,
          child: Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),

        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}
