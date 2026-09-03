class TmdbVideo {
  final String id;
  final String key;
  final String name;
  final String site;
  final String type;
  final bool official;
  final DateTime? publishedAt;

  const TmdbVideo({
    required this.id,
    required this.key,
    required this.name,
    required this.site,
    required this.type,
    required this.official,
    this.publishedAt,
  });

  factory TmdbVideo.fromJson(Map<String, dynamic> json) {
    return TmdbVideo(
      id: (json['id'] ?? '').toString(),
      key: (json['key'] ?? '').toString(),
      name: (json['name'] ?? 'Trailer').toString(),
      site: (json['site'] ?? 'YouTube').toString(),
      type: (json['type'] ?? 'Trailer').toString(),
      official: json['official'] == true,
      publishedAt: DateTime.tryParse(json['published_at']?.toString() ?? ''),
    );
  }

  bool get isYouTube => site.toLowerCase() == 'youtube' && key.isNotEmpty;

  String get youtubeUrl => 'https://www.youtube.com/watch?v=$key';

  String get youtubeThumbnailUrl => 'https://img.youtube.com/vi/$key/hqdefault.jpg';

  String get thumbnailUrl => youtubeThumbnailUrl;
}
