import 'dart:io';

import 'package:flutter/material.dart';

import '../services/poster_cache_service.dart';

// ============================================================
// POSTER IMAGE
// ============================================================
//
// Central poster widget used across Watcher.
//
// Behavior:
//
// 1. Preserve the existing HD poster URL behavior
// 2. Look for the poster in persistent offline storage
// 3. If missing, download and save it
// 4. Render the local cached file
// 5. After that, the same poster can load without internet
//
// ============================================================

class PosterImage extends StatefulWidget {
  final String url;

  final double width;

  final double height;

  final double radius;

  final BoxFit fit;

  const PosterImage({
    super.key,
    required this.url,
    required this.width,
    required this.height,
    this.radius = 18,
    this.fit = BoxFit.cover,
  });

  @override
  State<PosterImage> createState() => _PosterImageState();
}

// ============================================================
// POSTER IMAGE STATE
// ============================================================

class _PosterImageState extends State<PosterImage> {
  Future<File?>? _posterFuture;

  String _resolvedUrl = '';

  // ==========================================================
  // INIT
  // ==========================================================

  @override
  void initState() {
    super.initState();

    _preparePoster();
  }

  // ==========================================================
  // WIDGET UPDATE
  // ==========================================================

  @override
  void didUpdateWidget(covariant PosterImage oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.url != widget.url) {
      _preparePoster();
    }
  }

  // ==========================================================
  // PREPARE POSTER
  // ==========================================================

  void _preparePoster() {
    _resolvedUrl = _getHdUrl(widget.url);

    if (_resolvedUrl.trim().isEmpty) {
      _posterFuture = null;

      return;
    }

    _posterFuture = PosterCacheService.getPosterFile(_resolvedUrl);
  }

  // ==========================================================
  // EXISTING HD URL LOGIC
  // ==========================================================
  //
  // This intentionally keeps the same poster URL conversion
  // behavior that Watcher already had before offline caching.
  //
  // ==========================================================

  String _getHdUrl(String rawUrl) {
    final clean = rawUrl.trim();

    if (clean.isEmpty) {
      return '';
    }

    // ========================================================
    // OMDB / AMAZON
    // ========================================================
    //
    // Remove Amazon crop / resize parameters.
    // ========================================================

    if (clean.contains('media-amazon.com/images/M/')) {
      return clean.replaceAll(
        RegExp(r'_SX\d+_|_SY\d+_|_CR\d+,\d+,\d+,\d+_'),
        '',
      );
    }

    // ========================================================
    // TMDB
    // ========================================================
    //
    // Preserve the previous Watcher behavior:
    //
    // /w500/ -> /original/
    // /w780/ -> /original/
    //
    // ========================================================

    if (clean.contains('image.tmdb.org/t/p/')) {
      // Small list cards do not need an original-resolution source.
      // Use w500 for compact posters and keep original for large/detail use.
      if (widget.width <= 220) {
        return clean.replaceAll(RegExp(r'/(?:w\d+|original)/'), '/w500/');
      }

      return clean.replaceAll(RegExp(r'/w\d+/'), '/original/');
    }

    return clean;
  }

  // ==========================================================
  // PLACEHOLDER
  // ==========================================================

  Widget _buildPlaceholder(BuildContext context, {bool loading = false}) {
    final theme = Theme.of(context);

    return Container(
      width: widget.width,
      height: widget.height,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(widget.radius),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          Icon(
            Icons.movie_creation_outlined,
            size: widget.width * 0.34,
            color: theme.colorScheme.onSurfaceVariant.withOpacity(0.5),
          ),

          if (loading)
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
        ],
      ),
    );
  }

  // ==========================================================
  // CACHED IMAGE
  // ==========================================================

  Widget _buildCachedImage(BuildContext context, File file) {
    final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);

    final cacheWidth = (widget.width * devicePixelRatio)
        .round()
        .clamp(1, 1600)
        .toInt();

    final cacheHeight = (widget.height * devicePixelRatio)
        .round()
        .clamp(1, 2400)
        .toInt();

    return Image.file(
      file,
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      cacheWidth: cacheWidth,
      cacheHeight: cacheHeight,

      // Decode near the actual display size to reduce memory
      // pressure while keeping the cached source unchanged.
      filterQuality: FilterQuality.medium,

      errorBuilder: (context, error, stackTrace) {
        return _buildNetworkFallback(context);
      },
    );
  }

  // ==========================================================
  // NETWORK FALLBACK
  // ==========================================================
  //
  // PosterCacheService normally downloads the network image
  // itself.
  //
  // This fallback only exists for rare cases where disk writing
  // fails while the internet is still available.
  //
  // ==========================================================

  Widget _buildNetworkFallback(BuildContext context) {
    if (_resolvedUrl.isEmpty) {
      return _buildPlaceholder(context);
    }

    final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);

    final cacheWidth = (widget.width * devicePixelRatio)
        .round()
        .clamp(1, 1600)
        .toInt();

    final cacheHeight = (widget.height * devicePixelRatio)
        .round()
        .clamp(1, 2400)
        .toInt();

    return Image.network(
      _resolvedUrl,
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      cacheWidth: cacheWidth,
      cacheHeight: cacheHeight,
      filterQuality: FilterQuality.medium,
      errorBuilder: (context, error, stackTrace) {
        return _buildPlaceholder(context);
      },
      loadingBuilder: (context, child, progress) {
        if (progress == null) {
          return child;
        }

        return _buildPlaceholder(context, loading: true);
      },
    );
  }

  // ==========================================================
  // BUILD
  // ==========================================================

  @override
  Widget build(BuildContext context) {
    if (_resolvedUrl.isEmpty || _posterFuture == null) {
      return _buildPlaceholder(context);
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.radius),
      child: FutureBuilder<File?>(
        future: _posterFuture,
        builder: (context, snapshot) {
          // ==================================================
          // LOADING
          // ==================================================

          if (snapshot.connectionState != ConnectionState.done) {
            return _buildPlaceholder(context, loading: true);
          }

          // ==================================================
          // CACHE / DOWNLOAD SUCCESS
          // ==================================================

          final file = snapshot.data;

          if (file != null) {
            return _buildCachedImage(context, file);
          }

          // ==================================================
          // CACHE FAILED
          // ==================================================
          //
          // Try the network normally so Watcher can still show
          // the poster while online.
          // ==================================================

          return _buildNetworkFallback(context);
        },
      ),
    );
  }
}
