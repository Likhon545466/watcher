import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/settings_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/ambient_background.dart';
import '../widgets/glass_container.dart';

class AppearanceScreen extends StatelessWidget {
  const AppearanceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;

    final opacityPercentage = (settings.glassOpacity * 100).round();
    final isSolid = settings.glassOpacity == 0.0;

    return AmbientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () => Navigator.pop(context),
          ),
          title: const Text('Appearance'),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: <Widget>[
            Text(
              'Dynamic Color',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: primary,
              ),
            ),
            const SizedBox(height: 8),
            GlassContainer(
              borderRadius: 20,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: <Widget>[
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: primary.withOpacity(0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.palette_rounded,
                      color: primary,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const <Widget>[
                        Text(
                          'Dynamic Color',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Match app colors to wallpaper',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: settings.dynamicColorEnabled,
                    onChanged: settings.setDynamicColorEnabled,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Smooth Glass Opacity Slider Section (0.0 to 1.0 Max)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Glass Opacity & Blur',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: primary,
                  ),
                ),
                Text(
                  isSolid ? 'Solid Mode (0%)' : '$opacityPercentage%',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: isSolid ? Colors.orangeAccent : primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            GlassContainer(
              borderRadius: 20,
              padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        isSolid ? Icons.style_rounded : Icons.opacity_rounded,
                        color: primary,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          isSolid
                              ? 'Opacity set to 0. Background is now fully solid.'
                              : 'Adjust container background transparency',
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: Colors.grey,
                          ),
                        ),
                      ),
                      Tooltip(
                        message: 'Hold to reset to default',
                        child: InkWell(
                          borderRadius: BorderRadius.circular(20),
                          onTap: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Press and hold to reset glass opacity.',
                                ),
                                duration: Duration(seconds: 1),
                              ),
                            );
                          },
                          onLongPress: () {
                            settings.resetGlassOpacity();
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Glass opacity reset to default (12%).',
                                ),
                              ),
                            );
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: Icon(
                              Icons.restore_rounded,
                              color: primary,
                              size: 22,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: primary,
                      thumbColor: primary,
                      overlayColor: primary.withOpacity(0.18),
                      trackHeight: 5.0,
                    ),
                    child: Slider(
                      value: settings.glassOpacity.clamp(0.0, 1.0),
                      min: 0.0,
                      max: 1.0, // Updated Max Slider Value
                      onChanged: (val) => settings.setGlassOpacity(val),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            Text(
              'Theme mode',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: primary,
              ),
            ),
            const SizedBox(height: 10),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Expanded(
                    child: _ThemeModeCard(
                      title: 'System Default',
                      icon: Icons.auto_awesome_rounded,
                      value: ThemeMode.system,
                      groupValue: settings.themeMode,
                      onTap: () => settings.setThemeMode(ThemeMode.system),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _ThemeModeCard(
                      title: 'Light',
                      icon: Icons.wb_sunny_rounded,
                      value: ThemeMode.light,
                      groupValue: settings.themeMode,
                      onTap: () => settings.setThemeMode(ThemeMode.light),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _ThemeModeCard(
                      title: 'Dark',
                      icon: Icons.nightlight_round,
                      value: ThemeMode.dark,
                      groupValue: settings.themeMode,
                      onTap: () => settings.setThemeMode(ThemeMode.dark),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            Text(
              'App theme',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: primary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              settings.dynamicColorEnabled
                  ? 'Dynamic Color is active. Disable it to use a custom theme.'
                  : 'Select a custom color theme for your app.',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            Opacity(
              opacity: settings.dynamicColorEnabled ? 0.45 : 1.0,
              child: IgnorePointer(
                ignoring: settings.dynamicColorEnabled,
                child: GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    childAspectRatio: 0.9,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                  ),
                  itemCount: AppPalette.values.length,
                  itemBuilder: (context, index) {
                    final palette = AppPalette.values[index];
                    final selected = settings.selectedPalette == palette;
                    return _PaletteCard(
                      palette: palette,
                      selected: selected,
                      onTap: () => settings.setAppPalette(palette),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ThemeModeCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final ThemeMode value;
  final ThemeMode groupValue;
  final VoidCallback onTap;

  const _ThemeModeCard({
    required this.title,
    required this.icon,
    required this.value,
    required this.groupValue,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final selected = value == groupValue;
    final primary = Theme.of(context).colorScheme.primary;

    return GlassContainer(
      borderRadius: 18,
      opacity: selected ? 0.2 : 0.06,
      borderColor: selected ? primary : null,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(
              icon,
              size: 24,
              color: selected
                  ? primary
                  : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 8),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected
                    ? primary
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PaletteCard extends StatelessWidget {
  final AppPalette palette;
  final bool selected;
  final VoidCallback onTap;

  const _PaletteCard({
    required this.palette,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final dots = AppTheme.getPaletteDots(palette);
    final name = AppTheme.getPaletteName(palette);

    return GlassContainer(
      borderRadius: 18,
      opacity: selected ? 0.25 : 0.08,
      borderColor: selected ? primary : null,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                for (int i = 0; i < dots.length; i++) ...<Widget>[
                  Container(
                    width: i == 0 ? 20 : 16,
                    height: i == 0 ? 20 : 16,
                    decoration: BoxDecoration(
                      color: dots[i],
                      shape: BoxShape.circle,
                    ),
                    child: (i == 0 && selected)
                        ? const Icon(
                            Icons.check_rounded,
                            color: Colors.white,
                            size: 13,
                          )
                        : null,
                  ),
                  if (i < dots.length - 1) const SizedBox(width: 4),
                ],
              ],
            ),
            const SizedBox(height: 12),
            Text(
              name,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected
                    ? primary
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
