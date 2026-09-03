# Changelog

All notable changes to the Watcher application are documented in this file.

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
