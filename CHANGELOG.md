# Changelog

All notable changes to the Watcher application are documented in this file.

## [4.3.0] - 2026-09-11

### Added
- **Home Screen Auto Update Popup**: Automatic background GitHub update check on app startup with an interactive glassmorphic update popup directly on the Home Screen.
- **Direct Download & Release Details**: Version comparison (`Installed` ➔ `New Version`), APK file size badge, formatted release date, and instant APK download action.

### Changed / Improved
- **Non-Intrusive Background Checking**: Smooth, delayed startup check that fails silently if offline or up to date without impacting app launch speed or UI animations.

---

## [4.2.9] - 2026-09-11

### Added
- **In-App GitHub Update Checker**: Interactive modal with GitHub Releases integration, dual-tier fallback to bypass API rate limits, version comparison, and direct APK download.
- **Dedicated GitHub & Developer Info Screen**: Developer profile (@Likhon545466), live repository stats (stars, forks, open issues), quick links (releases, issues, changelog), and complete tech stack details.
- **Settings Integration**: Quick-action navigation pills in Watcher Info card for **Release Notes**, **Check Update**, and **GitHub Info**.

### Changed / Improved
- **Multi-Tier Update Architecture**: Robust update checking mechanism connecting to GitHub REST API with automatic fallback to raw GitHub version and changelog metadata.
- **Polished Glassmorphic UI**: High-fidelity frosted glass cards, pulsing radar animations during update checks, and responsive layout.

### Fixed
- **GitHub API Rate-Limit Handling**: Resolved 403 rate limit errors on unauthenticated network connections using smart raw repository fallback.

---

## [4.2.7] - 2026-09-03

### Added
- **Trailers & Official Videos**: Interactive YouTube videos and trailers carousel in Show Details with direct playback support.
- **Season & Episode Guide**: Comprehensive bottom sheet with episode still images, air dates, overviews, guest stars, and direct watch marking.
- **Release Calendar**: Track upcoming movie premieres and TV episode air dates for titles in your watchlist.
- **Advanced Statistics & Analytics**: Watch time analysis (total days/hours/minutes), genre breakdown charts, release year distribution, and movie vs series completion rates.
- **Custom Tags**: Categorize and filter library shows and movies with customized tags.
- **Movie & Episode Reminders**: Configurable notifications for upcoming movie releases and TV episode broadcasts.
- **Home Widget Support**: Widget integration for a quick glance at upcoming episodes.

### Changed / Improved
- Overhauled Show Details UI with expandable synopsis, cast & crew chips, and integrated media sections.
- Upgraded Notification Service with scheduled notification permissions and exact alarms on Android.
- Enhanced TMDB Service with episode detail and video fetching with smart caching.
- Optimized library provider with fast tag filtering, watch-time calculation, and calendar querying.
- Updated build automation and release artifact packaging in `build.bat`.

### Fixed
- Fixed notification scheduling issues on newer Android versions.
- Fixed episode progress state synchronization across detail views and stats.
- Fixed memory overhead during image caching of episode stills and backdrops.

---

## [4.1.6] - 2026-08-13

### Added
- Similar & Recommended titles in Details screen using TMDB recommendations.
- Quick library actions for recommended movies and series with status selection.
- Library status badges on recommended titles already saved in Watcher.
- Person Details for cast, directors, and writers with filmography and biographies.

### Changed / Improved
- Recommended titles open saved Details screen when in library.
- Added caching for recommendation and person metadata.
- Improved recommendation cards with rating, year, type, and library status.

---

## [4.0.0] - 2026-08-12

### Added
- TMDB-powered search inside Discover Details.
- Support for searching upcoming and unreleased movies and series directly by name.
- Multi-device Google Drive Auto Sync with deletion tracking tombstones.
- Broader Discover industry and genre coverage.
