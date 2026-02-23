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
import '../widgets/theme_settings_sheet.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  String _selectedPlaylistId = LocalMusicProvider.allPlaylistId;

  static const double _horizontalSwipeThreshold = 80;

  void _handleTopZoneHorizontalSwipe(DragEndDetails details) {
    final dx = details.primaryVelocity ?? 0;
    if (dx > _horizontalSwipeThreshold * 8) {
      _scaffoldKey.currentState?.openDrawer();
      return;
    }
    if (dx < -_horizontalSwipeThreshold * 8) {
      context.read<MainNavProvider>().setIndex(1);
    }
  }

  Future<void> _confirmLogout() async {
    final authProvider = context.read<AuthProvider>();
    String t(String key) => AppLocalizations.text(context, key);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
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
        );
      },
    );

    if (confirmed != true || !mounted) return;
    await authProvider.logout();
    if (!mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(t('logged_out'))));
  }

  @override
  Widget build(BuildContext context) {
    String t(String key) => AppLocalizations.text(context, key);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;

    return Consumer2<LocalMusicProvider, AudioPlayerProvider>(
      builder: (context, localMusicProvider, audioProvider, child) {
        final hasSelectedPlaylist =
            _selectedPlaylistId == LocalMusicProvider.allPlaylistId ||
            _selectedPlaylistId == LocalMusicProvider.likedPlaylistId ||
            localMusicProvider.playlists.any(
              (playlist) => playlist.id == _selectedPlaylistId,
            );
        final activePlaylistId = hasSelectedPlaylist
            ? _selectedPlaylistId
            : LocalMusicProvider.allPlaylistId;
        final tracks = localMusicProvider.getTracksForPlaylist(
          activePlaylistId,
        );
        final allLocalTracks = localMusicProvider.selectedFiles;
        final hasTracks = tracks.isNotEmpty;
        final currentTrackPath = audioProvider.currentTrackPath;
        final currentFile = currentTrackPath == null
            ? (hasTracks ? tracks.first : null)
            : allLocalTracks.cast<File?>().firstWhere(
                (track) => track?.path == currentTrackPath,
                orElse: () => hasTracks ? tracks.first : null,
              );
        final canControlPlayback = audioProvider.hasActiveQueue || hasTracks;
        final currentTitle = currentFile != null
            ? p.basenameWithoutExtension(currentFile.path)
            : t('no_track_selected');
        final currentSubtitle = currentFile != null
            ? p.basename(currentFile.path)
            : t('add_files_storage_hint');
        final isLiked = currentFile != null
            ? localMusicProvider.isTrackLiked(currentFile.path)
            : false;

        final durationSeconds = audioProvider.duration.inSeconds;
        final hasKnownDuration = durationSeconds > 0;
        final sliderMax = hasKnownDuration
            ? durationSeconds.toDouble()
            : (audioProvider.position.inSeconds > 0
                  ? audioProvider.position.inSeconds.toDouble() + 1
                  : 1.0);
        final sliderValue = hasKnownDuration
            ? audioProvider.position.inSeconds
                  .toDouble()
                  .clamp(0.0, sliderMax)
                  .toDouble()
            : 0.0;

        return Scaffold(
          key: _scaffoldKey,
          drawer: _buildSideMenu(context, localMusicProvider, activePlaylistId),
          body: SafeArea(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onHorizontalDragEnd: _handleTopZoneHorizontalSwipe,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
                child: Column(
                  children: [
                    GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onHorizontalDragEnd: _handleTopZoneHorizontalSwipe,
                      child: Row(
                        children: [
                          _TopActionButton(
                            icon: Icons.menu_rounded,
                            onTap: () =>
                                _scaffoldKey.currentState?.openDrawer(),
                          ),
                          const Spacer(),
                          Text(
                            'CloudTune',
                            style: textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const Spacer(),
                          const SizedBox(width: 42, height: 42),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    if (!hasTracks)
                      Expanded(
                        child: GestureDetector(
                          behavior: HitTestBehavior.translucent,
                          onHorizontalDragEnd: _handleTopZoneHorizontalSwipe,
                          child: Center(
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: colorScheme.surface,
                                borderRadius: BorderRadius.circular(24),
                                border: Border.all(color: colorScheme.outline),
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.music_off_rounded,
                                    size: 72,
                                    color: colorScheme.onSurface.withValues(
                                      alpha: 0.5,
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  Text(
                                    t('no_local_tracks_yet'),
                                    style: textTheme.titleMedium,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    t('go_storage_add_files'),
                                    textAlign: TextAlign.center,
                                    style: textTheme.bodyMedium?.copyWith(
                                      color: colorScheme.onSurface.withValues(
                                        alpha: 0.65,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      )
                    else
                      Expanded(
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final isCompactHeight = constraints.maxHeight < 640;
                            final artworkSize = isCompactHeight
                                ? (constraints.maxHeight * 0.38).clamp(
                                    176.0,
                                    280.0,
                                  )
                                : 312.0;
                            final titleSize = isCompactHeight ? 24.0 : 31.0;

                            return _buildTrackPlayerContent(
                              colorScheme: colorScheme,
                              textTheme: textTheme,
                              localMusicProvider: localMusicProvider,
                              audioProvider: audioProvider,
                              tracks: tracks,
                              currentFile: currentFile,
                              isLiked: isLiked,
                              currentTitle: currentTitle,
                              currentSubtitle: currentSubtitle,
                              sliderValue: sliderValue,
                              sliderMax: sliderMax,
                              hasKnownDuration: hasKnownDuration,
                              canControlPlayback: canControlPlayback,
                              isCompactHeight: isCompactHeight,
                              artworkSize: artworkSize,
                              titleSize: titleSize,
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildTrackPlayerContent({
    required ColorScheme colorScheme,
    required TextTheme textTheme,
    required LocalMusicProvider localMusicProvider,
    required AudioPlayerProvider audioProvider,
    required List<File> tracks,
    required File? currentFile,
    required bool isLiked,
    required String currentTitle,
    required String currentSubtitle,
    required double sliderValue,
    required double sliderMax,
    required bool hasKnownDuration,
    required bool canControlPlayback,
    required bool isCompactHeight,
    required double artworkSize,
    required double titleSize,
  }) {
    final header = <Widget>[
      SizedBox(height: isCompactHeight ? 12 : 22),
      Center(
        child: Container(
          width: artworkSize,
          height: artworkSize,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(42),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [colorScheme.primary, colorScheme.tertiary],
            ),
          ),
          child: Icon(
            Icons.music_note_rounded,
            size: artworkSize * 0.44,
            color: colorScheme.onPrimary.withValues(alpha: 0.92),
          ),
        ),
      ),
      SizedBox(height: isCompactHeight ? 16 : 30),
      SizedBox(
        height: 40,
        child: _AutoScrollingText(
          text: currentTitle,
          textStyle: textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w600,
            fontSize: titleSize,
          ),
        ),
      ),
      const SizedBox(height: 6),
      Text(
        currentSubtitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: isCompactHeight ? TextAlign.center : TextAlign.start,
        style: textTheme.bodyMedium?.copyWith(
          color: colorScheme.onSurface.withValues(alpha: 0.65),
        ),
      ),
      const SizedBox(height: 14),
      IconButton(
        onPressed: currentFile == null
            ? null
            : () => localMusicProvider.toggleTrackLike(currentFile.path),
        icon: Icon(
          isLiked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
        ),
        color: colorScheme.primary,
      ),
    ];

    final controls = <Widget>[
      Slider(
        value: sliderValue,
        max: sliderMax,
        onChanged: !hasKnownDuration
            ? null
            : (value) {
                audioProvider.seek(Duration(seconds: value.round()));
              },
      ),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            _formatDuration(audioProvider.position),
            style: textTheme.labelMedium?.copyWith(
              color: colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
          Text(
            _formatDuration(audioProvider.duration),
            style: textTheme.labelMedium?.copyWith(
              color: colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
      SizedBox(height: isCompactHeight ? 14 : 28),
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _ToggleCircleButton(
            active: audioProvider.shuffleEnabled,
            icon: Icons.shuffle_rounded,
            onTap: audioProvider.toggleShuffle,
          ),
          IconButton(
            onPressed: canControlPlayback
                ? () => audioProvider.skipToPreviousFromTracks(tracks)
                : null,
            icon: const Icon(Icons.skip_previous_rounded),
            iconSize: 34,
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: canControlPlayback
                ? () => audioProvider.playPauseFromTracks(tracks)
                : null,
            style: FilledButton.styleFrom(
              shape: const CircleBorder(),
              padding: const EdgeInsets.all(18),
            ),
            child: Icon(
              audioProvider.playing
                  ? Icons.pause_rounded
                  : Icons.play_arrow_rounded,
              size: 34,
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: canControlPlayback
                ? () => audioProvider.skipToNextFromTracks(tracks)
                : null,
            icon: const Icon(Icons.skip_next_rounded),
            iconSize: 34,
          ),
          _ToggleCircleButton(
            active: audioProvider.repeatOneEnabled,
            icon: Icons.repeat_rounded,
            onTap: audioProvider.toggleRepeatOne,
          ),
        ],
      ),
      SizedBox(height: isCompactHeight ? 10 : 0),
    ];

    if (isCompactHeight) {
      return ListView(
        padding: EdgeInsets.zero,
        children: [...header, const SizedBox(height: 8), ...controls],
      );
    }

    return Column(children: [...header, const Spacer(), ...controls]);
  }

  Widget _buildSideMenu(
    BuildContext context,
    LocalMusicProvider localMusicProvider,
    String activePlaylistId,
  ) {
    String t(String key) => AppLocalizations.text(context, key);
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final tracks = localMusicProvider.selectedFiles;
    final playlists = localMusicProvider.playlists;

    return Drawer(
      width: 320,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Row(
                children: [
                  Text(
                    t('menu'),
                    style: textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                t('playlists'),
                style: textTheme.labelLarge?.copyWith(
                  color: colorScheme.onSurface.withValues(alpha: 0.65),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  _PlaylistMenuCard(
                    title: t('all_songs'),
                    subtitle: '${tracks.length} ${t('tracks')}',
                    selected:
                        activePlaylistId == LocalMusicProvider.allPlaylistId,
                    onTap: () => _selectPlaylistAndStart(
                      context,
                      LocalMusicProvider.allPlaylistId,
                    ),
                  ),
                  _PlaylistMenuCard(
                    title: t('liked_songs'),
                    subtitle:
                        '${localMusicProvider.likedTracksCount} ${t('tracks')}',
                    selected:
                        activePlaylistId == LocalMusicProvider.likedPlaylistId,
                    onTap: () => _selectPlaylistAndStart(
                      context,
                      LocalMusicProvider.likedPlaylistId,
                    ),
                  ),
                  ...playlists.map(
                    (playlist) => _PlaylistMenuCard(
                      title: playlist.name,
                      subtitle: '${playlist.trackPaths.length} ${t('tracks')}',
                      selected: activePlaylistId == playlist.id,
                      onTap: () =>
                          _selectPlaylistAndStart(context, playlist.id),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
              child: Consumer<AuthProvider>(
                builder: (context, authProvider, child) {
                  final user = authProvider.currentUser;
                  return Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colorScheme.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: colorScheme.outline),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 18,
                          backgroundColor: colorScheme.secondary,
                          child: Icon(
                            Icons.person_rounded,
                            color: colorScheme.primary,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            user?.username ?? t('guest'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (user != null)
                          TextButton.icon(
                            onPressed: () => _confirmLogout(),
                            icon: const Icon(Icons.logout_rounded, size: 18),
                            label: Text(t('logout')),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.of(context).pop();
                    _openLanguageSettings(context);
                  },
                  icon: const Icon(Icons.language_rounded),
                  label: Text(t('language')),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.of(context).pop();
                    _openThemeSettings(context);
                  },
                  icon: const Icon(Icons.settings_rounded),
                  label: Text(t('settings')),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _selectPlaylistAndStart(BuildContext context, String playlistId) {
    setState(() {
      _selectedPlaylistId = playlistId;
    });
    Navigator.of(context).pop();
  }

  void _openThemeSettings(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => const ThemeSettingsSheet(),
    );
  }

  void _openLanguageSettings(BuildContext context) {
    String t(String key) => AppLocalizations.text(context, key);
    showModalBottomSheet<void>(
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
                Text(
                  t('select_language'),
                  style: Theme.of(
                    sheetContext,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
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

  String _formatDuration(Duration duration) {
    if (duration.inSeconds <= 0) return '--:--';

    String twoDigits(int value) => value.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));

    if (duration.inHours > 0) {
      return '${twoDigits(duration.inHours)}:$minutes:$seconds';
    }

    return '$minutes:$seconds';
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
    return SingleChildScrollView(
      controller: _scrollController,
      scrollDirection: Axis.horizontal,
      physics: const NeverScrollableScrollPhysics(),
      child: Text(widget.text, maxLines: 1, style: widget.textStyle),
    );
  }
}

class _TopActionButton extends StatelessWidget {
  const _TopActionButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: colorScheme.outline),
        ),
        child: Icon(icon, size: 20),
      ),
    );
  }
}

class _PlaylistMenuCard extends StatelessWidget {
  const _PlaylistMenuCard({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected ? colorScheme.secondary : colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? colorScheme.primary : colorScheme.outline,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                gradient: LinearGradient(
                  colors: [colorScheme.primary, colorScheme.tertiary],
                ),
              ),
              child: Icon(
                Icons.music_note_rounded,
                color: colorScheme.onPrimary,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: textTheme.bodyMedium),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: textTheme.labelMedium?.copyWith(
                      color: colorScheme.onSurface.withValues(alpha: 0.65),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ToggleCircleButton extends StatelessWidget {
  const _ToggleCircleButton({
    required this.active,
    required this.icon,
    required this.onTap,
  });

  final bool active;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: active ? colorScheme.primary : Colors.transparent,
        border: Border.all(
          color: active ? colorScheme.primary : colorScheme.outline,
        ),
      ),
      child: IconButton(
        onPressed: onTap,
        icon: Icon(icon),
        color: active
            ? colorScheme.onPrimary
            : colorScheme.onSurface.withValues(alpha: 0.6),
      ),
    );
  }
}
