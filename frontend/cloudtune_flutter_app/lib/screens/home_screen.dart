import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/audio_player_provider.dart';
import '../providers/local_music_provider.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Главная'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: Consumer2<LocalMusicProvider, AudioPlayerProvider>(
        builder: (context, localMusicProvider, audioProvider, child) {
          final tracks = localMusicProvider.selectedFiles;

          if (tracks.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.music_off, size: 100, color: Colors.grey),
                  SizedBox(height: 20),
                  Text(
                    'Нет загруженных треков',
                    style: TextStyle(fontSize: 18, color: Colors.grey),
                  ),
                  SizedBox(height: 10),
                  Text(
                    'Перейдите во вкладку "Локальная музыка", чтобы добавить файлы',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: Colors.grey),
                  ),
                ],
              ),
            );
          }

          return Column(
            children: [
              if (audioProvider.audioFiles.isNotEmpty)
                Container(
                  padding: const EdgeInsets.all(16),
                  child: Card(
                    elevation: 4,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.skip_previous),
                                onPressed: audioProvider.skipToPrevious,
                              ),
                              IconButton(
                                icon: Icon(
                                  audioProvider.playing
                                      ? Icons.pause
                                      : Icons.play_arrow,
                                ),
                                iconSize: 48,
                                onPressed: audioProvider.playPause,
                              ),
                              IconButton(
                                icon: const Icon(Icons.skip_next),
                                onPressed: audioProvider.skipToNext,
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          if (audioProvider.duration.inSeconds > 0)
                            Column(
                              children: [
                                Slider(
                                  value: audioProvider.position.inSeconds
                                      .toDouble()
                                      .clamp(
                                        0.0,
                                        audioProvider.duration.inSeconds
                                            .toDouble(),
                                      )
                                      .toDouble(),
                                  min: 0.0,
                                  max: audioProvider.duration.inSeconds.toDouble(),
                                  onChanged: (value) => audioProvider
                                      .seek(Duration(seconds: value.toInt())),
                                ),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      _formatDuration(audioProvider.position),
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                    Text(
                                      _formatDuration(audioProvider.duration),
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              Expanded(
                child: ListView.builder(
                  itemCount: tracks.length,
                  itemBuilder: (context, index) {
                    final fileName = tracks[index].path.split('/').last;
                    return Card(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: audioProvider.isCurrentTrack(index)
                              ? Colors.blue
                              : Colors.grey[300],
                          child: Icon(
                            audioProvider.isCurrentTrack(index)
                                ? Icons.music_note
                                : Icons.audiotrack,
                            color: audioProvider.isCurrentTrack(index)
                                ? Colors.white
                                : Colors.blue,
                          ),
                        ),
                        title: Text(fileName, overflow: TextOverflow.ellipsis),
                        subtitle: Text(
                          tracks[index].path,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: IconButton(
                          icon: Icon(
                            audioProvider.isTrackPlaying(index)
                                ? Icons.pause
                                : Icons.play_arrow,
                          ),
                          onPressed: () => audioProvider.toggleTrackAt(index),
                        ),
                        onTap: () => audioProvider.toggleTrackAt(index),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    final twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    return '${twoDigits(duration.inHours)}:$twoDigitMinutes:$twoDigitSeconds';
  }
}
