import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../providers/cloud_music_provider.dart';
import '../providers/local_music_provider.dart';
import '../services/api_service.dart';

class LocalMusicScreen extends StatefulWidget {
  const LocalMusicScreen({super.key});

  @override
  State<LocalMusicScreen> createState() => _LocalMusicScreenState();
}

class _LocalMusicScreenState extends State<LocalMusicScreen> {
  final ApiService _apiService = ApiService();
  bool _isPickingFiles = false;
  final Set<String> _uploadingPaths = <String>{};

  Future<void> _pickFiles(BuildContext context) async {
    if (_isPickingFiles) return;

    setState(() {
      _isPickingFiles = true;
    });

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.audio,
        allowMultiple: true,
      );

      if (result == null) return;

      final files = result.paths.whereType<String>().map(File.new).toList();
      if (files.isEmpty) return;

      if (!context.mounted) return;
      await context.read<LocalMusicProvider>().addFiles(files);
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('File picker error: $error')));
    } finally {
      if (mounted) {
        setState(() {
          _isPickingFiles = false;
        });
      }
    }
  }

  Future<void> _uploadTrack(
    BuildContext context,
    File file,
    CloudMusicProvider cloudMusicProvider,
  ) async {
    if (_uploadingPaths.contains(file.path)) return;

    setState(() {
      _uploadingPaths.add(file.path);
    });

    try {
      final result = await _apiService.uploadFile(file);
      if (!context.mounted) return;

      if (result['success'] == true) {
        await cloudMusicProvider.fetchUserLibrary(reset: true);
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Uploaded: ${p.basename(file.path)}')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Upload failed: ${result['message']}')),
        );
      }
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Upload error: $error')));
    } finally {
      if (mounted) {
        setState(() {
          _uploadingPaths.remove(file.path);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;

    return Consumer2<LocalMusicProvider, CloudMusicProvider>(
      builder: (context, localMusicProvider, cloudMusicProvider, child) {
        final tracks = localMusicProvider.selectedFiles;

        return Scaffold(
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Local Library',
                    style: textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${tracks.length} tracks saved',
                    style: textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurface.withValues(alpha: 0.65),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _isPickingFiles
                          ? null
                          : () => _pickFiles(context),
                      icon: _isPickingFiles
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.add_rounded),
                      label: Text(
                        _isPickingFiles ? 'Adding...' : 'Add audio files',
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: tracks.isEmpty
                        ? Center(
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: colorScheme.surface,
                                borderRadius: BorderRadius.circular(22),
                                border: Border.all(color: colorScheme.outline),
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.library_music_rounded,
                                    size: 60,
                                    color: colorScheme.onSurface.withValues(
                                      alpha: 0.5,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    'Local list is empty',
                                    style: textTheme.titleMedium,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Use "Add audio files" to start your collection.',
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
                          )
                        : ListView.separated(
                            itemCount: tracks.length,
                            separatorBuilder: (context, index) =>
                                const SizedBox(height: 10),
                            itemBuilder: (context, index) {
                              final track = tracks[index];
                              final uploading = _uploadingPaths.contains(
                                track.path,
                              );

                              return Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: colorScheme.surface,
                                  borderRadius: BorderRadius.circular(18),
                                  border: Border.all(
                                    color: colorScheme.outline,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 46,
                                      height: 46,
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(14),
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
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            p.basename(track.path),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            _humanFileSize(track),
                                            style: textTheme.labelMedium
                                                ?.copyWith(
                                                  color: colorScheme.onSurface
                                                      .withValues(alpha: 0.65),
                                                ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    IconButton.filledTonal(
                                      onPressed: uploading
                                          ? null
                                          : () => _uploadTrack(
                                              context,
                                              track,
                                              cloudMusicProvider,
                                            ),
                                      icon: uploading
                                          ? const SizedBox(
                                              width: 16,
                                              height: 16,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                              ),
                                            )
                                          : const Icon(
                                              Icons.cloud_upload_rounded,
                                            ),
                                      tooltip: 'Upload to cloud',
                                    ),
                                  ],
                                ),
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

  String _humanFileSize(File file) {
    try {
      final bytes = file.lengthSync();
      final megabytes = bytes / 1024 / 1024;
      return '${megabytes.toStringAsFixed(2)} MB';
    } catch (_) {
      return 'Unknown size';
    }
  }
}
