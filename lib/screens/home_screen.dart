import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/omdb_search_item.dart';
import '../models/show.dart';
import '../providers/show_provider.dart';
import '../services/omdb_service.dart';
import '../utils/status_style.dart';
import '../widgets/glass_container.dart';
import '../widgets/poster_image.dart';
import '../widgets/round_step_button.dart';
import 'add_edit_show_screen.dart';
import 'show_detail_screen.dart';

enum SortOption { dateAdded, rating, title, year }

enum TypeFilter { all, movies, series }

class HomeScreen extends StatefulWidget {
  final VoidCallback? onOverflowNext;

  const HomeScreen({super.key, this.onOverflowNext});

  @override
  State<HomeScreen> createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> {
  static const _categories = <String>[
    'All',
    'Watching',
    'Completed',
    'Plan to Watch',
    'On Hold',
    'Dropped',
  ];

  final _searchController = TextEditingController();

  final _searchFocus = FocusNode();

  final ScrollController _categoryScrollController = ScrollController();

  late final PageController _pageController;

  Timer? _debounce;

  List<OmdbSearchItem> _onlineResults = const <OmdbSearchItem>[];

  bool _searching = false;
  bool _adding = false;

  String? _searchError;

  bool _isSearchFocused = false;

  SortOption _currentSort = SortOption.dateAdded;

  TypeFilter _typeFilter = TypeFilter.all;

  int _activeCategoryIndex = 0;

  bool _backgroundSeriesSyncScheduled = false;

  // ==========================================================
  // INIT
  // ==========================================================

  @override
  void initState() {
    super.initState();

    final initialCat = context.read<ShowProvider>().selectedCategory;

    final initialIndex = _categories
        .indexOf(initialCat)
        .clamp(0, _categories.length - 1);

    _activeCategoryIndex = initialIndex;

    _pageController = PageController(initialPage: initialIndex);

    _searchFocus.addListener(() {
      if (!mounted) {
        return;
      }

      setState(() => _isSearchFocused = _searchFocus.hasFocus);
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      _scrollToCategory(initialIndex);
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();

    _searchController.dispose();
    _searchFocus.dispose();

    _pageController.dispose();

    _categoryScrollController.dispose();

    super.dispose();
  }

  // ==========================================================
  // BACKGROUND EPISODE SYNC
  // ==========================================================

  void _scheduleBackgroundSeriesSync(ShowProvider provider) {
    if (_backgroundSeriesSyncScheduled || provider.loading) {
      return;
    }

    _backgroundSeriesSyncScheduled = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future<void>.delayed(const Duration(milliseconds: 900), () {
        if (!mounted) {
          return;
        }

        unawaited(
          context.read<ShowProvider>().syncSeriesMetadataInBackground(),
        );
      });
    });
  }

  // ==========================================================
  // RESET HOME
  // ==========================================================

  void resetToAll() {
    if (_categories.isNotEmpty) {
      _onCategorySelected(0);
    }

    unawaited(context.read<ShowProvider>().syncSeriesMetadataInBackground());
  }

  // ==========================================================
  // EXTERNAL CATEGORY NAVIGATION
  // ==========================================================

  void goToCategory(String category) {
    final index = _categories.indexOf(category);

    if (index == -1) {
      return;
    }

    _onCategorySelected(index);
  }

  // ==========================================================
  // CATEGORY
  // ==========================================================

  void _scrollToCategory(int index) {
    if (!_categoryScrollController.hasClients) {
      return;
    }

    const itemWidth = 115.0;

    final screenWidth = MediaQuery.of(context).size.width;

    final currentOffset = _categoryScrollController.offset;

    final itemLeft = index * itemWidth;

    final itemRight = itemLeft + itemWidth;

    double targetOffset = currentOffset;

    if (itemRight > currentOffset + screenWidth - 16) {
      targetOffset = itemRight - screenWidth + 32;
    } else if (itemLeft < currentOffset + 16) {
      targetOffset = itemLeft - 16;
    }

    final clampedOffset = targetOffset.clamp(
      0.0,
      _categoryScrollController.position.maxScrollExtent,
    );

    if ((clampedOffset - currentOffset).abs() > 1.0) {
      _categoryScrollController.animateTo(
        clampedOffset,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _onCategorySelected(int index) {
    if (index < 0 || index >= _categories.length) {
      return;
    }

    if (_activeCategoryIndex != index) {
      setState(() => _activeCategoryIndex = index);
    }

    final category = _categories[index];

    context.read<ShowProvider>().setCategory(category);

    if (_pageController.hasClients) {
      final currentPage = _pageController.page?.round();

      if (currentPage != index) {
        _pageController.animateToPage(
          index,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
        );
      }
    }

    _scrollToCategory(index);
  }

  void _onPageChanged(int index) {
    if (index < 0 || index >= _categories.length) {
      return;
    }

    if (_activeCategoryIndex != index) {
      setState(() => _activeCategoryIndex = index);
    }

    final category = _categories[index];

    context.read<ShowProvider>().setCategory(category);

    _scrollToCategory(index);
  }

  // ==========================================================
  // SEARCH
  // ==========================================================

  void _onSearchChanged(String value) {
    context.read<ShowProvider>().setSearchQuery(value);

    _debounce?.cancel();

    if (value.trim().length < 2) {
      setState(() {
        _onlineResults = const <OmdbSearchItem>[];

        _searching = false;
        _searchError = null;
      });

      return;
    }

    _debounce = Timer(
      const Duration(milliseconds: 550),
      () => _searchOnline(value),
    );
  }

  Future<void> _searchOnline(String query) async {
    setState(() {
      _searching = true;
      _searchError = null;
    });

    try {
      String cleanQuery = query.trim();

      final lower = cleanQuery.toLowerCase();

      // স্পেশাল কেইস হ্যান্ডলিং (যেমন: its বা it's উভয়কেই সঠিকভাবে মেইনটেইন করা)
      if (lower == 'its' || lower == "it's") {
        cleanQuery = "It's";
      } else if (lower.startsWith('its ')) {
        cleanQuery = cleanQuery.replaceFirst(
          RegExp(r'its', caseSensitive: false),
          "It's",
        );
      } else if (lower == 'spiderman') {
        cleanQuery = 'Spider-Man';
      } else if (lower.contains('spiderman')) {
        cleanQuery = cleanQuery.replaceAll(
          RegExp(r'spiderman', caseSensitive: false),
          'Spider-Man',
        );
      }

      final results = await OmdbService.search(cleanQuery);

      if (!mounted || _searchController.text.trim() != query.trim()) {
        return;
      }

      setState(() => _onlineResults = results);
    } on OmdbException catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _onlineResults = const <OmdbSearchItem>[];

        _searchError = error.message;
      });
    } finally {
      if (mounted) {
        setState(() => _searching = false);
      }
    }
  }

  // ==========================================================
  // HANDLE ONLINE RESULT
  // ==========================================================

  Future<void> _handleOnlineResult(OmdbSearchItem item) async {
    if (_adding) {
      return;
    }

    final provider = context.read<ShowProvider>();

    final existing = provider.findLibraryMatchForImdb(
      imdbId: item.imdbId,
      title: item.title,
      type: item.type,
      yearText: item.year,
    );

    if (existing != null) {
      _clearSearch();

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ShowDetailScreen(showId: existing.id),
        ),
      );

      return;
    }

    await _addOnlineResult(item);
  }

  // ==========================================================
  // ADD ONLINE
  // ==========================================================

  Future<void> _addOnlineResult(OmdbSearchItem item) async {
    if (_adding) {
      return;
    }

    setState(() => _adding = true);

    final messenger = ScaffoldMessenger.of(context);

    try {
      Show show;

      try {
        show = await OmdbService.getDetails(item.imdbId);

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
          } on OmdbException {
            // TMDB background sync handles it later.
          }
        }
      } on OmdbException {
        show = Show.fromSearchResult(item.toJson());
      }

      if (!mounted) {
        return;
      }

      final provider = context.read<ShowProvider>();

      final existing = provider.findLibraryMatch(
        exactId: show.id,
        title: show.title,
        type: show.type,
        yearText: show.yearText,
      );

      if (existing != null) {
        _clearSearch();

        if (!mounted) {
          return;
        }

        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ShowDetailScreen(showId: existing.id),
          ),
        );

        return;
      }

      final added = await provider.addShow(show);

      if (!mounted) {
        return;
      }

      if (added) {
        _clearSearch();

        if (show.isSeries) {
          unawaited(provider.syncSeriesMetadataForShow(show.id, force: true));
        }

        messenger.showSnackBar(
          SnackBar(content: Text('${item.title} added to Plan to Watch.')),
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
        setState(() => _adding = false);
      }
    }
  }

  // ==========================================================
  // CLEAR SEARCH
  // ==========================================================

  void _clearSearch() {
    _debounce?.cancel();

    _searchController.clear();

    _searchFocus.unfocus();

    context.read<ShowProvider>().setSearchQuery('');

    setState(() {
      _onlineResults = const <OmdbSearchItem>[];

      _searching = false;
      _searchError = null;
    });
  }

  // ==========================================================
  // MANUAL ADD
  // ==========================================================

  Future<void> _openManualAdd() async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const AddEditShowScreen()),
    );

    if (result == true && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Added to Watcher.')));

      unawaited(context.read<ShowProvider>().syncSeriesMetadataInBackground());
    }
  }

  // ==========================================================
  // SORT FILTER
  // ==========================================================

  void _openSortFilterSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        final theme = Theme.of(context);

        final isDark = theme.brightness == Brightness.dark;

        return Padding(
          padding: EdgeInsets.only(
            left: 14,
            right: 14,
            bottom: MediaQuery.of(context).viewInsets.bottom + 16,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
              child: Container(
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF0F172A).withOpacity(0.68)
                      : Colors.white.withOpacity(0.65),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(
                    color: isDark
                        ? Colors.white.withOpacity(0.22)
                        : Colors.black.withOpacity(0.12),
                    width: 1.2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(isDark ? 0.35 : 0.12),
                      blurRadius: 30,
                      spreadRadius: 2,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                child: StatefulBuilder(
                  builder: (context, setSheetState) {
                    final primary = theme.colorScheme.primary;

                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Center(
                          child: Container(
                            width: 38,
                            height: 4,
                            margin: const EdgeInsets.only(bottom: 16),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? Colors.white.withOpacity(0.3)
                                  : Colors.black.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),

                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: <Widget>[
                            Text(
                              'Sort & Filter',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: primary,
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close_rounded),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              onPressed: () => Navigator.pop(context),
                            ),
                          ],
                        ),

                        const SizedBox(height: 14),

                        Text(
                          'Sort By',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),

                        const SizedBox(height: 8),

                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: SortOption.values.map((opt) {
                            final name = opt == SortOption.dateAdded
                                ? 'Recent Activity'
                                : opt == SortOption.rating
                                ? 'Rating'
                                : opt == SortOption.title
                                ? 'Title (A-Z)'
                                : 'Release Year';

                            final isSelected = _currentSort == opt;

                            return ChoiceChip(
                              label: Text(name),
                              selected: isSelected,
                              selectedColor: primary.withOpacity(0.3),
                              backgroundColor: isDark
                                  ? Colors.white.withOpacity(0.1)
                                  : Colors.black.withOpacity(0.06),
                              side: BorderSide(
                                color: isSelected
                                    ? primary
                                    : isDark
                                    ? Colors.white.withOpacity(0.18)
                                    : Colors.black.withOpacity(0.1),
                              ),
                              labelStyle: TextStyle(
                                color: isSelected
                                    ? primary
                                    : theme.colorScheme.onSurface,
                                fontWeight: isSelected
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                              ),
                              onSelected: (_) {
                                setState(() => _currentSort = opt);

                                setSheetState(() {});
                              },
                            );
                          }).toList(),
                        ),

                        const SizedBox(height: 18),

                        Text(
                          'Format Filter',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),

                        const SizedBox(height: 8),

                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: TypeFilter.values.map((tf) {
                            final name = tf == TypeFilter.all
                                ? 'All Formats'
                                : tf == TypeFilter.movies
                                ? 'Movies Only'
                                : 'Series Only';

                            final isSelected = _typeFilter == tf;

                            return ChoiceChip(
                              label: Text(name),
                              selected: isSelected,
                              selectedColor: primary.withOpacity(0.3),
                              backgroundColor: isDark
                                  ? Colors.white.withOpacity(0.1)
                                  : Colors.black.withOpacity(0.06),
                              side: BorderSide(
                                color: isSelected
                                    ? primary
                                    : isDark
                                    ? Colors.white.withOpacity(0.18)
                                    : Colors.black.withOpacity(0.1),
                              ),
                              labelStyle: TextStyle(
                                color: isSelected
                                    ? primary
                                    : theme.colorScheme.onSurface,
                                fontWeight: isSelected
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                              ),
                              onSelected: (_) {
                                setState(() => _typeFilter = tf);

                                setSheetState(() {});
                              },
                            );
                          }).toList(),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // ==========================================================
  // DELETE
  // ==========================================================

  Future<void> _deleteShow(Show show) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Title?'),
        content: Text('Do you want to remove "${show.title}" from Watcher?'),
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

    if (confirmed == true && mounted) {
      await context.read<ShowProvider>().deleteShow(show.id);

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('"${show.title}" deleted.')));
      }
    }
  }

  // ==========================================================
  // CATEGORY LIST BUILDING
  // ==========================================================

  List<Show> _showsForCategory(List<Show> input, String category) {
    Iterable<Show> result = input;

    if (category != 'All') {
      result = result.where((show) => show.status == category);
    }

    final query = _searchController.text.trim().toLowerCase();

    if (query.isNotEmpty) {
      result = result.where((show) {
        return show.title.toLowerCase().contains(query) ||
            show.yearText.toLowerCase().contains(query) ||
            show.genre.toLowerCase().contains(query) ||
            show.type.toLowerCase().contains(query) ||
            show.status.toLowerCase().contains(query);
      });
    }

    return result.toList(growable: false);
  }

  // ==========================================================
  // SORT
  // ==========================================================

  List<Show> _processShows(List<Show> input) {
    var filtered = input;

    if (_typeFilter == TypeFilter.movies) {
      filtered = filtered.where((show) => !show.isSeries).toList();
    } else if (_typeFilter == TypeFilter.series) {
      filtered = filtered.where((show) => show.isSeries).toList();
    }

    final sorted = List<Show>.from(filtered);

    switch (_currentSort) {
      case SortOption.dateAdded:
        sorted.sort((a, b) {
          final activity = b.recentActivityAt.compareTo(a.recentActivityAt);

          if (activity != 0) {
            return activity;
          }

          return b.createdAt.compareTo(a.createdAt);
        });

        break;

      case SortOption.rating:
        sorted.sort((a, b) => b.rating.compareTo(a.rating));

        break;

      case SortOption.title:
        sorted.sort(
          (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
        );

        break;

      case SortOption.year:
        sorted.sort((a, b) => b.yearText.compareTo(a.yearText));

        break;
    }

    return sorted;
  }

  // ==========================================================
  // BUILD
  // ==========================================================

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ShowProvider>();

    final theme = Theme.of(context);

    _scheduleBackgroundSeriesSync(provider);

    final currentCatIndex = _activeCategoryIndex.clamp(
      0,
      _categories.length - 1,
    );

    final showSearchPanel =
        _searchController.text.trim().length >= 2 &&
        (_searching || _onlineResults.isNotEmpty || _searchError != null);

    return PopScope(
      canPop: currentCatIndex == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          return;
        }

        if (currentCatIndex != 0) {
          _onCategorySelected(0);
        }
      },
      child: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  Text(
                    'Watcher',
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Sort & Filter',
                    icon: Icon(
                      Icons.tune_rounded,
                      color: theme.colorScheme.primary,
                    ),
                    onPressed: _openSortFilterSheet,
                  ),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: _GlassSearchBar(
                controller: _searchController,
                focusNode: _searchFocus,
                isFocused: _isSearchFocused,
                loading: _searching || _adding,
                onChanged: _onSearchChanged,
                onAdd: _openManualAdd,
                onClear: _clearSearch,
              ),
            ),

            Expanded(
              child: Stack(
                children: <Widget>[
                  Column(
                    children: <Widget>[
                      SizedBox(
                        height: 42,
                        child: ListView.separated(
                          controller: _categoryScrollController,
                          physics: const BouncingScrollPhysics(),
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          scrollDirection: Axis.horizontal,
                          itemCount: _categories.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 8),
                          itemBuilder: (context, index) {
                            final category = _categories[index];

                            return _CategoryPill(
                              category: category,
                              selected: currentCatIndex == index,
                              onTap: () => _onCategorySelected(index),
                            );
                          },
                        ),
                      ),

                      const SizedBox(height: 10),

                      Expanded(
                        child: provider.loading
                            ? ListView.builder(
                                physics: const NeverScrollableScrollPhysics(),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 6,
                                ),
                                itemCount: 5,
                                itemBuilder: (_, __) => const ShowRowSkeleton(),
                              )
                            : GestureDetector(
                                onHorizontalDragEnd: (details) {
                                  if (currentCatIndex ==
                                          _categories.length - 1 &&
                                      (details.primaryVelocity ?? 0) < -300) {
                                    widget.onOverflowNext?.call();
                                  }
                                },
                                child: PageView.builder(
                                  controller: _pageController,
                                  physics: const PageScrollPhysics(
                                    parent: BouncingScrollPhysics(),
                                  ),
                                  allowImplicitScrolling: true,
                                  onPageChanged: _onPageChanged,
                                  itemCount: _categories.length,
                                  itemBuilder: (context, catIndex) {
                                    final pageCategory = _categories[catIndex];

                                    final categoryShows = _processShows(
                                      _showsForCategory(
                                        provider.allShows,
                                        pageCategory,
                                      ),
                                    );

                                    if (categoryShows.isEmpty) {
                                      return _EmptyState(
                                        category: pageCategory,
                                      );
                                    }

                                    return ListView.builder(
                                      physics: const BouncingScrollPhysics(),
                                      padding: const EdgeInsets.fromLTRB(
                                        16,
                                        6,
                                        16,
                                        100,
                                      ),
                                      itemCount: categoryShows.length,
                                      itemBuilder: (context, index) {
                                        final show = categoryShows[index];

                                        return _ShowRow(
                                          show: show,
                                          onOpen: () => Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) => ShowDetailScreen(
                                                showId: show.id,
                                              ),
                                            ),
                                          ),
                                          onDelete: () => _deleteShow(show),
                                          onIncrement: () {
                                            HapticFeedback.lightImpact();
                                            provider.incrementEpisode(show.id);
                                          },
                                          onDecrement: () {
                                            HapticFeedback.lightImpact();
                                            provider.decrementEpisode(show.id);
                                          },
                                        );
                                      },
                                    );
                                  },
                                ),
                              ),
                      ),
                    ],
                  ),

                  if (showSearchPanel)
                    Positioned(
                      top: 0,
                      left: 16,
                      right: 16,
                      child: _OnlineSearchPanel(
                        loading: _searching,
                        error: _searchError,
                        results: _onlineResults,
                        onSelect: _handleOnlineResult,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// SEARCH BAR
// ============================================================

class _GlassSearchBar extends StatelessWidget {
  final TextEditingController controller;

  final FocusNode focusNode;

  final bool isFocused;
  final bool loading;

  final ValueChanged<String> onChanged;

  final VoidCallback onAdd;
  final VoidCallback onClear;

  const _GlassSearchBar({
    required this.controller,
    required this.focusNode,
    required this.isFocused,
    required this.loading,
    required this.onChanged,
    required this.onAdd,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return GlassContainer(
      borderRadius: 24,
      opacity: 0.15,
      borderColor: isFocused ? colors.primary.withOpacity(0.6) : null,
      boxShadow: [
        BoxShadow(
          color: isFocused
              ? colors.primary.withOpacity(0.2)
              : Colors.black.withOpacity(0.04),
          blurRadius: isFocused ? 20 : 12,
          spreadRadius: isFocused ? 2 : 0,
        ),
      ],
      child: SizedBox(
        height: 48,
        child: Row(
          children: <Widget>[
            const SizedBox(width: 14),

            Icon(
              Icons.search_rounded,
              size: 22,
              color: isFocused ? colors.primary : colors.onSurfaceVariant,
            ),

            const SizedBox(width: 10),

            Expanded(
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                onChanged: onChanged,
                textInputAction: TextInputAction.search,
                style: const TextStyle(fontSize: 15),
                decoration: const InputDecoration(
                  hintText: 'Search movie or series...',
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                  filled: false,
                  contentPadding: EdgeInsets.zero,
                  isDense: true,
                ),
              ),
            ),

            if (controller.text.isNotEmpty && !loading)
              IconButton(
                tooltip: 'Clear',
                iconSize: 20,
                onPressed: onClear,
                icon: const Icon(Icons.close_rounded),
              ),

            if (loading)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 10),
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),

            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Material(
                color: colors.primary,
                shape: const CircleBorder(),
                child: InkWell(
                  onTap: onAdd,
                  customBorder: const CircleBorder(),
                  child: const SizedBox(
                    width: 36,
                    height: 36,
                    child: Icon(
                      Icons.add_rounded,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// ONLINE SEARCH
// ============================================================

class _OnlineSearchPanel extends StatelessWidget {
  final bool loading;

  final String? error;

  final List<OmdbSearchItem> results;

  final ValueChanged<OmdbSearchItem> onSelect;

  const _OnlineSearchPanel({
    required this.loading,
    required this.error,
    required this.results,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final isDark = theme.brightness == Brightness.dark;

    final provider = context.watch<ShowProvider>();

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          decoration: BoxDecoration(
            color: isDark
                ? const Color(0xFF0F172A).withOpacity(0.85)
                : Colors.white.withOpacity(0.82),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isDark
                  ? Colors.white.withOpacity(0.18)
                  : Colors.black.withOpacity(0.12),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(isDark ? 0.35 : 0.12),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Container(
            constraints: const BoxConstraints(maxHeight: 280),
            child: loading && results.isEmpty
                ? SizedBox(
                    height: 70,
                    child: Center(
                      child: Text(
                        'Searching OMDb...',
                        style: TextStyle(
                          fontSize: 14,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                    ),
                  )
                : error != null
                ? SizedBox(
                    height: 70,
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          error!,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            color: theme.colorScheme.error,
                          ),
                        ),
                      ),
                    ),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: results.length,
                    separatorBuilder: (_, __) => Divider(
                      height: 1,
                      color: isDark
                          ? Colors.white.withOpacity(0.08)
                          : Colors.black.withOpacity(0.08),
                    ),
                    itemBuilder: (context, index) {
                      final item = results[index];

                      final existing = provider.findLibraryMatchForImdb(
                        imdbId: item.imdbId,
                        title: item.title,
                        type: item.type,
                        yearText: item.year,
                      );

                      final statusColor = existing != null
                          ? StatusStyle.color(existing.status)
                          : theme.colorScheme.primary;

                      return ListTile(
                        dense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 2,
                        ),
                        leading: PosterImage(
                          url: item.posterUrl,
                          width: 34,
                          height: 50,
                          radius: 6,
                        ),
                        title: Text(
                          item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                        subtitle: Text(
                          '${item.type} • ${item.year}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        trailing: existing == null
                            ? Icon(
                                Icons.add_circle_rounded,
                                color: theme.colorScheme.primary,
                                size: 24,
                              )
                            : Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: statusColor.withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: statusColor.withOpacity(0.35),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: <Widget>[
                                    Icon(
                                      Icons.check_circle_rounded,
                                      color: statusColor,
                                      size: 14,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      existing.status,
                                      style: TextStyle(
                                        color: statusColor,
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                        onTap: () => onSelect(item),
                      );
                    },
                  ),
          ),
        ),
      ),
    );
  }
}

// ============================================================
// CATEGORY PILL
// ============================================================

class _CategoryPill extends StatelessWidget {
  final String category;

  final bool selected;

  final VoidCallback onTap;

  const _CategoryPill({
    required this.category,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final color = StatusStyle.color(category);

    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(22),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 18),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected
                    ? color.withOpacity(isDark ? 0.28 : 0.20)
                    : isDark
                    ? Colors.white.withOpacity(0.08)
                    : Colors.black.withOpacity(0.04),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: selected
                      ? color.withOpacity(0.85)
                      : isDark
                      ? Colors.white.withOpacity(0.18)
                      : Colors.black.withOpacity(0.12),
                  width: selected ? 1.5 : 1,
                ),
                boxShadow: selected
                    ? [
                        BoxShadow(
                          color: color.withOpacity(0.30),
                          blurRadius: 12,
                          spreadRadius: 1,
                        ),
                      ]
                    : null,
              ),
              child: Text(
                category,
                style: TextStyle(
                  color: selected
                      ? color
                      : Theme.of(context).colorScheme.onSurface,
                  fontSize: 13.5,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
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
// SHOW ROW
// ============================================================

class _ShowRow extends StatefulWidget {
  final Show show;

  final VoidCallback onOpen;
  final VoidCallback onDelete;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;

  const _ShowRow({
    required this.show,
    required this.onOpen,
    required this.onDelete,
    required this.onIncrement,
    required this.onDecrement,
  });

  @override
  State<_ShowRow> createState() => _ShowRowState();
}

class _ShowRowState extends State<_ShowRow> {
  double _scale = 1.0;

  void _onTapDown(TapDownDetails details) => setState(() => _scale = 0.98);

  void _onTapUp(TapUpDetails details) => setState(() => _scale = 1.0);

  void _onTapCancel() => setState(() => _scale = 1.0);

  String _formatMovieRuntime(int minutes) {
    if (minutes <= 0) {
      return '';
    }

    final hours = minutes ~/ 60;
    final remainingMinutes = minutes % 60;

    if (hours > 0 && remainingMinutes > 0) {
      return '${hours}h ${remainingMinutes}m';
    }

    if (hours > 0) {
      return '${hours}h';
    }

    return '${minutes}m';
  }

  String? _movieReleaseYear(Show show) {
    final match = RegExp(r'(?:19|20)\\d{2}').firstMatch(show.yearText);

    return match?.group(0);
  }

  String? _firstMovieGenre(Show show) {
    if (show.genre.isEmpty || show.genre == 'N/A') {
      return null;
    }

    final genres = show.genre
        .split(',')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty && item != 'N/A')
        .toList(growable: false);

    if (genres.isEmpty) {
      return null;
    }

    return genres.first;
  }

  List<_MovieMetaItem> _movieMetaItems(Show show) {
    final items = <_MovieMetaItem>[];

    final year = _movieReleaseYear(show);

    if (year != null && year.isNotEmpty) {
      items.add(
        _MovieMetaItem(
          icon: Icons.calendar_month_rounded,
          label: year,
        ),
      );
    }

    final runtime = _formatMovieRuntime(show.runtimeMinutes);

    if (runtime.isNotEmpty) {
      items.add(
        _MovieMetaItem(
          icon: Icons.schedule_rounded,
          label: runtime,
        ),
      );
    }

    if (show.rating > 0) {
      items.add(
        _MovieMetaItem(
          icon: Icons.star_rounded,
          label: 'IMDb ${show.rating.toStringAsFixed(1)}',
        ),
      );
    }

    if (items.length < 3) {
      final genre = _firstMovieGenre(show);

      if (genre != null && genre.isNotEmpty) {
        items.add(
          _MovieMetaItem(
            icon: Icons.local_movies_rounded,
            label: genre,
          ),
        );
      }
    }

    if (items.isEmpty) {
      items.add(
        const _MovieMetaItem(
          icon: Icons.movie_creation_outlined,
          label: 'Movie',
        ),
      );
    }

    return items.take(3).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final show = widget.show;

    final isDark = Theme.of(context).brightness == Brightness.dark;

    final typeColor = show.isSeries
        ? const Color(0xFF269CDE)
        : const Color(0xFF9C28B4);

    final typeBackground = show.isSeries
        ? const Color(0xFFDDF3FF)
        : const Color(0xFFF6DFF7);

    final statusColor = StatusStyle.color(show.status);

    final knownCount = show.currentSeasonEpisodeCount;

    final countIsFinal = show.currentSeasonEpisodeCountIsFinal;

    final displayLimit = countIsFinal ? knownCount : 0;

    int progressBase;

    if (displayLimit > 0) {
      progressBase = displayLimit;
    } else {
      progressBase = 10;

      if (knownCount > progressBase) {
        progressBase = knownCount;
      }

      if (show.currentSeasonLastAiredEpisode > progressBase) {
        progressBase = show.currentSeasonLastAiredEpisode;
      }

      if (show.currentEpisode > progressBase) {
        progressBase = show.currentEpisode;
      }
    }

    final progress = progressBase > 0
        ? (show.currentEpisode / progressBase).clamp(0.0, 1.0).toDouble()
        : 0.0;

    final epText = displayLimit > 0
        ? 'S${show.currentSeason} • EP${show.currentEpisode} / $displayLimit'
        : 'S${show.currentSeason} • EP${show.currentEpisode}';

    return AnimatedScale(
      scale: _scale,
      duration: const Duration(milliseconds: 120),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: GestureDetector(
          onTapDown: _onTapDown,
          onTapUp: _onTapUp,
          onTapCancel: _onTapCancel,
          onLongPress: widget.onDelete,
          child: GlassContainer(
            borderRadius: 16,
            padding: const EdgeInsets.all(10),
            onTap: widget.onOpen,
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Hero(
                    tag: 'poster-${show.id}',
                    child: PosterImage(
                      url: show.posterUrl,
                      width: 80,
                      height: 115,
                      radius: 12,
                    ),
                  ),

                  const SizedBox(width: 12),

                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: <Widget>[
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Text(
                              show.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w700,
                                height: 1.2,
                              ),
                            ),

                            const SizedBox(height: 6),

                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: typeBackground.withOpacity(0.8),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    show.type,
                                    style: TextStyle(
                                      color: typeColor,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),

                                const SizedBox(width: 6),

                                Theme(
                                  data: Theme.of(context).copyWith(
                                    popupMenuTheme: PopupMenuThemeData(
                                      color: isDark
                                          ? const Color(0xFF1E293B)
                                          : Colors.white,
                                      elevation: 8,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(18),
                                        side: BorderSide(
                                          color: isDark
                                              ? Colors.white.withOpacity(0.12)
                                              : Colors.black.withOpacity(0.08),
                                        ),
                                      ),
                                    ),
                                  ),
                                  child: PopupMenuButton<String>(
                                    initialValue: show.status,
                                    tooltip: 'Change Status',
                                    offset: const Offset(0, 32),
                                    onSelected: (newStatus) {
                                      context.read<ShowProvider>().setStatus(
                                        show.id,
                                        newStatus,
                                      );
                                    },
                                    itemBuilder: (context) =>
                                        StatusStyle.statuses.map((status) {
                                          final isCurrent =
                                              show.status == status;

                                          final color = StatusStyle.color(
                                            status,
                                          );

                                          return PopupMenuItem<String>(
                                            value: status,
                                            height: 38,
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                            ),
                                            child: Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                    vertical: 4,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: isCurrent
                                                    ? color.withOpacity(.18)
                                                    : color.withOpacity(.06),
                                                borderRadius:
                                                    BorderRadius.circular(16),
                                                border: Border.all(
                                                  color: isCurrent
                                                      ? color
                                                      : color.withOpacity(.25),
                                                  width: isCurrent ? 1.5 : 1,
                                                ),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: <Widget>[
                                                  Icon(
                                                    StatusStyle.icon(status),
                                                    size: 13,
                                                    color: color,
                                                  ),
                                                  const SizedBox(width: 5),
                                                  Text(
                                                    status,
                                                    style: TextStyle(
                                                      fontSize: 11.5,
                                                      fontWeight: isCurrent
                                                          ? FontWeight.w700
                                                          : FontWeight.w500,
                                                      color: color,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          );
                                        }).toList(),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: statusColor.withOpacity(.15),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: statusColor.withOpacity(.4),
                                          width: 1,
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: <Widget>[
                                          Icon(
                                            StatusStyle.icon(show.status),
                                            size: 11,
                                            color: statusColor,
                                          ),
                                          const SizedBox(width: 3),
                                          Text(
                                            show.status,
                                            style: TextStyle(
                                              color: statusColor,
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          Icon(
                                            Icons.arrow_drop_down_rounded,
                                            size: 14,
                                            color: statusColor,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),

                        const SizedBox(height: 6),

                        if (show.isSeries)
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              SizedBox(
                                width: 56,
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: LinearProgressIndicator(
                                    value: progress,
                                    minHeight: 3.5,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primary,
                                    backgroundColor: Theme.of(
                                      context,
                                    ).colorScheme.primary.withOpacity(0.18),
                                  ),
                                ),
                              ),

                              const SizedBox(height: 3),

                              Text(
                                epText,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          )
                        else
                          _MovieMetaCapsules(
                            items: _movieMetaItems(show),
                          ),
                      ],
                    ),
                  ),

                  if (show.isSeries) ...<Widget>[
                    const SizedBox(width: 4),

                    Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: <Widget>[
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            RoundStepButton(
                              isAdd: false,
                              size: 32,
                              onPressed:
                                  show.currentSeason == 1 &&
                                      show.currentEpisode == 0
                                  ? null
                                  : widget.onDecrement,
                            ),

                            const SizedBox(width: 4),

                            RoundStepButton(
                              isAdd: true,
                              size: 32,
                              onPressed: widget.onIncrement,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================
// MOVIE META SINGLE GLASS CAPSULE
// ============================================================

class _MovieMetaItem {
  final IconData icon;
  final String label;

  const _MovieMetaItem({required this.icon, required this.label});
}

class _MovieMetaCapsules extends StatelessWidget {
  final List<_MovieMetaItem> items;

  const _MovieMetaCapsules({required this.items});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Align(
      alignment: Alignment.centerLeft,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(999),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            constraints: const BoxConstraints(maxWidth: double.infinity),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withOpacity(0.075)
                  : colors.surface.withOpacity(0.52),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: isDark
                    ? Colors.white.withOpacity(0.13)
                    : Colors.black.withOpacity(0.075),
              ),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  for (int index = 0; index < items.length; index++) ...<Widget>[
                    Icon(
                      items[index].icon,
                      size: 11.5,
                      color: colors.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      items[index].label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10.8,
                        height: 1,
                        fontWeight: FontWeight.w700,
                        color: colors.onSurfaceVariant,
                        letterSpacing: -0.08,
                      ),
                    ),
                    if (index != items.length - 1) ...<Widget>[
                      const SizedBox(width: 7),
                      Container(
                        width: 3,
                        height: 3,
                        decoration: BoxDecoration(
                          color: colors.onSurfaceVariant.withOpacity(0.38),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 7),
                    ],
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================
// EMPTY
// ============================================================

class _EmptyState extends StatelessWidget {
  final String category;

  const _EmptyState({required this.category});

  IconData _iconForCategory() {
    if (category == 'All') {
      return Icons.movie_filter_rounded;
    }

    return StatusStyle.icon(category);
  }

  String _titleForCategory() {
    switch (category) {
      case 'Watching':
        return 'Nothing Watching Now';
      case 'Completed':
        return 'No Completed Titles';
      case 'Plan to Watch':
        return 'No Plans Yet';
      case 'On Hold':
        return 'Nothing On Hold';
      case 'Dropped':
        return 'No Dropped Titles';
      case 'All':
      default:
        return 'Your Watchlist is Empty';
    }
  }

  String _subtitleForCategory() {
    switch (category) {
      case 'Watching':
        return 'Titles you start watching will appear here.';
      case 'Completed':
        return 'Finished movies and series will be collected here.';
      case 'Plan to Watch':
        return 'Save movies or series for later and they will show up here.';
      case 'On Hold':
        return 'Paused titles will stay here until you continue them.';
      case 'Dropped':
        return 'Titles you stop watching will be kept here.';
      case 'All':
      default:
        return 'Search above or tap the plus icon to add your favorite movies and series.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final accent = category == 'All' ? colors.primary : StatusStyle.color(category);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                child: Container(
                  width: 78,
                  height: 78,
                  decoration: BoxDecoration(
                    color: accent.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(color: accent.withOpacity(0.26)),
                    boxShadow: [
                      BoxShadow(
                        color: accent.withOpacity(0.10),
                        blurRadius: 24,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Icon(
                    _iconForCategory(),
                    size: 38,
                    color: accent,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              _titleForCategory(),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 285),
              child: Text(
                _subtitleForCategory(),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13.5,
                  height: 1.35,
                  color: colors.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
