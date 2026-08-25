import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
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
import 'discover_detail_screen.dart';
import 'show_detail_screen.dart';

enum _WorksFilter { all, movies, series }

enum _WorksSort { popularity, latest, rating }

class PersonDetailScreen extends StatefulWidget {
  final String personId;
  final String personName;

  const PersonDetailScreen({
    super.key,
    required this.personId,
    required this.personName,
  });

  @override
  State<PersonDetailScreen> createState() => _PersonDetailScreenState();
}

class _PersonDetailScreenState extends State<PersonDetailScreen> {
  static const int _initialVisibleWorks = 12;
  static const int _loadMoreStep = 9;

  TmdbPersonDetails? _details;
  bool _loading = true;
  bool _refreshing = false;
  String? _error;

  bool _biographyExpanded = false;
  _WorksFilter _worksFilter = _WorksFilter.all;
  _WorksSort _worksSort = _WorksSort.popularity;
  int _visibleWorks = _initialVisibleWorks;

  final Set<String> _addingWorkIds = <String>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool forceRefresh = false}) async {
    if (forceRefresh) {
      if (_refreshing) {
        return;
      }

      setState(() {
        _refreshing = true;
        _error = null;
      });
    } else {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final details = await TmdbService.fetchPersonDetails(
        widget.personId,
        forceRefresh: forceRefresh,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _details = details;
        _error = details == null ? 'Person details are not available.' : null;
        _visibleWorks = _initialVisibleWorks;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Could not load person details.';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _refreshing = false;
        });
      }
    }
  }

  Future<void> _openWork(TmdbDiscoverItem item) async {
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

  Future<void> _showQuickAddMenu(TmdbDiscoverItem item) async {
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

    await _quickAddWork(item, selectedStatus);
  }

  Future<void> _quickAddWork(TmdbDiscoverItem item, String status) async {
    if (_addingWorkIds.contains(item.uniqueKey)) {
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
      _addingWorkIds.add(item.uniqueKey);
    });

    final messenger = ScaffoldMessenger.of(context);

    try {
      final imdbId = await TmdbService.getImdbId(item.id, item.mediaType);

      Show show;

      if (imdbId != null && imdbId.isNotEmpty) {
        try {
          show = await OmdbService.getDetails(imdbId, status: status);
        } catch (_) {
          show = _createFallbackShow(item, imdbId, status);
        }
      } else {
        show = _createFallbackShow(
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
          _addingWorkIds.remove(item.uniqueKey);
        });
      }
    }
  }

  Show _createFallbackShow(TmdbDiscoverItem item, String id, String status) {
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

  String _formatDate(String raw) {
    if (raw.trim().isEmpty) {
      return '';
    }

    final parsed = DateTime.tryParse(raw);

    if (parsed == null) {
      return raw;
    }

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

    return '${months[parsed.month - 1]} ${parsed.day}, ${parsed.year}';
  }

  List<TmdbDiscoverItem> _filteredWorks(TmdbPersonDetails details) {
    Iterable<TmdbDiscoverItem> items = details.knownFor;

    switch (_worksFilter) {
      case _WorksFilter.movies:
        items = items.where((item) => item.mediaType == 'movie');
        break;
      case _WorksFilter.series:
        items = items.where((item) => item.mediaType == 'tv');
        break;
      case _WorksFilter.all:
        break;
    }

    final list = items.toList(growable: false);

    switch (_worksSort) {
      case _WorksSort.latest:
        list.sort((a, b) => b.releaseDate.compareTo(a.releaseDate));
        break;
      case _WorksSort.rating:
        list.sort((a, b) => b.voteAverage.compareTo(a.voteAverage));
        break;
      case _WorksSort.popularity:
        // TMDB service already ranks person credits by relevance/popularity.
        // Keep that order to avoid extra work and preserve department relevance.
        break;
    }

    return list;
  }

  void _setFilter(_WorksFilter filter) {
    if (_worksFilter == filter) {
      return;
    }

    setState(() {
      _worksFilter = filter;
      _visibleWorks = _initialVisibleWorks;
    });
  }

  void _setSort(_WorksSort sort) {
    if (_worksSort == sort) {
      return;
    }

    setState(() {
      _worksSort = sort;
      _visibleWorks = _initialVisibleWorks;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AmbientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text(
            _details?.name.isNotEmpty == true
                ? _details!.name
                : widget.personName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          actions: <Widget>[
            IconButton(
              tooltip: 'Refresh',
              onPressed: _refreshing ? null : () => _load(forceRefresh: true),
              icon: _refreshing
                  ? const SizedBox(
                      width: 17,
                      height: 17,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null && _details == null
            ? _PersonErrorState(
                message: _error!,
                onRetry: () => _load(forceRefresh: true),
              )
            : _buildContent(context, _details!),
      ),
    );
  }

  Widget _buildContent(BuildContext context, TmdbPersonDetails details) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    final birthday = _formatDate(details.birthday);
    final deathday = _formatDate(details.deathday);

    final allFilteredWorks = _filteredWorks(details);
    final visibleCount = _visibleWorks
        .clamp(0, allFilteredWorks.length)
        .toInt();
    final visibleWorks = allFilteredWorks
        .take(visibleCount)
        .toList(growable: false);

    // One provider subscription for the whole screen instead of one watch()
    // subscription per card. This keeps rebuild overhead low.
    final libraryItems = context.select<ShowProvider, List<Show>>(
      (provider) => provider.shows,
    );

    Show? findExisting(TmdbDiscoverItem item) {
      final provider = context.read<ShowProvider>();

      return provider.findLibraryMatchForTmdb(
        tmdbId: item.id,
        mediaType: item.mediaType,
        title: item.title,
        yearText: item.year,
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 36),
      cacheExtent: 500,
      children: <Widget>[
        _CompactProfileHeader(
          details: details,
          birthday: birthday,
          deathday: deathday,
        ),

        if (details.biography.isNotEmpty) ...<Widget>[
          const SizedBox(height: 20),
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  'Biography',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
              ),
              TextButton(
                onPressed: () {
                  setState(() {
                    _biographyExpanded = !_biographyExpanded;
                  });
                },
                child: Text(_biographyExpanded ? 'Show Less' : 'Read More'),
              ),
            ],
          ),
          GlassContainer(
            borderRadius: 16,
            padding: const EdgeInsets.all(14),
            child: Text(
              details.biography,
              maxLines: _biographyExpanded ? null : 5,
              overflow: _biographyExpanded
                  ? TextOverflow.visible
                  : TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                height: 1.45,
                color: colors.onSurfaceVariant,
              ),
            ),
          ),
        ],

        const SizedBox(height: 22),
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                details.knownForDepartment.toLowerCase().contains('direct')
                    ? 'Directed / Known Works'
                    : details.knownForDepartment.toLowerCase().contains(
                        'acting',
                      )
                    ? 'Known For'
                    : 'Previous & Known Works',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
            ),
            Text(
              '${allFilteredWorks.length}',
              style: TextStyle(
                fontSize: 12,
                color: colors.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        _WorksControls(
          filter: _worksFilter,
          sort: _worksSort,
          onFilterChanged: _setFilter,
          onSortChanged: _setSort,
        ),
        const SizedBox(height: 12),

        if (allFilteredWorks.isEmpty)
          GlassContainer(
            borderRadius: 16,
            padding: const EdgeInsets.all(18),
            child: Text(
              'No matching movie or series credits are available.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: colors.onSurfaceVariant),
            ),
          )
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: visibleWorks.length,
            addAutomaticKeepAlives: false,
            addRepaintBoundaries: true,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: MediaQuery.sizeOf(context).width >= 700 ? 4 : 3,
              mainAxisSpacing: 12,
              crossAxisSpacing: 10,
              childAspectRatio: 0.50,
            ),
            itemBuilder: (context, index) {
              final item = visibleWorks[index];
              final existing = findExisting(item);
              final isAdding = _addingWorkIds.contains(item.uniqueKey);

              return _PersonWorkCard(
                item: item,
                existingStatus: existing?.status,
                adding: isAdding,
                onTap: () => _openWork(item),
                onAdd: existing == null ? () => _showQuickAddMenu(item) : null,
              );
            },
          ),

        if (visibleWorks.length < allFilteredWorks.length) ...<Widget>[
          const SizedBox(height: 14),
          Center(
            child: FilledButton.tonalIcon(
              onPressed: () {
                setState(() {
                  _visibleWorks = (_visibleWorks + _loadMoreStep).clamp(
                    0,
                    allFilteredWorks.length,
                  );
                });
              },
              icon: const Icon(Icons.expand_more_rounded),
              label: Text(
                'View More (${allFilteredWorks.length - visibleWorks.length})',
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _CompactProfileHeader extends StatelessWidget {
  final TmdbPersonDetails details;
  final String birthday;
  final String deathday;

  const _CompactProfileHeader({
    required this.details,
    required this.birthday,
    required this.deathday,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return GlassContainer(
      borderRadius: 20,
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: details.profileUrl != null
                ? CachedNetworkImage(
                    imageUrl: details.profileUrl!,
                    width: 104,
                    height: 148,
                    fit: BoxFit.cover,
                    memCacheWidth: 312,
                    memCacheHeight: 444,
                    placeholder: (_, __) =>
                        _ProfileFallback(width: 104, height: 148),
                    errorWidget: (_, __, ___) =>
                        const _ProfileFallback(width: 104, height: 148),
                  )
                : const _ProfileFallback(width: 104, height: 148),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  details.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    height: 1.12,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: <Widget>[
                    if (details.knownForDepartment.isNotEmpty)
                      _InfoPill(
                        icon: Icons.work_outline_rounded,
                        text: details.knownForDepartment,
                      ),
                    if (birthday.isNotEmpty)
                      _InfoPill(icon: Icons.cake_outlined, text: birthday),
                    if (deathday.isNotEmpty)
                      _InfoPill(
                        icon: Icons.event_busy_outlined,
                        text: deathday,
                      ),
                    if (details.placeOfBirth.isNotEmpty)
                      _InfoPill(
                        icon: Icons.place_outlined,
                        text: details.placeOfBirth,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WorksControls extends StatelessWidget {
  final _WorksFilter filter;
  final _WorksSort sort;
  final ValueChanged<_WorksFilter> onFilterChanged;
  final ValueChanged<_WorksSort> onSortChanged;

  const _WorksControls({
    required this.filter,
    required this.sort,
    required this.onFilterChanged,
    required this.onSortChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: <Widget>[
                _FilterChip(
                  label: 'All',
                  selected: filter == _WorksFilter.all,
                  onTap: () => onFilterChanged(_WorksFilter.all),
                ),
                const SizedBox(width: 6),
                _FilterChip(
                  label: 'Movies',
                  selected: filter == _WorksFilter.movies,
                  onTap: () => onFilterChanged(_WorksFilter.movies),
                ),
                const SizedBox(width: 6),
                _FilterChip(
                  label: 'Series',
                  selected: filter == _WorksFilter.series,
                  onTap: () => onFilterChanged(_WorksFilter.series),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        PopupMenuButton<_WorksSort>(
          tooltip: 'Sort works',
          initialValue: sort,
          onSelected: onSortChanged,
          itemBuilder: (_) => const <PopupMenuEntry<_WorksSort>>[
            PopupMenuItem(
              value: _WorksSort.popularity,
              child: Text('Popularity'),
            ),
            PopupMenuItem(value: _WorksSort.latest, child: Text('Latest')),
            PopupMenuItem(value: _WorksSort.rating, child: Text('Rating')),
          ],
          child: const Padding(
            padding: EdgeInsets.all(8),
            child: Icon(Icons.sort_rounded, size: 20),
          ),
        ),
      ],
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        decoration: BoxDecoration(
          color: selected
              ? colors.primary.withOpacity(0.14)
              : colors.onSurface.withOpacity(0.04),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected
                ? colors.primary.withOpacity(0.28)
                : colors.outline.withOpacity(0.10),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w800,
            color: selected ? colors.primary : colors.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  final IconData icon;
  final String text;

  const _InfoPill({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Container(
      constraints: const BoxConstraints(maxWidth: 220),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: colors.primary.withOpacity(0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colors.primary.withOpacity(0.14)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 12.5, color: colors.primary),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10.8,
                height: 1.1,
                fontWeight: FontWeight.w700,
                color: colors.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PersonWorkCard extends StatelessWidget {
  final TmdbDiscoverItem item;
  final String? existingStatus;
  final bool adding;
  final VoidCallback onTap;
  final VoidCallback? onAdd;

  const _PersonWorkCard({
    required this.item,
    required this.existingStatus,
    required this.adding,
    required this.onTap,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final status = existingStatus;
    final statusColor = status != null ? StatusStyle.color(status) : null;

    return RepaintBoundary(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  LayoutBuilder(
                    builder: (context, constraints) {
                      return PosterImage(
                        url: item.posterUrl ?? '',
                        width: constraints.maxWidth,
                        height: constraints.maxHeight,
                        radius: 11,
                      );
                    },
                  ),
                  if (status != null && statusColor != null)
                    Positioned(
                      left: 5,
                      right: 5,
                      bottom: 5,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: statusColor.withOpacity(0.92),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          status,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 8.8,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  if (status == null)
                    Positioned(
                      top: 5,
                      right: 5,
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: adding ? null : onAdd,
                          customBorder: const CircleBorder(),
                          child: Container(
                            width: 28,
                            height: 28,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.66),
                              shape: BoxShape.circle,
                            ),
                            child: adding
                                ? const SizedBox(
                                    width: 12,
                                    height: 12,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 1.6,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(
                                    Icons.add_rounded,
                                    size: 17,
                                    color: Colors.white,
                                  ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Text(
              item.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11.3,
                height: 1.15,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 2),
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    '${item.mediaType == 'tv' ? 'Series' : 'Movie'}'
                    '${item.year == 'N/A' ? '' : ' • ${item.year}'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 9.8,
                      fontWeight: FontWeight.w600,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ),
                if (item.voteAverage > 0) ...<Widget>[
                  const SizedBox(width: 3),
                  const Icon(
                    Icons.star_rounded,
                    color: Color(0xFFFFC400),
                    size: 10.5,
                  ),
                  const SizedBox(width: 1),
                  Text(
                    item.voteAverage.toStringAsFixed(1),
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileFallback extends StatelessWidget {
  final double width;
  final double height;

  const _ProfileFallback({required this.width, required this.height});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Container(
      width: width,
      height: height,
      alignment: Alignment.center,
      color: colors.surfaceContainerHighest,
      child: Icon(
        Icons.person_rounded,
        size: 48,
        color: colors.onSurfaceVariant,
      ),
    );
  }
}

class _PersonErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _PersonErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.person_search_rounded,
              size: 46,
              color: colors.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.onSurfaceVariant, fontSize: 13.5),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
