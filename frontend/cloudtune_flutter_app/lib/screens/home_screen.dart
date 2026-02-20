import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../providers/audio_player_provider.dart';
import '../providers/local_music_provider.dart';
import '../widgets/theme_settings_sheet.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final Set<String> _likedTracks = <String>{};
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  String _selectedPlaylistId = 'all';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;

    return Consumer2<LocalMusicProvider, AudioPlayerProvider>(
      builder: (context, localMusicProvider, audioProvider, child) {
        final hasSelectedPlaylist =
            _selectedPlaylistId == 'all' ||
            localMusicProvider.playlists.any(
              (playlist) => playlist.id == _selectedPlaylistId,
            );
        final activePlaylistId = hasSelectedPlaylist ? _selectedPlaylistId : 'all';
        final tracks = localMusicProvider.getTracksForPlaylist(activePlaylistId);
        final hasTracks = tracks.isNotEmpty;
        final currentTrackPath = audioProvider.currentTrackPath;
        final currentTrackIndex = currentTrackPath == null
            ? -1
            : tracks.indexWhere((track) => track.path == currentTrackPath);
        final currentFile = hasTracks
            ? (currentTrackIndex >= 0 ? tracks[currentTrackIndex] : tracks.first)
            : null;
        final currentTitle = currentFile != null
            ? p.basenameWithoutExtension(currentFile.path)
            : 'No track selected';
        final currentSubtitle = currentFile != null
            ? p.basename(currentFile.path)
            : 'Add files in Storage > Local';
        final isLiked = currentFile != null
            ? _likedTracks.contains(currentFile.path)
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
          drawer: _buildSideMenu(
            context,
            localMusicProvider,
            activePlaylistId,
          ),
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
              child: Column(
                children: [
                  Row(
                    children: [
                      _TopActionButton(
                        icon: Icons.menu_rounded,
                        onTap: () => _scaffoldKey.currentState?.openDrawer(),
                      ),
                      const Spacer(),
                      Text(
                        'Minimal Player',
                        style: textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      _TopActionButton(
                        icon: Icons.music_note_rounded,
                        onTap: () =>
                            _openQueueSheet(context, tracks, audioProvider),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  if (!hasTracks)
                    Expanded(
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
                                'No local tracks yet',
                                style: textTheme.titleMedium,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Go to Storage tab and add files.',
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
                    )
                  else
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          children: [
                            const SizedBox(height: 22),
                            Container(
                              width: 312,
                              height: 312,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(42),
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    colorScheme.primary,
                                    colorScheme.tertiary,
                                  ],
                                ),
                              ),
                              child: Icon(
                                Icons.music_note_rounded,
                                size: 136,
                                color: colorScheme.onPrimary.withValues(
                                  alpha: 0.92,
                                ),
                              ),
                            ),
                            const SizedBox(height: 30),
                            Text(
                              currentTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w600,
                                fontSize: 31,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              currentSubtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: textTheme.bodyMedium?.copyWith(
                                color: colorScheme.onSurface.withValues(
                                  alpha: 0.65,
                                ),
                              ),
                            ),
                            const SizedBox(height: 14),
                            IconButton(
                              onPressed: currentFile == null
                                  ? null
                                  : () {
                                      setState(() {
                                        if (isLiked) {
                                          _likedTracks.remove(currentFile.path);
                                        } else {
                                          _likedTracks.add(currentFile.path);
                                        }
                                      });
                                    },
                              icon: Icon(
                                isLiked
                                    ? Icons.favorite_rounded
                                    : Icons.favorite_border_rounded,
                              ),
                              color: colorScheme.primary,
                            ),
                            const SizedBox(height: 12),
                            Slider(
                              value: sliderValue,
                              max: sliderMax,
                              onChanged: !hasKnownDuration
                                  ? null
                                  : (value) {
                                      audioProvider.seek(
                                        Duration(seconds: value.round()),
                                      );
                                    },
                            ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  _formatDuration(audioProvider.position),
                                  style: textTheme.labelMedium?.copyWith(
                                    color: colorScheme.onSurface.withValues(
                                      alpha: 0.6,
                                    ),
                                  ),
                                ),
                                Text(
                                  _formatDuration(audioProvider.duration),
                                  style: textTheme.labelMedium?.copyWith(
                                    color: colorScheme.onSurface.withValues(
                                      alpha: 0.6,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 28),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                _ToggleCircleButton(
                                  active: audioProvider.shuffleEnabled,
                                  icon: Icons.shuffle_rounded,
                                  onTap: audioProvider.toggleShuffle,
                                ),
                                IconButton(
                                  onPressed: hasTracks
                                      ? () => audioProvider
                                            .skipToPreviousFromTracks(tracks)
                                      : null,
                                  icon: const Icon(Icons.skip_previous_rounded),
                                  iconSize: 34,
                                ),
                                const SizedBox(width: 8),
                                FilledButton(
                                  onPressed: hasTracks
                                      ? () =>
                                          audioProvider.playPauseFromTracks(tracks)
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
                                  onPressed: hasTracks
                                      ? () =>
                                            audioProvider.skipToNextFromTracks(
                                              tracks,
                                            )
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
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSideMenu(
    BuildContext context,
    LocalMusicProvider localMusicProvider,
    String activePlaylistId,
  ) {
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
                    'Menu',
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
                'Playlists',
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
                    title: 'All songs',
                    subtitle: '${tracks.length} tracks',
                    selected: activePlaylistId == 'all',
                    onTap: () => _selectPlaylistAndStart(context, 'all'),
                  ),
                  ...playlists.map(
                    (playlist) => _PlaylistMenuCard(
                      title: playlist.name,
                      subtitle: '${playlist.trackPaths.length} tracks',
                      selected: activePlaylistId == playlist.id,
                      onTap: () =>
                          _selectPlaylistAndStart(context, playlist.id),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.of(context).pop();
                    _openThemeSettings(context);
                  },
                  icon: const Icon(Icons.settings_rounded),
                  label: const Text('Settings'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _selectPlaylistAndStart(
    BuildContext context,
    String playlistId,
  ) async {
    final localMusicProvider = context.read<LocalMusicProvider>();
    final audioProvider = context.read<AudioPlayerProvider>();

    setState(() {
      _selectedPlaylistId = playlistId;
    });
    Navigator.of(context).pop();

    final tracks = localMusicProvider.getTracksForPlaylist(playlistId);
    if (tracks.isEmpty) return;
    await audioProvider.playFromTracks(tracks, initialIndex: 0);
  }

  void _openThemeSettings(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => const ThemeSettingsSheet(),
    );
  }

  void _openQueueSheet(
    BuildContext context,
    List<File> tracks,
    AudioPlayerProvider audioProvider,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;

    if (tracks.isEmpty) return;

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: SizedBox(
              height: MediaQuery.of(sheetContext).size.height * 0.6,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Playback Queue',
                    style: textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: Consumer<AudioPlayerProvider>(
                      builder: (context, queueProvider, child) {
                        return ListView.separated(
                          itemCount: tracks.length,
                          separatorBuilder: (context, index) =>
                              const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final track = tracks[index];
                            final isCurrent = queueProvider.isCurrentTrackPath(
                              track.path,
                            );
                            final title = p.basenameWithoutExtension(
                              track.path,
                            );

                            return InkWell(
                              borderRadius: BorderRadius.circular(16),
                              onTap: () async {
                                await queueProvider.playFromTracks(
                                  tracks,
                                  initialIndex: index,
                                );
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(16),
                                  color: isCurrent
                                      ? colorScheme.secondary
                                      : colorScheme.surface,
                                  border: Border.all(
                                    color: colorScheme.outline,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 42,
                                      height: 42,
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(12),
                                        gradient: LinearGradient(
                                          colors: [
                                            colorScheme.primary,
                                            colorScheme.tertiary,
                                          ],
                                        ),
                                      ),
                                      child: Icon(
                                        Icons.music_note_rounded,
                                        color: colorScheme.onPrimary,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    IconButton(
                                      onPressed: () async {
                                        await queueProvider.toggleTrackFromTracks(
                                          tracks,
                                          index,
                                        );
                                      },
                                      icon: Icon(
                                        isCurrent && queueProvider.playing
                                            ? Icons.pause_rounded
                                            : Icons.play_arrow_rounded,
                                      ),
                                      color: colorScheme.primary,
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
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
        color: active
            ? colorScheme.primary
            : Colors.transparent,
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
