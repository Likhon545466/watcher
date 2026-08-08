import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/show_provider.dart';
import '../utils/status_style.dart';
import '../widgets/ambient_background.dart';
import '../widgets/glass_container.dart';

class StatsScreen extends StatelessWidget {
  final ValueChanged<String> onCategoryTap;

  const StatsScreen({super.key, required this.onCategoryTap});

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

    for (final show in allShows) {
      if (show.isSeries) {
        totalEpisodesWatched += show.currentEpisode;
        totalMinutesWatched += (show.currentEpisode * 45);
      } else {
        if (show.status == 'Completed') {
          totalMinutesWatched += (show.runtimeMinutes > 0
              ? show.runtimeMinutes
              : 120);
        }
      }
    }

    final totalHoursWatched = (totalMinutesWatched / 60).toStringAsFixed(1);

    final completedCount = allShows
        .where((s) => s.status == 'Completed')
        .length;
    final watchingCount = allShows.where((s) => s.status == 'Watching').length;
    final planCount = allShows.where((s) => s.status == 'Plan to Watch').length;

    String milestoneTitle = 'Movie Beginner';
    IconData milestoneIcon = Icons.star_border_rounded;
    if (completedCount >= 20) {
      milestoneTitle = 'Master Binge Watcher';
      milestoneIcon = Icons.workspace_premium_rounded;
    } else if (completedCount >= 5) {
      milestoneTitle = 'Dedicated Cinephile';
      milestoneIcon = Icons.military_tech_rounded;
    }

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
            GlassContainer(
              borderRadius: 18,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: primary.withOpacity(0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(milestoneIcon, color: primary, size: 24),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Current Achievement',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          milestoneTitle,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: primary,
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
            const SizedBox(height: 12),
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
