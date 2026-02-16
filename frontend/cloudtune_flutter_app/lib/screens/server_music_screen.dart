import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/cloud_music_provider.dart';
import '../providers/local_music_provider.dart';
import '../models/track.dart';
import '../models/playlist.dart';
import 'dart:io';

class ServerMusicScreen extends StatefulWidget {
  const ServerMusicScreen({Key? key}) : super(key: key);

  @override
  State<ServerMusicScreen> createState() => _ServerMusicScreenState();
}

class _ServerMusicScreenState extends State<ServerMusicScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final cloudMusicProvider = Provider.of<CloudMusicProvider>(context, listen: false);
      cloudMusicProvider.fetchUserLibrary();
      cloudMusicProvider.fetchUserPlaylists();
    });
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
              // Список плейлистов (квадратные карточки)
              Container(
                height: 120,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                              Playlist playlist = cloudMusicProvider.playlists[index];
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
              
              // Разделитель
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text(
                  'Все треки',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              
              // Список треков (прямоугольные карточки как на 3-й странице)
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
                              Track track = cloudMusicProvider.tracks[index];
                              return Card(
                                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                child: ListTile(
                                  leading: const Icon(Icons.music_note, color: Colors.blue),
                                  title: Text(
                                    track.originalFilename ?? track.filename,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  subtitle: Text(
                                    'Размер: ${track.filesize != null ? (track.filesize! / 1024 / 1024).toStringAsFixed(2) : 'N/A'} MB',
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        icon: const Icon(Icons.download, color: Colors.green),
                                        onPressed: () async {
                                          // Получаем провайдеры до асинхронной операции
                                          final cloudMusicProvider = context.read<CloudMusicProvider>();
                                          final localMusicProvider = context.read<LocalMusicProvider>();
                                          
                                          // Получаем путь для сохранения файла
                                          String downloadsPath = Directory.systemTemp.path;
                                          String fileName = track.originalFilename ?? track.filename;
                                          String savePath = '$downloadsPath/$fileName';
                                          
                                          // Скачиваем трек
                                          bool success = await cloudMusicProvider.downloadTrack(track.id, savePath);
                                          
                                          if (success) {
                                            // Добавляем в локальное хранилище
                                            File downloadedFile = File(savePath);
                                            await localMusicProvider.addFiles([downloadedFile]);
                                            
                                            // Используем mounted для проверки, что виджет все еще в дереве
                                            if (mounted) {
                                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                                if (mounted) { // Проверяем снова, на случай, если состояние изменилось
                                                  ScaffoldMessenger.of(context).showSnackBar(
                                                    const SnackBar(
                                                      content: Text('Трек успешно скачан и добавлен в локальное хранилище'),
                                                      backgroundColor: Colors.green,
                                                    ),
                                                  );
                                                }
                                              });
                                            }
                                          } else {
                                            if (mounted) {
                                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                                if (mounted) { // Проверяем снова, на случай, если состояние изменилось
                                                  ScaffoldMessenger.of(context).showSnackBar(
                                                    const SnackBar(
                                                      content: Text('Ошибка при скачивании трека'),
                                                      backgroundColor: Colors.red,
                                                    ),
                                                  );
                                                }
                                              });
                                            }
                                          }
                                        },
                                      ),
                                    ],
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