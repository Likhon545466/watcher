import 'package:flutter/material.dart';

class StatusStyle {
  static const statuses = <String>[
    'Watching',
    'Completed',
    'On Hold',
    'Dropped',
    'Plan to Watch',
  ];

  static Color color(String status) {
    switch (status) {
      case 'Watching':
        return const Color(0xFF2499E8);
      case 'Completed':
        return const Color(0xFF4CAF59);
      case 'On Hold':
        return const Color(0xFFFF9800);
      case 'Dropped':
        return const Color(0xFFFF4D4F);
      case 'Plan to Watch':
        return const Color(0xFFA824B7);
      case 'All':
      default:
        return const Color(0xFF6E54A5);
    }
  }

  static IconData icon(String status) {
    switch (status) {
      case 'Watching':
        return Icons.play_arrow_rounded;
      case 'Completed':
        return Icons.check_rounded;
      case 'On Hold':
        return Icons.pause_rounded;
      case 'Dropped':
        return Icons.close_rounded;
      case 'Plan to Watch':
        return Icons.bookmark_rounded;
      default:
        return Icons.apps_rounded;
    }
  }
}
