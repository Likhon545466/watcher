import 'dart:async';

import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'providers/cloud_backup_provider.dart';
import 'providers/settings_provider.dart';
import 'providers/show_provider.dart';
import 'screens/discover_screen.dart';
import 'screens/home_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/stats_screen.dart';
import 'services/cloud_auto_backup_controller.dart';
import 'services/notification_service.dart';
import 'services/tmdb_service.dart';
import 'theme/app_theme.dart';
import 'widgets/ambient_background.dart';

// ============================================================
// MAIN
// ============================================================

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<ShowProvider>(create: (_) => ShowProvider()),

        ChangeNotifierProvider<SettingsProvider>(
          create: (_) => SettingsProvider(),
        ),

        ChangeNotifierProvider<CloudBackupProvider>(
          create: (_) {
            final provider = CloudBackupProvider();

            unawaited(provider.initialize());

            return provider;
          },
        ),
      ],
      child: const WatcherApp(),
    ),
  );

  unawaited(NotificationService.initialize());
}

// ============================================================
// WATCHER APP
// ============================================================

class WatcherApp extends StatelessWidget {
  const WatcherApp({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();

    return DynamicColorBuilder(
      builder: (lightDynamic, darkDynamic) {
        final useDynamic = settings.dynamicColorEnabled;

        return MaterialApp(
          title: 'Watcher',

          debugShowCheckedModeBanner: false,

          theme: AppTheme.light(
            scheme: useDynamic ? lightDynamic : null,
            palette: settings.selectedPalette,
          ),

          darkTheme: AppTheme.dark(
            scheme: useDynamic ? darkDynamic : null,
            palette: settings.selectedPalette,
          ),

          themeMode: settings.themeMode,

          home: const MainNavigation(),
        );
      },
    );
  }
}

// ============================================================
// MAIN NAVIGATION
// ============================================================

class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  final GlobalKey<HomeScreenState> _homeScreenKey =
      GlobalKey<HomeScreenState>();

  late final PageController _mainPageController;

  late final List<Widget> _screens;

  late final CloudAutoBackupController _cloudAutoBackupController;

  int _index = 0;

  bool _backupOnboardingScheduled = false;

  bool _backupOnboardingOpen = false;

  // ==========================================================
  // INIT
  // ==========================================================

  @override
  void initState() {
    super.initState();

    _mainPageController = PageController(initialPage: _index);

    _cloudAutoBackupController = CloudAutoBackupController(
      showProvider: context.read<ShowProvider>(),
      cloudProvider: context.read<CloudBackupProvider>(),
    );

    _screens = <Widget>[
      HomeScreen(
        key: _homeScreenKey,
        onOverflowNext: () {
          _onTabTapped(1);
        },
      ),

      DiscoverScreen(
        onOverflowNext: () {
          _onTabTapped(2);
        },
        onOverflowPrev: () {
          _onTabTapped(0);
        },
      ),

      StatsScreen(onCategoryTap: _navigateToCategory),

      const SettingsScreen(),
    ];

    _scheduleDiscoverPrefetch();
  }

  // ==========================================================
  // STARTUP PREFETCH
  // ==========================================================
  //
  // Keep Discover cache warm, but delay it a bit so the first
  // app frames, Google backup init, and Home UI animation do
  // not compete with TMDB network/cache work.
  //
  // ==========================================================

  void _scheduleDiscoverPrefetch() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future<void>.delayed(const Duration(milliseconds: 1800), () {
        if (!mounted) {
          return;
        }

        unawaited(TmdbService.prefetchDiscoverData());
      });
    });
  }

  // ==========================================================
  // BACKUP ONBOARDING
  // ==========================================================

  void _scheduleBackupOnboarding() {
    if (_backupOnboardingScheduled || _backupOnboardingOpen) {
      return;
    }

    final cloud = context.read<CloudBackupProvider>();

    if (!cloud.shouldShowBackupOnboarding) {
      return;
    }

    _backupOnboardingScheduled = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      unawaited(_showBackupOnboarding());
    });
  }

  Future<void> _showBackupOnboarding() async {
    if (!mounted || _backupOnboardingOpen) {
      return;
    }

    final cloud = context.read<CloudBackupProvider>();

    if (!cloud.shouldShowBackupOnboarding) {
      return;
    }

    _backupOnboardingOpen = true;

    try {
      await Future<void>.delayed(const Duration(milliseconds: 450));

      if (!mounted || !cloud.shouldShowBackupOnboarding) {
        return;
      }

      await showModalBottomSheet<void>(
        context: context,

        isDismissible: false,

        enableDrag: false,

        isScrollControlled: true,

        backgroundColor: Colors.transparent,

        builder: (sheetContext) {
          return _BackupOnboardingSheet(
            onGoogleConnected: () {
              Navigator.of(sheetContext).pop();
            },
          );
        },
      );
    } finally {
      _backupOnboardingOpen = false;
    }
  }

  // ==========================================================
  // DISPOSE
  // ==========================================================

  @override
  void dispose() {
    _cloudAutoBackupController.dispose();

    _mainPageController.dispose();

    super.dispose();
  }

  // ==========================================================
  // TAB TAP
  // ==========================================================

  void _onTabTapped(int index) {
    if (index < 0 || index >= _screens.length) {
      return;
    }

    if (_index == index && index == 0) {
      _homeScreenKey.currentState?.resetToAll();

      return;
    }

    if (_index == index) {
      return;
    }

    setState(() {
      _index = index;
    });

    if (!_mainPageController.hasClients) {
      return;
    }

    _mainPageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }

  // ==========================================================
  // PAGE CHANGED
  // ==========================================================

  void _onMainPageChanged(int index) {
    if (_index == index) {
      return;
    }

    setState(() {
      _index = index;
    });
  }

  // ==========================================================
  // STATS -> HOME CATEGORY
  // ==========================================================

  void _navigateToCategory(String category) {
    context.read<ShowProvider>().setCategory(category);

    _homeScreenKey.currentState?.goToCategory(category);

    _onTabTapped(0);
  }

  // ==========================================================
  // BUILD
  // ==========================================================

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Only listen to the onboarding flag.
    // Do not rebuild the whole navigation shell for every
    // cloud backup timestamp/loading/status update.
    final shouldShowBackupOnboarding = context
        .select<CloudBackupProvider, bool>(
          (cloud) => cloud.shouldShowBackupOnboarding,
        );

    if (shouldShowBackupOnboarding) {
      _scheduleBackupOnboarding();
    }

    final overlayStyle = SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,

      statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,

      statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
    );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlayStyle,

      child: AmbientBackground(
        child: Scaffold(
          backgroundColor: Colors.transparent,

          extendBody: true,

          body: PageView(
            controller: _mainPageController,

            // IMPORTANT:
            // Main navigation no longer takes horizontal drag gestures.
            // Home and Discover have their own horizontal category PageViews.
            // Keeping both enabled creates a gesture conflict.
            physics: const NeverScrollableScrollPhysics(),

            allowImplicitScrolling: true,

            onPageChanged: _onMainPageChanged,

            children: _screens,
          ),

          bottomNavigationBar: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),

            child: Container(
              height: 68,

              decoration: BoxDecoration(
                color: (isDark ? Colors.black : Colors.white).withOpacity(0.85),

                borderRadius: BorderRadius.circular(30),

                border: Border.all(
                  color: (isDark ? Colors.white : Colors.black).withOpacity(
                    0.12,
                  ),
                  width: 1,
                ),
              ),

              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,

                children: <Widget>[
                  _NavBarItem(
                    icon: Icons.movie_creation_outlined,
                    activeIcon: Icons.movie_creation_rounded,
                    label: 'Home',
                    selected: _index == 0,
                    onTap: () {
                      _onTabTapped(0);
                    },
                  ),

                  _NavBarItem(
                    icon: Icons.explore_outlined,
                    activeIcon: Icons.explore_rounded,
                    label: 'Discover',
                    selected: _index == 1,
                    onTap: () {
                      _onTabTapped(1);
                    },
                  ),

                  _NavBarItem(
                    icon: Icons.bar_chart_outlined,
                    activeIcon: Icons.bar_chart_rounded,
                    label: 'Stats',
                    selected: _index == 2,
                    onTap: () {
                      _onTabTapped(2);
                    },
                  ),

                  _NavBarItem(
                    icon: Icons.settings_outlined,
                    activeIcon: Icons.settings_rounded,
                    label: 'Settings',
                    selected: _index == 3,
                    onTap: () {
                      _onTabTapped(3);
                    },
                  ),
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
// BACKUP ONBOARDING SHEET
// ============================================================

class _BackupOnboardingSheet extends StatefulWidget {
  final VoidCallback onGoogleConnected;

  const _BackupOnboardingSheet({required this.onGoogleConnected});

  @override
  State<_BackupOnboardingSheet> createState() => _BackupOnboardingSheetState();
}

class _BackupOnboardingSheetState extends State<_BackupOnboardingSheet> {
  bool _connecting = false;

  String? _error;

  // ==========================================================
  // CONNECT GOOGLE
  // ==========================================================

  Future<void> _continueWithGoogle() async {
    if (_connecting) {
      return;
    }

    setState(() {
      _connecting = true;

      _error = null;
    });

    final cloud = context.read<CloudBackupProvider>();

    try {
      final connected = await cloud.connectGoogle();

      if (!mounted) {
        return;
      }

      if (!connected) {
        setState(() {
          _error = cloud.lastError ?? 'Could not connect your Google account.';
        });

        return;
      }

      widget.onGoogleConnected();
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _error = 'Could not connect your Google account.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _connecting = false;
        });
      }
    }
  }

  // ==========================================================
  // SKIP
  // ==========================================================

  Future<void> _skip() async {
    if (_connecting) {
      return;
    }

    await context.read<CloudBackupProvider>().skipBackupOnboarding();

    if (!mounted) {
      return;
    }

    Navigator.of(context).pop();
  }

  // ==========================================================
  // BUILD
  // ==========================================================

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final colors = theme.colorScheme;

    final isDark = theme.brightness == Brightness.dark;

    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),

      child: Container(
        margin: EdgeInsets.only(bottom: 12 + bottomPadding),

        padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),

        decoration: BoxDecoration(
          color: (isDark ? const Color(0xFF111827) : Colors.white).withOpacity(
            0.97,
          ),

          borderRadius: BorderRadius.circular(28),

          border: Border.all(
            color: colors.outline.withOpacity(isDark ? 0.20 : 0.10),
          ),

          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Colors.black.withOpacity(isDark ? 0.42 : 0.14),
              blurRadius: 32,
              offset: const Offset(0, 12),
            ),
          ],
        ),

        child: SafeArea(
          top: false,

          child: Column(
            mainAxisSize: MainAxisSize.min,

            children: <Widget>[
              Container(
                width: 38,
                height: 4,

                margin: const EdgeInsets.only(bottom: 22),

                decoration: BoxDecoration(
                  color: colors.onSurfaceVariant.withOpacity(0.28),
                  borderRadius: BorderRadius.circular(100),
                ),
              ),

              Container(
                width: 66,
                height: 66,

                decoration: BoxDecoration(
                  color: colors.primary.withOpacity(0.12),

                  shape: BoxShape.circle,

                  border: Border.all(color: colors.primary.withOpacity(0.20)),
                ),

                child: Icon(
                  Icons.cloud_done_outlined,

                  size: 31,

                  color: colors.primary,
                ),
              ),

              const SizedBox(height: 17),

              Text(
                'Keep your library safe',

                textAlign: TextAlign.center,

                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                ),
              ),

              const SizedBox(height: 8),

              Text(
                'Connect your Google account to automatically '
                'back up your Watcher library, progress, notes '
                'and reminder data.',

                textAlign: TextAlign.center,

                style: TextStyle(
                  fontSize: 13,
                  height: 1.45,
                  color: colors.onSurfaceVariant,
                ),
              ),

              const SizedBox(height: 20),

              SizedBox(
                width: double.infinity,

                height: 50,

                child: FilledButton(
                  onPressed: _connecting ? null : _continueWithGoogle,

                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),

                  child: _connecting
                      ? const SizedBox(
                          width: 21,
                          height: 21,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            color: Colors.white,
                          ),
                        )
                      : const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: <Widget>[
                            Icon(Icons.account_circle_outlined, size: 20),
                            SizedBox(width: 9),
                            Text(
                              'Continue with Google',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                ),
              ),

              if (_error != null) ...<Widget>[
                const SizedBox(height: 10),

                Container(
                  width: double.infinity,

                  padding: const EdgeInsets.all(10),

                  decoration: BoxDecoration(
                    color: colors.error.withOpacity(0.08),

                    borderRadius: BorderRadius.circular(12),
                  ),

                  child: Text(
                    _error!,

                    textAlign: TextAlign.center,

                    style: TextStyle(
                      color: colors.error,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 8),

              SizedBox(
                width: double.infinity,

                height: 46,

                child: TextButton(
                  onPressed: _connecting ? null : _skip,

                  child: const Text('Skip for now • Use manual backup'),
                ),
              ),

              Text(
                'You can connect Google later from '
                'Settings → Data & Backup.',

                textAlign: TextAlign.center,

                style: TextStyle(
                  fontSize: 10.8,
                  height: 1.35,
                  color: colors.onSurfaceVariant.withOpacity(0.78),
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
// NAV BAR ITEM
// ============================================================

class _NavBarItem extends StatelessWidget {
  final IconData icon;

  final IconData activeIcon;

  final String label;

  final bool selected;

  final VoidCallback onTap;

  const _NavBarItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final activeColor = theme.colorScheme.primary;

    return InkWell(
      onTap: onTap,

      borderRadius: BorderRadius.circular(20),

      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),

        curve: Curves.easeOutCubic,

        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),

        decoration: BoxDecoration(
          color: selected ? activeColor.withOpacity(0.2) : Colors.transparent,

          borderRadius: BorderRadius.circular(20),

          border: selected
              ? Border.all(color: activeColor.withOpacity(0.4), width: 1)
              : null,
        ),

        child: Row(
          mainAxisSize: MainAxisSize.min,

          children: <Widget>[
            Icon(
              selected ? activeIcon : icon,

              color: selected
                  ? activeColor
                  : theme.colorScheme.onSurfaceVariant,

              size: 22,
            ),

            if (selected) ...<Widget>[
              const SizedBox(width: 6),

              Text(
                label,

                style: TextStyle(
                  color: activeColor,

                  fontWeight: FontWeight.w700,

                  fontSize: 12.5,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
