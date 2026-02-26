import 'dart:async';
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
import '../services/playlist_progress_tracker.dart';
import '../services/server_music_sync_controller.dart';
import '../services/upload_notification_service.dart';
import '../utils/app_localizations.dart';

part '../widgets/server_music_screen_components.dart';

enum _StorageType { local, cloud }

enum _LocalTrackSort { addedToPlayer, name, fileModified }

enum _CloudTrackSort { uploadDate, name, fileSize }

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

class _ServerMusicScreenState extends State<ServerMusicScreen>
    with AutomaticKeepAliveClientMixin {
  static const double _storageHeaderControlWidth = 156;
  static const double _storageHeaderControlHeight = 46;
  static const int _cloudUploadParallelism = 3;

  final ApiService _apiService = ApiService();
  final ServerMusicSyncController _syncController = ServerMusicSyncController(
    parallelism: _cloudUploadParallelism,
  );
  final Set<int> _downloadingTrackIds = <int>{};
  final Set<String> _uploadingPaths = <String>{};
  final Set<String> _syncingLocalPlaylistIds = <String>{};
  final Set<int> _downloadingCloudPlaylistIds = <int>{};
  final Set<int> _deletingCloudPlaylistIds = <int>{};
  final Map<String, String> _localFileSizeCache = <String, String>{};
  final Set<String> _localFileSizeLoadingPaths = <String>{};
  final PlaylistProgressTracker _playlistProgressTracker =
      PlaylistProgressTracker();

  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final ScrollController _localTracksScrollController = ScrollController();
  final ScrollController _cloudTracksScrollController = ScrollController();
  final ScrollController _cloudPlaylistsScrollController = ScrollController();

  _StorageType _storageType = _StorageType.local;
  bool _cloudAuthRegisterMode = false;
  String _selectedLocalPlaylistId = LocalMusicProvider.allPlaylistId;
  int? _selectedCloudPlaylistId;
  String _localTracksSearchQuery = '';
  _LocalTrackSort _localTrackSort = _LocalTrackSort.addedToPlayer;
  _CloudTrackSort _cloudTrackSort = _CloudTrackSort.uploadDate;
  String _cloudTracksSearchQuery = '';
  Timer? _cloudSearchDebounce;
  final Set<String> _selectedLocalTrackPaths = <String>{};
  String? _lastLocalTracksAutoScrollKey;
  static const double _storageSwipeVelocityThreshold = 280;

  static const List<String> _supportedAudioExtensions = <String>[
    '.mp3',
    '.wav',
    '.flac',
    '.m4a',
    '.mp4',
    '.aac',
    '.ogg',
    '.opus',
  ];
  static const Set<String> _supportedAudioExtensionsSet = <String>{
    '.mp3',
    '.wav',
    '.flac',
    '.m4a',
    '.mp4',
    '.aac',
    '.ogg',
    '.opus',
  };
  @override
  void initState() {
    super.initState();
    _cloudTracksScrollController.addListener(_handleCloudTracksLazyLoad);
    _cloudPlaylistsScrollController.addListener(_handleCloudPlaylistsLazyLoad);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final navProvider = context.read<MainNavProvider>();
      if (_selectedLocalPlaylistId != navProvider.selectedLocalPlaylistId) {
        _setSelectedLocalPlaylist(
          navProvider.selectedLocalPlaylistId,
          syncNav: false,
        );
      }
      _refreshCloudData();
    });
  }

  @override
  void dispose() {
    _cloudSearchDebounce?.cancel();
    _emailController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _localTracksScrollController.dispose();
    _cloudTracksScrollController.dispose();
    _cloudPlaylistsScrollController.dispose();
    super.dispose();
  }

  @override
  bool get wantKeepAlive => true;

  Future<void> _refreshCloudData() async {
    if (!mounted) return;
    final cloudMusicProvider = context.read<CloudMusicProvider>();
    final localMusicProvider = context.read<LocalMusicProvider>();
    await Future.wait([
      cloudMusicProvider.fetchUserLibrary(
        reset: true,
        search: _selectedCloudPlaylistId == null ? _cloudTracksSearchQuery : '',
      ),
      cloudMusicProvider.fetchUserPlaylists(reset: true),
      cloudMusicProvider.fetchStorageUsage(),
    ]);

    final selectedId = _selectedCloudPlaylistId;
    if (selectedId != null &&
        !cloudMusicProvider.playlists.any((item) => item.id == selectedId)) {
      setState(() {
        _selectedCloudPlaylistId = null;
      });
    }

    final selectedCloudPlaylistId = _selectedCloudPlaylistId;
    if (selectedCloudPlaylistId != null) {
      await cloudMusicProvider.fetchPlaylistTracks(
        selectedCloudPlaylistId,
        reset: true,
        search: _cloudTracksSearchQuery,
      );
    }

    await _syncCloudFavoritesLikesToLocal(
      cloudMusicProvider: cloudMusicProvider,
      localMusicProvider: localMusicProvider,
    );
  }

  void _handleCloudTracksLazyLoad() {
    if (!mounted || !_cloudTracksScrollController.hasClients) return;
    final position = _cloudTracksScrollController.position;
    if (position.extentAfter > 240) return;

    final cloudMusicProvider = context.read<CloudMusicProvider>();
    final selectedCloudPlaylistId = _selectedCloudPlaylistId;
    if (selectedCloudPlaylistId == null) {
      cloudMusicProvider.loadMoreUserLibrary();
      return;
    }
    cloudMusicProvider.loadMorePlaylistTracks(selectedCloudPlaylistId);
  }

  void _handleCloudPlaylistsLazyLoad() {
    if (!mounted || !_cloudPlaylistsScrollController.hasClients) return;
    final position = _cloudPlaylistsScrollController.position;
    if (position.extentAfter > 200) return;
    context.read<CloudMusicProvider>().loadMoreUserPlaylists();
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
    final showFolderImportOption = Platform.isAndroid;
    final showAutoScanOption = Platform.isAndroid;
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
                if (showFolderImportOption)
                  ListTile(
                    leading: const Icon(Icons.folder_rounded),
                    title: Text(t('pick_folder')),
                    subtitle: Text(t('import_from_folder_with_filters')),
                    onTap: () async {
                      Navigator.of(sheetContext).pop();
                      await _pickLocalFolderWithFilters();
                    },
                  ),
                if (showAutoScanOption)
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
    Directory baseDir;
    if (Platform.isAndroid) {
      final baseExternalDir = await getExternalStorageDirectory();
      baseDir = baseExternalDir ?? await getApplicationDocumentsDirectory();
    } else {
      baseDir = await getApplicationDocumentsDirectory();
    }
    final cloudTuneDir = Directory(p.join(baseDir.path, 'CloudTune'));

    if (!await cloudTuneDir.exists()) {
      await cloudTuneDir.create(recursive: true);
    }
    return cloudTuneDir;
  }

  String _sanitizeFileName(String name) {
    final sanitized = name
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_')
        .trim();
    if (sanitized.isEmpty) {
      return 'track_${DateTime.now().millisecondsSinceEpoch}.bin';
    }
    return sanitized;
  }

  Future<String> _resolveUniquePath({
    required Directory dir,
    required String fileName,
  }) async {
    final sanitizedName = _sanitizeFileName(fileName);
    var candidatePath = p.join(dir.path, sanitizedName);
    var counter = 1;

    while (await File(candidatePath).exists()) {
      final base = p.basenameWithoutExtension(sanitizedName);
      final ext = p.extension(sanitizedName);
      candidatePath = p.join(dir.path, '$base ($counter)$ext');
      counter++;
    }
    return candidatePath;
  }

  bool _pathsEqual(String left, String right) {
    if (Platform.isWindows) {
      return left.toLowerCase() == right.toLowerCase();
    }
    return left == right;
  }

  bool _isCurrentTrackPath(String? currentPath, String targetPath) {
    if (currentPath == null) return false;
    return _pathsEqual(currentPath, targetPath);
  }

  String _pathSelectionKey(String path) {
    return Platform.isWindows ? path.toLowerCase() : path;
  }

  bool _isLocalTrackSelectionMode() => _selectedLocalTrackPaths.isNotEmpty;

  void _clearLocalTrackSelection() {
    if (_selectedLocalTrackPaths.isEmpty || !mounted) return;
    setState(() => _selectedLocalTrackPaths.clear());
  }

  void _startLocalTrackSelection(String trackPath) {
    if (!mounted) return;
    setState(() {
      _selectedLocalTrackPaths
        ..clear()
        ..add(trackPath);
    });
  }

  void _toggleLocalTrackSelection(String trackPath) {
    if (!mounted) return;
    setState(() {
      if (_selectedLocalTrackPaths.contains(trackPath)) {
        _selectedLocalTrackPaths.remove(trackPath);
      } else {
        _selectedLocalTrackPaths.add(trackPath);
      }
    });
  }

  List<File> _resolveTrackActionTargets({
    required File anchorTrack,
    required List<File> playlistTracks,
  }) {
    if (_selectedLocalTrackPaths.isEmpty ||
        !_selectedLocalTrackPaths.contains(anchorTrack.path)) {
      return <File>[anchorTrack];
    }

    final selectedKeys = _selectedLocalTrackPaths
        .map(_pathSelectionKey)
        .toSet();
    final uniqueByPath = <String, File>{};
    for (final file in playlistTracks) {
      final key = _pathSelectionKey(file.path);
      if (!selectedKeys.contains(key)) continue;
      uniqueByPath.putIfAbsent(key, () => file);
    }

    if (uniqueByPath.isEmpty) {
      return <File>[anchorTrack];
    }
    return uniqueByPath.values.toList();
  }

  void _setSelectedLocalPlaylist(String playlistId, {bool syncNav = true}) {
    if (_selectedLocalPlaylistId != playlistId && mounted) {
      setState(() {
        _selectedLocalPlaylistId = playlistId;
        _selectedLocalTrackPaths.clear();
      });
    }
    if (syncNav) {
      context.read<MainNavProvider>().setSelectedLocalPlaylistId(playlistId);
    }
  }

  void _maybeAutoScrollToCurrentLocalTrack({
    required List<File> visibleLocalTracks,
    required String? currentTrackPath,
  }) {
    if (_storageType != _StorageType.local) return;
    if (currentTrackPath == null || visibleLocalTracks.isEmpty) return;

    final targetIndex = visibleLocalTracks.indexWhere(
      (item) => _pathsEqual(item.path, currentTrackPath),
    );
    if (targetIndex < 0) return;

    final key =
        '$_selectedLocalPlaylistId|$currentTrackPath|$targetIndex|${visibleLocalTracks.length}';
    if (_lastLocalTracksAutoScrollKey == key) return;
    _lastLocalTracksAutoScrollKey = key;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_localTracksScrollController.hasClients) return;
      final position = _localTracksScrollController.position;
      final itemExtent = 84.0;
      final viewportHeight = position.viewportDimension;
      final targetOffset =
          ((targetIndex * itemExtent) - (viewportHeight * 0.35)).clamp(
            0.0,
            position.maxScrollExtent,
          );
      if ((position.pixels - targetOffset).abs() < 20) return;

      final platform = Theme.of(context).platform;
      final isMobilePlatform =
          platform == TargetPlatform.android || platform == TargetPlatform.iOS;

      if (isMobilePlatform) {
        _localTracksScrollController.jumpTo(targetOffset);
        return;
      }

      _localTracksScrollController.animateTo(
        targetOffset,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    });
  }

  bool _isCloudFavoritesPlaylist(Playlist playlist) {
    if (playlist.isFavorite) return true;

    final normalized = playlist.name.trim().toLowerCase();
    if (normalized.isEmpty) return false;

    final localizedLiked = AppLocalizations.text(
      context,
      'liked_songs',
    ).trim().toLowerCase();

    return normalized == localizedLiked ||
        normalized == 'liked songs' ||
        normalized == 'Р»СЋР±РёРјС‹Рµ';
  }

  String _cloudPlaylistDisplayName(Playlist playlist) {
    if (_isCloudFavoritesPlaylist(playlist)) {
      return AppLocalizations.text(context, 'liked_songs');
    }
    return playlist.name;
  }

  String _trackLookupName(String value) {
    return p.basename(value).trim().toLowerCase();
  }

  String _trackLookupNameWithSizeKey({
    required String trackName,
    required int? fileSize,
  }) {
    if (fileSize == null || fileSize < 0) return trackName;
    return '$trackName|$fileSize';
  }

  int? _safeLocalFileSize(File file) {
    try {
      final fileSize = file.lengthSync();
      if (fileSize < 0) return null;
      return fileSize;
    } catch (_) {
      return null;
    }
  }

  String _supportedUploadFormatsLabel() {
    return _supportedAudioExtensions
        .map((item) => item.replaceFirst('.', '').toUpperCase())
        .join(', ');
  }

  bool _isUploadableAudioFile(File file) {
    final extension = p.extension(file.path).toLowerCase();
    return _supportedAudioExtensionsSet.contains(extension);
  }

  String _uploadFailureReason(Object? rawReason) {
    if (rawReason is String && rawReason.trim().isNotEmpty) {
      return rawReason.trim();
    }
    return 'Upload failed';
  }

  String _unsupportedUploadMessage(File file) {
    final extension = p.extension(file.path).toLowerCase();
    final extensionLabel = extension.isEmpty ? 'unknown' : extension;
    return 'Unsupported format "$extensionLabel". Allowed: ${_supportedUploadFormatsLabel()}';
  }

  Future<({bool success, List<Track> tracks, String? message})>
  _fetchAllCloudPlaylistTracks(int playlistId) async {
    const pageLimit = 200;
    var offset = 0;
    final tracks = <Track>[];
    final seenTrackIds = <int>{};

    while (true) {
      final result = await _apiService.getPlaylistSongs(
        playlistId,
        limit: pageLimit,
        offset: offset,
      );
      if (result['success'] != true) {
        return (
          success: false,
          tracks: tracks,
          message: _uploadFailureReason(result['message']),
        );
      }

      final pageTracks = (result['songs'] as List<dynamic>)
          .map((item) => Track.fromJson(item as Map<String, dynamic>))
          .toList();
      if (pageTracks.isEmpty) {
        break;
      }

      for (final track in pageTracks) {
        if (seenTrackIds.add(track.id)) {
          tracks.add(track);
        }
      }

      final hasMore = result['has_more'] == true;
      if (!hasMore) {
        break;
      }
      offset += pageTracks.length;
    }

    return (success: true, tracks: tracks, message: null);
  }

  int? _resolveCloudSongIdForLocalTrack({
    required String trackName,
    required int? fileSize,
    required Map<String, int> cloudSongIdByNameAndSize,
    required Map<String, int> cloudSongIdByName,
  }) {
    if (fileSize != null && fileSize >= 0) {
      final sizedKey = _trackLookupNameWithSizeKey(
        trackName: trackName,
        fileSize: fileSize,
      );
      final sizedMatch = cloudSongIdByNameAndSize[sizedKey];
      if (sizedMatch != null) return sizedMatch;
      return null;
    }
    return cloudSongIdByName[trackName];
  }

  bool _isTrackAlreadyInCloudLibrary(File file, CloudMusicProvider provider) {
    final key = _trackLookupName(file.path);
    final localFileSize = _safeLocalFileSize(file);
    for (final track in provider.tracks) {
      final cloudKey = _trackLookupName(
        track.originalFilename ?? track.filename,
      );
      if (cloudKey != key) continue;

      final cloudFileSize = track.filesize;
      if (localFileSize != null) {
        if (cloudFileSize == null || cloudFileSize < 0) continue;
        if (localFileSize != cloudFileSize) continue;
      }
      return true;
    }
    return false;
  }

  String _normalizePlaylistName(String value) => value.trim().toLowerCase();

  int? _extractSongIdFromUploadResult(Map<String, dynamic> uploadResult) {
    final rawSongID = uploadResult['data']?['song_id'];
    if (rawSongID is int) return rawSongID;
    if (rawSongID is num) return rawSongID.toInt();
    if (rawSongID is String) return int.tryParse(rawSongID);

    final nestedSongID = uploadResult['data']?['song']?['id'];
    if (nestedSongID is int) return nestedSongID;
    if (nestedSongID is num) return nestedSongID.toInt();
    if (nestedSongID is String) return int.tryParse(nestedSongID);

    final topLevelSongID = uploadResult['song_id'];
    if (topLevelSongID is int) return topLevelSongID;
    if (topLevelSongID is num) return topLevelSongID.toInt();
    if (topLevelSongID is String) return int.tryParse(topLevelSongID);

    return null;
  }

  String _playlistTrackCounterLabel({
    required String syncKey,
    required int trackCount,
  }) {
    return _playlistProgressTracker.counterLabel(
      syncKey: syncKey,
      trackCount: trackCount,
      tracksLabel: AppLocalizations.text(context, 'tracks'),
    );
  }

  Future<void> _syncCloudFavoritesLikesToLocal({
    required CloudMusicProvider cloudMusicProvider,
    required LocalMusicProvider localMusicProvider,
  }) async {
    final favoritePlaylist = cloudMusicProvider.playlists
        .cast<Playlist?>()
        .firstWhere(
          (item) => item != null && _isCloudFavoritesPlaylist(item),
          orElse: () => null,
        );
    if (favoritePlaylist == null) return;

    await cloudMusicProvider.fetchPlaylistTracks(
      favoritePlaylist.id,
      reset: true,
    );
    while (cloudMusicProvider.hasMorePlaylistTracks(favoritePlaylist.id)) {
      await cloudMusicProvider.loadMorePlaylistTracks(favoritePlaylist.id);
    }

    final favoriteSongs = cloudMusicProvider.getTracksForPlaylist(
      favoritePlaylist.id,
    );

    final cloudLibraryNames = cloudMusicProvider.tracks
        .map((item) => _trackLookupName(item.originalFilename ?? item.filename))
        .toSet();
    final likedNames = favoriteSongs
        .map((item) => _trackLookupName(item.originalFilename ?? item.filename))
        .toSet();

    final candidatePaths = <String>{};
    final likedPaths = <String>{};
    for (final file in localMusicProvider.selectedFiles) {
      final localName = _trackLookupName(file.path);
      if (!cloudLibraryNames.contains(localName)) continue;
      candidatePaths.add(file.path);
      if (likedNames.contains(localName)) {
        likedPaths.add(file.path);
      }
    }

    await localMusicProvider.syncLikedTracksForCandidates(
      likedTrackPaths: likedPaths,
      candidateTrackPaths: candidatePaths,
    );
  }

  Future<File?> _ensureCloudTrackDownloaded(
    Track track,
    CloudMusicProvider cloudMusicProvider,
  ) async {
    final fileName = track.originalFilename ?? track.filename;
    final targetDir = await _getPersistentDownloadDir();
    final sanitizedName = _sanitizeFileName(fileName);
    final existingPath = p.join(targetDir.path, sanitizedName);
    final existingFile = File(existingPath);
    if (await existingFile.exists()) {
      final expectedSize = track.filesize;
      if (expectedSize != null) {
        final actualSize = await existingFile.length();
        if (actualSize != expectedSize) {
          final refreshed = await cloudMusicProvider.downloadTrack(
            track.id,
            existingPath,
          );
          if (!refreshed) return null;
        }
      }
      return existingFile;
    }

    final savePath = await _resolveUniquePath(
      dir: targetDir,
      fileName: fileName,
    );
    final success = await cloudMusicProvider.downloadTrack(track.id, savePath);
    if (!success) return null;
    final downloadedFile = File(savePath);
    if (!await downloadedFile.exists()) return null;
    return downloadedFile;
  }

  Future<void> _downloadTrack(Track track) async {
    if (_downloadingTrackIds.contains(track.id)) return;
    setState(() => _downloadingTrackIds.add(track.id));

    final cloudMusicProvider = context.read<CloudMusicProvider>();
    final localMusicProvider = context.read<LocalMusicProvider>();

    try {
      final fileName = track.originalFilename ?? track.filename;
      final downloadedFile = await _ensureCloudTrackDownloaded(
        track,
        cloudMusicProvider,
      );
      if (!mounted) return;

      if (downloadedFile != null) {
        await localMusicProvider.addFiles([downloadedFile]);
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

  Future<({bool success, String? failureReason})> _uploadLocalTrack(
    File file, {
    bool silent = false,
    bool refreshCloudData = true,
  }) async {
    if (!_isUploadableAudioFile(file)) {
      final reason = _unsupportedUploadMessage(file);
      if (!silent && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(reason)));
      }
      return (success: false, failureReason: reason);
    }

    if (_uploadingPaths.contains(file.path)) {
      return (success: false, failureReason: 'Upload already in progress');
    }
    setState(() => _uploadingPaths.add(file.path));

    var uploaded = false;
    String? failureReason;
    try {
      final cloudMusicProvider = context.read<CloudMusicProvider>();
      if (_isTrackAlreadyInCloudLibrary(file, cloudMusicProvider)) {
        uploaded = true;
        if (!silent && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Already in cloud: ${p.basename(file.path)}'),
            ),
          );
        }
        return (success: true, failureReason: null);
      }

      final result = await _apiService.uploadFile(file);
      if (result['success'] == true) {
        uploaded = true;
        if (refreshCloudData) {
          await _refreshCloudData();
        }
        if (!mounted) {
          return (success: true, failureReason: null);
        }
        if (!silent && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Uploaded: ${p.basename(file.path)}')),
          );
        }
      } else {
        failureReason = _uploadFailureReason(result['message']);
        if (!silent && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Upload failed: $failureReason')),
          );
        }
      }
    } catch (error) {
      failureReason = _uploadFailureReason(error.toString());
      if (!silent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Upload failed: $failureReason')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _uploadingPaths.remove(file.path));
      }
    }
    return (success: uploaded, failureReason: failureReason);
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

  String _localTrackSortLabel(_LocalTrackSort sort, BuildContext context) {
    switch (sort) {
      case _LocalTrackSort.addedToPlayer:
        return 'РџРѕ РґР°С‚Рµ РґРѕР±Р°РІР»РµРЅРёСЏ';
      case _LocalTrackSort.name:
        return 'РџРѕ РЅР°Р·РІР°РЅРёСЋ';
      case _LocalTrackSort.fileModified:
        return 'РџРѕ РґР°С‚Рµ РёР·РјРµРЅРµРЅРёСЏ С„Р°Р№Р»Р°';
    }
  }

  String _cloudTrackSortLabel(_CloudTrackSort sort) {
    switch (sort) {
      case _CloudTrackSort.uploadDate:
        return 'By upload date';
      case _CloudTrackSort.name:
        return 'By name';
      case _CloudTrackSort.fileSize:
        return 'By file size';
    }
  }

  String _cloudTrackSortButtonLabel() {
    switch (_cloudTrackSort) {
      case _CloudTrackSort.uploadDate:
        return 'Date';
      case _CloudTrackSort.name:
        return 'Name';
      case _CloudTrackSort.fileSize:
        return 'Size';
    }
  }

  int _safeFileModifiedEpoch(File file) {
    try {
      return file.statSync().modified.millisecondsSinceEpoch;
    } catch (_) {
      return 0;
    }
  }

  List<File> _sortLocalTracks({
    required List<File> playlistTracks,
    required List<File> allLocalTracks,
  }) {
    final sorted = List<File>.from(playlistTracks);

    switch (_localTrackSort) {
      case _LocalTrackSort.addedToPlayer:
        final indexByPath = <String, int>{
          for (var i = 0; i < allLocalTracks.length; i++)
            _pathSelectionKey(allLocalTracks[i].path): i,
        };
        sorted.sort((left, right) {
          final leftIndex = indexByPath[_pathSelectionKey(left.path)] ?? -1;
          final rightIndex = indexByPath[_pathSelectionKey(right.path)] ?? -1;
          return rightIndex.compareTo(leftIndex);
        });
        break;
      case _LocalTrackSort.name:
        sorted.sort(
          (left, right) => p
              .basenameWithoutExtension(left.path)
              .toLowerCase()
              .compareTo(p.basenameWithoutExtension(right.path).toLowerCase()),
        );
        break;
      case _LocalTrackSort.fileModified:
        sorted.sort(
          (left, right) => _safeFileModifiedEpoch(
            right,
          ).compareTo(_safeFileModifiedEpoch(left)),
        );
        break;
    }

    return sorted;
  }

  List<Track> _sortCloudTracks(List<Track> tracks) {
    final sorted = List<Track>.from(tracks);

    String trackName(Track track) {
      final original = track.originalFilename?.trim();
      if (original != null && original.isNotEmpty) return original;
      return track.filename;
    }

    switch (_cloudTrackSort) {
      case _CloudTrackSort.uploadDate:
        sorted.sort(
          (left, right) => right.uploadDate.compareTo(left.uploadDate),
        );
        break;
      case _CloudTrackSort.name:
        sorted.sort(
          (left, right) => trackName(
            left,
          ).toLowerCase().compareTo(trackName(right).toLowerCase()),
        );
        break;
      case _CloudTrackSort.fileSize:
        sorted.sort(
          (left, right) =>
              (right.filesize ?? -1).compareTo(left.filesize ?? -1),
        );
        break;
    }

    return sorted;
  }

  bool _matchesLocalTrackSearch(File file) {
    if (_localTracksSearchQuery.trim().isEmpty) return true;
    final query = _localTracksSearchQuery.toLowerCase().trim();
    final fileName = p.basename(file.path).toLowerCase();
    final fileTitle = p.basenameWithoutExtension(file.path).toLowerCase();
    return fileName.contains(query) || fileTitle.contains(query);
  }

  void _onCloudTrackSearchChanged(String value) {
    _cloudSearchDebounce?.cancel();
    _cloudSearchDebounce = Timer(const Duration(milliseconds: 320), () async {
      if (!mounted) return;
      final query = value.trim();
      setState(() => _cloudTracksSearchQuery = query);
      final cloudMusicProvider = context.read<CloudMusicProvider>();
      final selectedCloudPlaylistId = _selectedCloudPlaylistId;
      if (selectedCloudPlaylistId == null) {
        await cloudMusicProvider.fetchUserLibrary(reset: true, search: query);
        return;
      }
      await cloudMusicProvider.fetchPlaylistTracks(
        selectedCloudPlaylistId,
        reset: true,
        search: query,
      );
    });
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
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              t('select_tracks'),
                              style: textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          OutlinedButton.icon(
                            onPressed: () {
                              setModalState(() {
                                if (selectedPaths.length ==
                                    localTracks.length) {
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
                        ],
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
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 220),
                                curve: Curves.easeOutCubic,
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
                                    AnimatedSwitcher(
                                      duration: const Duration(
                                        milliseconds: 180,
                                      ),
                                      transitionBuilder: (child, animation) {
                                        return ScaleTransition(
                                          scale: animation,
                                          child: FadeTransition(
                                            opacity: animation,
                                            child: child,
                                          ),
                                        );
                                      },
                                      child: isSelected
                                          ? Icon(
                                              Icons.check_rounded,
                                              key: const ValueKey('selected'),
                                              color: colorScheme.onPrimary,
                                            )
                                          : const SizedBox(
                                              key: ValueKey('not_selected'),
                                              width: 20,
                                              height: 20,
                                            ),
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
                                  _setSelectedLocalPlaylist(playlistId);
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
      _setSelectedLocalPlaylist(LocalMusicProvider.allPlaylistId);
    }
  }

  Future<void> _uploadLocalPlaylistToCloud({
    required LocalPlaylist playlist,
    required LocalMusicProvider localMusicProvider,
  }) async {
    final playlistTracks = localMusicProvider.getTracksForPlaylist(playlist.id);
    await _uploadTracksAsCloudPlaylist(
      syncKey: playlist.id,
      playlistName: playlist.name,
      playlistTracks: playlistTracks,
      isFavorite: false,
    );
  }

  Future<void> _uploadSystemPlaylistToCloud({
    required String playlistId,
    required String playlistName,
    required LocalMusicProvider localMusicProvider,
    bool silent = false,
  }) async {
    final playlistTracks = localMusicProvider.getTracksForPlaylist(playlistId);
    await _uploadTracksAsCloudPlaylist(
      syncKey: 'system_$playlistId',
      playlistName: playlistName,
      playlistTracks: playlistTracks,
      isFavorite: playlistId == LocalMusicProvider.likedPlaylistId,
      silent: silent,
    );
  }

  Future<
    ({
      Map<String, int> uploadedSongIDsByPath,
      Map<String, String> failedUploadsByPath,
      int completedTracks,
    })
  >
  _uploadMissingCloudTracks({
    required List<File> missingFiles,
    required String syncKey,
    required String playlistName,
    required int completedTracks,
    required int totalTracks,
  }) async {
    if (missingFiles.isEmpty) {
      return (
        uploadedSongIDsByPath: <String, int>{},
        failedUploadsByPath: <String, String>{},
        completedTracks: completedTracks,
      );
    }

    final uploadBatch = await _syncController.uploadMissingTracks(
      missingFiles: missingFiles,
      completedTracks: completedTracks,
      totalTracks: totalTracks,
      isUploadableAudioFile: _isUploadableAudioFile,
      unsupportedUploadMessage: _unsupportedUploadMessage,
      uploadFailureReason: _uploadFailureReason,
      extractSongIdFromUploadResult: _extractSongIdFromUploadResult,
      onProgress: (completed, total) async {
        if (mounted) {
          setState(() {
            _playlistProgressTracker.setProgress(
              syncKey,
              uploaded: completed,
              total: total,
            );
          });
        }
        await UploadNotificationService.showPlaylistUploadProgress(
          syncKey: syncKey,
          playlistName: playlistName,
          uploadedTracks: completed,
          totalTracks: total,
        );
      },
    );

    return (
      uploadedSongIDsByPath: uploadBatch.uploadedSongIDsByPath,
      failedUploadsByPath: uploadBatch.failedUploadsByPath,
      completedTracks: uploadBatch.completedTracks,
    );
  }

  Future<void> _uploadTracksAsCloudPlaylist({
    required String syncKey,
    required String playlistName,
    required List<File> playlistTracks,
    required bool isFavorite,
    bool silent = false,
  }) async {
    if (_syncingLocalPlaylistIds.contains(syncKey)) return;

    if (playlistTracks.isEmpty) {
      if (!silent) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Playlist "$playlistName" is empty')),
        );
      }
      return;
    }

    setState(() {
      _syncingLocalPlaylistIds.add(syncKey);
      _playlistProgressTracker.clear(syncKey);
    });

    final totalTracks = playlistTracks.length;
    var completedTracks = 0;

    try {
      final cloudMusicProvider = context.read<CloudMusicProvider>();
      await cloudMusicProvider.fetchUserLibrary(reset: true, search: '');
      while (cloudMusicProvider.hasMoreTracks) {
        await cloudMusicProvider.loadMoreUserLibrary();
      }
      await cloudMusicProvider.fetchUserPlaylists(reset: true);
      while (cloudMusicProvider.hasMorePlaylists) {
        await cloudMusicProvider.loadMoreUserPlaylists();
      }

      final cloudSongIdByName = <String, int>{};
      final cloudSongIdByNameAndSize = <String, int>{};
      void seedCloudLookupMaps(Iterable<Track> tracks) {
        for (final track in tracks) {
          final key = _trackLookupName(
            track.originalFilename ?? track.filename,
          );
          cloudSongIdByName.putIfAbsent(key, () => track.id);

          final trackSize = track.filesize;
          if (trackSize == null || trackSize < 0) continue;
          final sizedKey = _trackLookupNameWithSizeKey(
            trackName: key,
            fileSize: trackSize,
          );
          cloudSongIdByNameAndSize.putIfAbsent(sizedKey, () => track.id);
        }
      }

      seedCloudLookupMaps(cloudMusicProvider.tracks);

      final localLookupByPath = <String, ({String trackName, int? fileSize})>{};
      ({String trackName, int? fileSize}) localLookup(File file) {
        final cached = localLookupByPath[file.path];
        if (cached != null) return cached;

        final lookup = (
          trackName: _trackLookupName(file.path),
          fileSize: _safeLocalFileSize(file),
        );
        localLookupByPath[file.path] = lookup;
        return lookup;
      }

      final desiredSongIDsInOrder = <int>[];
      final missingFiles = <File>[];
      for (final file in playlistTracks) {
        final lookup = localLookup(file);
        final matchedSongId = _resolveCloudSongIdForLocalTrack(
          trackName: lookup.trackName,
          fileSize: lookup.fileSize,
          cloudSongIdByNameAndSize: cloudSongIdByNameAndSize,
          cloudSongIdByName: cloudSongIdByName,
        );
        if (matchedSongId != null) {
          desiredSongIDsInOrder.add(matchedSongId);
          completedTracks += 1;
        } else {
          missingFiles.add(file);
        }
      }

      if (mounted) {
        setState(() {
          _playlistProgressTracker.setProgress(
            syncKey,
            uploaded: completedTracks,
            total: totalTracks,
          );
        });
      }
      await UploadNotificationService.showPlaylistUploadProgress(
        syncKey: syncKey,
        playlistName: playlistName,
        uploadedTracks: completedTracks,
        totalTracks: totalTracks,
      );

      final uploadedBatch = await _uploadMissingCloudTracks(
        missingFiles: missingFiles,
        syncKey: syncKey,
        playlistName: playlistName,
        completedTracks: completedTracks,
        totalTracks: totalTracks,
      );
      completedTracks = uploadedBatch.completedTracks;
      final uploadedSongIDsByPath = Map<String, int>.from(
        uploadedBatch.uploadedSongIDsByPath,
      );
      final failedUploadsByPath = Map<String, String>.from(
        uploadedBatch.failedUploadsByPath,
      );
      for (final file in missingFiles) {
        final uploadedSongID = uploadedSongIDsByPath[file.path];
        if (uploadedSongID != null) {
          desiredSongIDsInOrder.add(uploadedSongID);
          failedUploadsByPath.remove(file.path);
        }
      }

      if (missingFiles.isNotEmpty) {
        await cloudMusicProvider.fetchUserLibrary(reset: true, search: '');
        while (cloudMusicProvider.hasMoreTracks) {
          await cloudMusicProvider.loadMoreUserLibrary();
        }
        cloudSongIdByName.clear();
        cloudSongIdByNameAndSize.clear();
        seedCloudLookupMaps(cloudMusicProvider.tracks);

        var resolvedAfterUploadCount = 0;
        for (final file in missingFiles) {
          if (uploadedSongIDsByPath.containsKey(file.path)) continue;

          final lookup = localLookup(file);
          final resolvedSongID = _resolveCloudSongIdForLocalTrack(
            trackName: lookup.trackName,
            fileSize: lookup.fileSize,
            cloudSongIdByNameAndSize: cloudSongIdByNameAndSize,
            cloudSongIdByName: cloudSongIdByName,
          );
          if (resolvedSongID == null) {
            failedUploadsByPath.putIfAbsent(
              file.path,
              () =>
                  'Track is still missing in cloud library after upload verification',
            );
            continue;
          }

          uploadedSongIDsByPath[file.path] = resolvedSongID;
          desiredSongIDsInOrder.add(resolvedSongID);
          failedUploadsByPath.remove(file.path);
          resolvedAfterUploadCount += 1;
        }

        if (resolvedAfterUploadCount > 0) {
          completedTracks += resolvedAfterUploadCount;
          if (mounted) {
            setState(() {
              _playlistProgressTracker.setProgress(
                syncKey,
                uploaded: completedTracks,
                total: totalTracks,
              );
            });
          }
          await UploadNotificationService.showPlaylistUploadProgress(
            syncKey: syncKey,
            playlistName: playlistName,
            uploadedTracks: completedTracks,
            totalTracks: totalTracks,
          );
        }
      }

      if (desiredSongIDsInOrder.isEmpty) {
        if (!mounted) return;
        if (!silent) {
          final failureDetails = failedUploadsByPath.entries
              .map((entry) => '${p.basename(entry.key)}: ${entry.value}')
              .join(' | ');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                failureDetails.isEmpty
                    ? 'No tracks from "$playlistName" were matched in cloud library'
                    : 'Sync partial for "$playlistName": $failureDetails',
              ),
            ),
          );
        }
        await UploadNotificationService.showPlaylistUploadFinished(
          syncKey: syncKey,
          playlistName: playlistName,
          uploadedTracks: 0,
          totalTracks: totalTracks,
        );
        return;
      }

      final normalizedName = _normalizePlaylistName(playlistName);
      final existingPlaylist = cloudMusicProvider.playlists
          .cast<Playlist?>()
          .firstWhere((item) {
            if (item == null) return false;
            if (isFavorite && _isCloudFavoritesPlaylist(item)) return true;
            return _normalizePlaylistName(item.name) == normalizedName;
          }, orElse: () => null);
      if (existingPlaylist != null) {
        cloudMusicProvider.invalidatePlaylistTracks(existingPlaylist.id);
      }

      final createResult = await _apiService.createPlaylist(
        name: playlistName,
        description: 'Synced from local',
        isFavorite: isFavorite,
        replaceExisting: true,
      );
      if (createResult['success'] != true) {
        if (!mounted) return;
        if (!silent) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Cloud playlist create failed: ${createResult['message']}',
              ),
            ),
          );
        }
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
        if (!silent) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Cloud playlist id missing in response'),
            ),
          );
        }
        return;
      }

      final uniqueSongIDsInOrder = <int>[];
      final seenSongIDs = <int>{};
      for (final songID in desiredSongIDsInOrder) {
        if (seenSongIDs.add(songID)) {
          uniqueSongIDsInOrder.add(songID);
        }
      }

      final desiredSongIDsSet = uniqueSongIDsInOrder.toSet();
      final deduplicatedBySongIdCount =
          completedTracks - uniqueSongIDsInOrder.length;
      var finalLinkedCount = 0;
      var lastReconcileReason = '';

      final bulkResult = await _apiService.addSongsToPlaylistBulk(
        playlistId: cloudPlaylistID,
        songIds: uniqueSongIDsInOrder,
      );
      if (bulkResult['success'] != true) {
        lastReconcileReason =
            'bulk add failed: ${_uploadFailureReason(bulkResult['message'])}';
        for (final songID in uniqueSongIDsInOrder) {
          final addResult = await _apiService.addSongToPlaylist(
            playlistId: cloudPlaylistID,
            songId: songID,
          );
          if (addResult['success'] != true) {
            lastReconcileReason = _uploadFailureReason(addResult['message']);
          }
        }
      } else {
        final skippedNotInLibraryCount =
            (bulkResult['skipped_not_in_library_song_ids'] as List<dynamic>?)
                ?.length ??
            0;
        if (skippedNotInLibraryCount > 0 && lastReconcileReason.isEmpty) {
          lastReconcileReason =
              '$skippedNotInLibraryCount song(s) were skipped as not in cloud library';
        }
      }

      for (var attempt = 0; attempt < 3; attempt++) {
        final verifySnapshot = await _fetchAllCloudPlaylistTracks(
          cloudPlaylistID,
        );
        if (!verifySnapshot.success) {
          lastReconcileReason =
              'playlist verify failed: ${verifySnapshot.message ?? 'unknown'}';
          break;
        }

        final currentSongIDs = verifySnapshot.tracks
            .map((item) => item.id)
            .toSet();
        finalLinkedCount = desiredSongIDsSet
            .where((songID) => currentSongIDs.contains(songID))
            .length;
        final missingSongIDs = uniqueSongIDsInOrder
            .where((songID) => !currentSongIDs.contains(songID))
            .toList();

        if (missingSongIDs.isEmpty) {
          break;
        }

        var addedInAttempt = 0;
        for (final songID in missingSongIDs) {
          final addResult = await _apiService.addSongToPlaylist(
            playlistId: cloudPlaylistID,
            songId: songID,
          );
          if (addResult['success'] == true) {
            addedInAttempt += 1;
            continue;
          }
          lastReconcileReason =
              'song_id=$songID: ${_uploadFailureReason(addResult['message'])}';
        }

        if (addedInAttempt == 0) {
          if (lastReconcileReason.isEmpty) {
            lastReconcileReason = 'reconcile could not add missing songs';
          }
          break;
        }
      }

      final finalVerifySnapshot = await _fetchAllCloudPlaylistTracks(
        cloudPlaylistID,
      );
      final missingSongIDsAfterReconcile = <int>[];
      if (finalVerifySnapshot.success) {
        final currentSongIDs = finalVerifySnapshot.tracks
            .map((item) => item.id)
            .toSet();
        for (final songID in uniqueSongIDsInOrder) {
          if (!currentSongIDs.contains(songID)) {
            missingSongIDsAfterReconcile.add(songID);
          }
        }
        finalLinkedCount = desiredSongIDsSet
            .where((songID) => currentSongIDs.contains(songID))
            .length;
      } else if (lastReconcileReason.isEmpty) {
        lastReconcileReason =
            'final verify failed: ${finalVerifySnapshot.message ?? 'unknown'}';
      }

      final unresolvedUploadCount = (totalTracks - completedTracks)
          .clamp(0, totalTracks)
          .toInt();
      final missingLinkCount = missingSongIDsAfterReconcile.length;
      final syncComplete =
          unresolvedUploadCount == 0 &&
          deduplicatedBySongIdCount <= 0 &&
          missingLinkCount == 0 &&
          finalLinkedCount >= uniqueSongIDsInOrder.length;

      final reasonParts = <String>[];
      if (unresolvedUploadCount > 0) {
        final uniqueUploadFailures = failedUploadsByPath.values
            .toSet()
            .toList();
        if (uniqueUploadFailures.isEmpty) {
          reasonParts.add('$unresolvedUploadCount track(s) failed upload');
        } else {
          reasonParts.add(
            '$unresolvedUploadCount track(s) failed upload: ${uniqueUploadFailures.take(3).join(' | ')}',
          );
        }
      }
      if (deduplicatedBySongIdCount > 0) {
        reasonParts.add(
          '$deduplicatedBySongIdCount track(s) were merged by server deduplication',
        );
      }
      if (missingLinkCount > 0) {
        reasonParts.add(
          '$missingLinkCount playlist link(s) are still missing after reconcile',
        );
      }
      if (lastReconcileReason.isNotEmpty) {
        reasonParts.add(lastReconcileReason);
      }

      await _refreshCloudData();
      await UploadNotificationService.showPlaylistUploadFinished(
        syncKey: syncKey,
        playlistName: playlistName,
        uploadedTracks: finalLinkedCount,
        totalTracks: totalTracks,
      );
      if (!mounted) return;
      if (!silent) {
        final reasonText = reasonParts.join('; ');
        final message = syncComplete
            ? 'Playlist "$playlistName" sync complete ($finalLinkedCount/$totalTracks)'
            : reasonText.isEmpty
            ? 'Playlist "$playlistName" sync partial ($finalLinkedCount/$totalTracks)'
            : 'Playlist "$playlistName" sync partial ($finalLinkedCount/$totalTracks): $reasonText';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            duration: const Duration(seconds: 8),
          ),
        );
      }
    } catch (error) {
      await UploadNotificationService.showPlaylistUploadFinished(
        syncKey: syncKey,
        playlistName: playlistName,
        uploadedTracks: completedTracks,
        totalTracks: totalTracks,
      );
      if (!mounted || silent) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Playlist sync partial: ${error.toString()}')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _syncingLocalPlaylistIds.remove(syncKey);
          _playlistProgressTracker.clear(syncKey);
        });
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
      final playlistDisplayName = _cloudPlaylistDisplayName(playlist);
      final playlistSnapshot = await _fetchAllCloudPlaylistTracks(playlist.id);
      if (!playlistSnapshot.success) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to load cloud playlist: ${playlistSnapshot.message ?? 'unknown'}',
            ),
          ),
        );
        return;
      }

      final songs = playlistSnapshot.tracks;
      if (songs.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Cloud playlist "$playlistDisplayName" is empty'),
          ),
        );
        return;
      }

      final downloadedFiles = <File>[];
      for (final song in songs) {
        final downloaded = await _ensureCloudTrackDownloaded(
          song,
          cloudMusicProvider,
        );
        if (downloaded == null) continue;
        downloadedFiles.add(downloaded);
      }

      if (downloadedFiles.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No tracks downloaded from "$playlistDisplayName"'),
          ),
        );
        return;
      }

      await localMusicProvider.addFiles(downloadedFiles);
      final downloadedPaths = downloadedFiles.map((file) => file.path).toSet();

      String? localPlaylistId;
      if (_isCloudFavoritesPlaylist(playlist)) {
        await localMusicProvider.ensureTracksLiked(downloadedPaths);
        localPlaylistId = LocalMusicProvider.likedPlaylistId;
      } else {
        localPlaylistId = await localMusicProvider.upsertPlaylistByName(
          name: playlistDisplayName,
          trackPaths: downloadedPaths,
        );
      }

      if (mounted) {
        _setSelectedLocalPlaylist(
          localPlaylistId ?? LocalMusicProvider.allPlaylistId,
        );
        setState(() {
          _storageType = _StorageType.local;
        });
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Downloaded "$playlistDisplayName" (${downloadedFiles.length} tracks)',
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
    final cloudMusicProvider = context.read<CloudMusicProvider>();
    final result = await _apiService.deleteSong(track.id);
    if (!mounted) return;

    if (result['success'] == true) {
      cloudMusicProvider.invalidatePlaylistTracks();
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
    final cloudMusicProvider = context.read<CloudMusicProvider>();

    try {
      final result = await _apiService.deletePlaylist(playlist.id);
      if (!mounted) return;

      if (result['success'] == true) {
        cloudMusicProvider.invalidatePlaylistTracks(playlist.id);
        if (_selectedCloudPlaylistId == playlist.id) {
          setState(() {
            _selectedCloudPlaylistId = null;
          });
        }
        await _refreshCloudData();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Deleted cloud playlist "${_cloudPlaylistDisplayName(playlist)}"',
            ),
          ),
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
    final cloudMusicProvider = context.read<CloudMusicProvider>();
    if (playlistId == null) {
      if (!mounted) return;
      setState(() {
        _selectedCloudPlaylistId = null;
      });
      await cloudMusicProvider.fetchUserLibrary(
        reset: true,
        search: _cloudTracksSearchQuery,
      );
      return;
    }

    setState(() {
      _selectedCloudPlaylistId = playlistId;
    });

    await cloudMusicProvider.fetchPlaylistTracks(
      playlistId,
      reset: true,
      search: _cloudTracksSearchQuery,
    );
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

    setState(() {
      _storageType = nextType;
      _selectedLocalTrackPaths.clear();
    });

    final isCloudAuthed = context.read<AuthProvider>().currentUser != null;
    if (nextType == _StorageType.cloud && isCloudAuthed) {
      await _refreshCloudData();
    }
  }

  List<File> _uniqueFilesByPath(Iterable<File> files) {
    final unique = <String, File>{};
    for (final file in files) {
      unique.putIfAbsent(_pathSelectionKey(file.path), () => file);
    }
    return unique.values.toList();
  }

  Future<void> _uploadLocalTracks(List<File> files) async {
    final uniqueFiles = _uniqueFilesByPath(files);
    if (uniqueFiles.isEmpty) return;

    final authProvider = context.read<AuthProvider>();
    final cloudMusicProvider = context.read<CloudMusicProvider>();
    if (authProvider.currentUser != null) {
      await cloudMusicProvider.fetchUserLibrary(reset: true, search: '');
      while (cloudMusicProvider.hasMoreTracks) {
        await cloudMusicProvider.loadMoreUserLibrary();
      }
    }

    var successCount = 0;
    final failureReasonsByFile = <String, String>{};
    for (final file in uniqueFiles) {
      final uploadResult = await _uploadLocalTrack(
        file,
        silent: true,
        refreshCloudData: false,
      );
      if (uploadResult.success) {
        successCount += 1;
        continue;
      }
      failureReasonsByFile[p.basename(file.path)] = _uploadFailureReason(
        uploadResult.failureReason,
      );
    }
    if (successCount > 0) {
      await _refreshCloudData();
    }
    if (!mounted) return;

    if (uniqueFiles.length == 1) {
      final fileName = p.basename(uniqueFiles.first.path);
      final failureReason = failureReasonsByFile[fileName];
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            successCount == 1
                ? 'Uploaded: $fileName'
                : 'Upload failed: $fileName${failureReason == null ? "" : " ($failureReason)"}',
          ),
        ),
      );
      return;
    }

    if (failureReasonsByFile.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Uploaded $successCount/${uniqueFiles.length} tracks'),
        ),
      );
    } else {
      final failureSummary = failureReasonsByFile.entries
          .map((entry) => '${entry.key}: ${entry.value}')
          .join(' | ');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Uploaded $successCount/${uniqueFiles.length}. Failed ${failureReasonsByFile.length}: $failureSummary',
          ),
          duration: const Duration(seconds: 8),
        ),
      );
    }
    _clearLocalTrackSelection();
  }

  Future<void> _removeLocalTracks(
    List<File> files, {
    bool showSummary = true,
  }) async {
    final localMusicProvider = context.read<LocalMusicProvider>();
    final uniqueFiles = _uniqueFilesByPath(files);
    if (uniqueFiles.isEmpty) return;

    for (final file in uniqueFiles) {
      await localMusicProvider.removeFile(file);
      _localFileSizeCache.remove(file.path);
      _selectedLocalTrackPaths.remove(file.path);
    }

    final playlists = localMusicProvider.playlists;
    if (_selectedLocalPlaylistId != LocalMusicProvider.allPlaylistId &&
        _selectedLocalPlaylistId != LocalMusicProvider.likedPlaylistId &&
        playlists.every((item) => item.id != _selectedLocalPlaylistId)) {
      _setSelectedLocalPlaylist(LocalMusicProvider.allPlaylistId);
    }

    if (!mounted) return;
    if (showSummary && uniqueFiles.length > 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Deleted ${uniqueFiles.length} tracks')),
      );
      _clearLocalTrackSelection();
    }
  }

  Future<void> _addTracksToPlaylist(List<File> files) async {
    final localMusicProvider = context.read<LocalMusicProvider>();
    final uniqueFiles = _uniqueFilesByPath(files);
    if (uniqueFiles.isEmpty) return;

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
              final alreadyAddedCount = uniqueFiles
                  .where((file) => playlist.trackPaths.contains(file.path))
                  .length;
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
                trailing: alreadyAddedCount == uniqueFiles.length
                    ? const Icon(Icons.check_rounded)
                    : const Icon(Icons.add_rounded),
                onTap: () async {
                  var addedCount = 0;
                  for (final file in uniqueFiles) {
                    final ok = await localMusicProvider.addTrackToPlaylist(
                      playlistId: playlist.id,
                      trackPath: file.path,
                    );
                    if (ok) addedCount += 1;
                  }
                  if (!mounted) return;
                  navigator.pop();
                  if (uniqueFiles.length == 1) {
                    scaffoldMessenger.showSnackBar(
                      SnackBar(
                        content: Text(
                          addedCount == 1
                              ? 'Added to "${playlist.name}"'
                              : 'Track already in "${playlist.name}"',
                        ),
                      ),
                    );
                  } else {
                    scaffoldMessenger.showSnackBar(
                      SnackBar(
                        content: Text(
                          'Added $addedCount/${uniqueFiles.length} to "${playlist.name}"',
                        ),
                      ),
                    );
                    _clearLocalTrackSelection();
                  }
                },
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _removeTracksFromCurrentPlaylist(List<File> files) async {
    if (_selectedLocalPlaylistId == LocalMusicProvider.allPlaylistId) return;

    final localMusicProvider = context.read<LocalMusicProvider>();
    final uniqueFiles = _uniqueFilesByPath(files);
    if (uniqueFiles.isEmpty) return;

    if (_selectedLocalPlaylistId == LocalMusicProvider.likedPlaylistId) {
      var changedCount = 0;
      for (final file in uniqueFiles) {
        if (!localMusicProvider.isTrackLiked(file.path)) continue;
        final changed = await localMusicProvider.toggleTrackLike(file.path);
        if (changed) changedCount += 1;
      }
      if (!mounted || changedCount == 0) return;

      final authProvider = context.read<AuthProvider>();
      if (authProvider.currentUser != null) {
        await _uploadSystemPlaylistToCloud(
          playlistId: LocalMusicProvider.likedPlaylistId,
          playlistName: AppLocalizations.text(context, 'liked_songs'),
          localMusicProvider: localMusicProvider,
          silent: true,
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            uniqueFiles.length == 1
                ? 'Track removed from liked songs'
                : 'Removed like from $changedCount tracks',
          ),
        ),
      );
      if (uniqueFiles.length > 1) {
        _clearLocalTrackSelection();
      }
      return;
    }

    var removedCount = 0;
    for (final file in uniqueFiles) {
      final removed = await localMusicProvider.removeTrackFromPlaylist(
        playlistId: _selectedLocalPlaylistId,
        trackPath: file.path,
      );
      if (removed) removedCount += 1;
    }
    if (!mounted || removedCount == 0) return;

    final existsSelectedPlaylist = localMusicProvider.playlists.any(
      (item) => item.id == _selectedLocalPlaylistId,
    );
    if (!existsSelectedPlaylist) {
      _setSelectedLocalPlaylist(LocalMusicProvider.allPlaylistId);
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          uniqueFiles.length == 1
              ? 'Track removed from playlist'
              : 'Removed $removedCount tracks from playlist',
        ),
      ),
    );
    if (uniqueFiles.length > 1) {
      _clearLocalTrackSelection();
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    String t(String key) => AppLocalizations.text(context, key);

    return Consumer4<
      CloudMusicProvider,
      LocalMusicProvider,
      AuthProvider,
      MainNavProvider
    >(
      builder: (context, cloudMusicProvider, localMusicProvider, authProvider, navProvider, child) {
        final navSelectedPlaylistId = navProvider.selectedLocalPlaylistId;
        if (navSelectedPlaylistId != _selectedLocalPlaylistId) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _setSelectedLocalPlaylist(navSelectedPlaylistId, syncNav: false);
          });
        }
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
        final sortedPlaylistLocalTracks = _sortLocalTracks(
          playlistTracks: playlistLocalTracks,
          allLocalTracks: localTracks,
        );
        final visibleLocalTracks = sortedPlaylistLocalTracks
            .where(_matchesLocalTrackSearch)
            .toList();
        _primeLocalFileSizeRequests(visibleLocalTracks);
        _maybeAutoScrollToCurrentLocalTrack(
          visibleLocalTracks: visibleLocalTracks,
          currentTrackPath: currentTrackPath,
        );
        final isCloudAuthed = authProvider.currentUser != null;
        final cloudTracks = _storageType == _StorageType.cloud
            ? cloudMusicProvider.tracks
            : const <Track>[];
        final cloudPlaylists = _storageType == _StorageType.cloud
            ? cloudMusicProvider.playlists
            : const <Playlist>[];
        final selectedCloudPlaylistId = _selectedCloudPlaylistId;
        final cloudTrackSource = _storageType == _StorageType.cloud
            ? (selectedCloudPlaylistId == null
                      ? cloudTracks
                      : cloudMusicProvider.getTracksForPlaylist(
                          selectedCloudPlaylistId,
                        ))
                  .toList()
            : const <Track>[];
        final visibleCloudTracks = _sortCloudTracks(cloudTrackSource);
        final isCloudPlaylistLoading =
            _storageType == _StorageType.cloud &&
            selectedCloudPlaylistId != null &&
            cloudMusicProvider.isPlaylistTracksLoading(selectedCloudPlaylistId);
        final hasMoreCloudTracks =
            _storageType == _StorageType.cloud &&
            (selectedCloudPlaylistId == null
                ? cloudMusicProvider.hasMoreTracks
                : cloudMusicProvider.hasMorePlaylistTracks(
                    selectedCloudPlaylistId,
                  ));
        final isWindowsDesktop =
            Theme.of(context).platform == TargetPlatform.windows &&
            MediaQuery.of(context).size.width >= 920;

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
                      physics: isWindowsDesktop
                          ? const NeverScrollableScrollPhysics()
                          : const AlwaysScrollableScrollPhysics(),
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
                                  '${localPlaylists.length + 2} ${t('playlists')} вЂў ${visibleLocalTracks.length} ${t('tracks')}',
                                  style: textTheme.bodyMedium?.copyWith(
                                    color: colorScheme.onSurface.withValues(
                                      alpha: 0.65,
                                    ),
                                  ),
                                ),
                              ),
                              _GradientHeaderButton(
                                width: _storageHeaderControlWidth,
                                height: _storageHeaderControlHeight,
                                label: t('upload'),
                                onTap: _showUploadOptions,
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
                                    trackCounterText: _playlistTrackCounterLabel(
                                      syncKey:
                                          'system_${LocalMusicProvider.allPlaylistId}',
                                      trackCount: localTracks.length,
                                    ),
                                    isTransferring: _syncingLocalPlaylistIds
                                        .contains(
                                          'system_${LocalMusicProvider.allPlaylistId}',
                                        ),
                                    selected:
                                        _selectedLocalPlaylistId ==
                                        LocalMusicProvider.allPlaylistId,
                                    onTap: () => _setSelectedLocalPlaylist(
                                      LocalMusicProvider.allPlaylistId,
                                    ),
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
                                    trackCounterText: _playlistTrackCounterLabel(
                                      syncKey:
                                          'system_${LocalMusicProvider.likedPlaylistId}',
                                      trackCount:
                                          localMusicProvider.likedTracksCount,
                                    ),
                                    isTransferring: _syncingLocalPlaylistIds
                                        .contains(
                                          'system_${LocalMusicProvider.likedPlaylistId}',
                                        ),
                                    selected:
                                        _selectedLocalPlaylistId ==
                                        LocalMusicProvider.likedPlaylistId,
                                    onTap: () => _setSelectedLocalPlaylist(
                                      LocalMusicProvider.likedPlaylistId,
                                    ),
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
                                  trackCounterText: _playlistTrackCounterLabel(
                                    syncKey: playlist.id,
                                    trackCount: trackCount,
                                  ),
                                  isTransferring: _syncingLocalPlaylistIds
                                      .contains(playlist.id),
                                  selected:
                                      _selectedLocalPlaylistId == playlist.id,
                                  onTap: () =>
                                      _setSelectedLocalPlaylist(playlist.id),
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
                                        _isLocalTrackSelectionMode()
                                            ? '${_selectedLocalTrackPaths.length} ${t('tracks')}'
                                            : t('tracks'),
                                        style: textTheme.titleMedium?.copyWith(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      if (_isLocalTrackSelectionMode()) ...[
                                        const SizedBox(width: 6),
                                        IconButton(
                                          onPressed: _clearLocalTrackSelection,
                                          visualDensity: VisualDensity.compact,
                                          icon: const Icon(Icons.close_rounded),
                                          tooltip: 'Clear selection',
                                        ),
                                      ],
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
                                      const SizedBox(width: 8),
                                      PopupMenuButton<_LocalTrackSort>(
                                        tooltip: 'РЎРѕСЂС‚РёСЂРѕРІРєР°',
                                        initialValue: _localTrackSort,
                                        onSelected: (value) {
                                          if (_localTrackSort == value) return;
                                          setState(
                                            () => _localTrackSort = value,
                                          );
                                        },
                                        itemBuilder: (context) => _LocalTrackSort
                                            .values
                                            .map(
                                              (sort) =>
                                                  PopupMenuItem<
                                                    _LocalTrackSort
                                                  >(
                                                    value: sort,
                                                    child: Row(
                                                      children: [
                                                        Expanded(
                                                          child: Text(
                                                            _localTrackSortLabel(
                                                              sort,
                                                              context,
                                                            ),
                                                          ),
                                                        ),
                                                        if (sort ==
                                                            _localTrackSort)
                                                          Icon(
                                                            Icons.check_rounded,
                                                            size: 18,
                                                            color: colorScheme
                                                                .primary,
                                                          ),
                                                      ],
                                                    ),
                                                  ),
                                            )
                                            .toList(),
                                        child: Container(
                                          height: 44,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                          ),
                                          decoration: BoxDecoration(
                                            color: colorScheme.surface,
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                            border: Border.all(
                                              color: colorScheme.outline,
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const Icon(
                                                Icons.sort_rounded,
                                                size: 20,
                                              ),
                                              const SizedBox(width: 6),
                                              Text(
                                                'РЎРѕСЂС‚РёСЂРѕРІРєР°',
                                                style: textTheme.labelMedium,
                                              ),
                                            ],
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
                                        controller:
                                            _localTracksScrollController,
                                        primary: false,
                                        itemCount: visibleLocalTracks.length,
                                        separatorBuilder: (context, index) =>
                                            const SizedBox(height: 10),
                                        itemBuilder: (context, index) {
                                          final file =
                                              visibleLocalTracks[index];
                                          final uploading = _uploadingPaths
                                              .contains(file.path);
                                          final canUploadTrack =
                                              _isUploadableAudioFile(file);
                                          final isCurrentTrack =
                                              _isCurrentTrackPath(
                                                currentTrackPath,
                                                file.path,
                                              );
                                          final isSelectionMode =
                                              _isLocalTrackSelectionMode();
                                          final isSelectionChecked =
                                              _selectedLocalTrackPaths.contains(
                                                file.path,
                                              );

                                          return _TrackRow(
                                            title: p.basename(file.path),
                                            subtitle: _localFileSize(file),
                                            isUploading: uploading,
                                            selected: isCurrentTrack,
                                            batchSelected: isSelectionChecked,
                                            isPlaying:
                                                isCurrentTrack &&
                                                isCurrentTrackPlaying,
                                            onTap: () {
                                              if (isSelectionMode) {
                                                _toggleLocalTrackSelection(
                                                  file.path,
                                                );
                                                return;
                                              }
                                              final targetIndex =
                                                  sortedPlaylistLocalTracks
                                                      .indexWhere(
                                                        (item) => _pathsEqual(
                                                          item.path,
                                                          file.path,
                                                        ),
                                                      );
                                              if (targetIndex < 0) return;
                                              context
                                                  .read<AudioPlayerProvider>()
                                                  .toggleTrackFromTracks(
                                                    sortedPlaylistLocalTracks,
                                                    targetIndex,
                                                  );
                                            },
                                            onLongPress: () =>
                                                _startLocalTrackSelection(
                                                  file.path,
                                                ),
                                            menuItems: [
                                              _TrackMenuAction(
                                                label: uploading
                                                    ? 'Uploading...'
                                                    : canUploadTrack
                                                    ? t('upload')
                                                    : 'Unsupported format',
                                                icon:
                                                    Icons.cloud_upload_rounded,
                                                enabled:
                                                    !uploading &&
                                                    canUploadTrack,
                                                onTap: () async {
                                                  if (!canUploadTrack) {
                                                    if (!mounted) return;
                                                    ScaffoldMessenger.of(
                                                      context,
                                                    ).showSnackBar(
                                                      SnackBar(
                                                        content: Text(
                                                          _unsupportedUploadMessage(
                                                            file,
                                                          ),
                                                        ),
                                                      ),
                                                    );
                                                    return;
                                                  }
                                                  final targets =
                                                      _resolveTrackActionTargets(
                                                        anchorTrack: file,
                                                        playlistTracks:
                                                            sortedPlaylistLocalTracks,
                                                      );
                                                  await _uploadLocalTracks(
                                                    targets,
                                                  );
                                                },
                                              ),
                                              _TrackMenuAction(
                                                label: t('add_to_playlist'),
                                                icon:
                                                    Icons.playlist_add_rounded,
                                                onTap: () async {
                                                  final targets =
                                                      _resolveTrackActionTargets(
                                                        anchorTrack: file,
                                                        playlistTracks:
                                                            sortedPlaylistLocalTracks,
                                                      );
                                                  await _addTracksToPlaylist(
                                                    targets,
                                                  );
                                                },
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
                                                  onTap: () async {
                                                    final targets =
                                                        _resolveTrackActionTargets(
                                                          anchorTrack: file,
                                                          playlistTracks:
                                                              sortedPlaylistLocalTracks,
                                                        );
                                                    await _removeTracksFromCurrentPlaylist(
                                                      targets,
                                                    );
                                                  },
                                                ),
                                              _TrackMenuAction(
                                                label: t('delete'),
                                                icon: Icons.delete_rounded,
                                                onTap: () async {
                                                  final targets =
                                                      _resolveTrackActionTargets(
                                                        anchorTrack: file,
                                                        playlistTracks:
                                                            sortedPlaylistLocalTracks,
                                                      );
                                                  await _removeLocalTracks(
                                                    targets,
                                                  );
                                                },
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
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(
                                        color: colorScheme.outline,
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.cloud_rounded,
                                          size: 22,
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
                                controller: _cloudPlaylistsScrollController,
                                itemCount:
                                    cloudPlaylists.length +
                                    1 +
                                    (cloudMusicProvider.hasMorePlaylists
                                        ? 1
                                        : 0),
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

                                  if (index == cloudPlaylists.length + 1) {
                                    return const SizedBox(
                                      width: 88,
                                      child: Center(
                                        child: CircularProgressIndicator(),
                                      ),
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
                                    playlistName: _cloudPlaylistDisplayName(
                                      item,
                                    ),
                                    trackCount: item.songCount ?? 0,
                                    isTransferring: downloadingPlaylist,
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
                                            onChanged:
                                                _onCloudTrackSearchChanged,
                                            decoration: InputDecoration(
                                              isDense: true,
                                              hintText: t('search_track'),
                                              prefixIcon: Icon(
                                                Icons.search_rounded,
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        PopupMenuButton<_CloudTrackSort>(
                                          tooltip: 'Sort tracks',
                                          initialValue: _cloudTrackSort,
                                          onSelected: (value) {
                                            if (_cloudTrackSort == value) {
                                              return;
                                            }
                                            setState(
                                              () => _cloudTrackSort = value,
                                            );
                                          },
                                          itemBuilder: (context) => _CloudTrackSort
                                              .values
                                              .map(
                                                (
                                                  sort,
                                                ) => PopupMenuItem<_CloudTrackSort>(
                                                  value: sort,
                                                  child: Row(
                                                    children: [
                                                      Expanded(
                                                        child: Text(
                                                          _cloudTrackSortLabel(
                                                            sort,
                                                          ),
                                                        ),
                                                      ),
                                                      if (sort ==
                                                          _cloudTrackSort)
                                                        Icon(
                                                          Icons.check_rounded,
                                                          size: 18,
                                                          color: colorScheme
                                                              .primary,
                                                        ),
                                                    ],
                                                  ),
                                                ),
                                              )
                                              .toList(),
                                          child: Container(
                                            height: 44,
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 12,
                                            ),
                                            decoration: BoxDecoration(
                                              color: colorScheme.surface,
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              border: Border.all(
                                                color: colorScheme.outline,
                                              ),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                const Icon(
                                                  Icons.sort_rounded,
                                                  size: 20,
                                                ),
                                                const SizedBox(width: 6),
                                                Text(
                                                  _cloudTrackSortButtonLabel(),
                                                  style: textTheme.labelMedium,
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 10),
                                    if ((cloudMusicProvider.isLibraryLoading &&
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
                                      SizedBox(
                                        height:
                                            MediaQuery.of(context).size.height *
                                            0.56,
                                        child: ListView.separated(
                                          primary: false,
                                          controller:
                                              _cloudTracksScrollController,
                                          itemCount:
                                              visibleCloudTracks.length +
                                              (hasMoreCloudTracks ? 1 : 0),
                                          separatorBuilder: (context, index) =>
                                              const SizedBox(height: 10),
                                          itemBuilder: (context, index) {
                                            if (index >=
                                                visibleCloudTracks.length) {
                                              return const Padding(
                                                padding: EdgeInsets.symmetric(
                                                  vertical: 10,
                                                ),
                                                child: Center(
                                                  child:
                                                      CircularProgressIndicator(),
                                                ),
                                              );
                                            }
                                            final track =
                                                visibleCloudTracks[index];
                                            final downloading =
                                                _downloadingTrackIds.contains(
                                                  track.id,
                                                );
                                            return _TrackRow(
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
                                            );
                                          },
                                        ),
                                      ),
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

  void _primeLocalFileSizeRequests(List<File> files) {
    final limit = math.min(files.length, 18);
    for (var i = 0; i < limit; i++) {
      _requestLocalFileSize(files[i]);
    }
  }

  void _requestLocalFileSize(File file) {
    final path = file.path;
    if (_localFileSizeCache.containsKey(path) ||
        _localFileSizeLoadingPaths.contains(path)) {
      return;
    }
    _localFileSizeLoadingPaths.add(path);
    file
        .length()
        .then((bytes) {
          final mb = bytes / 1024 / 1024;
          return '${mb.toStringAsFixed(2)} MB';
        })
        .catchError((_) => 'Unknown size')
        .then((value) {
          if (!mounted) return;
          setState(() {
            _localFileSizeCache[path] = value;
            _localFileSizeLoadingPaths.remove(path);
          });
        });
  }

  String _localFileSize(File file) {
    final cached = _localFileSizeCache[file.path];
    if (cached != null) return cached;
    _requestLocalFileSize(file);
    return '...';
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
