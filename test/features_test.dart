import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:watcher/models/show.dart';
import 'package:watcher/models/tmdb_episode_detail.dart';
import 'package:watcher/models/tmdb_video.dart';
import 'package:watcher/providers/show_provider.dart';

Show createTestShow({
  required String id,
  required String title,
  required String type,
  String status = 'Watching',
  List<String> customTags = const [],
  bool movieReminderEnabled = false,
  DateTime? movieReleaseDate,
  int currentSeason = 1,
  int currentEpisode = 0,
  int totalSeasons = 1,
  Map<int, int> seasonEpisodeCounts = const {},
}) {
  return Show(
    id: id,
    title: title,
    type: type,
    posterUrl: '',
    yearText: '2026',
    genre: 'Drama',
    plot: 'A test plot overview',
    director: 'Director Name',
    writer: 'Writer Name',
    actors: 'Actor 1, Actor 2',
    language: 'English',
    awards: 'N/A',
    runtimeMinutes: 120,
    rating: 8.5,
    status: status,
    totalSeasons: totalSeasons,
    currentSeason: currentSeason,
    currentEpisode: currentEpisode,
    seasonProgress: currentEpisode > 0 ? {currentSeason: currentEpisode} : {},
    seasonEpisodeCounts: seasonEpisodeCounts,
    customTags: customTags,
    movieReminderEnabled: movieReminderEnabled,
    movieReleaseDate: movieReleaseDate,
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Feature 2: TmdbVideo Model Tests', () {
    test('Correctly parses YouTube video payload and builds URLs', () {
      final json = {
        'id': 'v1',
        'key': 'dQw4w9WgXcQ',
        'name': 'Official Trailer',
        'site': 'YouTube',
        'type': 'Trailer',
        'official': true,
        'published_at': '2026-05-15T12:00:00.000Z',
      };

      final video = TmdbVideo.fromJson(json);
      expect(video.id, 'v1');
      expect(video.key, 'dQw4w9WgXcQ');
      expect(video.name, 'Official Trailer');
      expect(video.isYouTube, true);
      expect(video.type, 'Trailer');
      expect(video.official, true);
      expect(video.youtubeUrl, 'https://www.youtube.com/watch?v=dQw4w9WgXcQ');
      expect(video.thumbnailUrl, 'https://img.youtube.com/vi/dQw4w9WgXcQ/hqdefault.jpg');
      expect(video.youtubeThumbnailUrl, 'https://img.youtube.com/vi/dQw4w9WgXcQ/hqdefault.jpg');
    });
  });

  group('Feature 4: TmdbEpisodeDetail Model Tests', () {
    test('Correctly parses season episode detail with still image', () {
      final json = {
        'id': 101,
        'episode_number': 3,
        'name': 'The Great Battle',
        'overview': 'An epic showdown unfolds.',
        'air_date': '2026-04-12',
        'still_path': '/still123.jpg',
        'vote_average': 8.9,
      };

      final ep = TmdbEpisodeDetail.fromJson(json);
      expect(ep.episodeNumber, 3);
      expect(ep.name, 'The Great Battle');
      expect(ep.overview, 'An epic showdown unfolds.');
      expect(ep.airDate, '2026-04-12');
      expect(ep.stillUrl, 'https://image.tmdb.org/t/p/w500/still123.jpg');
      expect(ep.voteAverage, 8.9);
    });
  });

  group('Feature 7 & 11: Show Model Custom Tags & Movie Reminder Serialization', () {
    test('Serializes and deserializes customTags, movieReminderEnabled, and movieReleaseDate', () {
      final releaseDate = DateTime(2026, 11, 20);
      final show = createTestShow(
        id: 'tmdb_movie_9999',
        title: 'Future Odyssey',
        type: 'Movie',
        status: 'Plan to Watch',
        customTags: ['Sci-Fi', 'Must Watch', 'IMAX'],
        movieReminderEnabled: true,
        movieReleaseDate: releaseDate,
      );

      final json = show.toJson();
      expect(json['customTags'], ['Sci-Fi', 'Must Watch', 'IMAX']);
      expect(json['movieReminderEnabled'], true);
      expect(json['movieReleaseDate'], releaseDate.toIso8601String());

      final restored = Show.fromJson(json);
      expect(restored.id, 'tmdb_movie_9999');
      expect(restored.title, 'Future Odyssey');
      expect(restored.customTags, ['Sci-Fi', 'Must Watch', 'IMAX']);
      expect(restored.movieReminderEnabled, true);
      expect(restored.movieReleaseDate?.year, 2026);
      expect(restored.movieReleaseDate?.month, 11);
      expect(restored.movieReleaseDate?.day, 20);
    });

    test('Backward compatibility: defaults for older JSON payloads', () {
      final legacyJson = {
        'id': 'tt1234567',
        'title': 'Legacy Show',
        'type': 'Series',
        'posterUrl': '',
        'year': '2020',
        'rating': 8.0,
        'status': 'Watching',
      };

      final restored = Show.fromJson(legacyJson);
      expect(restored.customTags, isEmpty);
      expect(restored.movieReminderEnabled, false);
      expect(restored.movieReleaseDate, isNull);
    });
  });

  group('ShowProvider Features State Management', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('Tag manipulation and filtering in ShowProvider', () async {
      final provider = ShowProvider();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final testShow = createTestShow(
        id: 'show_1',
        title: 'Cyberpunk Edgerunners',
        type: 'Series',
        status: 'Watching',
        customTags: ['Anime'],
      );

      await provider.addShow(testShow);
      expect(provider.allCustomTags, contains('Anime'));

      await provider.addTagToShow('show_1', 'Masterpiece');
      final updated = provider.byId('show_1');
      expect(updated?.customTags, containsAll(['Anime', 'Masterpiece']));
      expect(provider.allCustomTags, containsAll(['Anime', 'Masterpiece']));

      provider.setSelectedTag('Masterpiece');
      expect(provider.shows.length, 1);

      provider.setSelectedTag('NonExistentTag');
      expect(provider.shows.length, 0);

      provider.setSelectedTag(null);
      expect(provider.shows.length, 1);

      await provider.removeTagFromShow('show_1', 'Masterpiece');
      expect(provider.byId('show_1')?.customTags, ['Anime']);
    });

    test('Episode Guide setEpisodeWatched marks progress correctly', () async {
      final provider = ShowProvider();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final testSeries = createTestShow(
        id: 'series_1',
        title: 'Arcane',
        type: 'Series',
        status: 'Plan to Watch',
        currentSeason: 1,
        currentEpisode: 0,
        totalSeasons: 2,
        seasonEpisodeCounts: {1: 9, 2: 9},
      );

      await provider.addShow(testSeries);

      await provider.setEpisodeWatched('series_1', 1, 4, true);
      var current = provider.byId('series_1');
      expect(current?.seasonProgress[1], 4);
      expect(current?.currentEpisode, 4);
      expect(current?.status, 'Watching');

      await provider.setEpisodeWatched('series_1', 1, 4, false);
      current = provider.byId('series_1');
      expect(current?.seasonProgress[1], 3);
      expect(current?.currentEpisode, 3);
    });

    test('Release Calendar: Upcoming releases in watchlist are retrieved correctly', () async {
      final provider = ShowProvider();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final futureDate = DateTime.now().add(const Duration(days: 5));
      final movie = createTestShow(
        id: 'upcoming_movie_1',
        title: 'Avatar 3',
        type: 'Movie',
        movieReleaseDate: futureDate,
        movieReminderEnabled: true,
      );

      await provider.addShow(movie);
      final all = provider.allShows;
      expect(all.any((s) => s.id == 'upcoming_movie_1'), true);
      expect(all.firstWhere((s) => s.id == 'upcoming_movie_1').movieReleaseDate, futureDate);
    });
  });
}
