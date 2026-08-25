import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/show.dart';
import '../providers/show_provider.dart';
import '../services/omdb_service.dart';
import '../services/tmdb_service.dart';
import '../utils/status_style.dart';
import '../widgets/glass_container.dart';
import '../widgets/poster_image.dart';
import 'discover_detail_screen.dart';
import 'show_detail_screen.dart';

// ============================================================
// DISCOVER MAIN FILTER
// ============================================================

enum DiscoverFilter { trending, nowPlaying, upcoming }

// ============================================================
// DISCOVER SCREEN
// ============================================================

class DiscoverScreen extends StatefulWidget {
  final VoidCallback? onOverflowNext;
  final VoidCallback? onOverflowPrev;

  const DiscoverScreen({super.key, this.onOverflowNext, this.onOverflowPrev});

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen>
    with AutomaticKeepAliveClientMixin<DiscoverScreen> {
  static const List<DiscoverFilter> _filters = DiscoverFilter.values;

  late final PageController _pageController;

  Timer? _selectionLoadTimer;

  int _selectedIndex = 0;

  TmdbMediaType _selectedMedia = TmdbMediaType.movie;

  // ==========================================================
  // LOCAL SCREEN CACHE
  // ==========================================================

  final Map<String, List<TmdbDiscoverItem>> _data =
      <String, List<TmdbDiscoverItem>>{};

  final Map<String, bool> _loading = <String, bool>{};

  final Map<String, bool> _loadingMore = <String, bool>{};

  final Map<String, bool> _hasMore = <String, bool>{};

  final Map<String, int> _nextPage = <String, int>{};

  final Map<String, String?> _errors = <String, String?>{};

  final Set<String> _screenInFlight = <String>{};

  final Map<String, bool> _addingMap = <String, bool>{};

  DateTime _lastOverflowTrigger = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  bool get wantKeepAlive => true;

  // ==========================================================
  // INIT
  // ==========================================================

  @override
  void initState() {
    super.initState();

    _pageController = PageController(initialPage: _selectedIndex);

    // Use already-prefetched app-level cache immediately.
    _seedFromServiceCache();

    // Shared in-flight protection prevents duplicate work.
    // Delay the first network check slightly so the initial
    // screen animation does not compete with TMDB work.
    _scheduleLoadCurrentSelection(delay: const Duration(milliseconds: 260));
  }

  // ==========================================================
  // DISPOSE
  // ==========================================================

  @override
  void dispose() {
    _selectionLoadTimer?.cancel();

    _pageController.dispose();

    super.dispose();
  }

  // ==========================================================
  // CACHE KEY
  // ==========================================================

  String _combinationKey(DiscoverFilter filter, TmdbMediaType media) {
    return '${filter.name}_${media.name}';
  }

  String _itemKey(TmdbDiscoverItem item) {
    return '${item.mediaType}_${item.id}';
  }

  String _addingKey(TmdbDiscoverItem item) {
    return '${item.mediaType}_${item.id}';
  }

  // ==========================================================
  // SERVICE SECTION
  // ==========================================================

  TmdbDiscoverSection _serviceSection(DiscoverFilter filter) {
    switch (filter) {
      case DiscoverFilter.trending:
        return TmdbDiscoverSection.trending;

      case DiscoverFilter.nowPlaying:
        return TmdbDiscoverSection.newReleases;

      case DiscoverFilter.upcoming:
        return TmdbDiscoverSection.upcoming;
    }
  }

  // ==========================================================
  // SEED ALL 6 PREFETCH COMBINATIONS
  // ==========================================================

  void _seedFromServiceCache() {
    for (final filter in _filters) {
      for (final media in TmdbMediaType.values) {
        final cached = TmdbService.getCachedDiscoverPage(
          section: _serviceSection(filter),
          mediaType: media,
          page: 1,
        );

        if (cached == null || cached.items.isEmpty) {
          continue;
        }

        final key = _combinationKey(filter, media);

        _data[key] = cached.items;

        _nextPage[key] = 2;

        _hasMore[key] = cached.hasMore;
      }
    }
  }

  // ==========================================================
  // SCHEDULE CURRENT SELECTION LOAD
  // ==========================================================
  //
  // Category swipe should feel immediate. Network/cache work is
  // scheduled after the visual state changes, so it does not
  // fight the PageView animation.
  //
  // ==========================================================

  void _scheduleLoadCurrentSelection({
    Duration delay = const Duration(milliseconds: 90),
    bool forceRefresh = false,
  }) {
    _selectionLoadTimer?.cancel();

    _selectionLoadTimer = Timer(delay, () {
      if (!mounted) {
        return;
      }

      unawaited(_loadCurrentSelection(forceRefresh: forceRefresh));
    });
  }

  // ==========================================================
  // CURRENT SELECTION
  // ==========================================================

  Future<void> _loadCurrentSelection({bool forceRefresh = false}) {
    return _loadCombination(
      _filters[_selectedIndex],
      _selectedMedia,
      forceRefresh: forceRefresh,
    );
  }

  // ==========================================================
  // LOAD PAGE 1
  // ==========================================================

  Future<void> _loadCombination(
    DiscoverFilter filter,
    TmdbMediaType media, {
    bool forceRefresh = false,
  }) async {
    final key = _combinationKey(filter, media);

    final existingItems = _data[key] ?? const <TmdbDiscoverItem>[];

    if (!forceRefresh && existingItems.isNotEmpty) {
      return;
    }

    if (_screenInFlight.contains(key)) {
      return;
    }

    // ========================================================
    // SHARED PREFETCH CACHE
    // ========================================================

    if (!forceRefresh) {
      final cached = TmdbService.getCachedDiscoverPage(
        section: _serviceSection(filter),
        mediaType: media,
        page: 1,
      );

      if (cached != null && cached.items.isNotEmpty) {
        if (!mounted) {
          _data[key] = cached.items;

          _nextPage[key] = 2;

          _hasMore[key] = cached.hasMore;

          return;
        }

        setState(() {
          _data[key] = cached.items;

          _nextPage[key] = 2;

          _hasMore[key] = cached.hasMore;

          _errors[key] = null;

          _loading[key] = false;
        });

        return;
      }
    }

    _screenInFlight.add(key);

    if (existingItems.isEmpty && mounted) {
      setState(() {
        _loading[key] = true;

        _errors[key] = null;
      });
    }

    try {
      final result = await TmdbService.fetchDiscoverPage(
        section: _serviceSection(filter),
        mediaType: media,
        page: 1,
        forceRefresh: forceRefresh,
      );

      if (!mounted) {
        return;
      }

      final sorted = _sortItems(filter, result.items);

      setState(() {
        if (sorted.isNotEmpty) {
          _data[key] = sorted;
        } else if (existingItems.isEmpty) {
          _data[key] = const <TmdbDiscoverItem>[];
        }

        _nextPage[key] = 2;

        _hasMore[key] = result.hasMore;

        _errors[key] = null;

        _loading[key] = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _errors[key] =
            'Could not load content. Check your internet connection and try again.';

        _loading[key] = false;
      });
    } finally {
      _screenInFlight.remove(key);

      if (mounted && _loading[key] == true) {
        setState(() {
          _loading[key] = false;
        });
      }
    }
  }

  // ==========================================================
  // PAGINATION
  // ==========================================================
  //
  // TMDB service diversifies later pages by alternating
  // industry/language and genre lanes. The screen itself keeps
  // the same lightweight one-page-at-a-time loading behavior.
  //

  Future<void> _loadMore(DiscoverFilter filter, TmdbMediaType media) async {
    final key = _combinationKey(filter, media);

    final currentItems = _data[key] ?? const <TmdbDiscoverItem>[];

    if (currentItems.isEmpty) {
      return;
    }

    if (_screenInFlight.contains(key)) {
      return;
    }

    if (_loadingMore[key] == true) {
      return;
    }

    if (_hasMore[key] == false) {
      return;
    }

    final page = _nextPage[key] ?? 2;

    _screenInFlight.add(key);

    if (mounted) {
      setState(() {
        _loadingMore[key] = true;
      });
    }

    try {
      final result = await TmdbService.fetchDiscoverPage(
        section: _serviceSection(filter),
        mediaType: media,
        page: page,
      );

      if (!mounted) {
        return;
      }

      final merged = <String, TmdbDiscoverItem>{};

      for (final item in currentItems) {
        merged[_itemKey(item)] = item;
      }

      for (final item in result.items) {
        merged[_itemKey(item)] = item;
      }

      final sorted = _sortItems(filter, merged.values.toList());

      setState(() {
        _data[key] = sorted;

        _nextPage[key] = page + 1;

        _hasMore[key] = result.hasMore;

        _loadingMore[key] = false;
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not load more content.')),
        );
      }
    } finally {
      _screenInFlight.remove(key);

      if (mounted && _loadingMore[key] == true) {
        setState(() {
          _loadingMore[key] = false;
        });
      }
    }
  }

  // ==========================================================
  // SORT
  // ==========================================================

  List<TmdbDiscoverItem> _sortItems(
    DiscoverFilter filter,
    List<TmdbDiscoverItem> items,
  ) {
    final result = List<TmdbDiscoverItem>.from(items);

    switch (filter) {
      case DiscoverFilter.trending:
        return result;

      case DiscoverFilter.nowPlaying:
        result.sort((a, b) => b.releaseDate.compareTo(a.releaseDate));

        return result;

      case DiscoverFilter.upcoming:
        result.sort((a, b) => a.releaseDate.compareTo(b.releaseDate));

        return result;
    }
  }

  // ==========================================================
  // REFRESH
  // ==========================================================

  Future<void> _refreshFilter(DiscoverFilter filter) async {
    await _loadCombination(filter, _selectedMedia, forceRefresh: true);
  }

  // ==========================================================
  // MAIN CATEGORY SELECT
  // ==========================================================

  void _onCategorySelected(int index) {
    if (index < 0 || index >= _filters.length) {
      return;
    }

    if (_selectedIndex != index) {
      setState(() {
        _selectedIndex = index;
      });
    }

    _scheduleLoadCurrentSelection(delay: const Duration(milliseconds: 140));

    if (_pageController.hasClients) {
      _pageController.animateToPage(
        index,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    }
  }

  // ==========================================================
  // PAGE CHANGED
  // ==========================================================

  void _onPageChanged(int index) {
    if (_selectedIndex != index) {
      setState(() {
        _selectedIndex = index;
      });
    }

    _scheduleLoadCurrentSelection(delay: const Duration(milliseconds: 110));
  }

  // ==========================================================
  // MEDIA SELECT
  // ==========================================================

  void _onMediaSelected(TmdbMediaType media) {
    if (_selectedMedia == media) {
      return;
    }

    setState(() {
      _selectedMedia = media;
    });

    _scheduleLoadCurrentSelection(delay: const Duration(milliseconds: 120));
  }

  // ==========================================================
  // MAIN OVERFLOW DEBOUNCE
  // ==========================================================

  bool _canTriggerOverflow() {
    final now = DateTime.now();

    if (now.difference(_lastOverflowTrigger).inMilliseconds < 600) {
      return false;
    }

    _lastOverflowTrigger = now;

    return true;
  }

  // ==========================================================
  // MAIN CATEGORY LABEL
  // ==========================================================

  String _filterLabel(DiscoverFilter filter) {
    switch (filter) {
      case DiscoverFilter.trending:
        return 'Trending';

      case DiscoverFilter.nowPlaying:
        return 'New Releases';

      case DiscoverFilter.upcoming:
        return 'Upcoming';
    }
  }

  // ==========================================================
  // MAIN CATEGORY ICON
  // ==========================================================

  IconData _filterIcon(DiscoverFilter filter) {
    switch (filter) {
      case DiscoverFilter.trending:
        return Icons.local_fire_department_rounded;

      case DiscoverFilter.nowPlaying:
        return Icons.new_releases_rounded;

      case DiscoverFilter.upcoming:
        return Icons.event_available_rounded;
    }
  }

  // ==========================================================
  // MAIN CATEGORY COLOR
  // ==========================================================

  Color _filterColor(DiscoverFilter filter) {
    switch (filter) {
      case DiscoverFilter.trending:
        return Colors.orangeAccent;

      case DiscoverFilter.nowPlaying:
        return const Color(0xFF269CDE);

      case DiscoverFilter.upcoming:
        return const Color(0xFF9C28B4);
    }
  }

  // ==========================================================
  // RESPONSIVE MAIN CATEGORY WIDTHS
  // ==========================================================

  double _measureCategoryButtonWidth(BuildContext context, String label) {
    final painter = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(fontSize: 11.2, fontWeight: FontWeight.w800),
      ),
      textDirection: Directionality.of(context),
      maxLines: 1,
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();

    return painter.width + 37;
  }

  List<double> _responsiveCategoryWidths(
    BuildContext context,
    double totalWidth,
  ) {
    const gap = 6.0;

    final usableWidth = (totalWidth - (gap * (_filters.length - 1)))
        .clamp(0.0, double.infinity)
        .toDouble();

    const minimumWidths = <double>[72, 100, 78];

    final desiredWidths = <double>[
      _measureCategoryButtonWidth(
        context,
        _filterLabel(DiscoverFilter.trending),
      ),
      _measureCategoryButtonWidth(
        context,
        _filterLabel(DiscoverFilter.nowPlaying),
      ),
      _measureCategoryButtonWidth(
        context,
        _filterLabel(DiscoverFilter.upcoming),
      ),
    ];

    final widths = List<double>.generate(
      desiredWidths.length,
      (index) => desiredWidths[index] < minimumWidths[index]
          ? minimumWidths[index]
          : desiredWidths[index],
    );

    double total = widths.fold(0.0, (sum, width) => sum + width);

    if (total < usableWidth) {
      final extra = (usableWidth - total) / widths.length;

      for (int i = 0; i < widths.length; i++) {
        widths[i] += extra;
      }

      return widths;
    }

    double overflow = total - usableWidth;

    final sideIndexes = <int>[0, 2];

    for (final index in sideIndexes) {
      if (overflow <= 0) {
        break;
      }

      final availableShrink = (widths[index] - minimumWidths[index])
          .clamp(0.0, double.infinity)
          .toDouble();

      final shrink = overflow < availableShrink ? overflow : availableShrink;

      widths[index] -= shrink;

      overflow -= shrink;
    }

    for (int i = 0; i < widths.length && overflow > 0; i++) {
      final availableShrink = (widths[i] - minimumWidths[i])
          .clamp(0.0, double.infinity)
          .toDouble();

      final shrink = overflow < availableShrink ? overflow : availableShrink;

      widths[i] -= shrink;

      overflow -= shrink;
    }

    if (overflow > 0) {
      final minimumTotal = minimumWidths.fold(0.0, (sum, width) => sum + width);

      if (minimumTotal > 0 && usableWidth > 0) {
        final scale = usableWidth / minimumTotal;

        for (int i = 0; i < widths.length; i++) {
          widths[i] = minimumWidths[i] * scale;
        }
      }
    }

    return widths;
  }

  // ==========================================================
  // MEDIA COLOR
  // ==========================================================

  Color _mediaColor(TmdbMediaType media) {
    return media == TmdbMediaType.movie
        ? const Color(0xFFFF7A45)
        : const Color(0xFF7C5CFC);
  }

  // ==========================================================
  // MEDIA ICON
  // ==========================================================

  IconData _mediaIcon(TmdbMediaType media) {
    return media == TmdbMediaType.movie
        ? Icons.movie_rounded
        : Icons.tv_rounded;
  }

  // ==========================================================
  // MEDIA LABEL
  // ==========================================================

  String _mediaLabel(TmdbMediaType media) {
    return media == TmdbMediaType.movie ? 'Movies' : 'Series';
  }

  // ==========================================================
  // DATE FORMAT
  // ==========================================================

  String _formatDate(String rawDate) {
    if (rawDate.isEmpty) {
      return 'N/A';
    }

    try {
      final parsedDate = DateTime.parse(rawDate);

      final day = parsedDate.day.toString().padLeft(2, '0');

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

      final month = months[parsedDate.month - 1];

      return '$day $month ${parsedDate.year}';
    } catch (_) {
      return rawDate;
    }
  }

  // ==========================================================
  // PHASE 2
  // OPEN DISCOVER / EXISTING LIBRARY ITEM
  // ==========================================================

  void _openDiscoverItem(TmdbDiscoverItem item) {
    final provider = context.read<ShowProvider>();

    final existing = provider.findLibraryMatchForTmdb(
      tmdbId: item.id,
      mediaType: item.mediaType,
      title: item.title,
      yearText: item.year,
    );

    if (existing != null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ShowDetailScreen(showId: existing.id),
        ),
      );

      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => DiscoverDetailScreen(item: item)),
    );
  }

  // ==========================================================
  // ADD TO LIBRARY
  // ==========================================================

  Future<void> _addDiscoverItem(TmdbDiscoverItem item) async {
    final addingKey = _addingKey(item);

    if (_addingMap[addingKey] == true) {
      return;
    }

    final provider = context.read<ShowProvider>();

    // ========================================================
    // PHASE 2
    // CHECK BEFORE NETWORK REQUEST
    // ========================================================

    final alreadyExisting = provider.findLibraryMatchForTmdb(
      tmdbId: item.id,
      mediaType: item.mediaType,
      title: item.title,
      yearText: item.year,
    );

    if (alreadyExisting != null) {
      return;
    }

    setState(() {
      _addingMap[addingKey] = true;
    });

    try {
      final imdbId = await TmdbService.getImdbId(item.id, item.mediaType);

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

                  // OMDb season listing is only a fallback.
                  seasonEpisodeCountFinalized: const <int, bool>{1: false},

                  updatedAt: show.updatedAt,
                );
              }
            } catch (_) {
              // TMDB metadata can update it later.
            }
          }
        } catch (_) {
          show = _createFallbackShow(item, 'tmdb_${item.mediaType}_${item.id}');
        }
      } else {
        show = _createFallbackShow(item, 'tmdb_${item.mediaType}_${item.id}');
      }

      if (!mounted) {
        return;
      }

      // ======================================================
      // CHECK AGAIN AFTER NETWORK REQUEST
      // ======================================================

      final latestProvider = context.read<ShowProvider>();

      final existing = latestProvider.findLibraryMatch(
        exactId: show.id,
        tmdbId: item.id,
        tmdbMediaType: item.mediaType,
        title: show.title,
        type: show.type,
        yearText: show.yearText,
      );

      if (existing != null) {
        return;
      }

      final added = await latestProvider.addShow(show);

      if (!mounted) {
        return;
      }

      if (added) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${item.title} added to Plan to Watch.')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('This title is already in your watchlist.'),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not add this title. Please try again.'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _addingMap[addingKey] = false;
        });
      }
    }
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
  // ERROR / EMPTY STATE
  // ==========================================================

  Widget _buildStateView({
    required DiscoverFilter filter,
    required ThemeData theme,
    required String title,
    required String message,
    required IconData icon,
  }) {
    return RefreshIndicator(
      onRefresh: () => _refreshFilter(filter),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        padding: const EdgeInsets.fromLTRB(20, 70, 20, 140),
        children: <Widget>[
          GlassContainer(
            borderRadius: 20,
            padding: const EdgeInsets.all(22),
            child: Column(
              children: <Widget>[
                Icon(icon, size: 34, color: theme.colorScheme.primary),
                const SizedBox(height: 12),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.4,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton.tonalIcon(
                  onPressed: () {
                    _loadCombination(
                      filter,
                      _selectedMedia,
                      forceRefresh: true,
                    );
                  },
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Try Again'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // DISCOVER SEARCH
  // ==========================================================

  Future<void> _openDiscoverSearch() async {
    final result = await showSearch<TmdbDiscoverItem?>(
      context: context,
      delegate: _DiscoverScreenSearchDelegate(),
    );

    if (!mounted || result == null) {
      return;
    }

    _openDiscoverItem(result);
  }

  // ==========================================================
  // BUILD
  // ==========================================================

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final theme = Theme.of(context);

    // Only rebuild Discover library indicators when the
    // saved library/status data changes. Do not rebuild the
    // full screen for unrelated provider state such as Home
    // category/search changes.
    context.select<ShowProvider, String>(
      (provider) => provider.allShows
          .map(
            (show) =>
                '${show.id}:${show.status}:${show.updatedAt.millisecondsSinceEpoch}',
          )
          .join('|'),
    );

    final provider = context.read<ShowProvider>();

    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // ==================================================
          // TITLE
          // ==================================================
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 8, 10, 6),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    'Discover',
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Search Discover',
                  onPressed: _openDiscoverSearch,
                  icon: const Icon(Icons.search_rounded),
                ),
              ],
            ),
          ),

          // ==================================================
          // MAIN CATEGORIES
          // ==================================================
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: LayoutBuilder(
              builder: (context, constraints) {
                const gap = 6.0;

                final widths = _responsiveCategoryWidths(
                  context,
                  constraints.maxWidth,
                );

                return Row(
                  children: List.generate(_filters.length, (index) {
                    final filter = _filters[index];

                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        SizedBox(
                          width: widths[index],
                          child: _MainCategoryButton(
                            label: _filterLabel(filter),
                            icon: _filterIcon(filter),
                            selected: _selectedIndex == index,
                            color: _filterColor(filter),
                            onTap: () {
                              _onCategorySelected(index);
                            },
                          ),
                        ),
                        if (index < _filters.length - 1)
                          const SizedBox(width: gap),
                      ],
                    );
                  }),
                );
              },
            ),
          ),

          const SizedBox(height: 10),

          // ==================================================
          // MOVIES / SERIES
          // ==================================================
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 46),
            child: Row(
              children: TmdbMediaType.values.map((media) {
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: _MediaFilterButton(
                      label: _mediaLabel(media),
                      icon: _mediaIcon(media),
                      selected: _selectedMedia == media,
                      color: _mediaColor(media),
                      onTap: () {
                        _onMediaSelected(media);
                      },
                    ),
                  ),
                );
              }).toList(),
            ),
          ),

          const SizedBox(height: 10),

          // ==================================================
          // MAIN CONTENT
          // ==================================================
          Expanded(
            child: NotificationListener<ScrollNotification>(
              onNotification: (notification) {
                if (notification is OverscrollNotification &&
                    notification.metrics.axis == Axis.horizontal) {
                  if (notification.overscroll > 12 &&
                      _selectedIndex == _filters.length - 1 &&
                      _canTriggerOverflow()) {
                    widget.onOverflowNext?.call();
                  } else if (notification.overscroll < -12 &&
                      _selectedIndex == 0 &&
                      _canTriggerOverflow()) {
                    widget.onOverflowPrev?.call();
                  }
                }

                return false;
              },
              child: PageView.builder(
                controller: _pageController,
                physics: const BouncingScrollPhysics(),
                allowImplicitScrolling: false,
                onPageChanged: _onPageChanged,
                itemCount: _filters.length,
                itemBuilder: (context, catIndex) {
                  final filter = _filters[catIndex];

                  final media = _selectedMedia;

                  final key = _combinationKey(filter, media);

                  final items = _data[key] ?? const <TmdbDiscoverItem>[];

                  final isLoading = _loading[key] == true;

                  final isLoadingMore = _loadingMore[key] == true;

                  final error = _errors[key];

                  // ==========================================
                  // INITIAL LOADING
                  // ==========================================

                  if (isLoading && items.isEmpty) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  // ==========================================
                  // ERROR
                  // ==========================================

                  if (error != null && items.isEmpty) {
                    return _buildStateView(
                      filter: filter,
                      theme: theme,
                      title: 'Couldn\'t load content',
                      message: error,
                      icon: Icons.wifi_off_rounded,
                    );
                  }

                  // ==========================================
                  // EMPTY
                  // ==========================================

                  if (items.isEmpty) {
                    return _buildStateView(
                      filter: filter,
                      theme: theme,
                      title: 'No content found',
                      message:
                          'There are no titles available for this section right now.',
                      icon: Icons.movie_filter_outlined,
                    );
                  }

                  // ==========================================
                  // LIST
                  // ==========================================

                  return NotificationListener<ScrollNotification>(
                    onNotification: (notification) {
                      if (notification.metrics.axis == Axis.vertical &&
                          notification.metrics.extentAfter < 650) {
                        _loadMore(filter, media);
                      }

                      return false;
                    },
                    child: RefreshIndicator(
                      onRefresh: () => _refreshFilter(filter),
                      child: ListView.builder(
                        key: PageStorageKey<String>(
                          'discover_${filter.name}_${media.name}',
                        ),
                        physics: const AlwaysScrollableScrollPhysics(
                          parent: BouncingScrollPhysics(),
                        ),

                        cacheExtent: 350,

                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 135),

                        itemCount: items.length + (isLoadingMore ? 1 : 0),

                        itemBuilder: (context, index) {
                          if (index >= items.length) {
                            return const Padding(
                              padding: EdgeInsets.symmetric(vertical: 20),
                              child: Center(
                                child: SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              ),
                            );
                          }

                          final item = items[index];

                          final addingKey = _addingKey(item);

                          final isAdding = _addingMap[addingKey] == true;

                          // ==================================
                          // PHASE 2
                          // SAFE TMDB LIBRARY MATCH
                          // ==================================

                          final existing = provider.findLibraryMatchForTmdb(
                            tmdbId: item.id,
                            mediaType: item.mediaType,
                            title: item.title,
                            yearText: item.year,
                          );

                          final alreadyAdded = existing != null;

                          final formattedDate = _formatDate(item.releaseDate);

                          final isSeries = item.mediaType == 'tv';

                          final badgeColor = isSeries
                              ? const Color(0xFF7C5CFC)
                              : const Color(0xFFFF7A45);

                          final libraryColor = existing != null
                              ? StatusStyle.color(existing.status)
                              : theme.colorScheme.primary;

                          return RepaintBoundary(
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: GlassContainer(
                                borderRadius: 16,
                                padding: const EdgeInsets.all(10),

                                // ============================
                                // ALREADY SAVED -> LIBRARY DETAILS
                                // NEW -> DISCOVER DETAILS
                                // ============================
                                onTap: () => _openDiscoverItem(item),

                                child: Row(
                                  children: <Widget>[
                                    // ========================
                                    // POSTER
                                    // ========================
                                    PosterImage(
                                      url: item.posterUrl ?? '',
                                      width: 80,
                                      height: 118,
                                      radius: 12,
                                    ),

                                    const SizedBox(width: 12),

                                    // ========================
                                    // INFO
                                    // ========================
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: <Widget>[
                                          Text(
                                            item.title,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),

                                          const SizedBox(height: 4),

                                          Row(
                                            children: <Widget>[
                                              // =================
                                              // MOVIE / SERIES
                                              // =================
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 7,
                                                      vertical: 3,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: badgeColor.withOpacity(
                                                    0.13,
                                                  ),
                                                  borderRadius:
                                                      BorderRadius.circular(9),
                                                  border: Border.all(
                                                    color: badgeColor
                                                        .withOpacity(0.30),
                                                  ),
                                                ),
                                                child: Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: <Widget>[
                                                    Icon(
                                                      isSeries
                                                          ? Icons.tv_rounded
                                                          : Icons.movie_rounded,
                                                      size: 12,
                                                      color: badgeColor,
                                                    ),
                                                    const SizedBox(width: 4),
                                                    Text(
                                                      isSeries
                                                          ? 'Series'
                                                          : 'Movie',
                                                      style: TextStyle(
                                                        fontSize: 10.5,
                                                        fontWeight:
                                                            FontWeight.w700,
                                                        color: badgeColor,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),

                                              if (isSeries)
                                                _SeriesSeasonBadge(
                                                  tmdbId: item.id,
                                                  color: badgeColor,
                                                ),

                                              if (item.voteAverage >
                                                  0) ...<Widget>[
                                                const SizedBox(width: 8),
                                                const Icon(
                                                  Icons.star_rounded,
                                                  size: 14,
                                                  color: Colors.amber,
                                                ),
                                                const SizedBox(width: 2),
                                                Text(
                                                  item.voteAverage
                                                      .toStringAsFixed(1),
                                                  style: const TextStyle(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),

                                          const SizedBox(height: 6),

                                          Text(
                                            item.overview.trim().isEmpty
                                                ? 'No overview available.'
                                                : item.overview,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 11.5,
                                              color: theme
                                                  .colorScheme
                                                  .onSurfaceVariant
                                                  .withOpacity(0.8),
                                            ),
                                          ),

                                          const SizedBox(height: 6),

                                          Row(
                                            children: <Widget>[
                                              Icon(
                                                Icons.calendar_today_rounded,
                                                size: 12,
                                                color:
                                                    theme.colorScheme.primary,
                                              ),
                                              const SizedBox(width: 4),
                                              Flexible(
                                                child: Text(
                                                  formattedDate,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w600,
                                                    color: theme
                                                        .colorScheme
                                                        .primary,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),

                                    const SizedBox(width: 6),

                                    // ========================
                                    // ADD / CHECK BUTTON
                                    // ========================
                                    IconButton(
                                      tooltip: existing != null
                                          ? 'In library • ${existing.status}'
                                          : 'Add to watchlist',
                                      onPressed: isAdding || alreadyAdded
                                          ? null
                                          : () {
                                              _addDiscoverItem(item);
                                            },
                                      icon: isAdding
                                          ? const SizedBox(
                                              width: 20,
                                              height: 20,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                              ),
                                            )
                                          : Icon(
                                              alreadyAdded
                                                  ? Icons.check_circle_rounded
                                                  : Icons.add_circle_rounded,
                                              color: libraryColor,
                                              size: 28,
                                            ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// SERIES SEASON BADGE
// ============================================================

class _SeriesSeasonBadge extends StatefulWidget {
  final String tmdbId;
  final Color color;

  const _SeriesSeasonBadge({required this.tmdbId, required this.color});

  @override
  State<_SeriesSeasonBadge> createState() => _SeriesSeasonBadgeState();
}

class _SeriesSeasonBadgeState extends State<_SeriesSeasonBadge> {
  TmdbSeriesInfo? _info;

  @override
  void initState() {
    super.initState();

    _info = TmdbService.getCachedSeriesSeasonInfo(widget.tmdbId);

    if (_info == null) {
      _load();
    }
  }

  @override
  void didUpdateWidget(covariant _SeriesSeasonBadge oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.tmdbId == widget.tmdbId) {
      return;
    }

    _info = TmdbService.getCachedSeriesSeasonInfo(widget.tmdbId);

    if (_info == null) {
      _load();
    }
  }

  Future<void> _load() async {
    final info = await TmdbService.fetchSeriesSeasonInfo(widget.tmdbId);

    if (!mounted || info == null) {
      return;
    }

    setState(() {
      _info = info;
    });
  }

  @override
  Widget build(BuildContext context) {
    final info = _info;

    if (info == null) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: widget.color.withOpacity(0.09),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: widget.color.withOpacity(0.22)),
        ),
        child: Text(
          info.label,
          maxLines: 1,
          softWrap: false,
          style: TextStyle(
            fontSize: 10.2,
            fontWeight: FontWeight.w700,
            color: widget.color.withOpacity(0.92),
          ),
        ),
      ),
    );
  }
}

// ============================================================
// MAIN CATEGORY BUTTON
// ============================================================

class _MainCategoryButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  const _MainCategoryButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final isDark = theme.brightness == Brightness.dark;

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            height: 46,
            padding: const EdgeInsets.symmetric(horizontal: 5),
            decoration: BoxDecoration(
              color: selected
                  ? color.withOpacity(isDark ? 0.26 : 0.18)
                  : isDark
                  ? Colors.white.withOpacity(0.07)
                  : Colors.black.withOpacity(0.035),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: selected
                    ? color.withOpacity(0.78)
                    : isDark
                    ? Colors.white.withOpacity(0.14)
                    : Colors.black.withOpacity(0.09),
                width: selected ? 1.3 : 1,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.center,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(
                      icon,
                      size: 15,
                      color: selected
                          ? color
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      label,
                      maxLines: 1,
                      softWrap: false,
                      style: TextStyle(
                        fontSize: 11.2,
                        fontWeight: selected
                            ? FontWeight.w800
                            : FontWeight.w600,
                        color: selected ? color : theme.colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================
// MOVIES / SERIES BUTTON
// ============================================================

class _MediaFilterButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  const _MediaFilterButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final isDark = theme.brightness == Brightness.dark;

    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 170),
            curve: Curves.easeOutCubic,
            height: 36,
            decoration: BoxDecoration(
              color: selected
                  ? color.withOpacity(isDark ? 0.24 : 0.16)
                  : isDark
                  ? Colors.white.withOpacity(0.06)
                  : Colors.black.withOpacity(0.03),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: selected
                    ? color.withOpacity(0.72)
                    : isDark
                    ? Colors.white.withOpacity(0.13)
                    : Colors.black.withOpacity(0.08),
                width: selected ? 1.25 : 1,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Icon(
                  icon,
                  size: 15,
                  color: selected ? color : theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 5),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    color: selected ? color : theme.colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================
// DISCOVER SCREEN TMDB SEARCH
// ============================================================

class _DiscoverScreenSearchDelegate extends SearchDelegate<TmdbDiscoverItem?> {
  _DiscoverScreenSearchDelegate()
    : super(searchFieldLabel: 'Search movie or series...');

  @override
  List<Widget>? buildActions(BuildContext context) {
    return <Widget>[
      if (query.isNotEmpty)
        IconButton(
          tooltip: 'Clear',
          onPressed: () => query = '',
          icon: const Icon(Icons.close_rounded),
        ),
    ];
  }

  @override
  Widget? buildLeading(BuildContext context) {
    return IconButton(
      tooltip: 'Back',
      onPressed: () => close(context, null),
      icon: const Icon(Icons.arrow_back_rounded),
    );
  }

  @override
  Widget buildResults(BuildContext context) {
    return _DiscoverScreenSearchResults(
      query: query,
      onSelect: (item) => close(context, item),
    );
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    return _DiscoverScreenSearchResults(
      query: query,
      onSelect: (item) => close(context, item),
    );
  }
}

class _DiscoverScreenSearchResults extends StatefulWidget {
  final String query;
  final ValueChanged<TmdbDiscoverItem> onSelect;

  const _DiscoverScreenSearchResults({
    required this.query,
    required this.onSelect,
  });

  @override
  State<_DiscoverScreenSearchResults> createState() =>
      _DiscoverScreenSearchResultsState();
}

class _DiscoverScreenSearchResultsState
    extends State<_DiscoverScreenSearchResults> {
  Timer? _debounce;
  List<TmdbDiscoverItem> _results = const <TmdbDiscoverItem>[];
  bool _loading = false;
  String? _error;
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    _scheduleSearch();
  }

  @override
  void didUpdateWidget(covariant _DiscoverScreenSearchResults oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.query != widget.query) {
      _scheduleSearch();
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  ({String title, String? year}) _parseQuery(String raw) {
    final trimmed = raw.trim();

    final match = RegExp(
      r'^(.*?)(?:\s*\(?(18|19|20)\d{2}\)?)\s*$',
    ).firstMatch(trimmed);

    if (match == null) {
      return (title: trimmed, year: null);
    }

    final yearMatch = RegExp(
      r'(18|19|20)\d{2}',
    ).firstMatch(match.group(0) ?? '');

    final title = (match.group(1) ?? '').trim();
    final year = yearMatch?.group(0);

    if (title.isEmpty || year == null) {
      return (title: trimmed, year: null);
    }

    return (title: title, year: year);
  }

  bool _yearMatches(String source, String year) {
    return RegExp(
      r'(?<!\d)' + RegExp.escape(year) + r'(?!\d)',
    ).hasMatch(source);
  }

  String _formatReleaseDate(String rawDate) {
    final parsed = DateTime.tryParse(rawDate.trim());

    if (parsed == null) {
      return 'TBA';
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

  void _scheduleSearch() {
    _debounce?.cancel();

    final raw = widget.query.trim();

    if (raw.length < 2) {
      setState(() {
        _results = const <TmdbDiscoverItem>[];
        _loading = false;
        _error = null;
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    _debounce = Timer(const Duration(milliseconds: 450), () => _search(raw));
  }

  Future<void> _search(String raw) async {
    final requestId = ++_requestId;

    try {
      final parsed = _parseQuery(raw);
      final results = await TmdbService.searchTitles(parsed.title);

      if (!mounted || requestId != _requestId) {
        return;
      }

      final filtered = parsed.year == null
          ? results
          : results
                .where((item) => _yearMatches(item.year, parsed.year!))
                .toList(growable: false);

      setState(() {
        _results = filtered;
        _loading = false;
        _error = null;
      });
    } catch (_) {
      if (!mounted || requestId != _requestId) {
        return;
      }

      setState(() {
        _results = const <TmdbDiscoverItem>[];
        _loading = false;
        _error = 'Could not search TMDB right now.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final raw = widget.query.trim();

    if (raw.length < 2) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                Icons.manage_search_rounded,
                size: 40,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 12),
              Text(
                'Search Discover',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                'Search movies and series, including upcoming and unreleased titles.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_loading && _results.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _error!,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: theme.colorScheme.error,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
    }

    if (_results.isEmpty) {
      return Center(
        child: Text(
          'No movie or series found.',
          style: TextStyle(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      physics: const BouncingScrollPhysics(),
      itemCount: _results.length,
      separatorBuilder: (_, __) => Divider(
        height: 1,
        color: theme.colorScheme.outline.withOpacity(0.10),
      ),
      itemBuilder: (context, index) {
        final item = _results[index];
        final typeLabel = item.mediaType == 'tv' ? 'Series' : 'Movie';
        final releaseDate = _formatReleaseDate(item.releaseDate);

        return ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 8,
            vertical: 4,
          ),
          leading: PosterImage(
            url: item.posterUrl ?? '',
            width: 42,
            height: 62,
            radius: 8,
          ),
          title: Text(
            item.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800),
          ),
          subtitle: Text(
            '$typeLabel • $releaseDate',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: theme.colorScheme.onSurfaceVariant,
              fontSize: 12.2,
              fontWeight: FontWeight.w600,
            ),
          ),
          trailing: Icon(
            Icons.chevron_right_rounded,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          onTap: () => widget.onSelect(item),
        );
      },
    );
  }
}
