import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../models/changelog_item.dart';
import '../services/app_update_service.dart';
import '../widgets/ambient_background.dart';
import '../widgets/glass_container.dart';
import '../widgets/update_checker_modal.dart';

class GithubInfoScreen extends StatefulWidget {
  const GithubInfoScreen({super.key});

  @override
  State<GithubInfoScreen> createState() => _GithubInfoScreenState();
}

class _GithubInfoScreenState extends State<GithubInfoScreen> {
  GithubRepoStats _stats = GithubRepoStats.fallback();
  bool _isLoadingStats = true;
  String _appVersion = 'v0.0.0';
  String _buildNumber = '0';

  @override
  void initState() {
    super.initState();
    _loadAppInfo();
    _loadStats();
  }

  Future<void> _loadAppInfo() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) {
        setState(() {
          _appVersion = 'v${info.version}';
          _buildNumber = info.buildNumber;
        });
      }
    } catch (_) {}
  }

  Future<void> _loadStats() async {
    setState(() => _isLoadingStats = true);
    try {
      final stats = await AppUpdateService.fetchGithubStats();
      if (mounted) {
        setState(() {
          _stats = stats;
          _isLoadingStats = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoadingStats = false);
      }
    }
  }

  Future<void> _launchUrl(String url) async {
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {}
  }

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
            child: Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.84,
              ),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF0B1220).withOpacity(0.92)
                    : Colors.white.withOpacity(0.92),
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
                          onPressed: () => Navigator.pop(context),
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
                        return _ReleaseTimelineTile(
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
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final primary = colors.primary;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('GitHub & Developer'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            tooltip: 'Open Repository',
            icon: const Icon(Icons.open_in_new_rounded),
            onPressed: () => _launchUrl(AppUpdateService.githubRepoUrl),
          ),
          IconButton(
            tooltip: 'Refresh Stats',
            icon: _isLoadingStats
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded),
            onPressed: _isLoadingStats ? null : _loadStats,
          ),
        ],
      ),
      body: AmbientBackground(
        child: SafeArea(
          bottom: false,
          child: RefreshIndicator(
            onRefresh: _loadStats,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
              children: [
                // ====================================================
                // DEVELOPER CARD
                // ====================================================
                GlassContainer(
                  borderRadius: 24,
                  padding: const EdgeInsets.all(18),
                  opacity: 0.13,
                  borderColor: primary.withOpacity(0.20),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          // Profile Image / Avatar
                          Container(
                            width: 62,
                            height: 62,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(
                                colors: [primary, Colors.purpleAccent],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: primary.withOpacity(0.30),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            padding: const EdgeInsets.all(2.5),
                            child: ClipOval(
                              child: Image.network(
                                _stats.ownerAvatarUrl,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) => Container(
                                  color: primary.withOpacity(0.2),
                                  child: Icon(
                                    Icons.person_rounded,
                                    size: 34,
                                    color: primary,
                                  ),
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(width: 16),

                          // Name & Bio
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      _stats.ownerName,
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: -0.3,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 7,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: primary.withOpacity(0.12),
                                        borderRadius:
                                            BorderRadius.circular(100),
                                        border: Border.all(
                                          color: primary.withOpacity(0.3),
                                        ),
                                      ),
                                      child: Text(
                                        'DEV',
                                        style: TextStyle(
                                          fontSize: 9,
                                          fontWeight: FontWeight.w900,
                                          letterSpacing: 0.5,
                                          color: primary,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  _stats.ownerBio ??
                                      'Creator & Maintainer of Watcher',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: colors.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 16),

                      // Profile Action Button
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () =>
                              _launchUrl(_stats.ownerProfileUrl),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 11),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(15),
                            ),
                            side: BorderSide(
                              color: primary.withOpacity(0.35),
                            ),
                          ),
                          icon: Icon(
                            Icons.code_rounded,
                            size: 18,
                            color: primary,
                          ),
                          label: Text(
                            'Visit Developer GitHub Profile',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: primary,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // ====================================================
                // REPOSITORY OVERVIEW & STATS CARD
                // ====================================================
                GlassContainer(
                  borderRadius: 24,
                  padding: const EdgeInsets.all(18),
                  opacity: 0.11,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: colors.onSurface.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              Icons.folder_special_rounded,
                              size: 20,
                              color: primary,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  AppUpdateService.repoFullName,
                                  style: const TextStyle(
                                    fontSize: 15.5,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -0.2,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Public Open Source Repository',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: colors.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 12),

                      Text(
                        _stats.description,
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.42,
                          color: colors.onSurface.withOpacity(0.9),
                        ),
                      ),

                      const SizedBox(height: 16),

                      // Live Stats Grid
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: colors.onSurface.withOpacity(0.035),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: colors.outline.withOpacity(0.08),
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: _RepoStatItem(
                                icon: Icons.star_rounded,
                                iconColor: Colors.amber,
                                value: '${_stats.stars}',
                                label: 'Stars',
                              ),
                            ),
                            _DividerDot(color: colors.outline.withOpacity(0.15)),
                            Expanded(
                              child: _RepoStatItem(
                                icon: Icons.fork_right_rounded,
                                iconColor: Colors.blueAccent,
                                value: '${_stats.forks}',
                                label: 'Forks',
                              ),
                            ),
                            _DividerDot(color: colors.outline.withOpacity(0.15)),
                            Expanded(
                              child: _RepoStatItem(
                                icon: Icons.bug_report_rounded,
                                iconColor: Colors.redAccent,
                                value: '${_stats.openIssues}',
                                label: 'Issues',
                              ),
                            ),
                            _DividerDot(color: colors.outline.withOpacity(0.15)),
                            Expanded(
                              child: _RepoStatItem(
                                icon: Icons.verified_outlined,
                                iconColor: Colors.green,
                                value: _stats.license ?? 'MIT',
                                label: 'License',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // ====================================================
                // QUICK ACTIONS SECTION
                // ====================================================
                Text(
                  'Quick Actions',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.1,
                    color: colors.onSurface,
                  ),
                ),
                const SizedBox(height: 10),

                Row(
                  children: [
                    Expanded(
                      child: _ActionTile(
                        icon: Icons.open_in_browser_rounded,
                        title: 'Repository',
                        subtitle: 'View source code',
                        accent: Colors.indigoAccent,
                        onTap: () =>
                            _launchUrl(AppUpdateService.githubRepoUrl),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _ActionTile(
                        icon: Icons.star_border_rounded,
                        title: 'Star Project',
                        subtitle: 'Support on GitHub',
                        accent: Colors.amber,
                        onTap: () =>
                            _launchUrl(AppUpdateService.githubRepoUrl),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 10),

                Row(
                  children: [
                    Expanded(
                      child: _ActionTile(
                        icon: Icons.download_for_offline_outlined,
                        title: 'Releases & APK',
                        subtitle: 'All version downloads',
                        accent: Colors.teal,
                        onTap: () =>
                            _launchUrl(AppUpdateService.githubReleasesUrl),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _ActionTile(
                        icon: Icons.feedback_outlined,
                        title: 'Report Issue',
                        subtitle: 'Suggest feature / bug',
                        accent: Colors.deepOrangeAccent,
                        onTap: () =>
                            _launchUrl(AppUpdateService.githubNewIssueUrl),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 10),

                Row(
                  children: [
                    Expanded(
                      child: _ActionTile(
                        icon: Icons.system_update_alt_rounded,
                        title: 'Update Checker',
                        subtitle: 'Check latest release',
                        accent: primary,
                        onTap: () {
                          UpdateCheckerModal.show(
                            context,
                            currentVersion: _appVersion,
                            buildNumber: _buildNumber,
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _ActionTile(
                        icon: Icons.auto_awesome_rounded,
                        title: 'Release Notes',
                        subtitle: 'What\'s new history',
                        accent: Colors.purpleAccent,
                        onTap: _showChangelogModal,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 28),

                // ====================================================
                // TECH STACK & ARCHITECTURE
                // ====================================================
                Text(
                  'Tech Stack & Architecture',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.1,
                    color: colors.onSurface,
                  ),
                ),
                const SizedBox(height: 10),

                GlassContainer(
                  borderRadius: 20,
                  padding: const EdgeInsets.all(16),
                  opacity: 0.08,
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: const [
                      _TechBadge(label: 'Flutter', icon: Icons.flutter_dash),
                      _TechBadge(label: 'Dart', icon: Icons.code_rounded),
                      _TechBadge(label: 'Material 3', icon: Icons.palette_outlined),
                      _TechBadge(label: 'TMDB API', icon: Icons.movie_outlined),
                      _TechBadge(label: 'OMDb API', icon: Icons.search_rounded),
                      _TechBadge(label: 'SQLite Storage', icon: Icons.storage_rounded),
                      _TechBadge(label: 'Google Drive Sync', icon: Icons.cloud_sync_outlined),
                      _TechBadge(label: 'Glassmorphism UI', icon: Icons.blur_on_rounded),
                      _TechBadge(label: 'GitHub Actions CI', icon: Icons.rocket_launch_rounded),
                    ],
                  ),
                ),

                const SizedBox(height: 28),

                // ====================================================
                // OPEN SOURCE NOTE
                // ====================================================
                GlassContainer(
                  borderRadius: 20,
                  padding: const EdgeInsets.all(16),
                  opacity: 0.06,
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: Colors.green.withOpacity(0.12),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.favorite_rounded,
                          color: Colors.green,
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Watcher is an open-source, ad-free project. Contributions, feature requests, and feedback are always welcome!',
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.4,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
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

class _RepoStatItem extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String value;
  final String label;

  const _RepoStatItem({
    required this.icon,
    required this.iconColor,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 14, color: iconColor),
            const SizedBox(width: 4),
            Text(
              value,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: colors.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _DividerDot extends StatelessWidget {
  final Color color;

  const _DividerDot({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 24,
      color: color,
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color accent;
  final VoidCallback onTap;

  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return GlassContainer(
      borderRadius: 18,
      opacity: 0.08,
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: accent.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 18, color: accent),
          ),
          const SizedBox(height: 10),
          Text(
            title,
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              color: colors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _TechBadge extends StatelessWidget {
  final String label;
  final IconData icon;

  const _TechBadge({required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: colors.onSurface.withOpacity(0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.outline.withOpacity(0.07)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: colors.primary),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: colors.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReleaseTimelineTile extends StatelessWidget {
  final ChangelogItem item;
  final bool isLatest;
  final bool isLast;
  final Color primary;

  const _ReleaseTimelineTile({
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
                      _ReleaseNotesSection(
                        title: 'New',
                        icon: Icons.add_rounded,
                        color: Colors.green,
                        items: item.newFeatures,
                      ),
                    if (item.improvements.isNotEmpty)
                      _ReleaseNotesSection(
                        title: 'Improved',
                        icon: Icons.trending_up_rounded,
                        color: Colors.blueAccent,
                        items: item.improvements,
                      ),
                    if (item.bugFixes.isNotEmpty)
                      _ReleaseNotesSection(
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

class _ReleaseNotesSection extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final List<String> items;

  const _ReleaseNotesSection({
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
