import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/show.dart';
import '../providers/show_provider.dart';
import '../utils/status_style.dart';
import '../widgets/ambient_background.dart';
import '../widgets/glass_container.dart';

class AddEditShowScreen extends StatefulWidget {
  final Show? initialShow;

  const AddEditShowScreen({super.key, this.initialShow});

  @override
  State<AddEditShowScreen> createState() => _AddEditShowScreenState();
}

class _AddEditShowScreenState extends State<AddEditShowScreen> {
  final _formKey = GlobalKey<FormState>();

  late String _title;
  late String _type;
  late String _status;
  late String _posterUrl;
  late String _genre;
  late String _plot;
  late double _rating;
  late int _season;
  late int _episode;

  @override
  void initState() {
    super.initState();
    final show = widget.initialShow;
    _title = show?.title ?? '';
    _type = show?.type ?? 'Series';
    _status = show?.status ?? 'Plan to Watch';
    _posterUrl = show?.posterUrl ?? '';
    _genre = show?.genre ?? '';
    _plot = show?.plot ?? '';
    _rating = show?.rating ?? 0.0;
    _season = show?.currentSeason ?? 1;
    _episode = show?.currentEpisode ?? 0;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    _formKey.currentState!.save();

    final provider = context.read<ShowProvider>();
    final isEditing = widget.initialShow != null;
    final now = DateTime.now();

    final Show show;
    if (isEditing) {
      show = widget.initialShow!.copyWith(
        title: _title.trim(),
        type: _type,
        status: _status,
        posterUrl: _posterUrl.trim(),
        genre: _genre.trim(),
        plot: _plot.trim(),
        rating: _rating,
        currentSeason: _season,
        currentEpisode: _episode,
        updatedAt: now,
      );
    } else {
      final baseShow = Show.fromSearchResult(<String, dynamic>{
        'imdbID': now.millisecondsSinceEpoch.toString(),
        'Title': _title.trim(),
        'Type': _type.toLowerCase(),
        'Poster': _posterUrl.trim(),
        'Year': '',
      });

      show = baseShow.copyWith(
        title: _title.trim(),
        type: _type,
        status: _status,
        posterUrl: _posterUrl.trim(),
        genre: _genre.trim(),
        plot: _plot.trim(),
        rating: _rating,
        currentSeason: _season,
        currentEpisode: _episode,
        createdAt: now,
        updatedAt: now,
      );
    }

    if (isEditing) {
      await provider.updateShow(show);
    } else {
      await provider.addShow(show);
    }

    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.initialShow != null;
    final primary = Theme.of(context).colorScheme.primary;

    return AmbientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () => Navigator.pop(context),
          ),
          title: Text(isEditing ? 'Edit Title' : 'Add Custom Title'),
          actions: <Widget>[
            TextButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.check_rounded, size: 20),
              label: const Text(
                'Save',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        body: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
            children: <Widget>[
              GlassContainer(
                borderRadius: 20,
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Format Type',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: primary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(
                          value: 'Series',
                          label: Text('TV Series'),
                          icon: Icon(Icons.tv_rounded),
                        ),
                        ButtonSegment(
                          value: 'Movie',
                          label: Text('Movie'),
                          icon: Icon(Icons.movie_rounded),
                        ),
                      ],
                      selected: {_type},
                      onSelectionChanged: (set) =>
                          setState(() => _type = set.first),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      initialValue: _title,
                      decoration: const InputDecoration(
                        labelText: 'Title *',
                        hintText: 'Enter title name',
                      ),
                      validator: (val) => val == null || val.trim().isEmpty
                          ? 'Title is required'
                          : null,
                      onSaved: (val) => _title = val ?? '',
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      initialValue: _posterUrl,
                      decoration: const InputDecoration(
                        labelText: 'Poster URL',
                        hintText: 'https://image-link.jpg',
                      ),
                      onSaved: (val) => _posterUrl = val ?? '',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              GlassContainer(
                borderRadius: 20,
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Status & Progress',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: primary,
                      ),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      value: _status,
                      decoration: const InputDecoration(
                        labelText: 'Watch Status',
                      ),
                      items: StatusStyle.statuses.map((s) {
                        return DropdownMenuItem(value: s, child: Text(s));
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) setState(() => _status = val);
                      },
                    ),
                    if (_type == 'Series') ...<Widget>[
                      const SizedBox(height: 14),
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: TextFormField(
                              initialValue: '$_season',
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Current Season',
                              ),
                              onSaved: (val) =>
                                  _season = int.tryParse(val ?? '1') ?? 1,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              initialValue: '$_episode',
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Watched Episode',
                              ),
                              onSaved: (val) =>
                                  _episode = int.tryParse(val ?? '0') ?? 0,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              GlassContainer(
                borderRadius: 20,
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Additional Details',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: primary,
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      initialValue: _genre,
                      decoration: const InputDecoration(
                        labelText: 'Genre',
                        hintText: 'Action, Drama, Sci-Fi',
                      ),
                      onSaved: (val) => _genre = val ?? '',
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      initialValue: _rating > 0 ? '$_rating' : '',
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Rating (0 - 10)',
                        hintText: '8.5',
                      ),
                      onSaved: (val) =>
                          _rating = double.tryParse(val ?? '0') ?? 0.0,
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      initialValue: _plot,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Plot Summary',
                        hintText: 'Short description',
                      ),
                      onSaved: (val) => _plot = val ?? '',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: _save,
                icon: const Icon(Icons.save_rounded),
                label: Text(
                  isEditing ? 'Save Changes' : 'Add to Watchlist',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
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
