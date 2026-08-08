class SeasonInfo {
  final int season;

  /// Highest episode number currently listed by OMDb for this season.
  ///
  /// Important: for an airing season this is NOT treated as a guaranteed
  /// final season total. It is only a fallback/known-count signal.
  final int episodeCount;

  const SeasonInfo({required this.season, required this.episodeCount});

  factory SeasonInfo.fromJson(Map<String, dynamic> json) {
    final episodes = json['Episodes'];

    int highestEpisodeNumber = 0;
    int listLength = 0;

    if (episodes is List) {
      listLength = episodes.length;

      for (final rawEpisode in episodes) {
        if (rawEpisode is! Map) continue;

        final parsed = int.tryParse(rawEpisode['Episode']?.toString() ?? '');
        if (parsed != null && parsed > highestEpisodeNumber) {
          highestEpisodeNumber = parsed;
        }
      }
    }

    return SeasonInfo(
      season: int.tryParse(json['Season']?.toString() ?? '') ?? 1,
      episodeCount: highestEpisodeNumber > 0
          ? highestEpisodeNumber
          : listLength,
    );
  }
}
