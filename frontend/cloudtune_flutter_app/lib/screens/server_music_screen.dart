import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../models/track.dart';
import '../models/playlist.dart';
import '../providers/auth_provider.dart';
import '../providers/cloud_music_provider.dart';
import '../providers/local_music_provider.dart';
import '../providers/main_nav_provider.dart';
import '../services/api_service.dart';

enum _StorageType { local, cloud }

class _FolderImportFilters {
  const _FolderImportFilters({
    required this.allowedExtensions,
    required this.applyDurationFilter,
    required this.minDuration,
    required this.maxDuration,
  });

  final Set<String> allowedExtensions;
  final bool applyDurationFilter;
  final Duration minDuration;
  final Duration maxDuration;
}

class ServerMusicScreen extends StatefulWidget {
  const ServerMusicScreen({super.key});

  @override
  State<ServerMusicScreen> createState() => _ServerMusicScreenState();
}

class _ServerMusicScreenState extends State<ServerMusicScreen> {
  static const double _storageHeaderControlWidth = 130;
  static const double _storageHeaderControlHeight = 40;

  final ApiService _apiService = ApiService();
  final Set<int> _downloadingTrackIds = <int>{};
  final Set<String> _uploadingPaths = <String>{};
  final Set<String> _syncingLocalPlaylistIds = <String>{};
  final Set<int> _downloadingCloudPlaylistIds = <int>{};
  final Set<int> _deletingCloudPlaylistIds = <int>{};
  final Set<int> _loadingCloudPlaylistIds = <int>{};
  final Map<int, List<Track>> _cloudPlaylistTracksCache = <int, List<Track>>{};

  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  _StorageType _storageType = _StorageType.local;
  String _selectedLocalPlaylistId = 'all';
  int? _selectedCloudPlaylistId;
  static const double _storageSwipeVelocityThreshold = 280;

  static const List<String> _supportedAudioExtensions = <String>[
    '.mp3',
    '.wav',
    '.flac',
    '.m4a',
    '.aac',
    '.ogg',
    '.opus',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshCloudData());
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _refreshCloudData() async {
    if (!mounted) return;
    final cloudMusicProvider = context.read<CloudMusicProvider>();
    await Future.wait([
      cloudMusicProvider.fetchUserLibrary(),
      cloudMusicProvider.fetchUserPlaylists(),
    ]);
    _cloudPlaylistTracksCache.clear();

    final selectedId = _selectedCloudPlaylistId;
    if (selectedId != null &&
        !cloudMusicProvider.playlists.any((item) => item.id == selectedId)) {
      setState(() {
        _selectedCloudPlaylistId = null;
      });
    }

    final selectedCloudPlaylistId = _selectedCloudPlaylistId;
    if (selectedCloudPlaylistId != null) {
      final result = await _apiService.getPlaylistSongs(selectedCloudPlaylistId);
      if (result['success'] == true) {
        _cloudPlaylistTracksCache[selectedCloudPlaylistId] =
            (result['songs'] as List<dynamic>)
                .map((item) => Track.fromJson(item as Map<String, dynamic>))
                .toList();
      }
    }
  }

  Future<void> _pickLocalFiles() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.audio,
      allowMultiple: true,
    );
    if (result == null || !mounted) return;

    final files = result.paths.whereType<String>().map(File.new).toList();
    if (files.isEmpty) return;

    await context.read<LocalMusicProvider>().addFiles(files);
  }

  Future<void> _showUploadOptions() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.audiotrack_rounded),
                  title: const Text('Upload tracks'),
                  subtitle: const Text('Pick one or multiple audio files'),
                  onTap: () async {
                    Navigator.of(sheetContext).pop();
                    await _pickLocalFiles();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.folder_rounded),
                  title: const Text('Pick folder'),
                  subtitle: const Text(
                    'Import files from folder with filters',
                  ),
                  onTap: () async {
                    Navigator.of(sheetContext).pop();
                    await _pickLocalFolderWithFilters();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _pickLocalFolderWithFilters() async {
    final localMusicProvider = context.read<LocalMusicProvider>();
    final rawDirectoryPath = await FilePicker.platform.getDirectoryPath();
    if (rawDirectoryPath == null || !mounted) return;

    final directoryPath = _normalizePickedDirectoryPath(rawDirectoryPath);
    if (directoryPath == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Can not access this folder directly on Android. Use "Upload tracks" and select files.',
          ),
        ),
      );
      return;
    }

    final filters = await _showFolderImportFilters();
    if (filters == null || !mounted) return;

    final hasPermission = await _ensureFolderImportPermission();
    if (!mounted) return;
    if (!hasPermission) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Storage permission denied. Grant permission to import from folder.',
          ),
        ),
      );
      return;
    }

    final files = await _collectAudioFilesFromFolder(
      directoryPath: directoryPath,
      filters: filters,
    );
    if (!mounted) return;

    if (files.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No matching files in: $directoryPath'),
        ),
      );
      return;
    }

    await localMusicProvider.addFiles(files);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Imported ${files.length} files')),
    );
  }

  Future<_FolderImportFilters?> _showFolderImportFilters() async {
    const maxMinutes = 30.0;
    final selectedExtensions = _supportedAudioExtensions.toSet();
    RangeValues durationRange = const RangeValues(0, 30);
    var applyDurationFilter = false;

    return showModalBottomSheet<_FolderImportFilters>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final textTheme = Theme.of(context).textTheme;
            return SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: SizedBox(
                  height: MediaQuery.of(context).size.height * 0.68,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Folder import filters',
                        style: textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Extensions',
                        style: textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _supportedAudioExtensions.map((extension) {
                          final selected = selectedExtensions.contains(extension);
                          return FilterChip(
                            selected: selected,
                            label: Text(extension.replaceFirst('.', '').toUpperCase()),
                            onSelected: (value) {
                              setModalState(() {
                                if (value) {
                                  selectedExtensions.add(extension);
                                } else if (selectedExtensions.length > 1) {
                                  selectedExtensions.remove(extension);
                                }
                              });
                            },
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 20),
                      SwitchListTile(
                        value: applyDurationFilter,
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          'Filter by duration',
                          style: textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: const Text(
                          'If disabled, duration is ignored',
                        ),
                        onChanged: (value) {
                          setModalState(() => applyDurationFilter = value);
                        },
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Duration (${durationRange.start.round()}-${durationRange.end.round()} min)',
                        style: textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      RangeSlider(
                        values: durationRange,
                        min: 0,
                        max: maxMinutes,
                        divisions: maxMinutes.toInt(),
                        labels: RangeLabels(
                          '${durationRange.start.round()}m',
                          '${durationRange.end.round()}m',
                        ),
                        onChanged: applyDurationFilter
                            ? (value) {
                                setModalState(() => durationRange = value);
                              }
                            : null,
                      ),
                      const Spacer(),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: () {
                            Navigator.of(sheetContext).pop(
                              _FolderImportFilters(
                                allowedExtensions: Set<String>.from(selectedExtensions),
                                applyDurationFilter: applyDurationFilter,
                                minDuration: Duration(
                                  minutes: durationRange.start.round(),
                                ),
                                maxDuration: Duration(
                                  minutes: durationRange.end.round(),
                                ),
                              ),
                            );
                          },
                          child: const Text('Import from folder'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<List<File>> _collectAudioFilesFromFolder({
    required String directoryPath,
    required _FolderImportFilters filters,
  }) async {
    final directory = Directory(directoryPath);
    if (!await directory.exists()) return const <File>[];

    final entities = await directory.list(
      recursive: true,
      followLinks: false,
    ).toList();
    final matchingFiles = <File>[];
    AudioPlayer? probePlayer;

    if (filters.applyDurationFilter) {
      probePlayer = AudioPlayer();
    }

    try {
      for (final entity in entities) {
        if (entity is! File) continue;

        final extension = p.extension(entity.path).toLowerCase();
        if (!filters.allowedExtensions.contains(extension)) continue;

        if (filters.applyDurationFilter) {
          final duration = await _readAudioDuration(entity, probePlayer!);
          if (duration == null) continue;

          if (duration < filters.minDuration || duration > filters.maxDuration) {
            continue;
          }
        }
        matchingFiles.add(entity);
      }
    } finally {
      await probePlayer?.dispose();
    }

    return matchingFiles;
  }

  String? _normalizePickedDirectoryPath(String rawPath) {
    String normalized = rawPath.trim();

    if (normalized.isEmpty) return null;

    if (normalized.startsWith('content://')) {
      final decoded = Uri.decodeFull(normalized);
      final lastPrimaryIndex = decoded.lastIndexOf('primary:');
      if (lastPrimaryIndex != -1) {
        var relative = decoded.substring(lastPrimaryIndex + 'primary:'.length);
        final queryIndex = relative.indexOf('?');
        if (queryIndex != -1) {
          relative = relative.substring(0, queryIndex);
        }
        normalized = relative.isEmpty
            ? '/storage/emulated/0'
            : '/storage/emulated/0/$relative';
      }
    } else if (normalized.startsWith('primary:')) {
      final relative = normalized.substring('primary:'.length);
      normalized = relative.isEmpty
          ? '/storage/emulated/0'
          : '/storage/emulated/0/$relative';
    }

    if (!normalized.startsWith('/')) return null;
    return normalized;
  }

  Future<bool> _ensureFolderImportPermission() async {
    if (!Platform.isAndroid) return true;

    final audioStatus = await Permission.audio.status;
    if (audioStatus.isGranted) return true;

    final storageStatus = await Permission.storage.status;
    if (storageStatus.isGranted) return true;

    final requestedAudio = await Permission.audio.request();
    if (requestedAudio.isGranted) return true;

    final requestedStorage = await Permission.storage.request();
    if (requestedStorage.isGranted) return true;

    final manageStatus = await Permission.manageExternalStorage.status;
    if (manageStatus.isGranted) return true;

    final requestedManage = await Permission.manageExternalStorage.request();
    return requestedManage.isGranted;
  }

  Future<Duration?> _readAudioDuration(File file, AudioPlayer player) async {
    try {
      await player.setFilePath(file.path);
      return player.duration;
    } catch (_) {
      return null;
    }
  }

  Future<Directory> _getPersistentDownloadDir() async {
    final baseExternalDir = await getExternalStorageDirectory();
    final baseDir = baseExternalDir ?? await getApplicationDocumentsDirectory();
    final cloudTuneDir = Directory(p.join(baseDir.path, 'CloudTune'));

    if (!await cloudTuneDir.exists()) {
      await cloudTuneDir.create(recursive: true);
    }
    return cloudTuneDir;
  }

  Future<void> _downloadTrack(Track track) async {
    if (_downloadingTrackIds.contains(track.id)) return;
    setState(() => _downloadingTrackIds.add(track.id));

    final cloudMusicProvider = context.read<CloudMusicProvider>();
    final localMusicProvider = context.read<LocalMusicProvider>();

    try {
      final fileName = track.originalFilename ?? track.filename;
      final targetDir = await _getPersistentDownloadDir();
      final savePath = p.join(targetDir.path, fileName);

      final success = await cloudMusicProvider.downloadTrack(
        track.id,
        savePath,
      );
      if (!mounted) return;

      if (success) {
        await localMusicProvider.addFiles([File(savePath)]);
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Downloaded: $fileName')));
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Download failed')));
      }
    } finally {
      if (mounted) {
        setState(() => _downloadingTrackIds.remove(track.id));
      }
    }
  }

  Future<void> _uploadLocalTrack(File file) async {
    if (_uploadingPaths.contains(file.path)) return;
    setState(() => _uploadingPaths.add(file.path));

    try {
      final result = await _apiService.uploadFile(file);
      if (!mounted) return;

      if (result['success'] == true) {
        await _refreshCloudData();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Uploaded: ${p.basename(file.path)}')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Upload failed: ${result['message']}')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _uploadingPaths.remove(file.path));
      }
    }
  }

  Future<void> _submitCloudLogin(AuthProvider authProvider) async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    if (email.isEmpty || password.isEmpty) return;

    final ok = await authProvider.login(email, password);
    if (!mounted) return;

    if (ok) {
      _passwordController.clear();
      await _refreshCloudData();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Cloud login successful')));
    } else if (authProvider.errorMessage != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(authProvider.errorMessage!)));
    }
  }

  List<File> _localTracksForSelectedPlaylist(
    LocalMusicProvider localMusicProvider,
  ) {
    return localMusicProvider.getTracksForPlaylist(_selectedLocalPlaylistId);
  }

  void _openCreatePlaylistDialog(
    List<File> localTracks,
    LocalMusicProvider localMusicProvider,
  ) {
    if (localTracks.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Add local tracks first')));
      return;
    }

    var playlistName = '';
    final selectedPaths = <String>{};

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final colorScheme = Theme.of(context).colorScheme;
            final textTheme = Theme.of(context).textTheme;

            return SafeArea(
              top: false,
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  16,
                  8,
                  16,
                  16 + MediaQuery.of(context).viewInsets.bottom,
                ),
                child: SizedBox(
                  height: MediaQuery.of(context).size.height * 0.72,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Create playlist',
                        style: textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        onChanged: (value) {
                          playlistName = value;
                        },
                        decoration: const InputDecoration(
                          labelText: 'Playlist name',
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Select tracks',
                        style: textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: ListView.separated(
                          itemCount: localTracks.length,
                          separatorBuilder: (context, index) =>
                              const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final file = localTracks[index];
                            final isSelected = selectedPaths.contains(
                              file.path,
                            );

                            return InkWell(
                              borderRadius: BorderRadius.circular(14),
                              onTap: () {
                                setModalState(() {
                                  if (isSelected) {
                                    selectedPaths.remove(file.path);
                                  } else {
                                    selectedPaths.add(file.path);
                                  }
                                });
                              },
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? colorScheme.primary
                                      : colorScheme.surface,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: isSelected
                                        ? colorScheme.primary
                                        : colorScheme.outline,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.music_note_rounded,
                                      color: isSelected
                                          ? colorScheme.onPrimary
                                          : colorScheme.primary,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        p.basename(file.path),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: isSelected
                                              ? colorScheme.onPrimary
                                              : colorScheme.onSurface,
                                        ),
                                      ),
                                    ),
                                    if (isSelected)
                                      Icon(
                                        Icons.check_rounded,
                                        color: colorScheme.onPrimary,
                                      ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: () {
                            final name = playlistName.trim();
                            if (name.isEmpty || selectedPaths.isEmpty) return;

                            localMusicProvider
                                .createPlaylist(
                                  name: name,
                                  trackPaths: Set<String>.from(selectedPaths),
                                )
                                .then((playlistId) {
                                  if (!mounted || playlistId == null) return;
                                  setState(() {
                                    _selectedLocalPlaylistId = playlistId;
                                  });
                                });

                            Navigator.of(sheetContext).pop();
                          },
                          child: const Text('Create playlist'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _deleteLocalPlaylist(String playlistId) {
    context.read<LocalMusicProvider>().deletePlaylist(playlistId);
    if (_selectedLocalPlaylistId == playlistId) {
      setState(() {
        _selectedLocalPlaylistId = 'all';
      });
    }
  }

  Future<void> _uploadLocalPlaylistToCloud({
    required LocalPlaylist playlist,
    required LocalMusicProvider localMusicProvider,
    required CloudMusicProvider cloudMusicProvider,
  }) async {
    if (_syncingLocalPlaylistIds.contains(playlist.id)) return;

    final playlistTracks = localMusicProvider
        .getTracksForPlaylist(playlist.id)
        .toList();
    if (playlistTracks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Playlist "${playlist.name}" is empty')),
      );
      return;
    }

    setState(() => _syncingLocalPlaylistIds.add(playlist.id));

    try {
      // Ensure cloud library is fresh before matching local files.
      await cloudMusicProvider.fetchUserLibrary();
      final cloudByOriginalName = <String, int>{};
      for (final item in cloudMusicProvider.tracks) {
        final key = (item.originalFilename ?? item.filename).toLowerCase();
        cloudByOriginalName[key] = item.id;
      }

      final songIDsInOrder = <int>[];
      for (final file in playlistTracks) {
        final fileName = p.basename(file.path).toLowerCase();
        int? songId = cloudByOriginalName[fileName];

        if (songId == null) {
          final uploadResult = await _apiService.uploadFile(file);
          if (uploadResult['success'] == true) {
            final rawSongID = uploadResult['data']?['song_id'];
            if (rawSongID is int) {
              songId = rawSongID;
            } else if (rawSongID is num) {
              songId = rawSongID.toInt();
            } else if (rawSongID is String) {
              songId = int.tryParse(rawSongID);
            }
            if (songId != null) {
              cloudByOriginalName[fileName] = songId;
            }
          }
        }

        if (songId != null) {
          songIDsInOrder.add(songId);
        }
      }

      if (songIDsInOrder.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'No tracks from "${playlist.name}" were uploaded/matched in cloud',
            ),
          ),
        );
        return;
      }

      final createResult = await _apiService.createPlaylist(
        name: playlist.name,
        description: 'Synced from local',
      );
      if (createResult['success'] != true) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Cloud playlist create failed: ${createResult['message']}'),
          ),
        );
        return;
      }

      final rawPlaylistID = createResult['playlist_id'];
      int? cloudPlaylistID;
      if (rawPlaylistID is int) {
        cloudPlaylistID = rawPlaylistID;
      } else if (rawPlaylistID is num) {
        cloudPlaylistID = rawPlaylistID.toInt();
      } else if (rawPlaylistID is String) {
        cloudPlaylistID = int.tryParse(rawPlaylistID);
      }
      if (cloudPlaylistID == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cloud playlist id missing in response')),
        );
        return;
      }

      final added = <int>{};
      for (final songID in songIDsInOrder) {
        if (added.contains(songID)) continue;
        added.add(songID);
        await _apiService.addSongToPlaylist(
          playlistId: cloudPlaylistID,
          songId: songID,
        );
      }

      await _refreshCloudData();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Playlist "${playlist.name}" synced to cloud')),
      );
    } finally {
      if (mounted) {
        setState(() => _syncingLocalPlaylistIds.remove(playlist.id));
      }
    }
  }

  Future<void> _downloadCloudPlaylistToLocal({
    required Playlist playlist,
    required LocalMusicProvider localMusicProvider,
    required CloudMusicProvider cloudMusicProvider,
  }) async {
    if (_downloadingCloudPlaylistIds.contains(playlist.id)) return;
    setState(() => _downloadingCloudPlaylistIds.add(playlist.id));

    try {
      final result = await _apiService.getPlaylistSongs(playlist.id);
      if (result['success'] != true) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load cloud playlist: ${result['message']}'),
          ),
        );
        return;
      }

      final songs = (result['songs'] as List<dynamic>)
          .map((item) => Track.fromJson(item as Map<String, dynamic>))
          .toList();
      if (songs.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Cloud playlist "${playlist.name}" is empty')),
        );
        return;
      }

      final targetDir = await _getPersistentDownloadDir();
      final downloadedFiles = <File>[];
      for (final song in songs) {
        final fileName = song.originalFilename ?? song.filename;
        final savePath = p.join(targetDir.path, fileName);
        final file = File(savePath);
        if (await file.exists()) {
          downloadedFiles.add(file);
          continue;
        }

        final ok = await cloudMusicProvider.downloadTrack(song.id, savePath);
        if (ok) {
          downloadedFiles.add(File(savePath));
        }
      }

      if (downloadedFiles.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No tracks downloaded from "${playlist.name}"')),
        );
        return;
      }

      await localMusicProvider.addFiles(downloadedFiles);
      final localPlaylistId = await localMusicProvider.createPlaylist(
        name: playlist.name,
        trackPaths: downloadedFiles.map((file) => file.path).toSet(),
      );
      if (localPlaylistId != null && mounted) {
        setState(() {
          _selectedLocalPlaylistId = localPlaylistId;
          _storageType = _StorageType.local;
        });
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Downloaded "${playlist.name}" (${downloadedFiles.length} tracks)',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _downloadingCloudPlaylistIds.remove(playlist.id));
      }
    }
  }

  Future<void> _deleteCloudPlaylist(Playlist playlist) async {
    if (_deletingCloudPlaylistIds.contains(playlist.id)) return;
    setState(() => _deletingCloudPlaylistIds.add(playlist.id));

    try {
      final result = await _apiService.deletePlaylist(playlist.id);
      if (!mounted) return;

      if (result['success'] == true) {
        _cloudPlaylistTracksCache.remove(playlist.id);
        if (_selectedCloudPlaylistId == playlist.id) {
          setState(() {
            _selectedCloudPlaylistId = null;
          });
        }
        await _refreshCloudData();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Deleted cloud playlist "${playlist.name}"')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Delete failed: ${result['message']}'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _deletingCloudPlaylistIds.remove(playlist.id));
      }
    }
  }

  Future<void> _selectCloudPlaylist(int? playlistId) async {
    if (playlistId == null) {
      if (!mounted) return;
      setState(() {
        _selectedCloudPlaylistId = null;
      });
      return;
    }

    if (_loadingCloudPlaylistIds.contains(playlistId)) return;
    if (_cloudPlaylistTracksCache.containsKey(playlistId)) {
      if (!mounted) return;
      setState(() {
        _selectedCloudPlaylistId = playlistId;
      });
      return;
    }

    setState(() {
      _selectedCloudPlaylistId = playlistId;
      _loadingCloudPlaylistIds.add(playlistId);
    });

    try {
      final result = await _apiService.getPlaylistSongs(playlistId);
      final songs = result['success'] == true
          ? (result['songs'] as List<dynamic>)
                .map((item) => Track.fromJson(item as Map<String, dynamic>))
                .toList()
          : <Track>[];

      if (!mounted) return;
      setState(() {
        _cloudPlaylistTracksCache[playlistId] = songs;
      });
    } finally {
      if (mounted) {
        setState(() => _loadingCloudPlaylistIds.remove(playlistId));
      }
    }
  }

  void _handleLocalTracksSwipe(DragEndDetails details) {
    final dx = details.primaryVelocity ?? 0;
    if (dx > _storageSwipeVelocityThreshold) {
      context.read<MainNavProvider>().setIndex(0);
      return;
    }
    if (dx < -_storageSwipeVelocityThreshold) {
      _switchStorageType(_StorageType.cloud);
    }
  }

  void _handleCloudTracksSwipe(DragEndDetails details) {
    final dx = details.primaryVelocity ?? 0;
    if (dx > _storageSwipeVelocityThreshold) {
      _switchStorageType(_StorageType.local);
    }
  }

  Future<void> _switchStorageType(_StorageType nextType) async {
    if (_storageType == nextType) return;

    setState(() => _storageType = nextType);

    if (nextType == _StorageType.local) {
      await context.read<LocalMusicProvider>().refreshLocalLibrary();
      return;
    }

    final isCloudAuthed = context.read<AuthProvider>().currentUser != null;
    if (isCloudAuthed) {
      await _refreshCloudData();
    }
  }

  Future<void> _removeLocalTrack(File file) async {
    final localMusicProvider = context.read<LocalMusicProvider>();
    await localMusicProvider.removeFile(file);
    final playlists = localMusicProvider.playlists;
    if (_selectedLocalPlaylistId != 'all' &&
        playlists.every((item) => item.id != _selectedLocalPlaylistId)) {
      setState(() {
        _selectedLocalPlaylistId = 'all';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Consumer3<CloudMusicProvider, LocalMusicProvider, AuthProvider>(
      builder: (context, cloudMusicProvider, localMusicProvider, authProvider, child) {
        final localTracks = localMusicProvider.selectedFiles;
        final localPlaylists = localMusicProvider.playlists;
        final visibleLocalTracks = _localTracksForSelectedPlaylist(
          localMusicProvider,
        );
        final cloudTracks = cloudMusicProvider.tracks;
        final cloudPlaylists = cloudMusicProvider.playlists;
        final visibleCloudTracks = _selectedCloudPlaylistId == null
            ? cloudTracks
            : (_cloudPlaylistTracksCache[_selectedCloudPlaylistId!] ??
                  const <Track>[]);
        final isCloudPlaylistLoading = _selectedCloudPlaylistId != null &&
            _loadingCloudPlaylistIds.contains(_selectedCloudPlaylistId);
        final isCloudAuthed = authProvider.currentUser != null;

        return Scaffold(
          body: SafeArea(
            child: RefreshIndicator(
              onRefresh: _storageType == _StorageType.cloud && isCloudAuthed
                  ? _refreshCloudData
                  : () async {},
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 260),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, animation) {
                  final slideAnimation = Tween<Offset>(
                    begin: const Offset(0.08, 0),
                    end: Offset.zero,
                  ).animate(animation);
                  return FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: slideAnimation,
                      child: child,
                    ),
                  );
                },
                child: KeyedSubtree(
                  key: ValueKey<_StorageType>(_storageType),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                    children: [
                  Row(
                    children: [
                      Text(
                        'Storage',
                        style: textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: colorScheme.secondary,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: _ModeButton(
                            selected: _storageType == _StorageType.local,
                            label: 'Local',
                            icon: Icons.storage_rounded,
                            onTap: () => _switchStorageType(_StorageType.local),
                          ),
                        ),
                        Expanded(
                          child: _ModeButton(
                            selected: _storageType == _StorageType.cloud,
                            label: 'Cloud',
                            icon: Icons.cloud_rounded,
                            onTap: () => _switchStorageType(_StorageType.cloud),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (_storageType == _StorageType.local) ...[
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${localPlaylists.length + 1} playlists • ${visibleLocalTracks.length} tracks',
                            style: textTheme.bodyMedium?.copyWith(
                              color: colorScheme.onSurface.withValues(
                                alpha: 0.65,
                              ),
                            ),
                          ),
                        ),
                        FilledButton(
                          onPressed: _showUploadOptions,
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(
                              _storageHeaderControlWidth,
                              _storageHeaderControlHeight,
                            ),
                            maximumSize: const Size(
                              _storageHeaderControlWidth,
                              _storageHeaderControlHeight,
                            ),
                          ),
                          child: const Text('Upload'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 130,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        separatorBuilder: (context, index) =>
                            const SizedBox(width: 10),
                        itemCount: localPlaylists.length + 2,
                        itemBuilder: (context, index) {
                          if (index == 0) {
                            return _CreatePlaylistCard(
                              onTap: () => _openCreatePlaylistDialog(
                                localTracks,
                                localMusicProvider,
                              ),
                            );
                          }

                          if (index == 1) {
                            return _SelectablePlaylistCard(
                              playlistName: 'All songs',
                              trackCount: localTracks.length,
                              selected: _selectedLocalPlaylistId == 'all',
                              onTap: () {
                                setState(() {
                                  _selectedLocalPlaylistId = 'all';
                                });
                              },
                            );
                          }

                          final playlist = localPlaylists[index - 2];
                          final trackCount = playlist.trackPaths
                              .where(
                                (path) => localTracks.any(
                                  (track) => track.path == path,
                                ),
                              )
                              .length;

                          return _SelectablePlaylistCard(
                            playlistName: playlist.name,
                            trackCount: trackCount,
                            selected: _selectedLocalPlaylistId == playlist.id,
                            onTap: () {
                              setState(() {
                                _selectedLocalPlaylistId = playlist.id;
                              });
                            },
                            menuActions: [
                              _PlaylistMenuAction(
                                label: _syncingLocalPlaylistIds.contains(
                                      playlist.id,
                                    )
                                    ? 'Syncing...'
                                    : 'Upload to cloud',
                                icon: Icons.cloud_upload_rounded,
                                onTap: () => _uploadLocalPlaylistToCloud(
                                  playlist: playlist,
                                  localMusicProvider: localMusicProvider,
                                  cloudMusicProvider: cloudMusicProvider,
                                ),
                              ),
                              _PlaylistMenuAction(
                                label: 'Delete',
                                icon: Icons.delete_rounded,
                                onTap: () => _deleteLocalPlaylist(playlist.id),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 16),
                    GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onHorizontalDragEnd: _handleLocalTracksSwipe,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: MediaQuery.of(context).size.height * 0.34,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Tracks',
                              style: textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 10),
                            if (visibleLocalTracks.isEmpty)
                              const _EmptyInlineState(message: 'No local tracks yet')
                            else
                              ...visibleLocalTracks.map((file) {
                                final uploading = _uploadingPaths.contains(file.path);
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: _TrackRow(
                                    title: p.basename(file.path),
                                    subtitle: _localFileSize(file),
                                    menuItems: [
                                      _TrackMenuAction(
                                        label: uploading ? 'Uploading...' : 'Upload',
                                        icon: Icons.cloud_upload_rounded,
                                        enabled: !uploading,
                                        onTap: () => _uploadLocalTrack(file),
                                      ),
                                      _TrackMenuAction(
                                        label: 'Delete',
                                        icon: Icons.delete_rounded,
                                        onTap: () => _removeLocalTrack(file),
                                      ),
                                    ],
                                  ),
                                );
                              }),
                          ],
                        ),
                      ),
                    ),
                  ] else ...[
                    if (!isCloudAuthed)
                      _CloudLoginCard(
                        emailController: _emailController,
                        passwordController: _passwordController,
                        loading: authProvider.isLoading,
                        onSubmit: () => _submitCloudLogin(authProvider),
                      )
                    else ...[
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${cloudPlaylists.length + 1} playlists | ${visibleCloudTracks.length} tracks',
                              style: textTheme.bodyMedium?.copyWith(
                                color: colorScheme.onSurface.withValues(
                                  alpha: 0.65,
                                ),
                              ),
                            ),
                          ),
                          SizedBox(
                            width: _storageHeaderControlWidth,
                            height: _storageHeaderControlHeight,
                            child: Container(
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: colorScheme.surface,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: colorScheme.outline),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.cloud_rounded,
                                    size: 20,
                                    color: colorScheme.primary,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    '2GB / 10GB',
                                    style: textTheme.labelLarge?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 130,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: cloudPlaylists.length + 1,
                          separatorBuilder: (context, index) =>
                              const SizedBox(width: 10),
                          itemBuilder: (context, index) {
                            if (index == 0) {
                              return _PlaylistCard(
                                playlistName: 'All songs',
                                trackCount: cloudTracks.length,
                                selected: _selectedCloudPlaylistId == null,
                                onTap: () => _selectCloudPlaylist(null),
                              );
                            }

                            final item = cloudPlaylists[index - 1];
                            final downloadingPlaylist =
                                _downloadingCloudPlaylistIds.contains(item.id);
                            final deletingPlaylist =
                                _deletingCloudPlaylistIds.contains(item.id);
                            return _PlaylistCard(
                              playlistName: item.name,
                              trackCount: item.songCount ?? 0,
                              selected: _selectedCloudPlaylistId == item.id,
                              onTap: () => _selectCloudPlaylist(item.id),
                              menuActions: [
                                _PlaylistMenuAction(
                                  label: downloadingPlaylist
                                      ? 'Downloading...'
                                      : 'Download to local',
                                  icon: Icons.download_rounded,
                                  onTap: () => _downloadCloudPlaylistToLocal(
                                    playlist: item,
                                    localMusicProvider: localMusicProvider,
                                    cloudMusicProvider: cloudMusicProvider,
                                  ),
                                ),
                                _PlaylistMenuAction(
                                  label: deletingPlaylist
                                      ? 'Deleting...'
                                      : 'Delete',
                                  icon: Icons.delete_rounded,
                                  onTap: () => _deleteCloudPlaylist(item),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 16),
                      GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onHorizontalDragEnd: _handleCloudTracksSwipe,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minHeight: MediaQuery.of(context).size.height * 0.34,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Tracks',
                                style: textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 10),
                              if ((cloudMusicProvider.isLoading && cloudTracks.isEmpty) ||
                                  isCloudPlaylistLoading)
                                const Center(
                                  child: Padding(
                                    padding: EdgeInsets.symmetric(vertical: 28),
                                    child: CircularProgressIndicator(),
                                  ),
                                )
                              else if (visibleCloudTracks.isEmpty)
                                const _EmptyInlineState(message: 'No cloud tracks yet')
                              else
                                ...visibleCloudTracks.map((track) {
                                  final downloading = _downloadingTrackIds.contains(
                                    track.id,
                                  );
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 10),
                                    child: _TrackRow(
                                      title: track.originalFilename ?? track.filename,
                                      subtitle: _cloudFileSize(track),
                                      menuItems: [
                                        _TrackMenuAction(
                                          label: downloading
                                              ? 'Downloading...'
                                              : 'Download',
                                          icon: Icons.download_rounded,
                                          enabled: !downloading,
                                          onTap: () => _downloadTrack(track),
                                        ),
                                        _TrackMenuAction(
                                          label: 'Delete',
                                          icon: Icons.delete_rounded,
                                          onTap: () {
                                            if (!mounted) return;
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              const SnackBar(
                                                content: Text(
                                                  'Delete API will be connected later',
                                                ),
                                              ),
                                            );
                                          },
                                        ),
                                      ],
                                    ),
                                  );
                                }),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  String _localFileSize(File file) {
    try {
      final bytes = file.lengthSync();
      final mb = bytes / 1024 / 1024;
      return '${mb.toStringAsFixed(2)} MB';
    } catch (_) {
      return 'Unknown size';
    }
  }

  String _cloudFileSize(Track track) {
    final sizeInMb = track.filesize != null
        ? (track.filesize! / 1024 / 1024).toStringAsFixed(2)
        : 'n/a';
    return 'Size: $sizeInMb MB';
  }
}

class _ModeButton extends StatelessWidget {
  const _ModeButton({
    required this.selected,
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final bool selected;
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? colorScheme.surface : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18),
            const SizedBox(width: 6),
            Text(label),
          ],
        ),
      ),
    );
  }
}

class _PlaylistCard extends StatelessWidget {
  const _PlaylistCard({
    required this.playlistName,
    required this.trackCount,
    this.selected = false,
    this.onTap,
    this.menuActions,
  });

  final String playlistName;
  final int trackCount;
  final bool selected;
  final VoidCallback? onTap;
  final List<_PlaylistMenuAction>? menuActions;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
        width: 150,
        margin: const EdgeInsets.only(right: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected ? colorScheme.secondary : colorScheme.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? colorScheme.primary : colorScheme.outline,
          ),
        ),
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
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
                    Icons.queue_music_rounded,
                    color: colorScheme.onPrimary,
                  ),
                ),
                const Spacer(),
                Text(
                  playlistName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$trackCount tracks',
                  style: textTheme.labelMedium?.copyWith(
                    color: colorScheme.onSurface.withValues(alpha: 0.65),
                  ),
                ),
              ],
            ),
            if (menuActions != null && menuActions!.isNotEmpty)
              Positioned(
                right: -6,
                top: -6,
                child: PopupMenuButton<int>(
                  icon: const Icon(Icons.more_vert_rounded, size: 18),
                  onSelected: (index) => menuActions![index].onTap(),
                  itemBuilder: (context) {
                    return List.generate(menuActions!.length, (index) {
                      final action = menuActions![index];
                      return PopupMenuItem<int>(
                        value: index,
                        child: Row(
                          children: [
                            Icon(action.icon, size: 18),
                            const SizedBox(width: 8),
                            Text(action.label),
                          ],
                        ),
                      );
                    });
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PlaylistMenuAction {
  const _PlaylistMenuAction({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
}

class _CreatePlaylistCard extends StatelessWidget {
  const _CreatePlaylistCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
        width: 150,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: colorScheme.outline),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: colorScheme.secondary,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.add_rounded, color: colorScheme.primary),
            ),
            const SizedBox(height: 10),
            const Text('Create playlist'),
          ],
        ),
      ),
    );
  }
}

class _SelectablePlaylistCard extends StatelessWidget {
  const _SelectablePlaylistCard({
    required this.playlistName,
    required this.trackCount,
    required this.selected,
    required this.onTap,
    this.menuActions,
  });

  final String playlistName;
  final int trackCount;
  final bool selected;
  final VoidCallback onTap;
  final List<_PlaylistMenuAction>? menuActions;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
        width: 150,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected ? colorScheme.secondary : colorScheme.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? colorScheme.primary : colorScheme.outline,
          ),
        ),
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
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
                    Icons.queue_music_rounded,
                    color: colorScheme.onPrimary,
                  ),
                ),
                const Spacer(),
                Text(
                  playlistName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$trackCount tracks',
                  style: textTheme.labelMedium?.copyWith(
                    color: colorScheme.onSurface.withValues(alpha: 0.65),
                  ),
                ),
              ],
            ),
            if (menuActions != null && menuActions!.isNotEmpty)
              Positioned(
                right: -6,
                top: -6,
                child: PopupMenuButton<int>(
                  icon: const Icon(Icons.more_vert_rounded, size: 18),
                  onSelected: (index) => menuActions![index].onTap(),
                  itemBuilder: (context) {
                    return List.generate(menuActions!.length, (index) {
                      final action = menuActions![index];
                      return PopupMenuItem<int>(
                        value: index,
                        child: Row(
                          children: [
                            Icon(action.icon, size: 18),
                            const SizedBox(width: 8),
                            Text(action.label),
                          ],
                        ),
                      );
                    });
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TrackMenuAction {
  const _TrackMenuAction({
    required this.label,
    required this.icon,
    required this.onTap,
    this.enabled = true,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool enabled;
}

class _TrackRow extends StatelessWidget {
  const _TrackRow({
    required this.title,
    required this.subtitle,
    required this.menuItems,
  });

  final String title;
  final String subtitle;
  final List<_TrackMenuAction> menuItems;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colorScheme.outline),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: LinearGradient(
                colors: [colorScheme.primary, colorScheme.tertiary],
              ),
            ),
            child: Icon(Icons.music_note_rounded, color: colorScheme.onPrimary),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: textTheme.labelMedium?.copyWith(
                    color: colorScheme.onSurface.withValues(alpha: 0.65),
                  ),
                ),
              ],
            ),
          ),
          PopupMenuButton<int>(
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: (index) => menuItems[index].onTap(),
            itemBuilder: (context) {
              return List.generate(menuItems.length, (index) {
                final item = menuItems[index];
                return PopupMenuItem<int>(
                  value: index,
                  enabled: item.enabled,
                  child: Row(
                    children: [
                      Icon(item.icon, size: 18),
                      const SizedBox(width: 8),
                      Text(item.label),
                    ],
                  ),
                );
              });
            },
          ),
        ],
      ),
    );
  }
}

class _CloudLoginCard extends StatelessWidget {
  const _CloudLoginCard({
    required this.emailController,
    required this.passwordController,
    required this.loading,
    required this.onSubmit,
  });

  final TextEditingController emailController;
  final TextEditingController passwordController;
  final bool loading;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Theme.of(context).colorScheme.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Cloud login',
            style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(
            'Sign in to view cloud playlists and tracks.',
            style: textTheme.bodyMedium,
          ),
          const SizedBox(height: 14),
          TextField(
            controller: emailController,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: 'Email',
              prefixIcon: Icon(Icons.alternate_email_rounded),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: passwordController,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Password',
              prefixIcon: Icon(Icons.lock_rounded),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: loading ? null : onSubmit,
              child: loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Sign in'),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyInlineState extends StatelessWidget {
  const _EmptyInlineState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outline),
      ),
      child: Text(
        message,
        style: TextStyle(color: colorScheme.onSurface.withValues(alpha: 0.65)),
      ),
    );
  }
}

