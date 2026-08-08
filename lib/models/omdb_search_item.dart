class OmdbSearchItem {
  final String imdbId;
  final String title;
  final String year;
  final String type;
  final String posterUrl;

  const OmdbSearchItem({
    required this.imdbId,
    required this.title,
    required this.year,
    required this.type,
    required this.posterUrl,
  });

  factory OmdbSearchItem.fromJson(Map<String, dynamic> json) {
    String clean(dynamic value) {
      final text = value?.toString().trim() ?? '';
      return text == 'N/A' ? '' : text;
    }

    return OmdbSearchItem(
      imdbId: clean(json['imdbID']),
      title: clean(json['Title']),
      year: clean(json['Year']),
      type: clean(json['Type']).toLowerCase() == 'series' ? 'Series' : 'Movie',
      posterUrl: clean(json['Poster']),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'imdbID': imdbId,
        'Title': title,
        'Year': year,
        'Type': type.toLowerCase(),
        'Poster': posterUrl,
      };
}
