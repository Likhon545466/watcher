import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/show.dart';
import '../models/tmdb_video.dart';
import '../providers/settings_provider.dart';
import '../providers/show_provider.dart';
import '../services/omdb_service.dart';
import '../services/tmdb_service.dart';
import '../widgets/ambient_background.dart';
import '../widgets/glass_container.dart';
import '../widgets/poster_image.dart';
import 'discover_detail_screen.dart';
import 'show_detail_screen.dart';

enum CalendarFilter { all, seriesOnly, moviesOnly }

class _AgendaItem {
  final String id;
  final String title;
  final String subtitle;
  final DateTime date;
  final bool isMovie;
  final String? posterUrl;
  final String? backdropUrl;
  final Show? show;
  final TmdbDiscoverItem? discoverItem;
  final List<String> tags;
  final bool reminderEnabled;

  const _AgendaItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.date,
    required this.isMovie,
    this.posterUrl,
    this.backdropUrl,
    this.show,
    this.discoverItem,
    this.tags = const <String>[],
    this.reminderEnabled = false,
  });
}

class ReleaseCalendarScreen extends StatefulWidget {
  const ReleaseCalendarScreen({super.key});

  @override
  State<ReleaseCalendarScreen> createState() => _ReleaseCalendarScreenState();
}

class _ReleaseCalendarScreenState extends State<ReleaseCalendarScreen> {
  int _selectedTab = 0; // 0: My Watchlist, 1: Global Discover
  CalendarFilter _filter = CalendarFilter.all;
  DateTime? _selectedDate;

  // Global Discover State
  bool _isLoadingDiscover = false;
  String? _discoverError;
  List<TmdbDiscoverItem> _discoverUpcomingMovies = <TmdbDiscoverItem>[];
  List<TmdbDiscoverItem> _discoverAiringTv = <TmdbDiscoverItem>[];
  final Set<String> _addingIds = <String>{};

  @override
  void initState() {
    super.initState();
    _loadGlobalDiscover();
  }

  Future<void> _loadGlobalDiscover({bool forceRefresh = false}) async {
    if (_isLoadingDiscover) return;

    setState(() {
      _isLoadingDiscover = true;
      _discoverError = null;
    });

    try {
      final movieRes = await TmdbService.fetchDiscoverPage(
        section: TmdbDiscoverSection.upcoming,
        mediaType: TmdbMediaType.movie,
        page: 1,
        forceRefresh: forceRefresh,
      );
      final tvRes = await TmdbService.fetchDiscoverPage(
        section: TmdbDiscoverSection.upcoming,
        mediaType: TmdbMediaType.tv,
        page: 1,
        forceRefresh: forceRefresh,
      );

      if (mounted) {
        setState(() {
          _discoverUpcomingMovies = movieRes.items;
          _discoverAiringTv = tvRes.items;
          _isLoadingDiscover = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _discoverError = 'Could not load upcoming releases from TMDB.';
          _isLoadingDiscover = false;
        });
      }
    }
  }

  String _formatDayMonthYear(DateTime date) {
    const months = <String>[
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  String _formatWeekday(DateTime date) {
    const weekdays = <String>['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return weekdays[date.weekday - 1];
  }

  String _getCountdownText(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(date.year, date.month, date.day);
    final diffDays = target.difference(today).inDays;

    if (diffDays < 0) {
      return 'Released';
    } else if (diffDays == 0) {
      return 'TODAY!';
    } else if (diffDays == 1) {
      return 'Tomorrow';
    } else if (diffDays < 7) {
      return 'In $diffDays days';
    } else if (diffDays < 30) {
      final weeks = (diffDays / 7).round();
      return 'In $weeks week${weeks > 1 ? "s" : ""}';
    } else {
      final months = (diffDays / 30).round();
      return 'In $months month${months > 1 ? "s" : ""}';
    }
  }

  Color _getCountdownColor(DateTime date, ColorScheme scheme) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(date.year, date.month, date.day);
    final diffDays = target.difference(today).inDays;

    if (diffDays == 0) {
      return const Color(0xFF16A34A); // Green
    } else if (diffDays <= 3) {
      return const Color(0xFFD97706); // Amber
    } else {
      return scheme.primary;
    }
  }

  // ==========================================================
  // BUILD WATCHLIST AGENDA ITEMS
  // ==========================================================

  List<_AgendaItem> _buildWatchlistItems(List<Show> shows) {
    final items = <_AgendaItem>[];
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    for (final show in shows) {
      if (show.isSeries) {
        if (show.nextEpisodeAirDate != null) {
          final airDate = show.nextEpisodeAirDate!;
          if (!airDate.isBefore(today)) {
            final s = show.nextEpisodeSeason ?? show.currentSeason;
            final ep = show.nextEpisodeNumber ?? (show.currentEpisode + 1);
            items.add(
              _AgendaItem(
                id: show.id,
                title: show.title,
                subtitle: 'Season $s • Episode $ep',
                date: airDate,
                isMovie: false,
                posterUrl: show.posterUrl,
                backdropUrl: show.posterUrl,
                show: show,
                tags: show.customTags,
                reminderEnabled: show.episodeReminderEnabled,
              ),
            );
          }
        }
      } else {
        if (show.movieReleaseDate != null) {
          final releaseDate = show.movieReleaseDate!;
          if (!releaseDate.isBefore(today)) {
            items.add(
              _AgendaItem(
                id: show.id,
                title: show.title,
                subtitle: 'Movie Premiere',
                date: releaseDate,
                isMovie: true,
                posterUrl: show.posterUrl,
                backdropUrl: show.posterUrl,
                show: show,
                tags: show.customTags,
                reminderEnabled: show.movieReminderEnabled,
              ),
            );
          }
        }
      }
    }

    items.sort((a, b) => a.date.compareTo(b.date));
    return items;
  }

  // ==========================================================
  // BUILD GLOBAL DISCOVER AGENDA ITEMS
  // ==========================================================

  List<_AgendaItem> _buildDiscoverItems() {
    final items = <_AgendaItem>[];
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    for (final item in _discoverUpcomingMovies) {
      final parsed = DateTime.tryParse(item.releaseDate);
      if (parsed != null) {
        final d = DateTime(parsed.year, parsed.month, parsed.day);
        if (!d.isBefore(today)) {
          items.add(
            _AgendaItem(
              id: 'tmdb_movie_${item.id}',
              title: item.title,
              subtitle: 'Theatrical Premiere',
              date: d,
              isMovie: true,
              posterUrl: item.posterUrl,
              backdropUrl: item.backdropUrl ?? item.posterUrl,
              discoverItem: item,
            ),
          );
        }
      }
    }

    for (final item in _discoverAiringTv) {
      final parsed = DateTime.tryParse(item.releaseDate);
      if (parsed != null) {
        final d = DateTime(parsed.year, parsed.month, parsed.day);
        if (!d.isBefore(today)) {
          items.add(
            _AgendaItem(
              id: 'tmdb_tv_${item.id}',
              title: item.title,
              subtitle: 'Airing on Television',
              date: d,
              isMovie: false,
              posterUrl: item.posterUrl,
              backdropUrl: item.backdropUrl ?? item.posterUrl,
              discoverItem: item,
            ),
          );
        }
      }
    }

    items.sort((a, b) => a.date.compareTo(b.date));
    return items;
  }

  // ==========================================================
  // QUICK ADD DISCOVER ITEM TO WATCHLIST
  // ==========================================================

  Future<void> _addDiscoverItemToLibrary(TmdbDiscoverItem item) async {
    final provider = context.read<ShowProvider>();
    final key = '${item.mediaType}_${item.id}';

    if (_addingIds.contains(key)) return;

    setState(() => _addingIds.add(key));

    try {
      final imdbId = await TmdbService.getImdbId(item.id, item.mediaType);
      Show show;

      if (imdbId != null && imdbId.isNotEmpty) {
        try {
          show = await OmdbService.getDetails(imdbId);
        } catch (_) {
          show = Show(
            id: 'tmdb_${item.mediaType}_${item.id}',
            title: item.title,
            type: item.mediaType.toLowerCase() == 'tv' ? 'Series' : 'Movie',
            posterUrl: item.posterUrl ?? '',
            yearText: item.year,
            genre: 'N/A',
            plot: item.overview,
            director: 'N/A',
            writer: 'N/A',
            actors: 'N/A',
            language: 'N/A',
            awards: 'N/A',
            runtimeMinutes: 0,
            rating: item.voteAverage,
            status: 'Plan to Watch',
            totalSeasons: item.mediaType.toLowerCase() == 'tv' ? 1 : 1,
            currentSeason: 1,
            currentEpisode: 0,
            seasonProgress: const <int, int>{},
            seasonEpisodeCounts: const <int, int>{},
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          );
        }
      } else {
        show = Show(
          id: 'tmdb_${item.mediaType}_${item.id}',
          title: item.title,
          type: item.mediaType.toLowerCase() == 'tv' ? 'Series' : 'Movie',
          posterUrl: item.posterUrl ?? '',
          yearText: item.year,
          genre: 'N/A',
          plot: item.overview,
          director: 'N/A',
          writer: 'N/A',
          actors: 'N/A',
          language: 'N/A',
          awards: 'N/A',
          runtimeMinutes: 0,
          rating: item.voteAverage,
          status: 'Plan to Watch',
          totalSeasons: item.mediaType.toLowerCase() == 'tv' ? 1 : 1,
          currentSeason: 1,
          currentEpisode: 0,
          seasonProgress: const <int, int>{},
          seasonEpisodeCounts: const <int, int>{},
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
      }

      await provider.addShow(show);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Added "${show.title}" to Watchlist!'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not add to library: $e'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _addingIds.remove(key));
      }
    }
  }

  // ==========================================================
  // QUICK TRAILER POPUP
  // ==========================================================

  Future<void> _playTrailer(String title, String? tmdbId, bool isMovie) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: CircularProgressIndicator(),
      ),
    );

    try {
      final videos = await TmdbService.fetchVideos(
        showId: tmdbId ?? '',
        title: title,
        type: isMovie ? 'movie' : 'tv',
      );

      if (!mounted) return;
      Navigator.pop(context); // Close loading dialog

      if (videos.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No official trailer found for "$title"'),
          ),
        );
        return;
      }

      final topTrailer = videos.firstWhere(
        (v) => v.type.toLowerCase() == 'trailer' && v.isYouTube,
        orElse: () => videos.first,
      );

      _showTrailerBottomSheet(title, videos, topTrailer);
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not load trailer: $e'),
        ),
      );
    }
  }

  void _showTrailerBottomSheet(
    String title,
    List<TmdbVideo> videos,
    TmdbVideo selected,
  ) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colors.onSurface.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Icon(Icons.play_circle_filled_rounded, color: colors.primary, size: 22),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Official Trailers • $title',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: videos.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, idx) {
                    final video = videos[idx];
                    return GlassContainer(
                      borderRadius: 14,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      child: Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.network(
                              video.youtubeThumbnailUrl,
                              width: 76,
                              height: 46,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                width: 76,
                                height: 46,
                                color: colors.surfaceContainerHighest,
                                child: Icon(Icons.videocam_off_rounded, color: colors.onSurfaceVariant),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  video.name,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${video.type} • ${video.site}',
                                  style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: Icon(Icons.open_in_new_rounded, color: colors.primary, size: 20),
                            onPressed: () async {
                              final uri = Uri.tryParse(video.youtubeUrl);
                              if (uri != null && await canLaunchUrl(uri)) {
                                await launchUrl(uri, mode: LaunchMode.externalApplication);
                              }
                            },
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ==========================================================
  // EXPORT / SHARE CALENDAR SCHEDULE
  // ==========================================================

  Future<void> _exportCalendar(List<_AgendaItem> items) async {
    if (items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No upcoming releases to export.')),
      );
      return;
    }

    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colors.onSurface.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Export Release Calendar',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Sync your upcoming ${items.length} releases with Google Calendar, Apple Calendar, or share with friends.',
                style: TextStyle(fontSize: 13, color: colors.onSurfaceVariant),
              ),
              const SizedBox(height: 18),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: colors.primary.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.calendar_month_rounded, color: colors.primary),
                ),
                title: const Text('Share .ics Calendar File', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                subtitle: Text('Import directly into Google / Apple / Outlook Calendar', style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant)),
                trailing: Icon(Icons.chevron_right_rounded, size: 18, color: colors.onSurfaceVariant),
                onTap: () async {
                  Navigator.pop(ctx);
                  await _shareIcsFile(items);
                },
              ),
              Divider(color: colors.outlineVariant.withOpacity(0.3), height: 16),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: colors.secondary.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.copy_all_rounded, color: colors.secondary),
                ),
                title: const Text('Copy Formatted Schedule Text', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                subtitle: Text('Copy clean text schedule to clipboard', style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant)),
                trailing: Icon(Icons.chevron_right_rounded, size: 18, color: colors.onSurfaceVariant),
                onTap: () {
                  Navigator.pop(ctx);
                  _copyScheduleText(items);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _shareIcsFile(List<_AgendaItem> items) async {
    final buffer = StringBuffer();
    buffer.writeln('BEGIN:VCALENDAR');
    buffer.writeln('VERSION:2.0');
    buffer.writeln('PRODID:-//Watcher App//Release Agenda//EN');
    buffer.writeln('CALSCALE:GREGORIAN');

    for (final item in items) {
      final dateStr = '${item.date.year}'
          '${item.date.month.toString().padLeft(2, '0')}'
          '${item.date.day.toString().padLeft(2, '0')}';

      buffer.writeln('BEGIN:VEVENT');
      buffer.writeln('SUMMARY:${item.title} - ${item.subtitle}');
      buffer.writeln('DESCRIPTION:Release premiere tracked in Watcher App.');
      buffer.writeln('DTSTART;VALUE=DATE:$dateStr');
      buffer.writeln('DTEND;VALUE=DATE:$dateStr');
      buffer.writeln('UID:${item.id}_$dateStr@watcher.app');
      buffer.writeln('END:VEVENT');
    }

    buffer.writeln('END:VCALENDAR');

    try {
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/watcher_release_agenda.ics');
      await file.writeAsString(buffer.toString());

      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'text/calendar')],
        subject: 'Watcher Release Calendar Agenda',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not generate calendar file: $e')),
        );
      }
    }
  }

  void _copyScheduleText(List<_AgendaItem> items) {
    final buffer = StringBuffer();
    buffer.writeln('🎬 WATCHER UPCOMING RELEASES AGENDA 🍿');
    buffer.writeln('====================================');
    for (final item in items) {
      buffer.writeln('• ${_formatDayMonthYear(item.date)}: ${item.title} (${item.subtitle})');
    }
    Clipboard.setData(ClipboardData(text: buffer.toString()));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Agenda copied to clipboard!'),
      ),
    );
  }

  // ==========================================================
  // MAIN BUILD
  // ==========================================================

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final shows = context.watch<ShowProvider>().allShows;

    final allRawItems = _selectedTab == 0
        ? _buildWatchlistItems(shows)
        : _buildDiscoverItems();

    // Filter by Series / Movies
    var filteredItems = allRawItems.where((e) {
      if (_filter == CalendarFilter.seriesOnly) return !e.isMovie;
      if (_filter == CalendarFilter.moviesOnly) return e.isMovie;
      return true;
    }).toList();

    // Filter by Specific Date if clicked on Date Strip
    if (_selectedDate != null) {
      final target = DateTime(_selectedDate!.year, _selectedDate!.month, _selectedDate!.day);
      filteredItems = filteredItems.where((e) {
        final d = DateTime(e.date.year, e.date.month, e.date.day);
        return d.isAtSameMomentAs(target);
      }).toList();
    }

    // Identify unique dates with events for dot indicator on date strip
    final datesWithReleases = <DateTime>{};
    for (final it in allRawItems) {
      datesWithReleases.add(DateTime(it.date.year, it.date.month, it.date.day));
    }

    final closestItem = filteredItems.isNotEmpty ? filteredItems.first : null;

    return AmbientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text(
            'Release Calendar',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.share_outlined),
              tooltip: 'Export & Share Calendar',
              onPressed: () => _exportCalendar(filteredItems),
            ),
            if (_selectedTab == 1)
              IconButton(
                icon: const Icon(Icons.refresh_rounded),
                tooltip: 'Refresh Discover',
                onPressed: () => _loadGlobalDiscover(forceRefresh: true),
              ),
          ],
        ),
        body: Column(
          children: [
            // SCOPE CHIPS: MY WATCHLIST vs GLOBAL DISCOVER (Symmetrical & Themed)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
              child: Row(
                children: [
                  Expanded(
                    child: _buildScopeChip(
                      'My Watchlist',
                      Icons.bookmark_outline_rounded,
                      0,
                      const Color(0xFF2499E8), // Library / Watching Cyan Blue
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildScopeChip(
                      'Global Discover',
                      Icons.explore_outlined,
                      1,
                      const Color(0xFFA824B7), // Discover Magenta Purple
                    ),
                  ),
                ],
              ),
            ),

            // HORIZONTAL DATE STRIP
            _buildHorizontalDateStrip(datesWithReleases, colors),

            // TYPE FILTER CHIPS (Symmetrical across the width with distinct color shades)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              child: Row(
                children: [
                  Expanded(
                    child: _buildCategoryChip(
                      'All Types',
                      CalendarFilter.all,
                      const Color(0xFF6E54A5), // Indigo
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildCategoryChip(
                      'TV Series',
                      CalendarFilter.seriesOnly,
                      const Color(0xFF269CDE), // Series Blue
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildCategoryChip(
                      'Movies',
                      CalendarFilter.moviesOnly,
                      const Color(0xFF9C28B4), // Movie Purple
                    ),
                  ),
                ],
              ),
            ),

            // ACTIVE DATE FILTER BADGE (Centered & Symmetrical)
            if (_selectedDate != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Center(
                  child: GestureDetector(
                    onTap: () => setState(() => _selectedDate = null),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: colors.primary.withOpacity(0.16),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: colors.primary.withOpacity(0.4)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.event_busy_rounded, size: 14, color: colors.primary),
                          const SizedBox(width: 6),
                          Text(
                            'Filtered: ${_formatDayMonthYear(_selectedDate!)} • Tap to Clear',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: colors.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

            // MAIN AGENDA CONTENT
            Expanded(
              child: _selectedTab == 1 && _isLoadingDiscover
                  ? const Center(child: CircularProgressIndicator())
                  : filteredItems.isEmpty
                      ? _buildEmptyState(colors, theme)
                      : CustomScrollView(
                          physics: const BouncingScrollPhysics(),
                          slivers: [
                            // HERO SPOTLIGHT (Shown when viewing all dates)
                            if (_selectedDate == null && closestItem != null)
                              SliverToBoxAdapter(
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
                                  child: _buildHeroSpotlightCard(closestItem, colors, theme),
                                ),
                              ),

                            // GROUPED SECTIONS OR FLAT LIST
                            if (_selectedDate != null)
                              SliverPadding(
                                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                                sliver: SliverList(
                                  delegate: SliverChildBuilderDelegate(
                                    (ctx, idx) => _buildAgendaCard(filteredItems[idx], colors, theme),
                                    childCount: filteredItems.length,
                                  ),
                                ),
                              )
                            else
                              ..._buildGroupedAgendaSlivers(filteredItems, colors, theme),
                          ],
                        ),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================================
  // SCOPE CHIP (Vibrant Color Shade with Symmetrical Glow)
  // ==========================================================

  Widget _buildScopeChip(
    String label,
    IconData icon,
    int tabIndex,
    Color color,
  ) {
    final isSelected = _selectedTab == tabIndex;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            setState(() {
              _selectedTab = tabIndex;
              _selectedDate = null;
            });
          },
          borderRadius: BorderRadius.circular(16),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8.5),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isSelected
                  ? color.withOpacity(isDark ? 0.28 : 0.18)
                  : (isDark
                      ? Colors.white.withOpacity(0.06)
                      : Colors.black.withOpacity(0.04)),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isSelected
                    ? color.withOpacity(0.85)
                    : (isDark
                        ? Colors.white.withOpacity(0.14)
                        : Colors.black.withOpacity(0.08)),
                width: isSelected ? 1.5 : 1,
              ),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: color.withOpacity(0.30),
                        blurRadius: 8,
                        spreadRadius: 0.5,
                      ),
                    ]
                  : null,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 16,
                  color: isSelected
                      ? color
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                    color: isSelected
                        ? color
                        : Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ==========================================================
  // CATEGORY FILTER CHIP (Vibrant Color Shade with Symmetrical Glow)
  // ==========================================================

  Widget _buildCategoryChip(
    String label,
    CalendarFilter filter,
    Color color,
  ) {
    final isSelected = _filter == filter;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => setState(() => _filter = filter),
          borderRadius: BorderRadius.circular(16),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isSelected
                  ? color.withOpacity(isDark ? 0.28 : 0.18)
                  : (isDark
                      ? Colors.white.withOpacity(0.06)
                      : Colors.black.withOpacity(0.04)),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isSelected
                    ? color.withOpacity(0.85)
                    : (isDark
                        ? Colors.white.withOpacity(0.14)
                        : Colors.black.withOpacity(0.08)),
                width: isSelected ? 1.5 : 1,
              ),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: color.withOpacity(0.30),
                        blurRadius: 8,
                        spreadRadius: 0.5,
                      ),
                    ]
                  : null,
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                color: isSelected
                    ? color
                    : Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ==========================================================
  // HORIZONTAL DATE STRIP
  // ==========================================================

  Widget _buildHorizontalDateStrip(Set<DateTime> datesWithReleases, ColorScheme colors) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final days = List.generate(21, (index) => today.add(Duration(days: index)));

    return SizedBox(
      height: 68,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        itemCount: days.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          final day = days[index];
          final isToday = index == 0;
          final isSelected = _selectedDate != null &&
              _selectedDate!.year == day.year &&
              _selectedDate!.month == day.month &&
              _selectedDate!.day == day.day;
          final hasRelease = datesWithReleases.contains(day);

          return GestureDetector(
            onTap: () {
              setState(() {
                if (isSelected) {
                  _selectedDate = null;
                } else {
                  _selectedDate = day;
                }
              });
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: 50,
              decoration: BoxDecoration(
                color: isSelected
                    ? colors.primary
                    : isToday
                        ? colors.primary.withOpacity(0.14)
                        : colors.surfaceContainerHighest.withOpacity(0.35),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isSelected
                      ? colors.primary
                      : isToday
                          ? colors.primary.withOpacity(0.5)
                          : colors.outlineVariant.withOpacity(0.18),
                  width: isSelected || isToday ? 1.4 : 1,
                ),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: colors.primary.withOpacity(0.35),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ]
                    : null,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _formatWeekday(day),
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: isSelected
                          ? colors.onPrimary
                          : isToday
                              ? colors.primary
                              : colors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${day.day}',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: isSelected
                          ? colors.onPrimary
                          : isToday
                              ? colors.primary
                              : colors.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: hasRelease
                          ? (isSelected ? colors.onPrimary : const Color(0xFFF59E0B))
                          : Colors.transparent,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ==========================================================
  // HERO COUNTDOWN SPOTLIGHT CARD (Harmonized with Watcher Design)
  // ==========================================================

  Widget _buildHeroSpotlightCard(_AgendaItem item, ColorScheme colors, ThemeData theme) {
    final countdown = _getCountdownText(item.date);
    final countdownColor = _getCountdownColor(item.date, colors);

    final typeColor = item.isMovie
        ? const Color(0xFF9C28B4)
        : const Color(0xFF269CDE);

    final typeBackground = item.isMovie
        ? const Color(0xFFF6DFF7)
        : const Color(0xFFDDF3FF);

    return GlassContainer(
      borderRadius: 16,
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          PosterImage(
            url: item.posterUrl ?? '',
            width: 80,
            height: 115,
            radius: 12,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: SizedBox(
              height: 115,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: typeBackground.withOpacity(0.8),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              item.isMovie ? 'Movie' : 'Series',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                                color: typeColor,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: countdownColor.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: countdownColor.withOpacity(0.35)),
                            ),
                            child: Text(
                              countdown,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: countdownColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Text(
                        item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        item.subtitle,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: colors.primary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 1),
                      Text(
                        _formatDayMonthYear(item.date),
                        style: TextStyle(
                          fontSize: 11,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      GestureDetector(
                        onTap: () => _playTrailer(
                          item.title,
                          item.show?.id ?? item.discoverItem?.id,
                          item.isMovie,
                        ),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: colors.primary,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.play_arrow_rounded, size: 14, color: colors.onPrimary),
                              const SizedBox(width: 3),
                              Text(
                                'Trailer',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: colors.onPrimary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () => _openItem(item),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: colors.surfaceContainerHighest.withOpacity(0.4),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: colors.outlineVariant.withOpacity(0.25)),
                          ),
                          child: Text(
                            'Details',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: colors.onSurface,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // GROUPED AGENDA SLIVERS (Vibrant Colored Horizon Badges)
  // ==========================================================

  List<Widget> _buildGroupedAgendaSlivers(
    List<_AgendaItem> items,
    ColorScheme colors,
    ThemeData theme,
  ) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    final nextWeek = today.add(const Duration(days: 7));
    final endOfMonth = DateTime(today.year, today.month + 1, 0);

    final todayTomorrow = <_AgendaItem>[];
    final thisWeek = <_AgendaItem>[];
    final thisMonth = <_AgendaItem>[];
    final later = <_AgendaItem>[];

    for (final item in items) {
      final d = DateTime(item.date.year, item.date.month, item.date.day);
      if (d.isAtSameMomentAs(today) || d.isAtSameMomentAs(tomorrow)) {
        todayTomorrow.add(item);
      } else if (d.isBefore(nextWeek)) {
        thisWeek.add(item);
      } else if (d.isBefore(endOfMonth) || d.isAtSameMomentAs(endOfMonth)) {
        thisMonth.add(item);
      } else {
        later.add(item);
      }
    }

    final slivers = <Widget>[];

    if (todayTomorrow.isNotEmpty) {
      slivers.add(_buildSectionHeader('🔥 TODAY & TOMORROW', todayTomorrow.length, const Color(0xFFEF4444)));
      slivers.add(_buildSectionList(todayTomorrow, colors, theme));
    }

    if (thisWeek.isNotEmpty) {
      slivers.add(_buildSectionHeader('⚡ THIS WEEK', thisWeek.length, const Color(0xFFF59E0B)));
      slivers.add(_buildSectionList(thisWeek, colors, theme));
    }

    if (thisMonth.isNotEmpty) {
      slivers.add(_buildSectionHeader('🗓️ THIS MONTH', thisMonth.length, const Color(0xFF3B82F6)));
      slivers.add(_buildSectionList(thisMonth, colors, theme));
    }

    if (later.isNotEmpty) {
      slivers.add(_buildSectionHeader('🔮 LATER & ANNOUNCED', later.length, const Color(0xFF8B5CF6)));
      slivers.add(_buildSectionList(later, colors, theme));
    }

    return slivers;
  }

  Widget _buildSectionHeader(String title, int count, Color accent) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 6),
        child: Row(
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                color: accent,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: accent.withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: accent,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionList(List<_AgendaItem> items, ColorScheme colors, ThemeData theme) {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (ctx, idx) => _buildAgendaCard(items[idx], colors, theme),
          childCount: items.length,
        ),
      ),
    );
  }

  // ==========================================================
  // AGENDA CARD (Matching Watcher's standard _ShowRow height and layout)
  // ==========================================================

  Widget _buildAgendaCard(_AgendaItem item, ColorScheme colors, ThemeData theme) {
    final countdown = _getCountdownText(item.date);
    final countdownColor = _getCountdownColor(item.date, colors);
    final provider = context.watch<ShowProvider>();
    final isAdding = _addingIds.contains('${item.discoverItem?.mediaType}_${item.discoverItem?.id}');

    final typeColor = item.isMovie
        ? const Color(0xFF9C28B4)
        : const Color(0xFF269CDE);

    final typeBackground = item.isMovie
        ? const Color(0xFFF6DFF7)
        : const Color(0xFFDDF3FF);

    final alreadyInWatchlist = item.discoverItem != null &&
        provider.findLibraryMatchForTmdb(
          tmdbId: item.discoverItem!.id,
          mediaType: item.discoverItem!.mediaType,
          title: item.discoverItem!.title,
          yearText: item.discoverItem!.year,
        ) != null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassContainer(
        borderRadius: 16,
        padding: const EdgeInsets.all(10),
        onTap: () => _openItem(item),
        child: SizedBox(
          height: 115,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PosterImage(
                url: item.posterUrl ?? '',
                width: 80,
                height: 115,
                radius: 12,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: typeBackground.withOpacity(0.8),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                item.isMovie ? 'Movie' : 'Series',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                  color: typeColor,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: countdownColor.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: countdownColor.withOpacity(0.35)),
                              ),
                              child: Text(
                                countdown,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  color: countdownColor,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 5),
                        Text(
                          item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700,
                            height: 1.2,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          item.subtitle,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: colors.primary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 1),
                        Text(
                          _formatDayMonthYear(item.date),
                          style: TextStyle(
                            fontSize: 11,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    if (item.tags.isNotEmpty)
                      Wrap(
                        spacing: 4,
                        children: item.tags.take(2).map((t) {
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: colors.surfaceContainerHighest.withOpacity(0.4),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '#$t',
                              style: TextStyle(fontSize: 9.5, color: colors.primary, fontWeight: FontWeight.w600),
                            ),
                          );
                        }).toList(),
                      )
                    else
                      const SizedBox.shrink(),
                  ],
                ),
              ),
              // QUICK ACTION BUTTONS COLUMN
              Column(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  IconButton(
                    icon: Icon(Icons.play_circle_outline_rounded, color: colors.primary, size: 22),
                    tooltip: 'Watch Trailer',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _playTrailer(
                      item.title,
                      item.show?.id ?? item.discoverItem?.id,
                      item.isMovie,
                    ),
                  ),
                  if (item.show != null)
                    IconButton(
                      icon: Icon(
                        item.reminderEnabled
                            ? Icons.notifications_active_rounded
                            : Icons.notifications_none_rounded,
                        color: item.reminderEnabled ? const Color(0xFFD97706) : colors.onSurfaceVariant,
                        size: 20,
                      ),
                      tooltip: item.reminderEnabled ? 'Reminder Active' : 'Set Reminder',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => _toggleItemReminder(item),
                    )
                  else if (item.discoverItem != null)
                    alreadyInWatchlist
                        ? Icon(Icons.check_circle_rounded, color: colors.primary, size: 20)
                        : isAdding
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : IconButton(
                                icon: Icon(Icons.add_circle_outline_rounded, color: colors.primary, size: 20),
                                tooltip: 'Add to Watchlist',
                                visualDensity: VisualDensity.compact,
                                onPressed: () => _addDiscoverItemToLibrary(item.discoverItem!),
                              ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ==========================================================
  // TOGGLE REMINDER
  // ==========================================================

  Future<void> _toggleItemReminder(_AgendaItem item) async {
    final show = item.show;
    if (show == null) return;

    final provider = context.read<ShowProvider>();

    if (item.isMovie) {
      final res = await provider.setMovieReminderEnabled(
        show.id,
        !show.movieReminderEnabled,
      );
      if (mounted) {
        final enabled = res == EpisodeReminderResult.scheduled ||
            res == EpisodeReminderResult.enabledWaitingForEpisode;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              enabled
                  ? '🔔 Premiere reminder set for "${show.title}"!'
                  : '🔕 Reminder cancelled for "${show.title}".',
            ),
          ),
        );
      }
    } else {
      final res = await provider.setEpisodeReminderEnabled(
        show.id,
        !show.episodeReminderEnabled,
      );
      if (mounted) {
        final enabled = res == EpisodeReminderResult.scheduled ||
            res == EpisodeReminderResult.enabledWaitingForEpisode;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              enabled
                  ? '🔔 Episode reminder set for "${show.title}"!'
                  : '🔕 Episode reminder cancelled for "${show.title}".',
            ),
          ),
        );
      }
    }
  }

  // ==========================================================
  // NAVIGATION
  // ==========================================================

  void _openItem(_AgendaItem item) {
    if (item.show != null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ShowDetailScreen(showId: item.show!.id),
        ),
      );
    } else if (item.discoverItem != null) {
      final provider = context.read<ShowProvider>();
      final existing = provider.findLibraryMatchForTmdb(
        tmdbId: item.discoverItem!.id,
        mediaType: item.discoverItem!.mediaType,
        title: item.discoverItem!.title,
        yearText: item.discoverItem!.year,
      );
      if (existing != null) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ShowDetailScreen(showId: existing.id),
          ),
        );
      } else {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => DiscoverDetailScreen(item: item.discoverItem!),
          ),
        );
      }
    }
  }

  // ==========================================================
  // EMPTY STATE
  // ==========================================================

  Widget _buildEmptyState(ColorScheme colors, ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: colors.primary.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.event_available_rounded,
                size: 44,
                color: colors.primary,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              _selectedDate != null
                  ? 'No Releases on ${_formatDayMonthYear(_selectedDate!)}'
                  : _selectedTab == 0
                      ? 'No Upcoming Releases in Watchlist'
                      : 'No Discover Releases Found',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _selectedDate != null
                  ? 'Tap "Clear Date" above to view the full upcoming release timeline.'
                  : _selectedTab == 0
                      ? 'Switch to the "Global Discover" tab to discover upcoming movie & TV premieres!'
                      : 'Pull down to refresh or check your internet connection.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: colors.onSurfaceVariant,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
