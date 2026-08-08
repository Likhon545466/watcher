import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ============================================================
// APP PALETTE
// ============================================================

enum AppPalette {
  defaultBlue,
  skyBlue,
  teal,
  green,
  purple,
  indigo,
  rose,
  amber,
  orange,
  cyberpunk,
  midnightOled,
  sunsetAurora,
  oceanAbyss,
}

// ============================================================
// SETTINGS PROVIDER
// ============================================================

class SettingsProvider with ChangeNotifier {
  // ==========================================================
  // APPEARANCE KEYS
  // ==========================================================

  static const String _keyThemeMode = 'theme_mode';

  static const String _keyDynamicColor = 'dynamic_color';

  static const String _keyPalette = 'app_palette';

  static const String _keyGlassOpacity = 'glass_opacity';

  // ==========================================================
  // BACKUP HISTORY KEYS
  // ==========================================================

  static const String _keyLastBackupAt = 'watcher_last_backup_at';

  static const String _keyLastRestoreAt = 'watcher_last_restore_at';

  // ==========================================================
  // DEFAULTS
  // ==========================================================

  static const double defaultGlassOpacity = 0.12;

  // ==========================================================
  // STATE
  // ==========================================================

  ThemeMode _themeMode = ThemeMode.system;

  bool _dynamicColorEnabled = true;

  AppPalette _selectedPalette = AppPalette.defaultBlue;

  double _glassOpacity = defaultGlassOpacity;

  DateTime? _lastBackupAt;

  DateTime? _lastRestoreAt;

  // ==========================================================
  // CONSTRUCTOR
  // ==========================================================

  SettingsProvider() {
    _loadSettings();
  }

  // ==========================================================
  // GETTERS
  // ==========================================================

  ThemeMode get themeMode => _themeMode;

  bool get dynamicColorEnabled => _dynamicColorEnabled;

  AppPalette get selectedPalette => _selectedPalette;

  double get glassOpacity => _glassOpacity;

  DateTime? get lastBackupAt => _lastBackupAt;

  DateTime? get lastRestoreAt => _lastRestoreAt;

  // ==========================================================
  // LOAD SETTINGS
  // ==========================================================

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();

    // ========================================================
    // THEME MODE
    // ========================================================

    final themeIndex = prefs.getInt(_keyThemeMode);

    if (themeIndex != null) {
      _themeMode =
          ThemeMode.values[themeIndex.clamp(0, ThemeMode.values.length - 1)];
    }

    // ========================================================
    // DYNAMIC COLOR
    // ========================================================

    _dynamicColorEnabled = prefs.getBool(_keyDynamicColor) ?? true;

    // ========================================================
    // PALETTE
    // ========================================================

    final paletteIndex = prefs.getInt(_keyPalette);

    if (paletteIndex != null) {
      _selectedPalette = AppPalette
          .values[paletteIndex.clamp(0, AppPalette.values.length - 1)];
    }

    // ========================================================
    // GLASS OPACITY
    // ========================================================

    _glassOpacity = prefs.getDouble(_keyGlassOpacity) ?? defaultGlassOpacity;

    // ========================================================
    // BACKUP HISTORY
    // ========================================================

    final lastBackupMillis = prefs.getInt(_keyLastBackupAt);

    if (lastBackupMillis != null && lastBackupMillis > 0) {
      _lastBackupAt = DateTime.fromMillisecondsSinceEpoch(lastBackupMillis);
    }

    final lastRestoreMillis = prefs.getInt(_keyLastRestoreAt);

    if (lastRestoreMillis != null && lastRestoreMillis > 0) {
      _lastRestoreAt = DateTime.fromMillisecondsSinceEpoch(lastRestoreMillis);
    }

    notifyListeners();
  }

  // ==========================================================
  // THEME MODE
  // ==========================================================

  Future<void> setThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) {
      return;
    }

    _themeMode = mode;

    notifyListeners();

    final prefs = await SharedPreferences.getInstance();

    await prefs.setInt(_keyThemeMode, mode.index);
  }

  // ==========================================================
  // DYNAMIC COLOR
  // ==========================================================

  Future<void> setDynamicColorEnabled(bool enabled) async {
    if (_dynamicColorEnabled == enabled) {
      return;
    }

    _dynamicColorEnabled = enabled;

    notifyListeners();

    final prefs = await SharedPreferences.getInstance();

    await prefs.setBool(_keyDynamicColor, enabled);
  }

  // ==========================================================
  // APP PALETTE
  // ==========================================================

  Future<void> setAppPalette(AppPalette palette) async {
    if (_selectedPalette == palette) {
      return;
    }

    _selectedPalette = palette;

    notifyListeners();

    final prefs = await SharedPreferences.getInstance();

    await prefs.setInt(_keyPalette, palette.index);
  }

  // ==========================================================
  // GLASS OPACITY
  // ==========================================================

  Future<void> setGlassOpacity(double opacity) async {
    final clamped = opacity.clamp(0.0, 1.0);

    if (_glassOpacity == clamped) {
      return;
    }

    _glassOpacity = clamped;

    notifyListeners();

    final prefs = await SharedPreferences.getInstance();

    await prefs.setDouble(_keyGlassOpacity, clamped);
  }

  // ==========================================================
  // RESET GLASS OPACITY
  // ==========================================================

  Future<void> resetGlassOpacity() async {
    await setGlassOpacity(defaultGlassOpacity);
  }

  // ==========================================================
  // BACKUP CREATED
  // ==========================================================

  /// Call only after Watcher successfully creates the backup
  /// file and reaches the share/export stage.
  Future<void> markBackupCreated({DateTime? at}) async {
    final value = at ?? DateTime.now();

    _lastBackupAt = value;

    notifyListeners();

    final prefs = await SharedPreferences.getInstance();

    await prefs.setInt(_keyLastBackupAt, value.millisecondsSinceEpoch);
  }

  // ==========================================================
  // RESTORE COMPLETED
  // ==========================================================

  /// Call after a valid backup has successfully completed
  /// either Merge or Replace All.
  Future<void> markRestoreCompleted({DateTime? at}) async {
    final value = at ?? DateTime.now();

    _lastRestoreAt = value;

    notifyListeners();

    final prefs = await SharedPreferences.getInstance();

    await prefs.setInt(_keyLastRestoreAt, value.millisecondsSinceEpoch);
  }
}
