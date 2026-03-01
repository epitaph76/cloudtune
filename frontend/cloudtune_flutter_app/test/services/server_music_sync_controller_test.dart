import 'dart:io';

import 'package:cloudtune_flutter_app/services/api_service.dart';
import 'package:cloudtune_flutter_app/services/server_music_sync_controller.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeUploadApiService extends ApiService {
  final Map<String, Map<String, dynamic>> responsesByPath =
      <String, Map<String, dynamic>>{};

  @override
  Future<Map<String, dynamic>> uploadFile(
    File file, {
    CancelToken? cancelToken,
  }) async {
    return responsesByPath[file.path] ??
        {'success': false, 'message': 'unknown file'};
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('ServerMusicSyncController uploads files and tracks failures', () async {
    final fakeApi = _FakeUploadApiService();
    final controller = ServerMusicSyncController(
      apiService: fakeApi,
      parallelism: 2,
    );

    final files = <File>[File('ok.mp3'), File('bad.txt'), File('missing.mp3')];
    fakeApi.responsesByPath['ok.mp3'] = {'success': true, 'song_id': 77};
    fakeApi.responsesByPath['missing.mp3'] = {
      'success': false,
      'message': 'quota exceeded',
    };

    final progressEvents = <String>[];
    final result = await controller.uploadMissingTracks(
      missingFiles: files,
      completedTracks: 1,
      totalTracks: 4,
      isUploadableAudioFile: (file) => file.path.endsWith('.mp3'),
      unsupportedUploadMessage: (file) => 'unsupported: ${file.path}',
      uploadFailureReason: (raw) => (raw ?? '').toString(),
      extractSongIdFromUploadResult: (raw) {
        final songId = raw['song_id'];
        if (songId is int) return songId;
        return null;
      },
      isCancellationRequested: () => false,
      createCancelToken: (_) => CancelToken(),
      clearCancelToken: (_) {},
      onProgress: (completed, total) async {
        progressEvents.add('$completed/$total');
      },
    );

    expect(result.completedTracks, 2);
    expect(result.uploadedSongIDsByPath['ok.mp3'], 77);
    expect(result.failedUploadsByPath['bad.txt'], 'unsupported: bad.txt');
    expect(result.failedUploadsByPath['missing.mp3'], 'quota exceeded');
    expect(progressEvents.length, 3);
  });
}
