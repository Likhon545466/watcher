class ChangelogItem {
  final String version;
  final String date;
  final List<String> newFeatures;
  final List<String> improvements;
  final List<String> bugFixes;

  const ChangelogItem({
    required this.version,
    required this.date,
    this.newFeatures = const [],
    this.improvements = const [],
    this.bugFixes = const [],
  });

  ChangelogItem copyWith({
    String? version,
    String? date,
    List<String>? newFeatures,
    List<String>? improvements,
    List<String>? bugFixes,
  }) {
    return ChangelogItem(
      version: version ?? this.version,
      date: date ?? this.date,
      newFeatures: newFeatures ?? this.newFeatures,
      improvements: improvements ?? this.improvements,
      bugFixes: bugFixes ?? this.bugFixes,
    );
  }
}

class ChangelogData {
  static const List<ChangelogItem> _allHistory = [
    // =========================================================
    // CURRENT / LATEST VERSION
    //
    // Only this first entry uses AUTO.
    // changelogsFor() replaces AUTO with the installed app version.
    // Older entries always keep their fixed historical version.
    // =========================================================
    ChangelogItem(
      version: 'AUTO',
      date: '09 Aug 2026',
      newFeatures: [
        'Added a smarter Discover Details save flow with direct status selection before adding a title.',
        'Added quick save options so movies and series can be saved directly as Plan to Watch, Watching, Completed, or On Hold.',
        'Added Poster Cache Auto Clean with selectable storage limits: Off, 100 MB, 250 MB, 500 MB, and 1 GB.',
        'Added automatic poster cache trimming that removes the oldest cached posters only when the selected limit is crossed.',
        'Added a refined movie metadata capsule on Home cards for year, runtime, rating, and genre.',
      ],
      improvements: [
        'Improved Home movie cards with a single transparent glass-style metadata capsule instead of plain subtitle text.',
        'Kept Series Home cards, episode progress, and plus/minus tracking unchanged while improving movie-only presentation.',
        'Improved Google Drive Sync layout with a cleaner compact card, smaller icon, full-width email display, and clearer Last Backup information.',
        'Removed unnecessary Google Drive Sync badges from the backup card to reduce visual clutter.',
        'Improved Poster Cache layout with Size, Poster Count, and Auto Clean Limit shown as matching compact capsules.',
        'Improved Data & Backup spacing, hierarchy, and visual balance for a smoother settings experience.',
        'Improved restore and backup sections to keep actions easier to understand without changing backup behavior.',
      ],
      bugFixes: [
        'Fixed Home movie subtitle feeling too basic by replacing it with a cleaner glass capsule design.',
        'Fixed long Google account emails being visually cut off inside the Data & Backup screen.',
        'Fixed Poster Cache controls feeling disconnected by grouping cache size, poster count, and auto clean limit together.',
        'Fixed minor Data & Backup UI density issues that made some sections feel larger than necessary.',
        'Fixed analyzer warnings related to async context usage, unused local variables, and deprecated opacity usage.',
      ],
    ),
    ChangelogItem(
      version: '3.2.3',
      date: '08 Aug 2026',
      newFeatures: [
        'Added a compact Data & Backup screen with small status pills for Auto Backup, Google connection, JSON-only backup and no-poster-file safety.',
        'Added Restore Missing Only as the recommended restore flow so users can bring back missing cloud/local backup items without deleting anything.',
        'Added a clearer restore options sheet showing cloud items, missing items and already-saved items before the user chooses an action.',
        'Added Smart Official Info in Show Details with useful metadata pills for seasons, episodes, ended/ongoing state, current progress, OMDb, TMDB and poster availability.',
        'Added a metadata refresh icon directly inside the Official Info panel so users understand what is being refreshed.',
        'Added swipeable HD poster gallery support with the saved poster shown first and TMDB alternate posters after it.',
        'Added Mark Season Complete for quickly finishing the current season without completing the whole series.',
      ],
      improvements: [
        'Restored Google startup auto-login behavior so existing Google Backup sessions can become ready automatically when the app opens.',
        'Improved Auto Backup timing so changes are saved after a few seconds while the app is open.',
        'Improved backup wording so Google backup is easier to understand for normal users.',

        'Improved Show Details metadata layout so official series movie information feels useful instead of generic.',
        'Improved episode reminder UI so ended series clearly show that reminders are not needed.',
        'Improved Details poster viewer with swipe, zoom and share for multiple poster sources.',
      ],
      bugFixes: [
        'Fixed Home category swipe behavior by keeping main navigation tap-based while Home handles its own category swipes.',
        'Fixed the preferred Home card layout after category swipe changes.',
        'Fixed Auto Backup feeling delayed by reducing the backup debounce time.',
        'Fixed confusing backup/restore hierarchy by separating Back Up Now, Restore Missing Only and Replace this phones library.',
        'Fixed backup safety messaging so it clearly states that offline poster image cache and big image files are not uploaded to Google Drive.',
        'Fixed ended series reminder behavior so unnecessary episode reminders are disabled when there is no upcoming episode.',
        'Fixed HD poster opening order so the current saved poster remains the first poster in the viewer.',
      ],
    ),

    ChangelogItem(
      version: '3.2.1',
      date: '08 Aug 2026',
      newFeatures: [
        'Added a safer Google Backup onboarding flow that no longer appears repeatedly after Google is already connected.',
        'Added a refreshed Data & Backup Safety Dashboard with clearer backup health, auto backup and restore sections.',
        'Added Add Missing Titles as the recommended restore action for cloud and local backups.',
        'Added a polished metadata refresh card in Show Details with OMDb and TMDB source information.',
        'Added swipeable HD poster gallery support with the saved poster shown first and TMDB alternate posters after it.',
      ],
      improvements: [
        'Improved Home category swipe behavior by keeping main navigation tap-based while Home handles its own category swipes.',
        'Restored the preferred Home card layout with balanced poster size, compact chips, progress display and episode controls.',
        'Improved Auto Backup timing so changes are saved after a few seconds while the app is open.',
        'Improved backup restore wording so safe restore is easier to understand.',
        'Improved backup safety notes by making clear that offline poster image cache is not uploaded to Google Drive.',
        'Improved cloud backup layout with a separate Restore from Google Drive section.',
        'Improved manual metadata refresh feedback and kept existing local watch progress, notes, status and reminders safe.',
        'Improved Details metadata UI without changing the main Details screen structure.',
      ],
      bugFixes: [
        'Fixed Google backup onboarding showing again after the app was reopened from recent apps.',
        'Fixed Auto Backup feeling delayed by reducing the backup debounce time.',
        'Fixed Backup screen actions feeling confusing by separating Back Up Now and Restore Backup.',
        'Fixed restore dialog wording by replacing Safe Restore with Add Missing Titles.',
        'Fixed potential Backup UI overflow by using cleaner vertical sections instead of paired primary restore actions.',
        'Fixed metadata refresh presentation so Last Sync and Refresh are easier to understand.',
        'Fixed HD poster opening order so the current saved poster remains the first poster in the viewer.',
      ],
    ),

    ChangelogItem(
      version: '3.1.0',
      date: '08 Aug 2026',
      newFeatures: [
        'Restored original HD poster viewing using TMDB high-resolution artwork when available.',
        'HD poster viewer now falls back to an enhanced version of the saved poster when TMDB artwork is unavailable.',
        'Moved Data & Backup tools to a dedicated settings page for a cleaner and shorter Settings screen.',
        'Improved Data & Backup layout with separate backup history, offline storage and export sections.',
        'Added Next Episode information for series, including upcoming season, episode and air date.',
        'Added manual metadata refresh so movie and series information can be updated anytime.',
        'Added Mark Season Complete for faster episode tracking.',
        'Added automatic series completion when the final verified episode has been watched.',
        'Added Already in Library detection across Search, Discover and title details.',
        'Added backup history showing the last backup and restore time.',
        'Added persistent offline poster caching for faster loading and offline access.',
        'Added Upcoming Episode Reminders with local notifications on episode release day.',
        'Episode reminders now survive app restarts and device reboots.',
        'Added a dedicated Data & Backup screen for backup, restore, CSV export and offline poster management.',
      ],
      improvements: [
        'Improved episode tracking with safer season and episode count handling.',
        'Improved series metadata using TMDB season information when OMDb data is incomplete or outdated.',
        'Upcoming episode data now updates season, episode and air date together to prevent mismatched information.',
        'Reminder schedules automatically update when new upcoming episode information becomes available.',
        'Reminder preferences remain saved even when an upcoming episode date is not available yet.',
        'Completed and dropped titles automatically stop unnecessary episode reminders.',
        'Improved library matching using IMDb ID, TMDB ID, title, type and year for more reliable duplicate detection.',
        'Opening a title already in the library now takes you directly to the saved title instead of creating a duplicate.',
        'Improved Recent Activity sorting so actively watched titles appear based on actual viewing progress.',
        'Episode progress updates now correctly move Plan to Watch titles into Watching.',
        'Background metadata sync now preserves local watch activity and tracking information.',
        'Improved backup restore with safer Merge and Replace All behavior.',
        'Offline poster cache now includes cache size, poster count, refresh and clear controls.',
        'Improved notification scheduling using the device local timezone.',
        'Episode reminders are scheduled for 10:00 AM local time on the episode air date.',
        'Added a dedicated high-priority Episode Reminders notification channel with sound and vibration.',
        'Improved Android notification reliability with a proper notification icon and release-build resource protection.',
        'Settings has been reorganized to reduce scrolling and make Appearance and Data & Backup easier to access.',
        'Data & Backup now has a cleaner dedicated layout with backup history, offline storage and export tools.',
      ],
      bugFixes: [
        'Fixed HD poster viewer always opening the same saved poster instead of available TMDB original artwork.',
        'Fixed Data & Backup screen appearing in dark mode while Watcher was using Light or System theme.',
        'Data & Backup now correctly follows the active Watcher theme and ambient background.',
        'Fixed incorrect episode totals caused by incomplete OMDb season responses.',
        'Fixed cases where episode progress could be incorrectly clamped to an outdated episode count.',
        'Fixed A Shop for Killers-style cases where an ongoing season could incorrectly show an incomplete episode total.',
        'Fixed stale upcoming episode dates being paired with the wrong season or episode.',
        'Fixed series completion triggering before the final season or episode was safely verified.',
        'Fixed completed series returning to Watching incorrectly when episode progress was adjusted.',
        'Fixed metadata refresh accidentally overwriting locally tracked watch progress and reminder information.',
        'Fixed notification permission being reported as denied even when Android notification permission was already enabled.',
        'Fixed the Episode Reminders notification channel not being created correctly on some builds.',
        'Fixed reminder scheduling after notification permissions were enabled manually from Android Settings.',
        'Fixed notification initialization potentially delaying app startup on the splash screen.',
        'Fixed scheduled episode reminders disappearing after device reboot.',
      ],
    ),
    ChangelogItem(
      version: '2.2.3',
      date: '08 Aug 2026',

      newFeatures: [
        'Added a redesigned Settings experience with a cleaner and more professional layout.',
        'Added a new timeline-style Release Notes view for easier version history browsing.',
        'Added a dedicated app information card with version, build number, and library count.',
        'Added clearer Data & Backup actions for backup, CSV export, and restore.',
      ],

      improvements: [
        'Improved visual hierarchy across the Settings screen.',
        'Improved spacing, typography, icons, and glass card presentation.',
        'Improved Appearance section with a cleaner settings-style navigation row.',
        'Improved backup and restore section with clearer descriptions and action grouping.',
        'Improved Release Notes readability with New, Improved, and Fixed sections.',
        'Improved the latest-version badge and changelog presentation.',
        'Improved restore confirmation with clearer counts for new and existing titles.',
        'Improved dark and light mode consistency across Settings.',
      ],

      bugFixes: [
        'Improved long changelog content handling inside the Release Notes sheet.',
        'Improved text overflow handling for version, library, and backup information.',
        'Improved loading feedback while backup, export, or restore operations are running.',
      ],
    ),

    ChangelogItem(
      version: '2.2.2',
      date: '08 Aug 2026',

      newFeatures: [
        'Added automatic episode metadata syncing directly from the Home screen.',
        'Added Recent Activity sorting for movies and series.',
        'Added persistent last-watched tracking so recently watched titles stay at the top even after restarting the app.',
      ],

      improvements: [
        'Series episode data now refreshes silently in the background without requiring the Show Details screen to be opened.',
        'Watching series are prioritized during background episode metadata syncing.',
        'Background series syncing is limited to two simultaneous requests to keep Home scrolling smooth.',
        'Successful episode metadata syncs are cached to reduce unnecessary TMDB requests.',
        'Pressing EP + now automatically moves a newly started series from Plan to Watch to Watching.',
        'Pressing EP + on a series updates its recent activity time and moves it to the top of the list.',
        'Changing a movie or series status to Watching or Completed now moves it to the top of the relevant recent activity list.',
        'Background TMDB metadata updates no longer affect recent activity ordering.',
        'Renamed the default Home sort option from Recently Added to Recent Activity.',
        'Improved season progress handling for currently airing series.',
      ],

      bugFixes: [
        'Fixed running series showing incomplete episode totals such as "S2 • EP0 / 1".',
        'Fixed incomplete API episode counts being treated as confirmed final season limits.',
        'Fixed stale episode metadata potentially moving a series to the next season too early.',
        'Fixed API metadata updates potentially interfering with user watch progress.',
        'Fixed episode metadata requiring the Details screen to be opened before Home could receive updated information.',
        'Fixed watched progress being vulnerable to smaller or outdated API episode counts.',
      ],
    ),

    ChangelogItem(
      version: '2.2.1',
      date: '08 Aug 2026',

      newFeatures: [
        'Added smarter season metadata tracking for running TV series.',
        'Added support for tracking last aired episode, next scheduled episode, and verified season episode totals.',
        'Added safe season metadata syncing between TMDB, OMDb, and locally saved watch progress.',
      ],

      improvements: [
        'Improved episode tracking accuracy for currently airing series.',
        'Improved season episode count handling by distinguishing confirmed final totals from temporary or incomplete API data.',
        'Improved Home progress display so uncertain running-season totals are no longer shown as confirmed episode limits.',
        'Improved TMDB season metadata handling for current and upcoming episodes.',
        'Improved existing saved library compatibility with the new season metadata system.',
        'Preserved the existing Home and Show Details UI while improving the underlying episode tracking logic.',
      ],

      bugFixes: [
        'Fixed running series showing incorrect episode totals such as "S2 • EP0 / 1".',
        'Fixed incomplete OMDb season data being treated as the final episode count.',
        'Fixed stale API episode counts from reducing or overwriting existing user progress.',
        'Fixed watched progress potentially being clamped down when an API returned a smaller episode count.',
        'Fixed the + button incorrectly advancing to the next season when a running season had an incomplete episode limit.',
        'Fixed non-final season episode counts being displayed as guaranteed totals on the Home screen.',
        'Fixed outdated next-episode metadata remaining attached to seasons after their episode count becomes final.',
      ],
    ),
    ChangelogItem(
      version: 'v2.2.0',
      date: '08 Aug 2026',
      newFeatures: [
        'Redesigned the Discover screen with cleaner main category controls.',
        'Added dedicated Movies and Series sub-categories across Discover.',
        'Added separate Trending, New Releases, and Upcoming feeds for Movies and Series.',
        'Added responsive Discover category capsules that automatically redistribute width for smaller screens, higher DPI, and larger text scaling.',
        'Added lazy Series season information directly to Discover cards.',
        'Added cached Series season metadata with limited background requests to preserve smooth scrolling.',
        'Added automatic pagination and infinite scrolling for more Discover content.',
        'Added background Discover prefetching shortly after app startup.',
        'Added shared in-memory TMDB caching across Discover sessions.',
        'Added broader content coverage for English, Hindi, Korean, Tamil, Telugu, Malayalam, and Kannada titles.',
        'Added improved Movie and Series badges with dedicated icons and accent colors.',
        'Added an already-in-library check state to Discover add buttons.',
        'Added automatic app version and build number synchronization in Settings.',
        'Latest Release Notes version now automatically follows the installed app version.',
      ],
      improvements: [
        'Significantly improved Discover screen loading and scrolling performance.',
        'Improved app startup performance by delaying Discover prefetch until after the first frame.',
        'Prefetches all six main Discover combinations for faster first-time access.',
        'Limited startup prefetch concurrency to reduce frame drops and unnecessary load.',
        'Improved TMDB response handling with shared request caching and duplicate request protection.',
        'Moved larger TMDB JSON decoding away from the main UI isolate when needed.',
        'Improved Discover state preservation when switching between app tabs.',
        'Preserved independent scroll positions for Discover categories and media types.',
        'Improved page switching by removing unnecessary repeated navigation rebuilds.',
        'Improved New Releases and Upcoming coverage by supporting both Movies and TV Series.',
        'Expanded South Indian content support with Malayalam and Kannada alongside Tamil and Telugu.',
        'Improved Discover refresh behavior while keeping previously loaded content visible.',
        'Improved pagination by preloading additional content before reaching the end of the list.',
        'Improved fallback TMDB identifiers by separating Movie and Series IDs.',
        'Improved empty and error states with retry and pull-to-refresh support.',
        'Improved main category layout so longer labels such as New Releases receive extra space instead of being truncated.',
        'Improved Series cards with season metadata loaded independently so the full Discover screen does not rebuild.',
        'Improved app information display with version, build number, and live library item count.',
        'Library item count now updates automatically when movies or series are added, removed, imported, or restored.',
        'Added correct singular and plural library item labels.',
      ],
      bugFixes: [
        'Fixed Discover feeling slow or low-refresh-rate during initial data loading.',
        'Fixed repeated API requests when the same Discover data was already being fetched.',
        'Fixed unnecessary MainNavigation rebuilds during horizontal swiping.',
        'Fixed Discover screens being recreated unnecessarily during navigation updates.',
        'Fixed vertical Discover scrolling accidentally triggering previous or next main screen navigation.',
        'Fixed New Releases being limited mainly to movie results.',
        'Fixed Upcoming not properly supporting TV Series.',
        'Fixed failed or empty network responses replacing previously valid cached content.',
        'Fixed TMDB movie and TV items sharing the same numeric ID from causing fallback ID conflicts.',
        'Fixed repeated pagination requests while additional content was already loading.',
        'Fixed empty Discover states not being refreshable.',
        'Fixed long-running TMDB requests by adding request timeouts.',
        'Fixed New Releases text being clipped or ellipsized on narrow or high-DPI layouts.',
        'Fixed old Release Notes entries displaying AUTO by keeping AUTO exclusively on the current release.',
        'Fixed version mismatch between Android App Info and Watcher Settings.',
        'Fixed outdated changelog version being displayed as the current app version.',
        'Separated current app version information from historical release note versions.',
      ],
    ),

    // =========================================================
    // PREVIOUS RELEASES
    // =========================================================
    ChangelogItem(
      version: 'v2.1.2',
      date: '07 Aug 2026',
      newFeatures: [
        'Added Approx. Watch Time analytics card in Statistics screen.',
        'Dynamic Milestone & Achievement badge system based on completed shows.',
      ],
      improvements: [
        'Optimized Discover horizontal pill scrolling to center selected and upcoming categories seamlessly.',
        'Enhanced watch status breakdown progress bars with premium gradient effects.',
      ],
      bugFixes: [
        'Resolved category pill clipping issues on the right edge of the screen.',
      ],
    ),

    ChangelogItem(
      version: 'v2.1.1',
      date: '07 Aug 2026',
      newFeatures: [
        'Multi-page and multi-language TMDB integration for massive movie/series data.',
        'Expanded Discover categories to include Bollywood, Hollywood, K-Drama, and South Indian content.',
        'Pull-to-refresh mechanism and extended 90-day date range for upcoming releases.',
      ],
      improvements: [
        'Optimized Discover filtering to prevent out-of-range or old releases.',
        'Synchronized app package version with system and settings screen.',
      ],
      bugFixes: ['Resolved limited data population issues in Discover tabs.'],
    ),

    ChangelogItem(
      version: 'v2.1.0',
      date: '07 Aug 2026',
      newFeatures: [
        'Glass Opacity Slider extended up to 100% (Solid Mode).',
        'Personal Notes & Mini Review system added for shows.',
        'Continuous Horizontal Swipe across Home, Discover & Stats.',
      ],
      improvements: [
        'Clean app version display in Settings without build tags.',
      ],
      bugFixes: [
        'Resolved gesture lock on inner PageView overscroll.',
        'Fixed bottom navigation bar overlapping with bottom list items in Discover.',
      ],
    ),

    ChangelogItem(
      version: 'v2.0.0',
      date: '06 Aug 2026',
      newFeatures: [
        'Redesigned UI with Apple-style Glassmorphism aesthetics.',
        'Integrated TMDB media details for HD Backdrop banners.',
      ],
      improvements: ['Enhanced Statistics tab with watch time analytics.'],
      bugFixes: ['Fixed OMDb API search query formatting.'],
    ),
  ];

  static List<ChangelogItem> changelogsFor(String currentAppVersion) {
    return _allHistory
        .asMap()
        .entries
        .map((entry) {
          final index = entry.key;
          final item = entry.value;

          if (index == 0 && item.version == 'AUTO') {
            return item.copyWith(version: currentAppVersion);
          }

          return item;
        })
        .take(15)
        .toList();
  }
}
