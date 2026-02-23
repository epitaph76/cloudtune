import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../providers/audio_player_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/language_provider.dart';
import '../providers/local_music_provider.dart';
import '../providers/main_nav_provider.dart';
import '../utils/app_localizations.dart';
import '../widgets/now_playing_wave_background.dart';
import '../widgets/theme_settings_sheet.dart';
import 'server_music_screen.dart';

class WindowsDesktopShell extends StatefulWidget {
  const WindowsDesktopShell({super.key});

  @override
  State<WindowsDesktopShell> createState() => _WindowsDesktopShellState();
}

class _WindowsDesktopShellState extends State<WindowsDesktopShell> {
  bool _sidebarExpanded = false;
  static const double _sidebarTriggerWidth = 110;

  Future<void> _openThemeSettings(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        insetPadding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560, maxHeight: 720),
          child: const ThemeSettingsSheet(),
        ),
      ),
    );
  }

  Future<void> _openLanguageSettings(BuildContext context) async {
    String t(String key) => AppLocalizations.text(context, key);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        final languageProvider = sheetContext.read<LanguageProvider>();
        final currentCode = languageProvider.locale.languageCode;
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t('select_language')),
                ListTile(
                  leading: Icon(
                    currentCode == 'ru'
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_unchecked_rounded,
                  ),
                  onTap: () {
                    languageProvider.setLocale(const Locale('ru'));
                    Navigator.of(sheetContext).pop();
                  },
                  title: Text(t('russian')),
                ),
                ListTile(
                  leading: Icon(
                    currentCode == 'en'
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_unchecked_rounded,
                  ),
                  onTap: () {
                    languageProvider.setLocale(const Locale('en'));
                    Navigator.of(sheetContext).pop();
                  },
                  title: Text(t('english')),
                ),
                ListTile(
                  leading: Icon(
                    currentCode == 'es'
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_unchecked_rounded,
                  ),
                  onTap: () {
                    languageProvider.setLocale(const Locale('es'));
                    Navigator.of(sheetContext).pop();
                  },
                  title: Text(t('spanish')),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _openAccountPanel(BuildContext context) async {
    final authProvider = context.read<AuthProvider>();
    String t(String key) => AppLocalizations.text(context, key);
    final user = authProvider.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(t('guest'))));
      return;
    }
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(user.username),
        content: Text(t('logout_confirm')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(t('logout')),
          ),
        ],
      ),
    );
    if (shouldLogout == true) {
      await authProvider.logout();
      if (!mounted) return;
      ScaffoldMessenger.of(
        this.context,
      ).showSnackBar(SnackBar(content: Text(t('logged_out'))));
    }
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final authProvider = context.read<AuthProvider>();
    String t(String key) => AppLocalizations.text(context, key);
    if (authProvider.currentUser == null) return;
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(t('logout')),
        content: Text(t('logout_confirm')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(t('logout')),
          ),
        ],
      ),
    );
    if (shouldLogout == true) {
      await authProvider.logout();
      if (!mounted) return;
      ScaffoldMessenger.of(
        this.context,
      ).showSnackBar(SnackBar(content: Text(t('logged_out'))));
    }
  }

  void _playPlaylist(String playlistId) {
    context.read<MainNavProvider>().setSelectedLocalPlaylistId(playlistId);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final localMusicProvider = context.watch<LocalMusicProvider>();
    final audioProvider = context.watch<AudioPlayerProvider>();
    final authProvider = context.watch<AuthProvider>();
    final navProvider = context.watch<MainNavProvider>();
    final isNowPlaying = audioProvider.playing;
    String t(String key) => AppLocalizations.text(context, key);
    final selectedPlaylistId = navProvider.selectedLocalPlaylistId;

    final accountLabel = authProvider.currentUser?.username ?? t('guest');
    final playlists = [
      (
        id: LocalMusicProvider.allPlaylistId,
        name: t('all_songs'),
        count: localMusicProvider.selectedFiles.length,
        selected: selectedPlaylistId == LocalMusicProvider.allPlaylistId,
      ),
      (
        id: LocalMusicProvider.likedPlaylistId,
        name: t('liked_songs'),
        count: localMusicProvider.likedTracksCount,
        selected: selectedPlaylistId == LocalMusicProvider.likedPlaylistId,
      ),
      ...localMusicProvider.playlists.map(
        (item) => (
          id: item.id,
          name: item.name,
          count: item.trackPaths.length,
          selected: selectedPlaylistId == item.id,
        ),
      ),
    ];

    final sidebarWidth = _sidebarExpanded ? 296.0 : 92.0;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: NowPlayingWaveBackground(
        isActive: isNowPlaying,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Row(
                  children: [
                    MouseRegion(
                      onEnter: (_) => setState(() => _sidebarExpanded = true),
                      onExit: (_) => setState(() => _sidebarExpanded = false),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 780),
                        curve: Curves.easeInOutCubic,
                        width: sidebarWidth,
                        child: _SidebarContainer(
                          playlists: playlists,
                          expanded: _sidebarExpanded,
                          accountLabel: accountLabel,
                          hasUser: authProvider.currentUser != null,
                          onPlaylistTap: _playPlaylist,
                          onAccountTap: () => _openAccountPanel(context),
                          onLogoutTap: () => _confirmLogout(context),
                          onLanguageTap: () => _openLanguageSettings(context),
                          onSettingsTap: () => _openThemeSettings(context),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: colorScheme.surface,
                          borderRadius: BorderRadius.circular(26),
                          border: Border.all(color: colorScheme.outline),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: const ServerMusicScreen(),
                      ),
                    ),
                    const SizedBox(width: 14),
                    const SizedBox(width: 478, child: _WindowsPlayerPanel()),
                  ],
                ),
                Positioned(
                  left: -_sidebarTriggerWidth,
                  top: 0,
                  bottom: 0,
                  width: _sidebarTriggerWidth,
                  child: MouseRegion(
                    onEnter: (_) => setState(() => _sidebarExpanded = true),
                    child: const SizedBox.expand(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SidebarContainer extends StatelessWidget {
  const _SidebarContainer({
    required this.playlists,
    required this.expanded,
    required this.accountLabel,
    required this.hasUser,
    required this.onPlaylistTap,
    required this.onAccountTap,
    required this.onLogoutTap,
    required this.onLanguageTap,
    required this.onSettingsTap,
  });

  final List<({String id, String name, int count, bool selected})> playlists;
  final bool expanded;
  final String accountLabel;
  final bool hasUser;
  final ValueChanged<String> onPlaylistTap;
  final VoidCallback onAccountTap;
  final VoidCallback onLogoutTap;
  final VoidCallback onLanguageTap;
  final VoidCallback onSettingsTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    String t(String key) => AppLocalizations.text(context, key);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 780),
      curve: Curves.easeInOutCubic,
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: colorScheme.outline),
      ),
      child: Column(
        children: [
          const SizedBox(height: 14),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: playlists
                  .map(
                    (item) => _SidebarPlaylist(
                      title: item.name,
                      count: item.count,
                      selected: item.selected,
                      expanded: expanded,
                      onTap: () => onPlaylistTap(item.id),
                    ),
                  )
                  .toList(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
            child: Column(
              children: [
                _SidebarAccountCard(
                  expanded: expanded,
                  accountLabel: accountLabel,
                  hasUser: hasUser,
                  onAccountTap: onAccountTap,
                  onLogoutTap: onLogoutTap,
                  logoutLabel: t('logout'),
                ),
                const SizedBox(height: 8),
                _SidebarAction(
                  icon: Icons.language_rounded,
                  title: t('language'),
                  expanded: expanded,
                  active: false,
                  onTap: onLanguageTap,
                ),
                const SizedBox(height: 8),
                _SidebarAction(
                  icon: Icons.settings_rounded,
                  title: t('settings'),
                  expanded: expanded,
                  active: false,
                  onTap: onSettingsTap,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SidebarAction extends StatefulWidget {
  const _SidebarAction({
    required this.icon,
    required this.title,
    required this.expanded,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final bool expanded;
  final bool active;
  final VoidCallback onTap;

  @override
  State<_SidebarAction> createState() => _SidebarActionState();
}

class _SidebarActionState extends State<_SidebarAction> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final canShowExpanded =
              widget.expanded && constraints.maxWidth >= 184;

          return AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: widget.active ? colorScheme.primary : colorScheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _hovered
                    ? colorScheme.primary.withValues(alpha: 0.35)
                    : Colors.transparent,
              ),
            ),
            child: Row(
              children: [
                IconButton(
                  onPressed: widget.onTap,
                  visualDensity: VisualDensity.compact,
                  icon: Icon(
                    widget.icon,
                    size: 22,
                    color: widget.active
                        ? colorScheme.onPrimary
                        : colorScheme.onSurface.withValues(alpha: 0.72),
                  ),
                ),
                if (canShowExpanded) ...[
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      widget.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: widget.active
                            ? colorScheme.onPrimary
                            : colorScheme.onSurface.withValues(alpha: 0.8),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _SidebarPlaylist extends StatefulWidget {
  const _SidebarPlaylist({
    required this.title,
    required this.count,
    required this.selected,
    required this.expanded,
    required this.onTap,
  });

  final String title;
  final int count;
  final bool selected;
  final bool expanded;
  final VoidCallback onTap;

  @override
  State<_SidebarPlaylist> createState() => _SidebarPlaylistState();
}

class _SidebarPlaylistState extends State<_SidebarPlaylist> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final tileHeight = 56.0 + ((textScale - 1.0).clamp(0.0, 1.0) * 28.0);
    final showCount = textScale <= 1.25;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final canShowExpanded =
              widget.expanded && constraints.maxWidth >= 186;

          return InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(16),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 240),
              margin: const EdgeInsets.only(bottom: 8),
              height: tileHeight,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: widget.selected
                    ? colorScheme.secondary
                    : colorScheme.surface,
                border: Border.all(
                  color: widget.selected
                      ? colorScheme.primary
                      : _hovered
                      ? colorScheme.primary.withValues(alpha: 0.35)
                      : colorScheme.outline.withValues(alpha: 0.7),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      gradient: LinearGradient(
                        colors: [colorScheme.primary, colorScheme.tertiary],
                      ),
                    ),
                    child: Icon(
                      Icons.music_note_rounded,
                      color: colorScheme.onPrimary,
                    ),
                  ),
                  if (canShowExpanded) ...[
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (showCount)
                            Text(
                              '${widget.count}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: colorScheme.onSurface.withValues(
                                  alpha: 0.66,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SidebarAccountCard extends StatefulWidget {
  const _SidebarAccountCard({
    required this.expanded,
    required this.accountLabel,
    required this.hasUser,
    required this.onAccountTap,
    required this.onLogoutTap,
    required this.logoutLabel,
  });

  final bool expanded;
  final String accountLabel;
  final bool hasUser;
  final VoidCallback onAccountTap;
  final VoidCallback onLogoutTap;
  final String logoutLabel;

  @override
  State<_SidebarAccountCard> createState() => _SidebarAccountCardState();
}

class _SidebarAccountCardState extends State<_SidebarAccountCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final canShowExpanded =
              widget.expanded && constraints.maxWidth >= 184;
          final canShowLogoutLabel =
              canShowExpanded && constraints.maxWidth >= 246;

          return AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: colorScheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _hovered
                    ? colorScheme.primary.withValues(alpha: 0.35)
                    : Colors.transparent,
              ),
            ),
            child: Row(
              children: [
                IconButton(
                  onPressed: widget.onAccountTap,
                  visualDensity: VisualDensity.compact,
                  icon: Icon(
                    Icons.person_rounded,
                    color: colorScheme.onSurface.withValues(alpha: 0.72),
                  ),
                ),
                if (canShowExpanded) ...[
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      widget.accountLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colorScheme.onSurface.withValues(alpha: 0.8),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (widget.hasUser)
                    canShowLogoutLabel
                        ? TextButton.icon(
                            onPressed: widget.onLogoutTap,
                            style: TextButton.styleFrom(
                              minimumSize: const Size(0, 34),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 6,
                              ),
                              visualDensity: VisualDensity.compact,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            icon: const Icon(Icons.logout_rounded, size: 16),
                            label: Text(widget.logoutLabel),
                          )
                        : IconButton(
                            onPressed: widget.onLogoutTap,
                            tooltip: widget.logoutLabel,
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.logout_rounded, size: 18),
                          ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _WindowsPlayerPanel extends StatefulWidget {
  const _WindowsPlayerPanel();

  @override
  State<_WindowsPlayerPanel> createState() => _WindowsPlayerPanelState();
}

class _WindowsPlayerPanelState extends State<_WindowsPlayerPanel> {
  double? _dragSliderValue;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    String t(String key) => AppLocalizations.text(context, key);

    return Consumer2<LocalMusicProvider, AudioPlayerProvider>(
      builder: (context, localMusicProvider, audioProvider, _) {
        final tracks = localMusicProvider.selectedFiles;
        final currentPath = audioProvider.currentTrackPath;
        final currentTrack = currentPath == null
            ? (tracks.isEmpty ? null : tracks.first)
            : tracks.cast<File?>().firstWhere(
                (item) => item?.path == currentPath,
                orElse: () => tracks.isEmpty ? null : tracks.first,
              );
        final title = currentTrack == null
            ? t('no_track_selected')
            : p.basenameWithoutExtension(currentTrack.path);
        final subtitle = currentTrack == null
            ? t('go_storage_add_files')
            : p.basename(currentTrack.path);
        final sliderMax = audioProvider.duration.inSeconds > 0
            ? audioProvider.duration.inSeconds.toDouble()
            : 1.0;
        final sliderValue = audioProvider.duration.inSeconds > 0
            ? audioProvider.position.inSeconds.toDouble().clamp(0.0, sliderMax)
            : 0.0;
        final effectiveSliderValue = (_dragSliderValue ?? sliderValue).clamp(
          0.0,
          sliderMax,
        );
        final isLiked =
            currentTrack != null &&
            localMusicProvider.isTrackLiked(currentTrack.path);

        return Container(
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: colorScheme.outline),
          ),
          padding: const EdgeInsets.fromLTRB(18, 34, 18, 18),
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    const SizedBox(height: 28),
                    Center(
                      child: SizedBox.square(
                        dimension: 328,
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(34),
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                colorScheme.primary,
                                colorScheme.tertiary,
                              ],
                            ),
                          ),
                          child: Center(
                            child: SizedBox.square(
                              dimension: 144,
                              child: Icon(
                                Icons.music_note_rounded,
                                size: 126,
                                color: colorScheme.onPrimary,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 46),
                    SizedBox(
                      height: 42,
                      child: _AutoScrollingText(
                        text: title,
                        textStyle: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          fontSize: 32,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    SizedBox(
                      height: 24,
                      child: _AutoScrollingText(
                        text: subtitle,
                        textStyle: theme.textTheme.bodyMedium?.copyWith(
                          fontSize: 15,
                          color: colorScheme.onSurface.withValues(alpha: 0.65),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    IconButton(
                      onPressed: currentTrack == null
                          ? null
                          : () => localMusicProvider.toggleTrackLike(
                              currentTrack.path,
                            ),
                      icon: Icon(
                        isLiked
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                      ),
                      iconSize: 32,
                      color: colorScheme.primary,
                    ),
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 5,
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 8,
                        ),
                      ),
                      child: Slider(
                        value: effectiveSliderValue,
                        max: sliderMax,
                        onChangeStart: audioProvider.duration.inSeconds <= 0
                            ? null
                            : (value) =>
                                  setState(() => _dragSliderValue = value),
                        onChanged: audioProvider.duration.inSeconds <= 0
                            ? null
                            : (value) =>
                                  setState(() => _dragSliderValue = value),
                        onChangeEnd: audioProvider.duration.inSeconds <= 0
                            ? null
                            : (value) async {
                                setState(() => _dragSliderValue = null);
                                await audioProvider.seek(
                                  Duration(seconds: value.round()),
                                );
                              },
                      ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _formatDuration(audioProvider.position),
                          style: theme.textTheme.bodyMedium,
                        ),
                        Text(
                          _formatDuration(audioProvider.duration),
                          style: theme.textTheme.bodyMedium,
                        ),
                      ],
                    ),
                    const SizedBox(height: 22),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _ToggleCircleIconButton(
                          active: audioProvider.shuffleEnabled,
                          onPressed: tracks.isNotEmpty
                              ? audioProvider.toggleShuffle
                              : null,
                          icon: Icons.shuffle_rounded,
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          onPressed: tracks.isNotEmpty
                              ? () => audioProvider.skipToPreviousFromTracks(
                                  tracks,
                                )
                              : null,
                          icon: const Icon(Icons.skip_previous_rounded),
                          iconSize: 40,
                        ),
                        const SizedBox(width: 10),
                        FilledButton(
                          onPressed: tracks.isNotEmpty
                              ? () => audioProvider.playPauseFromTracks(tracks)
                              : null,
                          style: FilledButton.styleFrom(
                            shape: const CircleBorder(),
                            padding: const EdgeInsets.all(24),
                          ),
                          child: Icon(
                            audioProvider.playing
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                            size: 40,
                          ),
                        ),
                        const SizedBox(width: 10),
                        IconButton(
                          onPressed: tracks.isNotEmpty
                              ? () => audioProvider.skipToNextFromTracks(tracks)
                              : null,
                          icon: const Icon(Icons.skip_next_rounded),
                          iconSize: 40,
                        ),
                        const SizedBox(width: 8),
                        _ToggleCircleIconButton(
                          active: audioProvider.repeatOneEnabled,
                          onPressed: tracks.isNotEmpty
                              ? audioProvider.toggleRepeatOne
                              : null,
                          icon: Icons.repeat_rounded,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _formatDuration(Duration duration) {
    if (duration.inSeconds <= 0) return '--:--';
    String two(int v) => v.toString().padLeft(2, '0');
    final minutes = two(duration.inMinutes.remainder(60));
    final seconds = two(duration.inSeconds.remainder(60));
    if (duration.inHours > 0) {
      return '${two(duration.inHours)}:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }
}

class _ToggleCircleIconButton extends StatelessWidget {
  const _ToggleCircleIconButton({
    required this.active,
    required this.onPressed,
    required this.icon,
  });

  final bool active;
  final VoidCallback? onPressed;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final enabled = onPressed != null;
    final bgColor = active
        ? colorScheme.primary
        : colorScheme.surface.withValues(alpha: enabled ? 1.0 : 0.5);
    final iconColor = active
        ? colorScheme.onPrimary
        : colorScheme.onSurface.withValues(alpha: enabled ? 0.78 : 0.42);

    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(22),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: bgColor,
          shape: BoxShape.circle,
          border: Border.all(
            color: active ? colorScheme.primary : colorScheme.outline,
          ),
        ),
        child: Icon(icon, size: 26, color: iconColor),
      ),
    );
  }
}

class _AutoScrollingText extends StatefulWidget {
  const _AutoScrollingText({required this.text, this.textStyle});

  final String text;
  final TextStyle? textStyle;

  @override
  State<_AutoScrollingText> createState() => _AutoScrollingTextState();
}

class _AutoScrollingTextState extends State<_AutoScrollingText> {
  final ScrollController _scrollController = ScrollController();
  Timer? _timer;
  bool _forward = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startAnimation());
  }

  @override
  void didUpdateWidget(covariant _AutoScrollingText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      _timer?.cancel();
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
      WidgetsBinding.instance.addPostFrameCallback((_) => _startAnimation());
    }
  }

  void _startAnimation() {
    if (!mounted || !_scrollController.hasClients) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    if (maxScroll <= 0) return;

    _timer = Timer.periodic(const Duration(seconds: 3), (_) async {
      if (!mounted || !_scrollController.hasClients) return;
      final target = _forward ? maxScroll : 0.0;
      _forward = !_forward;
      await _scrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 1200),
        curve: Curves.easeInOut,
      );
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        controller: _scrollController,
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: constraints.maxWidth),
          child: Align(
            alignment: Alignment.center,
            child: Text(
              widget.text,
              maxLines: 1,
              textAlign: TextAlign.center,
              style: widget.textStyle,
            ),
          ),
        ),
      ),
    );
  }
}
