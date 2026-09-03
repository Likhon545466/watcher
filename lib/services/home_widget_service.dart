import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/show.dart';

class HomeWidgetService {
  HomeWidgetService._();

  static Future<void> initialize() async {}

  static Future<void> updateWidgetData(List<Show> shows) async {
    try {
      final watchingShows =
          shows.where((s) => s.status == 'Watching').toList();
      Show? topShow;
      if (watchingShows.isNotEmpty) {
        watchingShows.sort(
          (a, b) => b.recentActivityAt.compareTo(a.recentActivityAt),
        );
        topShow = watchingShows.first;
      } else if (shows.isNotEmpty) {
        topShow = shows.first;
      }

      final prefs = await SharedPreferences.getInstance();

      if (topShow != null) {
        await prefs.setString('widget_show_id', topShow.id);
        await prefs.setString('widget_show_title', topShow.title);
        final progressText = topShow.isSeries
            ? 'S${topShow.currentSeason} E${topShow.currentEpisode}'
            : (topShow.status == 'Completed' ? 'Completed' : 'Watching');
        await prefs.setString('widget_show_progress', progressText);
        await prefs.setString('widget_show_type', topShow.type);
        await prefs.setString('widget_show_poster', topShow.posterUrl);
      } else {
        await prefs.setString('widget_show_id', '');
        await prefs.setString('widget_show_title', 'Watcher');
        await prefs.setString('widget_show_progress', 'No active shows');
        await prefs.setString('widget_show_type', '');
        await prefs.setString('widget_show_poster', '');
      }
    } catch (e) {
      debugPrint('HomeWidget update error: $e');
    }
  }
}
