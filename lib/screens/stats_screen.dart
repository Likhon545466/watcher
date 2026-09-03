import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/show_provider.dart';
import '../utils/status_style.dart';
import '../widgets/ambient_background.dart';
import '../widgets/glass_container.dart';

class _BadgeInfo {
  final String id;
  final String title;
  final String description;
  final IconData icon;
  final Color color;
  final bool isUnlocked;
  final int currentProgress;
  final int targetProgress;

  const _BadgeInfo({
    required this.id,
    required this.title,
    required this.description,
    required this.icon,
    required this.color,
    required this.isUnlocked,
    required this.currentProgress,
    required this.targetProgress,
  });

  double get progressRatio =>
      (currentProgress / targetProgress).clamp(0.0, 1.0);
}

class StatsScreen extends StatelessWidget {
  final ValueChanged<String> onCategoryTap;

  const StatsScreen({super.key, required this.onCategoryTap});

  List<_BadgeInfo> _computeBadges({
    required int totalCount,
    required int completedCount,
    required int completedMovies,
    required int completedSeries,
    required int totalEpisodesWatched,
    required int totalHours,
    required int taggedShowsCount,
  }) {
    return [
      _BadgeInfo(
        id: 'first_spark',
        title: 'First Spark',
        description: 'Track your very first title in Watcher',
        icon: Icons.auto_awesome_rounded,
        color: const Color(0xFFEAB308),
        isUnlocked: totalCount >= 1,
        currentProgress: totalCount,
        targetProgress: 1,
      ),
      _BadgeInfo(
        id: 'movie_novice',
        title: 'Movie Novice',
        description: 'Finish watching 1 movie',
        icon: Icons.movie_outlined,
        color: const Color(0xFF3B82F6),
        isUnlocked: completedMovies >= 1,
        currentProgress: completedMovies,
        targetProgress: 1,
      ),
      _BadgeInfo(
        id: 'couch_potato',
        title: 'Couch Potato',
        description: 'Watch at least 10 TV episodes',
        icon: Icons.chair_rounded,
        color: const Color(0xFF10B981),
        isUnlocked: totalEpisodesWatched >= 10,
        currentProgress: totalEpisodesWatched,
        targetProgress: 10,
      ),
      _BadgeInfo(
        id: 'binge_initiate',
        title: 'Binge Initiate',
        description: 'Watch 50 TV episodes',
        icon: Icons.play_arrow_rounded,
        color: const Color(0xFF8B5CF6),
        isUnlocked: totalEpisodesWatched >= 50,
        currentProgress: totalEpisodesWatched,
        targetProgress: 50,
      ),
      _BadgeInfo(
        id: 'century_club',
        title: 'Century Club',
        description: 'Watch 100 TV episodes',
        icon: Icons.workspace_premium_rounded,
        color: const Color(0xFFEC4899),
        isUnlocked: totalEpisodesWatched >= 100,
        currentProgress: totalEpisodesWatched,
        targetProgress: 100,
      ),
      _BadgeInfo(
        id: 'series_finisher',
        title: 'Series Finisher',
        description: 'Complete 3 full TV series',
        icon: Icons.check_circle_outline_rounded,
        color: const Color(0xFF06B6D4),
        isUnlocked: completedSeries >= 3,
        currentProgress: completedSeries,
        targetProgress: 3,
      ),
      _BadgeInfo(
        id: 'cinema_buff',
        title: 'Cinema Buff',
        description: 'Complete 10 feature movies',
        icon: Icons.local_movies_rounded,
        color: const Color(0xFFF97316),
        isUnlocked: completedMovies >= 10,
        currentProgress: completedMovies,
        targetProgress: 10,
      ),
      _BadgeInfo(
        id: 'marathon_master',
        title: 'Marathon Master',
        description: 'Log 50+ hours of watch time',
        icon: Icons.timer_rounded,
        color: const Color(0xFF6366F1),
        isUnlocked: totalHours >= 50,
        currentProgress: totalHours,
        targetProgress: 50,
      ),
      _BadgeInfo(
        id: 'grand_cinephile',
        title: 'Grand Cinephile',
        description: 'Complete 25 total titles',
        icon: Icons.military_tech_rounded,
        color: const Color(0xFF14B8A6),
        isUnlocked: completedCount >= 25,
        currentProgress: completedCount,
        targetProgress: 25,
      ),
      _BadgeInfo(
        id: 'tag_organizer',
        title: 'List Organizer',
        description: 'Organize 3+ shows with custom tags',
        icon: Icons.label_important_rounded,
        color: const Color(0xFFA855F7),
        isUnlocked: taggedShowsCount >= 3,
        currentProgress: taggedShowsCount,
        targetProgress: 3,
      ),
      _BadgeInfo(
        id: 'vault_keeper',
        title: 'Vault Keeper',
        description: 'Keep 50 titles in your watchlist',
        icon: Icons.all_inbox_rounded,
        color: const Color(0xFF0284C7),
        isUnlocked: totalCount >= 50,
        currentProgress: totalCount,
        targetProgress: 50,
      ),
      _BadgeInfo(
        id: 'legendary_watcher',
        title: 'Legendary Watcher',
        description: 'Watch 500 episodes or 50 completed titles',
        icon: Icons.diamond_rounded,
        color: const Color(0xFFFF007A),
        isUnlocked: totalEpisodesWatched >= 500 || completedCount >= 50,
        currentProgress: totalEpisodesWatched >= 500 ? totalEpisodesWatched : completedCount,
        targetProgress: totalEpisodesWatched >= 500 ? 500 : 50,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ShowProvider>();
    final allShows = provider.allShows;
    final primary = Theme.of(context).colorScheme.primary;

    final totalCount = allShows.length;
    final seriesCount = allShows.where((s) => s.isSeries).length;
    final movieCount = allShows.where((s) => !s.isSeries).length;

    int totalEpisodesWatched = 0;
    int totalMinutesWatched = 0;
    int completedMovies = 0;
    int completedSeries = 0;
    int taggedShowsCount = 0;

    for (final show in allShows) {
      if (show.customTags.isNotEmpty) {
        taggedShowsCount++;
      }

      if (show.isSeries) {
        totalEpisodesWatched += show.currentEpisode;
        totalMinutesWatched += (show.currentEpisode * 45);
        if (show.status == 'Completed') {
          completedSeries++;
        }
      } else {
        if (show.status == 'Completed') {
          completedMovies++;
          totalMinutesWatched += (show.runtimeMinutes > 0
              ? show.runtimeMinutes
              : 120);
        }
      }
    }

    final totalHours = (totalMinutesWatched / 60).round();
    final totalHoursWatched = (totalMinutesWatched / 60).toStringAsFixed(1);

    final completedCount = allShows
        .where((s) => s.status == 'Completed')
        .length;
    final watchingCount = allShows.where((s) => s.status == 'Watching').length;
    final planCount = allShows.where((s) => s.status == 'Plan to Watch').length;

    final badges = _computeBadges(
      totalCount: totalCount,
      completedCount: completedCount,
      completedMovies: completedMovies,
      completedSeries: completedSeries,
      totalEpisodesWatched: totalEpisodesWatched,
      totalHours: totalHours,
      taggedShowsCount: taggedShowsCount,
    );

    final unlockedBadges = badges.where((b) => b.isUnlocked).toList();
    final topBadge = unlockedBadges.isNotEmpty ? unlockedBadges.last : badges.first;

    return AmbientBackground(
      child: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
          children: <Widget>[
            Text(
              'Statistics',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 16),

            // CURRENT ACHIEVEMENT HERO CARD
            GlassContainer(
              borderRadius: 18,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: topBadge.color.withOpacity(0.18),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(topBadge.icon, color: topBadge.color, size: 26),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Text(
                              'Rank Status',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: primary.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '${unlockedBadges.length}/${badges.length} Unlocked',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                  color: primary,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          topBadge.title,
                          style: TextStyle(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w800,
                            color: topBadge.color,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '$completedCount Finished',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // KEY METRICS
            Row(
              children: <Widget>[
                Expanded(
                  child: _MetricCard(
                    title: 'Total Tracked',
                    value: '$totalCount',
                    icon: Icons.video_library_rounded,
                    color: primary,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _MetricCard(
                    title: 'EPs Watched',
                    value: '$totalEpisodesWatched',
                    icon: Icons.play_circle_fill_rounded,
                    color: const Color(0xFF10B981),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: <Widget>[
                Expanded(
                  child: _MetricCard(
                    title: 'TV Series',
                    value: '$seriesCount',
                    icon: Icons.tv_rounded,
                    color: const Color(0xFF2563EB),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _MetricCard(
                    title: 'Movies',
                    value: '$movieCount',
                    icon: Icons.movie_rounded,
                    color: const Color(0xFFD97706),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _MetricCard(
              title: 'Approx. Watch Time',
              value: '$totalHoursWatched Hours',
              icon: Icons.timer_rounded,
              color: const Color(0xFF8B5CF6),
            ),
            const SizedBox(height: 24),

            // MILESTONE BADGES SECTION (FEATURE 6)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Milestone Badges',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: primary,
                  ),
                ),
                Text(
                  '${unlockedBadges.length} of ${badges.length}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 138,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                itemCount: badges.length,
                separatorBuilder: (ctx, _) => const SizedBox(width: 10),
                itemBuilder: (context, index) {
                  final badge = badges[index];
                  return _BadgeCard(badge: badge);
                },
              ),
            ),

            const SizedBox(height: 24),
            Text(
              'Watch Status Breakdown',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: primary,
              ),
            ),
            const SizedBox(height: 10),
            GlassContainer(
              padding: const EdgeInsets.all(16),
              borderRadius: 20,
              child: Column(
                children: StatusStyle.statuses.map((status) {
                  final count = allShows
                      .where((s) => s.status == status)
                      .length;
                  final percentage = totalCount > 0
                      ? (count / totalCount)
                      : 0.0;
                  final color = StatusStyle.color(status);

                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => onCategoryTap(status),
                      child: Column(
                        children: <Widget>[
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: <Widget>[
                              Row(
                                children: <Widget>[
                                  Icon(
                                    StatusStyle.icon(status),
                                    size: 16,
                                    color: color,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    status,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13.5,
                                    ),
                                  ),
                                ],
                              ),
                              Text(
                                '$count (${(percentage * 100).toStringAsFixed(0)}%)',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: Container(
                              height: 6,
                              decoration: BoxDecoration(
                                color: color.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              alignment: Alignment.centerLeft,
                              child: FractionallySizedBox(
                                widthFactor: percentage.clamp(0.0, 1.0),
                                child: Container(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [color.withOpacity(0.6), color],
                                    ),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Quick Overview',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: primary,
              ),
            ),
            const SizedBox(height: 10),
            GlassContainer(
              borderRadius: 20,
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: <Widget>[
                  _QuickStatItem(
                    label: 'Watching',
                    count: watchingCount,
                    color: StatusStyle.color('Watching'),
                  ),
                  _QuickStatItem(
                    label: 'Completed',
                    count: completedCount,
                    color: StatusStyle.color('Completed'),
                  ),
                  _QuickStatItem(
                    label: 'Plan to Watch',
                    count: planCount,
                    color: StatusStyle.color('Plan to Watch'),
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

class _BadgeCard extends StatelessWidget {
  final _BadgeInfo badge;

  const _BadgeCard({required this.badge});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isUnlocked = badge.isUnlocked;

    return Container(
      width: 140,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isUnlocked
            ? badge.color.withOpacity(0.12)
            : theme.colorScheme.surfaceContainerHighest.withOpacity(0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isUnlocked
              ? badge.color.withOpacity(0.4)
              : theme.colorScheme.outlineVariant.withOpacity(0.2),
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: isUnlocked
                      ? badge.color.withOpacity(0.2)
                      : Colors.grey.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  badge.icon,
                  color: isUnlocked ? badge.color : Colors.grey,
                  size: 20,
                ),
              ),
              Icon(
                isUnlocked ? Icons.lock_open_rounded : Icons.lock_outline_rounded,
                size: 14,
                color: isUnlocked ? badge.color : Colors.grey,
              ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                badge.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 12.5,
                  color: isUnlocked ? null : Colors.grey,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                badge.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10,
                  color: theme.colorScheme.onSurfaceVariant.withOpacity(isUnlocked ? 1.0 : 0.6),
                ),
              ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    isUnlocked ? 'Completed' : '${badge.currentProgress}/${badge.targetProgress}',
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      color: isUnlocked ? badge.color : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: badge.progressRatio,
                  minHeight: 4,
                  backgroundColor: Colors.black12,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    isUnlocked ? badge.color : Colors.grey,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const _MetricCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      borderRadius: 18,
      padding: const EdgeInsets.all(14),
      child: Row(
        children: <Widget>[
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
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

class _QuickStatItem extends StatelessWidget {
  final String label;
  final int count;
  final Color color;

  const _QuickStatItem({
    required this.label,
    required this.count,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Text(
          '$count',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
