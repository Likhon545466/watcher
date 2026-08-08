import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import '../models/changelog_item.dart';
import '../providers/settings_provider.dart';
import '../providers/show_provider.dart';
import '../widgets/glass_container.dart';
import 'appearance_screen.dart';
import 'data_backup_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _appVersion = 'v0.0.0';
  String _buildNumber = '0';

  @override
  void initState() {
    super.initState();

    _loadAppInfo();
  }

  // ==========================================================
  // APP INFO
  // ==========================================================

  Future<void> _loadAppInfo() async {
    try {
      final info = await PackageInfo.fromPlatform();

      if (!mounted) {
        return;
      }

      setState(() {
        _appVersion = 'v${info.version}';
        _buildNumber = info.buildNumber;
      });
    } catch (_) {}
  }

  // ==========================================================
  // CHANGELOG
  // ==========================================================

  void _showChangelogModal() {
    final changelogs = ChangelogData.changelogsFor(_appVersion);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) {
        final theme = Theme.of(context);
        final colors = theme.colorScheme;
        final isDark = theme.brightness == Brightness.dark;
        final primary = colors.primary;

        return Padding(
          padding: const EdgeInsets.fromLTRB(10, 12, 10, 10),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(30),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
              child: Container(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.84,
                ),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF0B1220).withOpacity(0.90)
                      : Colors.white.withOpacity(0.90),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(
                    color: isDark
                        ? Colors.white.withOpacity(0.15)
                        : Colors.black.withOpacity(0.08),
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(isDark ? 0.35 : 0.12),
                      blurRadius: 32,
                      offset: const Offset(0, 14),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    const SizedBox(height: 10),

                    Container(
                      width: 38,
                      height: 4,
                      decoration: BoxDecoration(
                        color: colors.onSurface.withOpacity(0.20),
                        borderRadius: BorderRadius.circular(100),
                      ),
                    ),

                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 16, 10, 14),
                      child: Row(
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: primary.withOpacity(0.13),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: primary.withOpacity(0.20),
                              ),
                            ),
                            child: Icon(
                              Icons.auto_awesome_rounded,
                              color: primary,
                              size: 21,
                            ),
                          ),

                          const SizedBox(width: 12),

                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'What\'s New',
                                  style: TextStyle(
                                    fontSize: 19,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -0.3,
                                    color: colors.onSurface,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Release history and improvements',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: colors.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),

                          IconButton(
                            tooltip: 'Close',
                            onPressed: () {
                              Navigator.pop(context);
                            },
                            icon: Icon(
                              Icons.close_rounded,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),

                    Divider(height: 1, color: colors.outline.withOpacity(0.10)),

                    Expanded(
                      child: ListView.builder(
                        physics: const BouncingScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                        itemCount: changelogs.length,
                        itemBuilder: (context, index) {
                          final item = changelogs[index];

                          return _ReleaseTimelineItem(
                            item: item,
                            isLatest: index == 0,
                            isLast: index == changelogs.length - 1,
                            primary: primary,
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // ==========================================================
  // BUILD
  // ==========================================================

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final primary = colors.primary;

    final showCount = context.watch<ShowProvider>().allShows.length;

    final settings = context.watch<SettingsProvider>();

    final itemLabel = showCount == 1 ? 'title' : 'titles';

    final modeText = switch (settings.themeMode) {
      ThemeMode.dark => 'Dark',
      ThemeMode.light => 'Light',
      ThemeMode.system => 'System',
    };

    return SafeArea(
      bottom: false,
      child: ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 130),
        children: [
          Text(
            'Settings',
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: -0.6,
            ),
          ),

          const SizedBox(height: 5),

          Text(
            'Customize Watcher and manage your library.',
            style: TextStyle(fontSize: 13, color: colors.onSurfaceVariant),
          ),

          const SizedBox(height: 20),

          // ==================================================
          // WATCHER CARD
          // ==================================================
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(24),
              onTap: _showChangelogModal,
              child: GlassContainer(
                borderRadius: 24,
                padding: const EdgeInsets.all(16),
                opacity: 0.13,
                borderColor: primary.withOpacity(0.18),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 54,
                          height: 54,
                          decoration: BoxDecoration(
                            color: primary.withOpacity(0.14),
                            borderRadius: BorderRadius.circular(17),
                            border: Border.all(
                              color: primary.withOpacity(0.18),
                            ),
                          ),
                          child: Icon(
                            Icons.movie_filter_rounded,
                            size: 28,
                            color: primary,
                          ),
                        ),

                        const SizedBox(width: 14),

                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Watcher',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.2,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Personal movie & series tracker',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),

                        Icon(
                          Icons.chevron_right_rounded,
                          size: 23,
                          color: colors.onSurfaceVariant,
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: colors.onSurface.withOpacity(0.035),
                        borderRadius: BorderRadius.circular(15),
                        border: Border.all(
                          color: colors.outline.withOpacity(0.07),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: _AppStat(
                              label: 'Version',
                              value: _appVersion,
                            ),
                          ),

                          _MiniDivider(color: colors.outline.withOpacity(0.12)),

                          Expanded(
                            child: _AppStat(
                              label: 'Build',
                              value: _buildNumber,
                            ),
                          ),

                          _MiniDivider(color: colors.outline.withOpacity(0.12)),

                          Expanded(
                            child: _AppStat(
                              label: 'Library',
                              value: '$showCount $itemLabel',
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 13),

                    Row(
                      children: [
                        Icon(
                          Icons.auto_awesome_rounded,
                          size: 16,
                          color: primary,
                        ),
                        const SizedBox(width: 7),
                        Text(
                          'View release notes',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: primary,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          'What\'s New',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(height: 28),

          // ==================================================
          // APPEARANCE
          // ==================================================
          const _SectionIntro(
            title: 'Appearance',
            subtitle: 'Personalize how Watcher looks and feels.',
          ),

          const SizedBox(height: 10),

          GlassContainer(
            borderRadius: 20,
            padding: const EdgeInsets.symmetric(vertical: 4),
            opacity: 0.09,
            child: _SettingsNavigationRow(
              icon: Icons.palette_outlined,
              title: 'Theme & Appearance',
              subtitle: '$modeText mode active',
              accent: primary,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AppearanceScreen()),
                );
              },
            ),
          ),

          const SizedBox(height: 28),

          // ==================================================
          // DATA & BACKUP
          // ==================================================
          const _SectionIntro(
            title: 'Data & Backup',
            subtitle: 'Protect and manage your local library.',
          ),

          const SizedBox(height: 10),

          GlassContainer(
            borderRadius: 20,
            padding: const EdgeInsets.symmetric(vertical: 4),
            opacity: 0.09,
            child: _SettingsNavigationRow(
              icon: Icons.cloud_sync_outlined,
              title: 'Data & Backup',
              subtitle: 'Backup, restore, CSV & offline posters',
              accent: Colors.teal,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const DataBackupScreen()),
                );
              },
            ),
          ),

          const SizedBox(height: 30),

          // ==================================================
          // FOOTER
          // ==================================================
          Center(
            child: Column(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: primary.withOpacity(0.09),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.movie_outlined,
                    size: 19,
                    color: primary.withOpacity(0.85),
                  ),
                ),

                const SizedBox(height: 9),

                Text(
                  'Watcher',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: colors.onSurface,
                  ),
                ),

                const SizedBox(height: 2),

                Text(
                  '$_appVersion  •  Build $_buildNumber',
                  style: TextStyle(
                    fontSize: 11,
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
// SECTION INTRO
// ============================================================

class _SectionIntro extends StatelessWidget {
  final String title;
  final String subtitle;

  const _SectionIntro({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 15.5,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.1,
              color: colors.onSurface,
            ),
          ),

          const SizedBox(height: 2),

          Text(
            subtitle,
            style: TextStyle(fontSize: 11.5, color: colors.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// SETTINGS NAVIGATION ROW
// ============================================================

class _SettingsNavigationRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color accent;
  final VoidCallback onTap;

  const _SettingsNavigationRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.11),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, size: 20, color: accent),
              ),

              const SizedBox(width: 12),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),

              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: colors.onSurface.withOpacity(0.04),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.chevron_right_rounded,
                  size: 19,
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// RELEASE TIMELINE
// ============================================================

class _ReleaseTimelineItem extends StatelessWidget {
  final ChangelogItem item;
  final bool isLatest;
  final bool isLast;
  final Color primary;

  const _ReleaseTimelineItem({
    required this.item,
    required this.isLatest,
    required this.isLast,
    required this.primary,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final colors = theme.colorScheme;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 28,
            child: Column(
              children: [
                Container(
                  width: isLatest ? 14 : 10,
                  height: isLatest ? 14 : 10,
                  margin: EdgeInsets.only(top: isLatest ? 4 : 6),
                  decoration: BoxDecoration(
                    color: isLatest
                        ? primary
                        : colors.onSurfaceVariant.withOpacity(0.35),
                    shape: BoxShape.circle,
                    border: isLatest
                        ? Border.all(
                            color: primary.withOpacity(0.22),
                            width: 4,
                            strokeAlign: BorderSide.strokeAlignOutside,
                          )
                        : null,
                  ),
                ),

                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 1.2,
                      margin: const EdgeInsets.symmetric(vertical: 6),
                      color: colors.outline.withOpacity(0.14),
                    ),
                  ),
              ],
            ),
          ),

          const SizedBox(width: 8),

          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 22),
              child: GlassContainer(
                borderRadius: 20,
                padding: const EdgeInsets.all(15),
                opacity: isLatest ? 0.16 : 0.06,
                borderColor: isLatest
                    ? primary.withOpacity(0.50)
                    : colors.outline.withOpacity(0.08),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 8,
                            runSpacing: 5,
                            children: [
                              Text(
                                item.version,
                                style: TextStyle(
                                  fontSize: 15.5,
                                  fontWeight: FontWeight.w800,
                                  color: isLatest ? primary : colors.onSurface,
                                ),
                              ),

                              if (isLatest)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 7,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: primary.withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(100),
                                    border: Border.all(
                                      color: primary.withOpacity(0.35),
                                    ),
                                  ),
                                  child: Text(
                                    'LATEST',
                                    style: TextStyle(
                                      fontSize: 8.5,
                                      letterSpacing: 0.5,
                                      fontWeight: FontWeight.w900,
                                      color: primary,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),

                        const SizedBox(width: 8),

                        Text(
                          item.date,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),

                    if (item.newFeatures.isNotEmpty)
                      _ReleaseSection(
                        title: 'New',
                        icon: Icons.add_rounded,
                        color: Colors.green,
                        items: item.newFeatures,
                      ),

                    if (item.improvements.isNotEmpty)
                      _ReleaseSection(
                        title: 'Improved',
                        icon: Icons.trending_up_rounded,
                        color: Colors.blueAccent,
                        items: item.improvements,
                      ),

                    if (item.bugFixes.isNotEmpty)
                      _ReleaseSection(
                        title: 'Fixed',
                        icon: Icons.build_circle_outlined,
                        color: Colors.amber.shade800,
                        items: item.bugFixes,
                      ),
                  ],
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
// RELEASE SECTION
// ============================================================

class _ReleaseSection extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final List<String> items;

  const _ReleaseSection({
    required this.title,
    required this.icon,
    required this.color,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(icon, size: 13, color: color),
              ),

              const SizedBox(width: 7),

              Text(
                title,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
            ],
          ),

          const SizedBox(height: 7),

          ...items.map((text) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 5, left: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Container(
                      width: 4,
                      height: 4,
                      decoration: BoxDecoration(
                        color: colors.onSurfaceVariant.withOpacity(0.65),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),

                  const SizedBox(width: 8),

                  Expanded(
                    child: Text(
                      text,
                      style: TextStyle(
                        fontSize: 12.3,
                        height: 1.38,
                        color: colors.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

// ============================================================
// APP STAT
// ============================================================

class _AppStat extends StatelessWidget {
  final String label;
  final String value;

  const _AppStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Column(
      children: [
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
        ),

        const SizedBox(height: 2),

        Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 9.5, color: colors.onSurfaceVariant),
        ),
      ],
    );
  }
}

// ============================================================
// MINI DIVIDER
// ============================================================

class _MiniDivider extends StatelessWidget {
  final Color color;

  const _MiniDivider({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(width: 1, height: 27, color: color);
  }
}
