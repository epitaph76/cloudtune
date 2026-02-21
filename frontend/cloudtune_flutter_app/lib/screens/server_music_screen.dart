import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../models/track.dart';
import '../models/playlist.dart';
import '../providers/audio_player_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/cloud_music_provider.dart';
import '../providers/local_music_provider.dart';
import '../providers/main_nav_provider.dart';
import '../services/api_service.dart';
import '../utils/app_localizations.dart';

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
  final Map<String, String> _localFileSizeCache = <String, String>{};

  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  _StorageType _storageType = _StorageType.local;
  bool _cloudAuthRegisterMode = false;
  String _selectedLocalPlaylistId = LocalMusicProvider.allPlaylistId;
  int? _selectedCloudPlaylistId;
  String _localTracksSearchQuery = '';
  String _cloudTracksSearchQuery = '';
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
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _refreshCloudData() async {
    if (!mounted) return;
    final cloudMusicProvider = context.read<CloudMusicProvider>();
    await Future.wait([
      cloudMusicProvider.fetchUserLibrary(),
      cloudMusicProvider.fetchUserPlaylists(),
      cloudMusicProvider.fetchStorageUsage(),
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
      final result = await _apiService.getPlaylistSongs(
        selectedCloudPlaylistId,
      );
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
    String t(String key) => AppLocalizations.text(context, key);
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
                  title: Text(t('upload_tracks')),
                  subtitle: Text(t('pick_one_or_multiple_audio')),
                  onTap: () async {
                    Navigator.of(sheetContext).pop();
                    await _pickLocalFiles();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.folder_rounded),
                  title: Text(t('pick_folder')),
                  subtitle: Text(t('import_from_folder_with_filters')),
                  onTap: () async {
                    Navigator.of(sheetContext).pop();
                    await _pickLocalFolderWithFilters();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.manage_search_rounded),
                  title: Text(t('auto_scan_device')),
                  subtitle: Text(t('find_new_audio_on_device')),
                  onTap: () async {
                    Navigator.of(sheetContext).pop();
                    await _scanDeviceForNewAudioFiles();
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
    String t(String key) => AppLocalizations.text(context, key);
    final localMusicProvider = context.read<LocalMusicProvider>();
    final rawDirectoryPath = await FilePicker.platform.getDirectoryPath();
    if (rawDirectoryPath == null || !mounted) return;

    final directoryPath = _normalizePickedDirectoryPath(rawDirectoryPath);
    if (directoryPath == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(t('cant_access_folder_directly'))));
      return;
    }

    final filters = await _showFolderImportFilters();
    if (filters == null || !mounted) return;

    final hasPermission = await _ensureFolderImportPermission();
    if (!mounted) return;
    if (!hasPermission) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t('storage_permission_import_denied'))),
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
        SnackBar(content: Text('${t('no_matching_files_in')} $directoryPath')),
      );
      return;
    }

    await localMusicProvider.addFiles(files);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${t('imported_files')} ${files.length}')),
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
                          final selected = selectedExtensions.contains(
                            extension,
                          );
                          return FilterChip(
                            selected: selected,
                            label: Text(
                              extension.replaceFirst('.', '').toUpperCase(),
                            ),
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
                                allowedExtensions: Set<String>.from(
                                  selectedExtensions,
                                ),
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
                          child: Text(
                            AppLocalizations.text(
                              context,
                              'import_from_folder',
                            ),
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
      },
    );
  }

  Future<void> _scanDeviceForNewAudioFiles() async {
    String t(String key) => AppLocalizations.text(context, key);
    if (!Platform.isAndroid) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(t('auto_scan_android_only'))));
      return;
    }

    final hasPermission = await _ensureFolderImportPermission();
    if (!mounted) return;
    if (!hasPermission) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t('storage_permission_scan_denied'))),
      );
      return;
    }

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) {
        return AlertDialog(
          content: Row(
            children: [
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.4),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(t('scanning_device_audio'))),
            ],
          ),
        );
      },
    );

    List<File> scannedFiles = const <File>[];
    try {
      scannedFiles = await _collectAudioFilesFromDevice();
    } finally {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
    }

    if (!mounted) return;
    final localMusicProvider = context.read<LocalMusicProvider>();
    final existingPaths = localMusicProvider.selectedFiles
        .map((item) => item.path)
        .toSet();

    final newFiles = scannedFiles
        .where((file) => !existingPaths.contains(file.path))
        .toList();
    if (newFiles.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(t('no_new_audio_files'))));
      return;
    }

    final selectedFiles = await _showScannedFilesPicker(newFiles);
    if (!mounted || selectedFiles == null || selectedFiles.isEmpty) return;

    await localMusicProvider.addFiles(selectedFiles);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${t('added_files')} ${selectedFiles.length}')),
    );
  }

  Future<List<File>> _collectAudioFilesFromDevice() async {
    final rootCandidates = <String>['/storage/emulated/0', '/sdcard'];

    final collected = <File>[];
    final seenPaths = <String>{};

    for (final rootPath in rootCandidates) {
      final rootDir = Directory(rootPath);
      if (!await rootDir.exists()) continue;

      final pending = <Directory>[rootDir];
      while (pending.isNotEmpty) {
        final dir = pending.removeLast();
        try {
          await for (final entity in dir.list(followLinks: false)) {
            if (entity is Directory) {
              if (_shouldSkipDirectory(entity.path)) continue;
              pending.add(entity);
              continue;
            }

            if (entity is! File) continue;
            final extension = p.extension(entity.path).toLowerCase();
            if (!_supportedAudioExtensions.contains(extension)) continue;
            if (seenPaths.add(entity.path)) {
              collected.add(entity);
            }
          }
        } catch (_) {
          // Skip directories that are inaccessible.
        }
      }
    }

    collected.sort(
      (a, b) => p
          .basename(a.path)
          .toLowerCase()
          .compareTo(p.basename(b.path).toLowerCase()),
    );
    return collected;
  }

  bool _shouldSkipDirectory(String path) {
    final normalized = path.replaceAll('\\', '/').toLowerCase();
    return normalized.contains('/android/data') ||
        normalized.contains('/android/obb') ||
        normalized.contains('/.thumbnails') ||
        normalized.contains('/cache') ||
        p.basename(normalized).startsWith('.');
  }

  Future<List<File>?> _showScannedFilesPicker(List<File> files) {
    String t(String key) => AppLocalizations.text(context, key);
    final selectedPaths = <String>{};
    String searchQuery = '';

    return showModalBottomSheet<List<File>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final normalizedQuery = searchQuery.trim().toLowerCase();
            final visibleFiles = normalizedQuery.isEmpty
                ? files
                : files.where((file) {
                    final fileName = p.basename(file.path).toLowerCase();
                    final dirName = p.dirname(file.path).toLowerCase();
                    return fileName.contains(normalizedQuery) ||
                        dirName.contains(normalizedQuery);
                  }).toList();

            return SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
                child: SizedBox(
                  height: MediaQuery.of(context).size.height * 0.74,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${t('found_new_audio_files')} ${files.length}',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          OutlinedButton.icon(
                            onPressed: () {
                              setModalState(() {
                                selectedPaths
                                  ..clear()
                                  ..addAll(
                                    visibleFiles.map((item) => item.path),
                                  );
                              });
                              context.read<AudioPlayerProvider>().stop();
                            },
                            icon: const Icon(Icons.done_all_rounded),
                            label: Text(t('select_all')),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton.icon(
                            onPressed: () {
                              setModalState(selectedPaths.clear);
                              context.read<AudioPlayerProvider>().stop();
                            },
                            icon: const Icon(Icons.deselect_rounded),
                            label: Text(t('clear')),
                          ),
                          const Spacer(),
                          Text(
                            '${selectedPaths.length} ${t('selected_shown')} ${visibleFiles.length}',
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        onChanged: (value) {
                          setModalState(() => searchQuery = value);
                        },
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: t('search_by_name_or_path'),
                          prefixIcon: Icon(Icons.search_rounded),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Expanded(
                        child: ListView.builder(
                          itemCount: visibleFiles.length,
                          itemBuilder: (context, index) {
                            final file = visibleFiles[index];
                            final checked = selectedPaths.contains(file.path);
                            return CheckboxListTile(
                              value: checked,
                              contentPadding: EdgeInsets.zero,
                              dense: true,
                              title: Text(
                                p.basename(file.path),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                p.dirname(file.path),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              onChanged: (value) {
                                final shouldSelect = value == true;
                                setModalState(() {
                                  if (shouldSelect) {
                                    selectedPaths.add(file.path);
                                  } else {
                                    selectedPaths.remove(file.path);
                                  }
                                });
                                _handleScannedTrackSelection(
                                  files: files,
                                  selectedTrack: file,
                                  shouldSelect: shouldSelect,
                                  selectedCount: selectedPaths.length,
                                  totalCount: files.length,
                                );
                              },
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: selectedPaths.isEmpty
                              ? null
                              : () {
                                  final selected = files
                                      .where(
                                        (item) =>
                                            selectedPaths.contains(item.path),
                                      )
                                      .toList();
                                  Navigator.of(sheetContext).pop(selected);
                                },
                          child: Text(t('add_selected_files')),
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

  Future<void> _handleScannedTrackSelection({
    required List<File> files,
    required File selectedTrack,
    required bool shouldSelect,
    required int selectedCount,
    required int totalCount,
  }) async {
    final audioProvider = context.read<AudioPlayerProvider>();

    if (selectedCount == totalCount || selectedCount == 0) {
      await audioProvider.stop();
      return;
    }

    if (!shouldSelect) {
      if (audioProvider.currentTrackPath == selectedTrack.path) {
        await audioProvider.stop();
      }
      return;
    }

    final index = files.indexWhere((item) => item.path == selectedTrack.path);
    if (index < 0) return;

    if (audioProvider.currentTrackPath == selectedTrack.path) {
      await audioProvider.playPauseFromTracks(files);
      return;
    }

    await audioProvider.playFromTracks(files, initialIndex: index);
  }

  Future<List<File>> _collectAudioFilesFromFolder({
    required String directoryPath,
    required _FolderImportFilters filters,
  }) async {
    final directory = Directory(directoryPath);
    if (!await directory.exists()) return const <File>[];

    final entities = await directory
        .list(recursive: true, followLinks: false)
        .toList();
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

          if (duration < filters.minDuration ||
              duration > filters.maxDuration) {
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

  Future<void> _submitCloudRegister(AuthProvider authProvider) async {
    final email = _emailController.text.trim();
    final username = _usernameController.text.trim();
    final password = _passwordController.text.trim();
    if (email.isEmpty || username.isEmpty || password.isEmpty) return;

    final ok = await authProvider.register(email, username, password);
    if (!mounted) return;

    if (ok) {
      _passwordController.clear();
      await _refreshCloudData();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cloud registration successful')),
      );
      setState(() => _cloudAuthRegisterMode = false);
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

  bool _matchesLocalTrackSearch(File file) {
    if (_localTracksSearchQuery.trim().isEmpty) return true;
    final query = _localTracksSearchQuery.toLowerCase().trim();
    final fileName = p.basename(file.path).toLowerCase();
    final fileTitle = p.basenameWithoutExtension(file.path).toLowerCase();
    return fileName.contains(query) || fileTitle.contains(query);
  }

  bool _matchesCloudTrackSearch(Track track) {
    if (_cloudTracksSearchQuery.trim().isEmpty) return true;
    final query = _cloudTracksSearchQuery.toLowerCase().trim();
    final title = (track.originalFilename ?? track.filename).toLowerCase();
    return title.contains(query);
  }

  void _openCreatePlaylistDialog(
    List<File> localTracks,
    LocalMusicProvider localMusicProvider,
  ) {
    String t(String key) => AppLocalizations.text(context, key);
    if (localTracks.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(t('add_local_tracks_first'))));
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
                        t('create_playlist_title'),
                        style: textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        onChanged: (value) {
                          playlistName = value;
                        },
                        decoration: InputDecoration(
                          labelText: t('playlist_name'),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        t('select_tracks'),
                        style: textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: OutlinedButton.icon(
                          onPressed: () {
                            setModalState(() {
                              if (selectedPaths.length == localTracks.length) {
                                selectedPaths.clear();
                              } else {
                                selectedPaths
                                  ..clear()
                                  ..addAll(
                                    localTracks.map((file) => file.path),
                                  );
                              }
                            });
                          },
                          icon: Icon(
                            selectedPaths.length == localTracks.length
                                ? Icons.deselect_rounded
                                : Icons.done_all_rounded,
                          ),
                          label: Text(
                            selectedPaths.length == localTracks.length
                                ? t('clear_selection')
                                : t('select_all'),
                          ),
                        ),
                      ),
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
                            if (name.isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    AppLocalizations.text(
                                      context,
                                      'playlist_name_required',
                                    ),
                                  ),
                                ),
                              );
                              return;
                            }
                            if (selectedPaths.isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    AppLocalizations.text(
                                      context,
                                      'playlist_tracks_required',
                                    ),
                                  ),
                                ),
                              );
                              return;
                            }

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
                          child: Text(t('create_playlist')),
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
        _selectedLocalPlaylistId = LocalMusicProvider.allPlaylistId;
      });
    }
  }

  Future<void> _uploadLocalPlaylistToCloud({
    required LocalPlaylist playlist,
    required LocalMusicProvider localMusicProvider,
    required CloudMusicProvider cloudMusicProvider,
  }) async {
    final playlistTracks = localMusicProvider.getTracksForPlaylist(playlist.id);
    await _uploadTracksAsCloudPlaylist(
      syncKey: playlist.id,
      playlistName: playlist.name,
      playlistTracks: playlistTracks,
      cloudMusicProvider: cloudMusicProvider,
    );
  }

  Future<void> _uploadSystemPlaylistToCloud({
    required String playlistId,
    required String playlistName,
    required LocalMusicProvider localMusicProvider,
    required CloudMusicProvider cloudMusicProvider,
  }) async {
    final playlistTracks = localMusicProvider.getTracksForPlaylist(playlistId);
    await _uploadTracksAsCloudPlaylist(
      syncKey: 'system_$playlistId',
      playlistName: playlistName,
      playlistTracks: playlistTracks,
      cloudMusicProvider: cloudMusicProvider,
    );
  }

  Future<void> _uploadTracksAsCloudPlaylist({
    required String syncKey,
    required String playlistName,
    required List<File> playlistTracks,
    required CloudMusicProvider cloudMusicProvider,
  }) async {
    if (_syncingLocalPlaylistIds.contains(syncKey)) return;

    if (playlistTracks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Playlist "$playlistName" is empty')),
      );
      return;
    }

    setState(() => _syncingLocalPlaylistIds.add(syncKey));

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
              'No tracks from "$playlistName" were uploaded/matched in cloud',
            ),
          ),
        );
        return;
      }

      final createResult = await _apiService.createPlaylist(
        name: playlistName,
        description: 'Synced from local',
      );
      if (createResult['success'] != true) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Cloud playlist create failed: ${createResult['message']}',
            ),
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
          const SnackBar(
            content: Text('Cloud playlist id missing in response'),
          ),
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
        SnackBar(content: Text('Playlist "$playlistName" synced to cloud')),
      );
    } finally {
      if (mounted) {
        setState(() => _syncingLocalPlaylistIds.remove(syncKey));
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
            content: Text(
              'Failed to load cloud playlist: ${result['message']}',
            ),
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
          SnackBar(
            content: Text('No tracks downloaded from "${playlist.name}"'),
          ),
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

  Future<void> _deleteCloudTrack(Track track) async {
    final result = await _apiService.deleteSong(track.id);
    if (!mounted) return;

    if (result['success'] == true) {
      _cloudPlaylistTracksCache.removeWhere(
        (_, songs) => songs.any((item) => item.id == track.id),
      );
      await _refreshCloudData();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Deleted: ${track.originalFilename ?? track.filename}'),
        ),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Delete failed: ${result['message']}')),
    );
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
          SnackBar(content: Text('Delete failed: ${result['message']}')),
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

    final isCloudAuthed = context.read<AuthProvider>().currentUser != null;
    if (nextType == _StorageType.cloud && isCloudAuthed) {
      await _refreshCloudData();
    }
  }

  Future<void> _removeLocalTrack(File file) async {
    final localMusicProvider = context.read<LocalMusicProvider>();
    await localMusicProvider.removeFile(file);
    _localFileSizeCache.remove(file.path);
    final playlists = localMusicProvider.playlists;
    if (_selectedLocalPlaylistId != LocalMusicProvider.allPlaylistId &&
        _selectedLocalPlaylistId != LocalMusicProvider.likedPlaylistId &&
        playlists.every((item) => item.id != _selectedLocalPlaylistId)) {
      setState(() {
        _selectedLocalPlaylistId = LocalMusicProvider.allPlaylistId;
      });
    }
  }

  Future<void> _addTrackToPlaylist(File file) async {
    final localMusicProvider = context.read<LocalMusicProvider>();
    final playlists = localMusicProvider.playlists;

    if (playlists.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Create a playlist first')));
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          top: false,
          child: ListView.separated(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
            itemCount: playlists.length,
            separatorBuilder: (context, index) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final playlist = playlists[index];
              final alreadyAdded = playlist.trackPaths.contains(file.path);
              final navigator = Navigator.of(sheetContext);
              final scaffoldMessenger = ScaffoldMessenger.of(this.context);
              return ListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                tileColor: Theme.of(context).colorScheme.surface,
                leading: const Icon(Icons.queue_music_rounded),
                title: Text(playlist.name),
                subtitle: Text(
                  '${playlist.trackPaths.length} ${AppLocalizations.text(context, 'tracks')}',
                ),
                trailing: alreadyAdded
                    ? const Icon(Icons.check_rounded)
                    : const Icon(Icons.add_rounded),
                onTap: () {
                  localMusicProvider
                      .addTrackToPlaylist(
                        playlistId: playlist.id,
                        trackPath: file.path,
                      )
                      .then((ok) {
                        if (!mounted) return;
                        navigator.pop();
                        scaffoldMessenger.showSnackBar(
                          SnackBar(
                            content: Text(
                              ok
                                  ? 'Added to "${playlist.name}"'
                                  : 'Track already in "${playlist.name}"',
                            ),
                          ),
                        );
                      });
                },
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _removeTrackFromCurrentPlaylist(File file) async {
    if (_selectedLocalPlaylistId == LocalMusicProvider.allPlaylistId) return;

    final localMusicProvider = context.read<LocalMusicProvider>();
    if (_selectedLocalPlaylistId == LocalMusicProvider.likedPlaylistId) {
      if (!localMusicProvider.isTrackLiked(file.path)) return;
      final changed = await localMusicProvider.toggleTrackLike(file.path);
      if (!mounted || !changed) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Track removed from liked songs')),
      );
      return;
    }

    final removed = await localMusicProvider.removeTrackFromPlaylist(
      playlistId: _selectedLocalPlaylistId,
      trackPath: file.path,
    );
    if (!mounted || !removed) return;

    final existsSelectedPlaylist = localMusicProvider.playlists.any(
      (item) => item.id == _selectedLocalPlaylistId,
    );
    if (!existsSelectedPlaylist) {
      setState(
        () => _selectedLocalPlaylistId = LocalMusicProvider.allPlaylistId,
      );
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Track removed from playlist')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    String t(String key) => AppLocalizations.text(context, key);

    return Consumer3<CloudMusicProvider, LocalMusicProvider, AuthProvider>(
      builder: (context, cloudMusicProvider, localMusicProvider, authProvider, child) {
        final currentTrackPath = context.select<AudioPlayerProvider, String?>(
          (provider) => provider.currentTrackPath,
        );
        final isCurrentTrackPlaying = context.select<AudioPlayerProvider, bool>(
          (provider) => provider.playing,
        );
        final localTracks = localMusicProvider.selectedFiles;
        final localPlaylists = localMusicProvider.playlists;
        final playlistLocalTracks = _localTracksForSelectedPlaylist(
          localMusicProvider,
        );
        final visibleLocalTracks = playlistLocalTracks
            .where(_matchesLocalTrackSearch)
            .toList();
        final cloudTracks = cloudMusicProvider.tracks;
        final cloudPlaylists = cloudMusicProvider.playlists;
        final baseCloudTracks = _selectedCloudPlaylistId == null
            ? cloudTracks
            : (_cloudPlaylistTracksCache[_selectedCloudPlaylistId!] ??
                  const <Track>[]);
        final visibleCloudTracks = baseCloudTracks
            .where(_matchesCloudTrackSearch)
            .toList();
        final isCloudPlaylistLoading =
            _selectedCloudPlaylistId != null &&
            _loadingCloudPlaylistIds.contains(_selectedCloudPlaylistId);
        final isCloudAuthed = authProvider.currentUser != null;

        return Scaffold(
          body: SafeArea(
            child: RefreshIndicator(
              onRefresh: () async {
                if (_storageType == _StorageType.local) {
                  await context
                      .read<LocalMusicProvider>()
                      .refreshLocalLibrary();
                  return;
                }
                if (isCloudAuthed) {
                  await _refreshCloudData();
                }
              },
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
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onHorizontalDragEnd: _storageType == _StorageType.local
                        ? _handleLocalTracksSwipe
                        : _handleCloudTracksSwipe,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                      children: [
                        Row(
                          children: [
                            Text(
                              t('storage_title'),
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
                                  label: t('local'),
                                  icon: Icons.storage_rounded,
                                  onTap: () =>
                                      _switchStorageType(_StorageType.local),
                                ),
                              ),
                              Expanded(
                                child: _ModeButton(
                                  selected: _storageType == _StorageType.cloud,
                                  label: t('cloud'),
                                  icon: Icons.cloud_rounded,
                                  onTap: () =>
                                      _switchStorageType(_StorageType.cloud),
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
                                  '${localPlaylists.length + 2} ${t('playlists')} • ${visibleLocalTracks.length} ${t('tracks')}',
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
                                child: Text(t('upload')),
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
                              itemCount: localPlaylists.length + 3,
                              itemBuilder: (context, index) {
                                if (index == 0) {
                                  return _CreatePlaylistCard(
                                    label: t('create_playlist'),
                                    onTap: () => _openCreatePlaylistDialog(
                                      localTracks,
                                      localMusicProvider,
                                    ),
                                  );
                                }

                                if (index == 1) {
                                  return _SelectablePlaylistCard(
                                    playlistName: t('all_songs'),
                                    trackCount: localTracks.length,
                                    selected:
                                        _selectedLocalPlaylistId ==
                                        LocalMusicProvider.allPlaylistId,
                                    onTap: () {
                                      setState(() {
                                        _selectedLocalPlaylistId =
                                            LocalMusicProvider.allPlaylistId;
                                      });
                                    },
                                    menuActions: [
                                      _PlaylistMenuAction(
                                        label:
                                            _syncingLocalPlaylistIds.contains(
                                              'system_${LocalMusicProvider.allPlaylistId}',
                                            )
                                            ? 'Syncing...'
                                            : t('upload_to_cloud'),
                                        icon: Icons.cloud_upload_rounded,
                                        onTap: () =>
                                            _uploadSystemPlaylistToCloud(
                                              playlistId: LocalMusicProvider
                                                  .allPlaylistId,
                                              playlistName: t('all_songs'),
                                              localMusicProvider:
                                                  localMusicProvider,
                                              cloudMusicProvider:
                                                  cloudMusicProvider,
                                            ),
                                      ),
                                    ],
                                  );
                                }

                                if (index == 2) {
                                  return _SelectablePlaylistCard(
                                    playlistName: t('liked_songs'),
                                    trackCount:
                                        localMusicProvider.likedTracksCount,
                                    selected:
                                        _selectedLocalPlaylistId ==
                                        LocalMusicProvider.likedPlaylistId,
                                    onTap: () {
                                      setState(() {
                                        _selectedLocalPlaylistId =
                                            LocalMusicProvider.likedPlaylistId;
                                      });
                                    },
                                    menuActions: [
                                      _PlaylistMenuAction(
                                        label:
                                            _syncingLocalPlaylistIds.contains(
                                              'system_${LocalMusicProvider.likedPlaylistId}',
                                            )
                                            ? 'Syncing...'
                                            : t('upload_to_cloud'),
                                        icon: Icons.cloud_upload_rounded,
                                        onTap: () =>
                                            _uploadSystemPlaylistToCloud(
                                              playlistId: LocalMusicProvider
                                                  .likedPlaylistId,
                                              playlistName: t('liked_songs'),
                                              localMusicProvider:
                                                  localMusicProvider,
                                              cloudMusicProvider:
                                                  cloudMusicProvider,
                                            ),
                                      ),
                                    ],
                                  );
                                }

                                final playlist = localPlaylists[index - 3];
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
                                  selected:
                                      _selectedLocalPlaylistId == playlist.id,
                                  onTap: () {
                                    setState(() {
                                      _selectedLocalPlaylistId = playlist.id;
                                    });
                                  },
                                  menuActions: [
                                    _PlaylistMenuAction(
                                      label:
                                          _syncingLocalPlaylistIds.contains(
                                            playlist.id,
                                          )
                                          ? 'Syncing...'
                                          : t('upload_to_cloud'),
                                      icon: Icons.cloud_upload_rounded,
                                      onTap: () => _uploadLocalPlaylistToCloud(
                                        playlist: playlist,
                                        localMusicProvider: localMusicProvider,
                                        cloudMusicProvider: cloudMusicProvider,
                                      ),
                                    ),
                                    _PlaylistMenuAction(
                                      label: t('delete'),
                                      icon: Icons.delete_rounded,
                                      onTap: () =>
                                          _deleteLocalPlaylist(playlist.id),
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
                                minHeight:
                                    MediaQuery.of(context).size.height * 0.34,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        t('tracks'),
                                        style: textTheme.titleMedium?.copyWith(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: TextField(
                                          onChanged: (value) {
                                            setState(
                                              () => _localTracksSearchQuery =
                                                  value,
                                            );
                                          },
                                          decoration: InputDecoration(
                                            isDense: true,
                                            hintText: t('search_track'),
                                            prefixIcon: Icon(
                                              Icons.search_rounded,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  if (visibleLocalTracks.isEmpty)
                                    _EmptyInlineState(
                                      message: t('no_local_tracks_yet'),
                                    )
                                  else
                                    SizedBox(
                                      height:
                                          MediaQuery.of(context).size.height *
                                          0.56,
                                      child: ListView.separated(
                                        primary: false,
                                        itemCount: visibleLocalTracks.length,
                                        separatorBuilder: (context, index) =>
                                            const SizedBox(height: 10),
                                        itemBuilder: (context, index) {
                                          final file =
                                              visibleLocalTracks[index];
                                          final uploading = _uploadingPaths
                                              .contains(file.path);
                                          final selected =
                                              currentTrackPath == file.path;

                                          return _TrackRow(
                                            title: p.basename(file.path),
                                            subtitle: _localFileSize(file),
                                            selected: selected,
                                            isPlaying:
                                                selected &&
                                                isCurrentTrackPlaying,
                                            onTap: () {
                                              final targetIndex =
                                                  playlistLocalTracks
                                                      .indexWhere(
                                                        (item) =>
                                                            item.path ==
                                                            file.path,
                                                      );
                                              if (targetIndex < 0) return;
                                              context
                                                  .read<AudioPlayerProvider>()
                                                  .toggleTrackFromTracks(
                                                    playlistLocalTracks,
                                                    targetIndex,
                                                  );
                                            },
                                            menuItems: [
                                              _TrackMenuAction(
                                                label: uploading
                                                    ? 'Uploading...'
                                                    : t('upload'),
                                                icon:
                                                    Icons.cloud_upload_rounded,
                                                enabled: !uploading,
                                                onTap: () =>
                                                    _uploadLocalTrack(file),
                                              ),
                                              _TrackMenuAction(
                                                label: t('add_to_playlist'),
                                                icon:
                                                    Icons.playlist_add_rounded,
                                                onTap: () =>
                                                    _addTrackToPlaylist(file),
                                              ),
                                              if (_selectedLocalPlaylistId !=
                                                  LocalMusicProvider
                                                      .allPlaylistId)
                                                _TrackMenuAction(
                                                  label:
                                                      _selectedLocalPlaylistId ==
                                                          LocalMusicProvider
                                                              .likedPlaylistId
                                                      ? 'Remove like'
                                                      : 'Remove from playlist',
                                                  icon: Icons
                                                      .playlist_remove_rounded,
                                                  onTap: () =>
                                                      _removeTrackFromCurrentPlaylist(
                                                        file,
                                                      ),
                                                ),
                                              _TrackMenuAction(
                                                label: t('delete'),
                                                icon: Icons.delete_rounded,
                                                onTap: () =>
                                                    _removeLocalTrack(file),
                                              ),
                                            ],
                                          );
                                        },
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ] else ...[
                          if (!isCloudAuthed)
                            GestureDetector(
                              behavior: HitTestBehavior.translucent,
                              onHorizontalDragEnd: _handleCloudTracksSwipe,
                              child: _CloudLoginCard(
                                emailController: _emailController,
                                usernameController: _usernameController,
                                passwordController: _passwordController,
                                loading: authProvider.isLoading,
                                isRegisterMode: _cloudAuthRegisterMode,
                                onSubmit: () => _cloudAuthRegisterMode
                                    ? _submitCloudRegister(authProvider)
                                    : _submitCloudLogin(authProvider),
                                onToggleMode: () {
                                  setState(
                                    () => _cloudAuthRegisterMode =
                                        !_cloudAuthRegisterMode,
                                  );
                                },
                              ),
                            )
                          else ...[
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '${cloudPlaylists.length + 1} ${t('playlists')} | ${visibleCloudTracks.length} ${t('tracks')}',
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
                                      border: Border.all(
                                        color: colorScheme.outline,
                                      ),
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
                                          _formatStorageUsage(
                                            cloudMusicProvider.usedBytes,
                                            cloudMusicProvider.quotaBytes,
                                          ),
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
                                      playlistName: t('all_songs'),
                                      trackCount: cloudTracks.length,
                                      selected:
                                          _selectedCloudPlaylistId == null,
                                      onTap: () => _selectCloudPlaylist(null),
                                    );
                                  }

                                  final item = cloudPlaylists[index - 1];
                                  final downloadingPlaylist =
                                      _downloadingCloudPlaylistIds.contains(
                                        item.id,
                                      );
                                  final deletingPlaylist =
                                      _deletingCloudPlaylistIds.contains(
                                        item.id,
                                      );
                                  return _PlaylistCard(
                                    playlistName: item.name,
                                    trackCount: item.songCount ?? 0,
                                    selected:
                                        _selectedCloudPlaylistId == item.id,
                                    onTap: () => _selectCloudPlaylist(item.id),
                                    menuActions: [
                                      _PlaylistMenuAction(
                                        label: downloadingPlaylist
                                            ? 'Downloading...'
                                            : t('download_to_local'),
                                        icon: Icons.download_rounded,
                                        onTap: () =>
                                            _downloadCloudPlaylistToLocal(
                                              playlist: item,
                                              localMusicProvider:
                                                  localMusicProvider,
                                              cloudMusicProvider:
                                                  cloudMusicProvider,
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
                                  minHeight:
                                      MediaQuery.of(context).size.height * 0.34,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text(
                                          t('tracks'),
                                          style: textTheme.titleMedium
                                              ?.copyWith(
                                                fontWeight: FontWeight.w600,
                                              ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: TextField(
                                            onChanged: (value) {
                                              setState(
                                                () => _cloudTracksSearchQuery =
                                                    value,
                                              );
                                            },
                                            decoration: InputDecoration(
                                              isDense: true,
                                              hintText: t('search_track'),
                                              prefixIcon: Icon(
                                                Icons.search_rounded,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 10),
                                    if ((cloudMusicProvider.isLoading &&
                                            cloudTracks.isEmpty) ||
                                        isCloudPlaylistLoading)
                                      const Center(
                                        child: Padding(
                                          padding: EdgeInsets.symmetric(
                                            vertical: 28,
                                          ),
                                          child: CircularProgressIndicator(),
                                        ),
                                      )
                                    else if (visibleCloudTracks.isEmpty)
                                      _EmptyInlineState(
                                        message: t('no_cloud_tracks_yet'),
                                      )
                                    else
                                      ...visibleCloudTracks.map((track) {
                                        final downloading = _downloadingTrackIds
                                            .contains(track.id);
                                        return Padding(
                                          padding: const EdgeInsets.only(
                                            bottom: 10,
                                          ),
                                          child: _TrackRow(
                                            title:
                                                track.originalFilename ??
                                                track.filename,
                                            subtitle: _cloudFileSize(track),
                                            menuItems: [
                                              _TrackMenuAction(
                                                label: downloading
                                                    ? 'Downloading...'
                                                    : t('download'),
                                                icon: Icons.download_rounded,
                                                enabled: !downloading,
                                                onTap: () =>
                                                    _downloadTrack(track),
                                              ),
                                              _TrackMenuAction(
                                                label: t('delete'),
                                                icon: Icons.delete_rounded,
                                                onTap: () =>
                                                    _deleteCloudTrack(track),
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
          ),
        );
      },
    );
  }

  String _localFileSize(File file) {
    final cached = _localFileSizeCache[file.path];
    if (cached != null) return cached;
    try {
      final bytes = file.lengthSync();
      final mb = bytes / 1024 / 1024;
      final value = '${mb.toStringAsFixed(2)} MB';
      _localFileSizeCache[file.path] = value;
      return value;
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

  String _formatStorageUsage(int usedBytes, int quotaBytes) {
    String prettyBytes(int bytes) {
      const units = ['B', 'KB', 'MB', 'GB', 'TB'];
      var value = bytes.toDouble();
      var unitIndex = 0;
      while (value >= 1024 && unitIndex < units.length - 1) {
        value /= 1024;
        unitIndex++;
      }
      final fixed = value >= 10 || unitIndex == 0
          ? value.toStringAsFixed(0)
          : value.toStringAsFixed(1);
      return '$fixed${units[unitIndex]}';
    }

    return '${prettyBytes(usedBytes)} / ${prettyBytes(quotaBytes)}';
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
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                softWrap: false,
              ),
            ),
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
                  '$trackCount ${AppLocalizations.text(context, 'tracks')}',
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
  const _CreatePlaylistCard({required this.onTap, required this.label});

  final VoidCallback onTap;
  final String label;

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
            Text(label),
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
                  '$trackCount ${AppLocalizations.text(context, 'tracks')}',
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
    this.selected = false,
    this.isPlaying = false,
    this.onTap,
  });

  final String title;
  final String subtitle;
  final List<_TrackMenuAction> menuItems;
  final bool selected;
  final bool isPlaying;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected ? colorScheme.secondary : colorScheme.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? colorScheme.primary : colorScheme.outline,
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
                  colors: [colorScheme.primary, colorScheme.tertiary],
                ),
              ),
              child: isPlaying
                  ? _AnimatedPlayingBars(color: colorScheme.onPrimary)
                  : Icon(
                      Icons.music_note_rounded,
                      color: colorScheme.onPrimary,
                    ),
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
      ),
    );
  }
}

class _AnimatedPlayingBars extends StatefulWidget {
  const _AnimatedPlayingBars({required this.color});

  final Color color;

  @override
  State<_AnimatedPlayingBars> createState() => _AnimatedPlayingBarsState();
}

class _AnimatedPlayingBarsState extends State<_AnimatedPlayingBars>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double _barHeight(int index, double t) {
    final phase = (t * 2 * math.pi) + (index * 0.9);
    final normalized = (math.sin(phase) + 1) / 2;
    return 8 + (normalized * 12);
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        width: 18,
        height: 22,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            return Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(3, (index) {
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 1),
                  child: Container(
                    width: 4,
                    height: _barHeight(index, _controller.value),
                    decoration: BoxDecoration(
                      color: widget.color,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                );
              }),
            );
          },
        ),
      ),
    );
  }
}

class _CloudLoginCard extends StatelessWidget {
  const _CloudLoginCard({
    required this.emailController,
    required this.usernameController,
    required this.passwordController,
    required this.loading,
    required this.isRegisterMode,
    required this.onSubmit,
    required this.onToggleMode,
  });

  final TextEditingController emailController;
  final TextEditingController usernameController;
  final TextEditingController passwordController;
  final bool loading;
  final bool isRegisterMode;
  final VoidCallback onSubmit;
  final VoidCallback onToggleMode;

  @override
  Widget build(BuildContext context) {
    String t(String key) => AppLocalizations.text(context, key);
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
            isRegisterMode ? t('cloud_register') : t('cloud_login'),
            style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(
            isRegisterMode ? t('cloud_register_hint') : t('cloud_login_hint'),
            style: textTheme.bodyMedium,
          ),
          const SizedBox(height: 14),
          TextField(
            controller: emailController,
            keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(
              labelText: 'Email',
              prefixIcon: Icon(Icons.alternate_email_rounded),
            ),
          ),
          if (isRegisterMode) ...[
            const SizedBox(height: 10),
            TextField(
              controller: usernameController,
              decoration: InputDecoration(
                labelText: t('username'),
                prefixIcon: Icon(Icons.person_rounded),
              ),
            ),
          ],
          const SizedBox(height: 10),
          TextField(
            controller: passwordController,
            obscureText: true,
            decoration: InputDecoration(
              labelText: t('password'),
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
                  : Text(isRegisterMode ? t('create_account') : t('sign_in')),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: loading ? null : onToggleMode,
              child: Text(
                isRegisterMode
                    ? t('already_have_account')
                    : t('no_account_register'),
              ),
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
