import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../models/playlist.dart';
import '../models/track.dart';
import '../providers/cloud_music_provider.dart';
import '../providers/local_music_provider.dart';

class ServerMusicScreen extends StatefulWidget {
  const ServerMusicScreen({super.key});

  @override
  State<ServerMusicScreen> createState() => _ServerMusicScreenState();
}

class _ServerMusicScreenState extends State<ServerMusicScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final cloudMusicProvider =
          Provider.of<CloudMusicProvider>(context, listen: false);
      cloudMusicProvider.fetchUserLibrary();
      cloudMusicProvider.fetchUserPlaylists();
    });
  }

  Future<Directory> _getPersistentDownloadDir() async {
    final Directory? baseExternalDir = await getExternalStorageDirectory();
    final Directory baseDir =
        baseExternalDir ?? await getApplicationDocumentsDirectory();

    final Directory cloudTuneDir = Directory(p.join(baseDir.path, 'CloudTune'));
    if (!await cloudTuneDir.exists()) {
      await cloudTuneDir.create(recursive: true);
    }

    return cloudTuneDir;
  }

  Future<void> _downloadTrack(
    CloudMusicProvider cloudMusicProvider,
    LocalMusicProvider localMusicProvider,
    Track track,
  ) async {
    final fileName = track.originalFilename ?? track.filename;
    final persistentDir = await _getPersistentDownloadDir();
    final savePath = p.join(persistentDir.path, fileName);

    final success = await cloudMusicProvider.downloadTrack(track.id, savePath);
    if (!mounted) return;

    if (success) {
      await localMusicProvider.addFiles([File(savePath)]);
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Трек сохранен: $savePath'),
          backgroundColor: Colors.green,
        ),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Ошибка при скачивании трека'),
        backgroundColor: Colors.red,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<CloudMusicProvider>(
      builder: (context, cloudMusicProvider, child) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('Облачное хранилище'),
            backgroundColor: Colors.blue,
            foregroundColor: Colors.white,
          ),
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 120,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: cloudMusicProvider.isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : cloudMusicProvider.playlists.isEmpty
                        ? const Padding(
                            padding: EdgeInsets.all(16),
                            child: Text(
                              'Нет плейлистов',
                              style: TextStyle(color: Colors.grey),
                            ),
                          )
                        : ListView.builder(
                            scrollDirection: Axis.horizontal,
                            itemCount: cloudMusicProvider.playlists.length,
                            itemBuilder: (context, index) {
                              final Playlist playlist =
                                  cloudMusicProvider.playlists[index];
                              return Container(
                                width: 100,
                                margin: const EdgeInsets.only(right: 12),
                                child: Card(
                                  elevation: 4,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(
                                        Icons.playlist_play,
                                        size: 40,
                                        color: Colors.blue,
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        playlist.name.length > 10
                                            ? '${playlist.name.substring(0, 10)}...'
                                            : playlist.name,
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text(
                  'Все треки',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              Expanded(
                child: cloudMusicProvider.isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : cloudMusicProvider.tracks.isEmpty
                        ? const Center(
                            child: Text(
                              'Нет треков в облачном хранилище',
                              style: TextStyle(fontSize: 16, color: Colors.grey),
                            ),
                          )
                        : ListView.builder(
                            itemCount: cloudMusicProvider.tracks.length,
                            itemBuilder: (context, index) {
                              final Track track = cloudMusicProvider.tracks[index];
                              return Card(
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 8,
                                ),
                                child: ListTile(
                                  leading: const Icon(
                                    Icons.music_note,
                                    color: Colors.blue,
                                  ),
                                  title: Text(
                                    track.originalFilename ?? track.filename,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  subtitle: Text(
                                    'Размер: ${track.filesize != null ? (track.filesize! / 1024 / 1024).toStringAsFixed(2) : 'N/A'} MB',
                                  ),
                                  trailing: IconButton(
                                    icon: const Icon(
                                      Icons.download,
                                      color: Colors.green,
                                    ),
                                    onPressed: () async {
                                      final localMusicProvider =
                                          context.read<LocalMusicProvider>();
                                      await _downloadTrack(
                                        cloudMusicProvider,
                                        localMusicProvider,
                                        track,
                                      );
                                    },
                                  ),
                                ),
                              );
                            },
                          ),
              ),
            ],
          ),
        );
      },
    );
  }
}
