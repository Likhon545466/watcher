import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart' hide XFile;

import '../models/show.dart';
import '../providers/cloud_backup_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/show_provider.dart';
import '../services/cloud_auto_backup_controller.dart';
import '../services/google_drive_backup_service.dart';
import '../services/poster_cache_service.dart';
import '../services/storage_service.dart';
import '../widgets/ambient_background.dart';
import '../widgets/glass_container.dart';

class DataBackupScreen extends StatefulWidget {
  const DataBackupScreen({super.key});

  @override
  State<DataBackupScreen> createState() => _DataBackupScreenState();
}

class _DataBackupScreenState extends State<DataBackupScreen> {
  bool _working = false;
  bool _cloudWorking = false;

  bool _loadingPosterCache = true;
  bool _clearingPosterCache = false;
  bool _loadingPosterCacheLimit = true;
  bool _updatingPosterCacheLimit = false;

  int _posterCacheBytes = 0;
  int _posterCacheCount = 0;
  int _posterCacheLimitBytes = PosterCacheService.cacheLimitOffBytes;

  @override
  void initState() {
    super.initState();

    _loadPosterCacheLimit();
    _loadPosterCacheStats(enforceLimit: true);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      final cloud = context.read<CloudBackupProvider>();

      if (cloud.isConnected && !cloud.checkingCloudBackup) {
        cloud.refreshCloudBackupInfo();
      }
    });
  }

  // ==========================================================
  // POSTER CACHE STATS
  // ==========================================================

  Future<void> _loadPosterCacheStats({bool enforceLimit = false}) async {
    if (mounted) {
      setState(() {
        _loadingPosterCache = true;
      });
    }

    try {
      if (enforceLimit) {
        await PosterCacheService.enforceAutoCleanLimit(force: true);
      }

      final bytes = await PosterCacheService.getCacheSizeBytes();
      final count = await PosterCacheService.getCachedPosterCount();

      if (!mounted) return;

      setState(() {
        _posterCacheBytes = bytes;
        _posterCacheCount = count;
        _loadingPosterCache = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingPosterCache = false;
      });
    }
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    if (bytes < 1024) return '$bytes B';
    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(kb >= 100 ? 0 : 1)} KB';
    final mb = kb / 1024;
    if (mb < 1024) return '${mb.toStringAsFixed(mb >= 100 ? 0 : 1)} MB';
    final gb = mb / 1024;
    return '${gb.toStringAsFixed(2)} GB';
  }

  // ==========================================================
  // POSTER CACHE AUTO CLEAN LIMIT
  // ==========================================================

  Future<void> _loadPosterCacheLimit() async {
    try {
      final limit = await PosterCacheService.getAutoCleanLimitBytes();

      if (!mounted) {
        return;
      }

      setState(() {
        _posterCacheLimitBytes = limit;
        _loadingPosterCacheLimit = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _loadingPosterCacheLimit = false;
      });
    }
  }

  String _formatCacheLimit(int bytes) {
    if (bytes <= 0) {
      return 'Off';
    }

    return _formatBytes(bytes);
  }

  Future<void> _openPosterCacheLimitSheet() async {
    if (_updatingPosterCacheLimit) {
      return;
    }

    final selected = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        final colors = Theme.of(context).colorScheme;
        final bottom = MediaQuery.of(context).padding.bottom;

        return Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + bottom),
          child: GlassContainer(
            borderRadius: 24,
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
            opacity: 0.95,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
                Text(
                  'Auto Clean Poster Cache',
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    color: colors.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Watcher will delete the oldest cached posters only after this size limit is crossed.',
                  style: TextStyle(
                    color: colors.onSurfaceVariant,
                    fontSize: 12.5,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 16),
                for (final option
                    in PosterCacheService.autoCleanLimitOptionsBytes)
                  _CacheLimitOption(
                    label: _formatCacheLimit(option),
                    subtitle: option <= 0
                        ? 'Manual clean only'
                        : 'Auto trim old posters above this size',
                    selected: _posterCacheLimitBytes == option,
                    onTap: () => Navigator.pop(context, option),
                  ),
              ],
            ),
          ),
        );
      },
    );

    if (selected == null || !mounted) {
      return;
    }

    await _setPosterCacheLimit(selected);
  }

  Future<void> _setPosterCacheLimit(int bytes) async {
    if (_updatingPosterCacheLimit) {
      return;
    }

    setState(() {
      _updatingPosterCacheLimit = true;
    });

    try {
      await PosterCacheService.setAutoCleanLimitBytes(bytes);

      if (bytes > 0) {
        await PosterCacheService.enforceAutoCleanLimit(force: true);
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _posterCacheLimitBytes = bytes;
      });

      await _loadPosterCacheStats();

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Poster cache auto clean set to ${_formatCacheLimit(bytes)}.',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not update poster cache limit.')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _updatingPosterCacheLimit = false;
        });
      }
    }
  }

  // ==========================================================
  // DATE / TIME FORMAT
  // ==========================================================

  String _formatHistoryDateTime(DateTime? value) {
    if (value == null) return 'Never';

    final date = value.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final targetDay = DateTime(date.year, date.month, date.day);

    final hour12 = date.hour == 0
        ? 12
        : date.hour > 12
        ? date.hour - 12
        : date.hour;
    final minute = date.minute.toString().padLeft(2, '0');
    final period = date.hour >= 12 ? 'PM' : 'AM';
    final timeText = '$hour12:$minute $period';

    if (targetDay == today) return 'Today at $timeText';
    if (targetDay == today.subtract(const Duration(days: 1))) {
      return 'Yesterday at $timeText';
    }

    const months = [
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
    return '${months[date.month - 1]} ${date.day}, $timeText';
  }

  // ==========================================================
  // GOOGLE CONNECT & BACKUP ACTIONS
  // ==========================================================

  Future<bool> _connectGoogle() async {
    if (_cloudWorking) return false;
    setState(() => _cloudWorking = true);

    try {
      final cloud = context.read<CloudBackupProvider>();
      final connected = await cloud.connectGoogle();

      if (!mounted) return false;

      if (!connected) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              cloud.lastError ?? 'Could not connect your Google account.',
            ),
          ),
        );
        return false;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Google Drive connected successfully.')),
      );
      return true;
    } catch (_) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not connect your Google account.')),
      );
      return false;
    } finally {
      if (mounted) setState(() => _cloudWorking = false);
    }
  }

  Future<void> _setBackupAndSync(bool enabled) async {
    if (_cloudWorking) return;
    setState(() => _cloudWorking = true);

    try {
      final cloud = context.read<CloudBackupProvider>();
      final success = await cloud.setBackupAndSyncEnabled(enabled);
      if (!mounted) return;

      if (!success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(cloud.lastError ?? 'Could not update Backup & Sync.'),
          ),
        );
        return;
      }

      if (enabled) {
        await CloudAutoBackupController.active?.syncNow();
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not update Backup & Sync.')),
      );
    } finally {
      if (mounted) setState(() => _cloudWorking = false);
    }
  }

  Future<void> _syncNow() async {
    if (_cloudWorking) return;

    final cloud = context.read<CloudBackupProvider>();

    if (!cloud.isConnected) {
      final connected = await _connectGoogle();
      if (!connected || !mounted) return;
    }

    setState(() => _cloudWorking = true);

    try {
      final success =
          await CloudAutoBackupController.active?.syncNow() ?? false;

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success
                ? 'Sync & Backup completed.'
                : 'Could not sync & backup right now. Please try again.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _cloudWorking = false);
    }
  }

  Future<void> _restoreFromCloud() async {
    if (_cloudWorking) return;
    final cloud = context.read<CloudBackupProvider>();

    if (!cloud.isConnected) {
      final connected = await _connectGoogle();
      if (!connected || !mounted) return;
    }

    setState(() => _cloudWorking = true);

    try {
      final raw = await GoogleDriveBackupService.instance.downloadBackupJson();
      if (!mounted) return;

      if (raw == null || raw.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No backup found in your Google Drive.'),
          ),
        );
        return;
      }

      late final List<Show> decoded;
      try {
        decoded = StorageService.decodeBackup(raw);
      } catch (_) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('The backup file is invalid or corrupted.'),
          ),
        );
        return;
      }

      setState(() => _cloudWorking = false);

      final restored = await _restoreDecodedBackup(
        decoded,
        title: 'Restore from Cloud',
      );
      if (!restored || !mounted) return;

      await cloud.markCloudRestoreCompleted();
      await cloud.refreshCloudBackupInfo();
    } on GoogleDriveAuthorizationRequiredException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Permission required. Please reconnect Google Drive.'),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to restore from Google Drive.')),
      );
    } finally {
      if (mounted && _cloudWorking) {
        setState(() => _cloudWorking = false);
      }
    }
  }

  Future<void> _refreshCloudInfo() async {
    if (_cloudWorking) return;
    final cloud = context.read<CloudBackupProvider>();
    if (!cloud.isConnected) return;

    await cloud.refreshCloudBackupInfo();
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(cloud.lastError ?? 'Cloud backup status updated.'),
      ),
    );
  }

  Future<void> _disconnectGoogle() async {
    if (_cloudWorking) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Disconnect Account?'),
        content: const Text(
          'Auto Backup will be disabled on this device. Your existing backups will remain safe in Google Drive.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Disconnect'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _cloudWorking = true);
    try {
      await context.read<CloudBackupProvider>().disconnectGoogle();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Google Drive disconnected.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not disconnect account.')),
      );
    } finally {
      if (mounted) setState(() => _cloudWorking = false);
    }
  }

  // ==========================================================
  // LOCAL ACTIONS
  // ==========================================================

  Future<void> _clearPosterCache() async {
    if (_clearingPosterCache || _posterCacheCount <= 0) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Offline Cache?'),
        content: Text(
          'This will free up ${_formatBytes(_posterCacheBytes)} of storage. '
          'Your watchlist data and cloud backup will remain unaffected.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear Storage'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _clearingPosterCache = true);
    try {
      await PosterCacheService.clearCache();
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();

      if (!mounted) return;
      setState(() {
        _posterCacheBytes = 0;
        _posterCacheCount = 0;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Offline storage cleared.')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to clear offline storage.')),
      );
    } finally {
      if (mounted) {
        setState(() => _clearingPosterCache = false);
        await _loadPosterCacheStats();
      }
    }
  }

  Future<void> _exportBackup() async {
    if (_working) return;
    setState(() => _working = true);

    try {
      final shows = context.read<ShowProvider>().allShows;
      final file = await StorageService.createBackupFile(shows);
      await Share.shareXFiles([
        XFile(file.path, mimeType: 'text/plain'),
      ], subject: 'Watcher Backup');
      await context.read<SettingsProvider>().markBackupCreated();
    } catch (_) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Could not export backup.')));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _importBackup() async {
    if (_working) return;

    const group = XTypeGroup(
      label: 'Watcher Backup',
      extensions: ['txt', 'json'],
      mimeTypes: ['text/plain', 'application/json'],
      uniformTypeIdentifiers: ['public.plain-text', 'public.json'],
    );

    final file = await openFile(acceptedTypeGroups: const [group]);
    if (file == null || !mounted) return;

    late final List<Show> decoded;
    try {
      decoded = StorageService.decodeBackup(await file.readAsString());
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid or corrupted backup file.')),
      );
      return;
    }

    if (!mounted) return;
    await _restoreDecodedBackup(decoded, title: 'Restore from Local File');
  }

  Future<void> _exportCsv() async {
    if (_working) return;
    setState(() => _working = true);

    try {
      final shows = context.read<ShowProvider>().allShows;
      final file = await StorageService.createCsvFile(shows);
      await Share.shareXFiles([
        XFile(file.path, mimeType: 'text/csv'),
      ], subject: 'Watcher CSV Export');
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not export CSV file.')),
      );
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  // ==========================================================
  // SHARED RESTORE UI LOGIC
  // ==========================================================

  Future<bool> _restoreDecodedBackup(
    List<Show> decoded, {
    required String title,
  }) async {
    if (!mounted) return false;
    final provider = context.read<ShowProvider>();

    final duplicateCount = decoded
        .where(
          (show) =>
              provider.findLibraryMatch(
                exactId: show.id,
                title: show.title,
                type: show.type,
                yearText: show.yearText,
              ) !=
              null,
        )
        .length;

    final newCount = decoded.length - duplicateCount;
    final action = await _showRestoreSheet(
      title: title,
      totalCount: decoded.length,
      newCount: newCount,
      duplicateCount: duplicateCount,
    );

    if (action == null || action == 'cancel' || !mounted) return false;

    if (action == 'replace') {
      final confirmed = await _confirmReplaceLibrary();
      if (!confirmed || !mounted) return false;
    }

    final settingsProvider = context.read<SettingsProvider>();
    final messenger = ScaffoldMessenger.of(context);

    setState(() => _working = true);

    try {
      if (action == 'replace') {
        await provider.replaceAll(decoded);
        await settingsProvider.markRestoreCompleted();

        if (!mounted) return false;

        messenger.showSnackBar(
          const SnackBar(content: Text('Library successfully replaced.')),
        );

        return true;
      }

      if (action == 'add') {
        final added = await provider.mergeShows(decoded);
        await settingsProvider.markRestoreCompleted();

        if (!mounted) return false;

        messenger.showSnackBar(
          SnackBar(
            content: Text(
              added == 0
                  ? 'All items are already in your library.'
                  : 'Restored $added missing item(s).',
            ),
          ),
        );

        return true;
      }

      return false;
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<String?> _showRestoreSheet({
    required String title,
    required int totalCount,
    required int newCount,
    required int duplicateCount,
  }) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final colors = Theme.of(context).colorScheme;
        final bottom = MediaQuery.of(context).padding.bottom;

        return Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + bottom),
          child: GlassContainer(
            borderRadius: 24,
            padding: const EdgeInsets.all(20),
            opacity: 0.95,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Found $totalCount items in the backup. How would you like to restore them?',
                  style: TextStyle(
                    color: colors.onSurfaceVariant,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 24),
                _DataStatRow(
                  label: 'New items to add',
                  value: '$newCount',
                  color: Colors.green,
                ),
                const SizedBox(height: 12),
                _DataStatRow(
                  label: 'Already in library',
                  value: '$duplicateCount',
                  color: Colors.grey,
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context, 'add'),
                    child: const Text(
                      'Merge Missing Items Only',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                    ),
                    onPressed: () => Navigator.pop(context, 'replace'),
                    child: const Text(
                      'Erase & Replace Library',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Center(
                  child: TextButton(
                    onPressed: () => Navigator.pop(context, 'cancel'),
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

  Future<bool> _confirmReplaceLibrary() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Warning: Replace Library?'),
        content: const Text(
          'This will permanently delete your current watchlist on this device and replace it with the backup data.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Replace'),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  // ==========================================================
  // BUILD
  // ==========================================================

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final cloud = context.watch<CloudBackupProvider>();

    final cloudBackupDate = cloud.lastCloudBackupAt ?? cloud.cloudModifiedTime;
    final cloudBackupText = _formatHistoryDateTime(cloudBackupDate);
    final cloudSyncText = _formatHistoryDateTime(cloud.lastCloudSyncAt);
    final busy =
        _working ||
        _cloudWorking ||
        cloud.connecting ||
        _updatingPosterCacheLimit;

    return AmbientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          title: const Text(
            'Data & Backup',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
        body: Stack(
          children: [
            ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              physics: const BouncingScrollPhysics(),
              children: [
                // CLOUD SYNC SECTION
                _SectionHeader(title: 'Google Drive Sync'),
                _GoogleDriveSyncCard(
                  connected: cloud.isConnected,
                  backupAndSyncEnabled:
                      cloud.autoBackupEnabled && cloud.autoSyncEnabled,
                  email: cloud.email,
                  lastBackupText: cloudBackupText,
                  lastSyncText: cloudSyncText,
                  hasCloudBackup: cloud.hasCloudBackup,
                  busy: busy,
                  onBackupAndSyncChanged: _setBackupAndSync,
                  onSyncNow: _syncNow,
                  onRefresh: _refreshCloudInfo,
                  onRestore: _restoreFromCloud,
                  onConnect: _connectGoogle,
                ),

                const SizedBox(height: 28),

                // ADVANCED / LOCAL SECTION
                _SectionHeader(title: 'Advanced & Local Settings'),
                GlassContainer(
                  borderRadius: 20,
                  padding: EdgeInsets.zero,
                  opacity: 0.1,
                  child: Column(
                    children: [
                      _SettingsTile(
                        icon: Icons.download_rounded,
                        title: 'Export Backup File',
                        subtitle: 'Save a local txt copy',
                        onTap: busy ? null : _exportBackup,
                      ),
                      _SettingsDivider(),
                      _SettingsTile(
                        icon: Icons.restore_page_rounded,
                        title: 'Import Local Backup',
                        subtitle: 'Restore from a txt file',
                        onTap: busy ? null : _importBackup,
                      ),
                      _SettingsDivider(),
                      _SettingsTile(
                        icon: Icons.table_chart_rounded,
                        title: 'Export as CSV',
                        subtitle: 'View your list in Excel/Sheets',
                        onTap: busy ? null : _exportCsv,
                      ),
                      _SettingsDivider(),
                      _PosterCacheTile(
                        loading:
                            _loadingPosterCache || _loadingPosterCacheLimit,
                        clearing:
                            _clearingPosterCache || _updatingPosterCacheLimit,
                        count: _posterCacheCount,
                        sizeText: _formatBytes(_posterCacheBytes),
                        limitText: _formatCacheLimit(_posterCacheLimitBytes),
                        onChangeLimit: busy ? null : _openPosterCacheLimitSheet,
                        onCleanNow: busy || _posterCacheCount == 0
                            ? null
                            : _clearPosterCache,
                      ),
                      if (cloud.isConnected) ...[
                        _SettingsDivider(),
                        _SettingsTile(
                          icon: Icons.logout_rounded,
                          title: 'Disconnect Google Drive',
                          subtitle: 'Stop auto-sync on this device',
                          isDestructive: true,
                          onTap: busy ? null : _disconnectGoogle,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 48),
              ],
            ),
            if (busy)
              const Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: LinearProgressIndicator(minHeight: 3),
              ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// CLEAN UI HELPERS
// ============================================================

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 8, bottom: 12),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.2,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final bool isDestructive;

  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
    this.isDestructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final contentColor = isDestructive ? Colors.redAccent : colors.onSurface;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      leading: Icon(icon, color: contentColor, size: 26),
      title: Text(
        title,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: contentColor,
          fontSize: 15,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(color: colors.onSurfaceVariant, fontSize: 13),
      ),
      onTap: onTap,
      trailing: onTap != null
          ? Icon(
              Icons.chevron_right_rounded,
              color: colors.onSurfaceVariant.withOpacity(0.5),
            )
          : null,
    );
  }
}

class _SettingsDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      thickness: 1,
      indent: 64,
      color: Theme.of(context).colorScheme.outline.withOpacity(0.15),
    );
  }
}

class _GoogleDriveSyncCard extends StatelessWidget {
  final bool connected;
  final bool backupAndSyncEnabled;
  final String? email;
  final String lastBackupText;
  final String lastSyncText;
  final bool hasCloudBackup;
  final bool busy;
  final Future<void> Function(bool) onBackupAndSyncChanged;
  final Future<void> Function() onSyncNow;
  final Future<void> Function() onRefresh;
  final Future<void> Function() onRestore;
  final Future<bool> Function() onConnect;

  const _GoogleDriveSyncCard({
    required this.connected,
    required this.backupAndSyncEnabled,
    required this.email,
    required this.lastBackupText,
    required this.lastSyncText,
    required this.hasCloudBackup,
    required this.busy,
    required this.onBackupAndSyncChanged,
    required this.onSyncNow,
    required this.onRefresh,
    required this.onRestore,
    required this.onConnect,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final connectedColor = connected ? const Color(0xFF16A34A) : colors.outline;

    return GlassContainer(
      borderRadius: 20,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 13),
      opacity: 0.1,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: connectedColor.withOpacity(0.11),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: connectedColor.withOpacity(0.20)),
                ),
                child: Icon(
                  connected
                      ? Icons.cloud_done_rounded
                      : Icons.cloud_off_rounded,
                  size: 19,
                  color: connectedColor,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Google Drive Sync',
                      style: TextStyle(
                        color: colors.onSurface,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      connected
                          ? (backupAndSyncEnabled
                                ? 'Connected • Backup & Sync is active'
                                : 'Connected • Backup & Sync is off')
                          : 'Connect to protect your library',
                      style: TextStyle(
                        color: colors.onSurfaceVariant,
                        fontSize: 11.8,
                        fontWeight: FontWeight.w600,
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
              if (connected)
                Icon(
                  backupAndSyncEnabled
                      ? Icons.sync_rounded
                      : Icons.cloud_queue_rounded,
                  color: connectedColor,
                  size: 21,
                ),
            ],
          ),

          if (connected) ...<Widget>[
            if (email?.trim().isNotEmpty == true) ...<Widget>[
              const SizedBox(height: 11),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: colors.onSurface.withOpacity(0.032),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: colors.outline.withOpacity(0.075)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Icon(
                      Icons.alternate_email_rounded,
                      size: 14,
                      color: colors.onSurfaceVariant,
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        email!.trim(),
                        softWrap: true,
                        maxLines: 2,
                        overflow: TextOverflow.visible,
                        style: TextStyle(
                          color: colors.onSurfaceVariant,
                          fontSize: 12.1,
                          fontWeight: FontWeight.w600,
                          height: 1.25,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
              decoration: BoxDecoration(
                color: colors.onSurface.withOpacity(0.028),
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: colors.outline.withOpacity(0.075)),
              ),
              child: Row(
                children: <Widget>[
                  const Icon(Icons.sync_rounded, size: 17),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const Text(
                          'Backup & Sync',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          backupAndSyncEnabled
                              ? 'Auto backup + multi-device sync enabled'
                              : 'Automatic backup and sync paused',
                          style: const TextStyle(fontSize: 10.5),
                        ),
                      ],
                    ),
                  ),
                  Switch.adaptive(
                    value: backupAndSyncEnabled,
                    onChanged: busy ? null : onBackupAndSyncChanged,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
              decoration: BoxDecoration(
                color: const Color(0xFF0D9488).withOpacity(0.09),
                borderRadius: BorderRadius.circular(15),
                border: Border.all(
                  color: const Color(0xFF0D9488).withOpacity(0.18),
                ),
              ),
              child: Row(
                children: <Widget>[
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: const Color(0xFF0D9488).withOpacity(0.13),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.schedule_rounded,
                      size: 15,
                      color: Color(0xFF0D9488),
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          'Last backup',
                          style: TextStyle(
                            color: colors.onSurfaceVariant,
                            fontSize: 10.8,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          lastBackupText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: colors.onSurface,
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.1,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Check cloud backup',
                    visualDensity: VisualDensity.compact,
                    onPressed: busy
                        ? null
                        : () {
                            onRefresh();
                          },
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
              decoration: BoxDecoration(
                color: colors.primary.withOpacity(0.07),
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: colors.primary.withOpacity(0.14)),
              ),
              child: Row(
                children: <Widget>[
                  Icon(Icons.sync_rounded, size: 17, color: colors.primary),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          'Last synced',
                          style: TextStyle(
                            color: colors.onSurfaceVariant,
                            fontSize: 10.8,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          lastSyncText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: colors.onSurface,
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: busy
                    ? null
                    : () {
                        onSyncNow();
                      },
                icon: const Icon(Icons.sync_rounded, size: 17),
                label: const Text(
                  'Sync & Backup Now',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(13),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonalIcon(
                onPressed: busy || !hasCloudBackup
                    ? null
                    : () {
                        onRestore();
                      },
                icon: const Icon(Icons.restore_rounded, size: 17),
                label: const Text(
                  'Restore from Google Drive',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(13),
                  ),
                ),
              ),
            ),
          ] else ...<Widget>[
            const SizedBox(height: 12),
            Text(
              'Back up your Watcher library to Google Drive app storage. Poster image files are not uploaded.',
              style: TextStyle(
                color: colors.onSurfaceVariant,
                fontSize: 12.2,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: busy
                    ? null
                    : () {
                        onConnect();
                      },
                icon: const Icon(Icons.login_rounded, size: 18),
                label: const Text(
                  'Connect Google Drive',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PosterCacheTile extends StatelessWidget {
  final bool loading;
  final bool clearing;
  final int count;
  final String sizeText;
  final String limitText;
  final VoidCallback? onChangeLimit;
  final VoidCallback? onCleanNow;

  const _PosterCacheTile({
    required this.loading,
    required this.clearing,
    required this.count,
    required this.sizeText,
    required this.limitText,
    required this.onChangeLimit,
    required this.onCleanNow,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final primary = colors.primary;

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: primary.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: primary.withOpacity(0.17)),
                ),
                child: Icon(
                  Icons.photo_library_outlined,
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
                      'Poster Cache',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: colors.onSurface,
                        fontSize: 14.5,
                        letterSpacing: -0.1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      loading
                          ? 'Calculating offline poster storage...'
                          : 'Auto clean removes oldest posters only',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colors.onSurfaceVariant,
                        fontSize: 11.8,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          Row(
            children: <Widget>[
              Expanded(
                child: _TinyMetricPill(
                  icon: Icons.sd_storage_rounded,
                  label: 'Size',
                  value: loading ? '...' : sizeText,
                  color: primary,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _TinyMetricPill(
                  icon: Icons.image_rounded,
                  label: 'Posters',
                  value: loading ? '...' : '$count',
                  color: const Color(0xFF0D9488),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _TinyMetricPill(
                  icon: Icons.auto_delete_outlined,
                  label: 'Auto',
                  value: limitText,
                  color: const Color(0xFFD97706),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          Row(
            children: <Widget>[
              Expanded(
                child: _MiniTextButton(
                  label: 'Change Limit',
                  onTap: clearing ? null : onChangeLimit,
                  leadingIcon: Icons.tune_rounded,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _MiniTextButton(
                  label: clearing ? 'Cleaning...' : 'Clean Now',
                  onTap: clearing ? null : onCleanNow,
                  destructive: true,
                  leadingIcon: Icons.cleaning_services_rounded,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TinyMetricPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _TinyMetricPill({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(isDark ? 0.15 : 0.085),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(isDark ? 0.28 : 0.16)),
      ),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color.withOpacity(0.82),
                    fontSize: 9.2,
                    fontWeight: FontWeight.w700,
                    height: 1,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color,
                    fontSize: 11.2,
                    fontWeight: FontWeight.w900,
                    height: 1,
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

class _MiniTextButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final bool destructive;
  final IconData? leadingIcon;

  const _MiniTextButton({
    required this.label,
    required this.onTap,
    this.destructive = false,
    this.leadingIcon,
  });

  @override
  Widget build(BuildContext context) {
    final color = destructive
        ? Colors.redAccent
        : Theme.of(context).colorScheme.primary;

    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Opacity(
        opacity: onTap == null ? 0.45 : 1,
        child: Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: color.withOpacity(0.08),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: color.withOpacity(0.18)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              if (leadingIcon != null) ...<Widget>[
                Icon(leadingIcon, size: 14, color: color),
                const SizedBox(width: 5),
              ],
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color,
                    fontSize: 11.6,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CacheLimitOption extends StatelessWidget {
  final String label;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  const _CacheLimitOption({
    required this.label,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final primary = colors.primary;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected
            ? primary.withOpacity(0.12)
            : colors.onSurface.withOpacity(0.035),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: selected
                    ? primary.withOpacity(0.45)
                    : colors.outline.withOpacity(0.10),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  selected ? Icons.check_circle_rounded : Icons.circle_outlined,
                  color: selected ? primary : colors.onSurfaceVariant,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: selected ? primary : colors.onSurface,
                          fontSize: 13.5,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: colors.onSurfaceVariant,
                          fontSize: 11.5,
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

class _DataStatRow extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _DataStatRow({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: color.withOpacity(0.15),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            value,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 15,
            ),
          ),
        ),
      ],
    );
  }
}
