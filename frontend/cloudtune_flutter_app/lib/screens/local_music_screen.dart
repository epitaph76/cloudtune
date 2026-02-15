import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../providers/local_music_provider.dart';
import 'dart:io';

class LocalMusicScreen extends StatelessWidget {
  const LocalMusicScreen({Key? key}) : super(key: key);

  Future<void> _pickFiles(BuildContext context) async {
    final localMusicProvider = Provider.of<LocalMusicProvider>(context, listen: false);
    
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.audio,  // Allow only audio files
        allowMultiple: true,   // Allow multiple file selection
      );

      if (result != null) {
        List<File> files = result.paths.map((path) => File(path!)).toList();
        
        localMusicProvider.addFiles(files);
      } else {
        // User canceled the picker
      }
    } catch (e) {
      // Handle errors
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка при выборе файлов: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<LocalMusicProvider>(
      builder: (context, localMusicProvider, child) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('Локальная музыка'),
            backgroundColor: Colors.blue,
            foregroundColor: Colors.white,
          ),
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: ElevatedButton(
                  onPressed: () => _pickFiles(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Выбрать музыкальные файлы'),
                ),
              ),
              Expanded(
                child: localMusicProvider.selectedFiles.isEmpty
                    ? const Center(
                        child: Text(
                          'Нет выбранных файлов. Нажмите кнопку выше, чтобы выбрать музыкальные файлы.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 16, color: Colors.grey),
                        ),
                      )
                    : ListView.builder(
                        itemCount: localMusicProvider.selectedFiles.length,
                        itemBuilder: (context, index) {
                          String fileName = localMusicProvider.selectedFiles[index].path.split('/').last;
                          return Card(
                            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            child: ListTile(
                              leading: const Icon(Icons.music_note, color: Colors.blue),
                              title: Text(
                                fileName,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                'Размер: ${(File(localMusicProvider.selectedFiles[index].path).lengthSync() / 1024 / 1024).toStringAsFixed(2)} MB',
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