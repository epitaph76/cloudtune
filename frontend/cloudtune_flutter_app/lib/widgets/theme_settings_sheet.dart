import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/theme_provider.dart';
import '../theme/app_theme.dart';

class ThemeSettingsSheet extends StatelessWidget {
  const ThemeSettingsSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, child) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Settings',
                      style: textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text('Theme mode', style: textTheme.labelLarge),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _ModeCard(
                        label: 'Light',
                        icon: Icons.light_mode,
                        selected: themeProvider.mode == AppVisualMode.light,
                        onTap: () => themeProvider.setMode(AppVisualMode.light),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _ModeCard(
                        label: 'Dark',
                        icon: Icons.dark_mode,
                        selected: themeProvider.mode == AppVisualMode.dark,
                        onTap: () => themeProvider.setMode(AppVisualMode.dark),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Text('Accent', style: textTheme.labelLarge),
                const SizedBox(height: 10),
                GridView.count(
                  crossAxisCount: 2,
                  childAspectRatio: 2.6,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  children: AppAccentScheme.values.map((scheme) {
                    final selected = themeProvider.scheme == scheme;
                    return InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => themeProvider.setScheme(scheme),
                      child: Container(
                        decoration: BoxDecoration(
                          color: selected
                              ? colorScheme.secondary
                              : colorScheme.surface,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: selected
                                ? colorScheme.primary
                                : colorScheme.outline,
                            width: selected ? 1.5 : 1,
                          ),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        child: Row(
                          children: [
                            _AccentPreview(scheme: scheme),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _schemeLabel(scheme),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (selected)
                              Icon(
                                Icons.check,
                                size: 18,
                                color: colorScheme.primary,
                              ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          color: selected ? colorScheme.secondary : colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? colorScheme.primary : colorScheme.outline,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(child: Text(label)),
            if (selected)
              Icon(Icons.check, size: 18, color: colorScheme.primary),
          ],
        ),
      ),
    );
  }
}

class _AccentPreview extends StatelessWidget {
  const _AccentPreview({required this.scheme});

  final AppAccentScheme scheme;

  @override
  Widget build(BuildContext context) {
    final gradient = _previewGradient(scheme);

    return Container(
      width: 26,
      height: 26,
      decoration: BoxDecoration(shape: BoxShape.circle, gradient: gradient),
    );
  }
}

LinearGradient _previewGradient(AppAccentScheme scheme) {
  switch (scheme) {
    case AppAccentScheme.green:
      return const LinearGradient(
        colors: [Color(0xFFA8E6B5), Color(0xFF7FD89A)],
      );
    case AppAccentScheme.blue:
      return const LinearGradient(
        colors: [Color(0xFFA8D5E6), Color(0xFF7FB8D8)],
      );
    case AppAccentScheme.yellow:
      return const LinearGradient(
        colors: [Color(0xFFF9E4A8), Color(0xFFF5D47F)],
      );
    case AppAccentScheme.pink:
      return const LinearGradient(
        colors: [Color(0xFFF9B8D4), Color(0xFFF58CB8)],
      );
    case AppAccentScheme.purple:
      return const LinearGradient(
        colors: [Color(0xFFD4B8F9), Color(0xFFB88CF5)],
      );
    case AppAccentScheme.peach:
      return const LinearGradient(
        colors: [Color(0xFFFFD4B8), Color(0xFFFFB88C)],
      );
  }
}

String _schemeLabel(AppAccentScheme scheme) {
  switch (scheme) {
    case AppAccentScheme.green:
      return 'Green';
    case AppAccentScheme.blue:
      return 'Blue';
    case AppAccentScheme.yellow:
      return 'Yellow';
    case AppAccentScheme.pink:
      return 'Pink';
    case AppAccentScheme.purple:
      return 'Purple';
    case AppAccentScheme.peach:
      return 'Peach';
  }
}
