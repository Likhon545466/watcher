class TmdbEpisodeDetail {
  final int id;
  final int episodeNumber;
  final int seasonNumber;
  final String name;
  final String overview;
  final String? stillPath;
  final String? airDate;
  final double voteAverage;
  final int? runtime;

  const TmdbEpisodeDetail({
    required this.id,
    required this.episodeNumber,
    required this.seasonNumber,
    required this.name,
    required this.overview,
    this.stillPath,
    this.airDate,
    required this.voteAverage,
    this.runtime,
  });

  factory TmdbEpisodeDetail.fromJson(Map<String, dynamic> json) {
    return TmdbEpisodeDetail(
      id: (json['id'] as num?)?.toInt() ?? 0,
      episodeNumber: (json['episode_number'] as num?)?.toInt() ?? 0,
      seasonNumber: (json['season_number'] as num?)?.toInt() ?? 0,
      name: (json['name'] ?? '').toString(),
      overview: (json['overview'] ?? '').toString(),
      stillPath: json['still_path']?.toString(),
      airDate: json['air_date']?.toString(),
      voteAverage: (json['vote_average'] as num?)?.toDouble() ?? 0.0,
      runtime: (json['runtime'] as num?)?.toInt(),
    );
  }

  String? get stillUrl {
    final path = stillPath?.trim();
    if (path == null || path.isEmpty) {
      return null;
    }
    return 'https://image.tmdb.org/t/p/w500$path';
  }

  DateTime? get parsedAirDate {
    final date = airDate?.trim();
    if (date == null || date.isEmpty) return null;
    return DateTime.tryParse(date);
  }
}
