import 'dart:io';
import 'dart:math' as math;

import 'api_service.dart';

class UploadBatchResult {
  const UploadBatchResult({
    required this.uploadedSongIDsByPath,
    required this.failedUploadsByPath,
    required this.completedTracks,
  });

  final Map<String, int> uploadedSongIDsByPath;
  final Map<String, String> failedUploadsByPath;
  final int completedTracks;
}

class ServerMusicSyncController {
  ServerMusicSyncController({ApiService? apiService, int parallelism = 3})
    : _apiService = apiService ?? ApiService(),
      _parallelism = math.max(1, parallelism);

  final ApiService _apiService;
  final int _parallelism;

  Future<UploadBatchResult> uploadMissingTracks({
    required List<File> missingFiles,
    required int completedTracks,
    required int totalTracks,
    required bool Function(File file) isUploadableAudioFile,
    required String Function(File file) unsupportedUploadMessage,
    required String Function(Object? rawReason) uploadFailureReason,
    required int? Function(Map<String, dynamic> uploadResult)
    extractSongIdFromUploadResult,
    Future<void> Function(int completed, int total)? onProgress,
  }) async {
    final entries = missingFiles.toList(growable: false);
    if (entries.isEmpty) {
      return UploadBatchResult(
        uploadedSongIDsByPath: const <String, int>{},
        failedUploadsByPath: const <String, String>{},
        completedTracks: completedTracks,
      );
    }

    final uploadedSongIDsByPath = <String, int>{};
    final failedUploadsByPath = <String, String>{};
    var processedTracks = completedTracks;
    var nextIndex = 0;
    final workerCount = math.max(1, math.min(_parallelism, entries.length));

    Future<void> worker() async {
      while (true) {
        if (nextIndex >= entries.length) {
          return;
        }
        final file = entries[nextIndex];
        nextIndex += 1;

        if (!isUploadableAudioFile(file)) {
          failedUploadsByPath[file.path] = unsupportedUploadMessage(file);
        } else {
          try {
            final uploadResult = await _apiService.uploadFile(file);
            if (uploadResult['success'] == true) {
              final uploadedSongId = extractSongIdFromUploadResult(
                uploadResult,
              );
              if (uploadedSongId != null) {
                uploadedSongIDsByPath[file.path] = uploadedSongId;
                completedTracks += 1;
              } else {
                failedUploadsByPath[file.path] =
                    'Upload failed: backend response missing song_id';
              }
            } else {
              failedUploadsByPath[file.path] = uploadFailureReason(
                uploadResult['message'],
              );
            }
          } catch (error) {
            failedUploadsByPath[file.path] = uploadFailureReason(
              error.toString(),
            );
          }
        }
        processedTracks += 1;

        if (onProgress != null) {
          await onProgress(processedTracks, totalTracks);
        }
      }
    }

    await Future.wait(List.generate(workerCount, (_) => worker()));
    return UploadBatchResult(
      uploadedSongIDsByPath: uploadedSongIDsByPath,
      failedUploadsByPath: failedUploadsByPath,
      completedTracks: completedTracks,
    );
  }
}
