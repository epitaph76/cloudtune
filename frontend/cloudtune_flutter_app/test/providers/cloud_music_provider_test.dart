import 'package:cloudtune_flutter_app/providers/cloud_music_provider.dart';
import 'package:cloudtune_flutter_app/services/api_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeApiService extends ApiService {
  final List<Map<String, dynamic>> libraryCalls = <Map<String, dynamic>>[];
  final List<Map<String, dynamic>> playlistCalls = <Map<String, dynamic>>[];
  final List<Map<String, dynamic>> playlistTrackCalls = <Map<String, dynamic>>[];

  @override
  Future<Map<String, dynamic>> getUserLibrary({
    int limit = 50,
    int offset = 0,
    String search = '',
  }) async {
    libraryCalls.add({'limit': limit, 'offset': offset, 'search': search});
    if (offset == 0) {
      return {
        'success': true,
        'songs': [
          {
            'id': 1,
            'filename': 'one.mp3',
            'original_filename': 'One.mp3',
            'upload_date': DateTime(2024, 1, 1).toIso8601String(),
          },
          {
            'id': 2,
            'filename': 'two.mp3',
            'original_filename': 'Two.mp3',
            'upload_date': DateTime(2024, 1, 2).toIso8601String(),
          },
        ],
        'has_more': true,
      };
    }
    return {
      'success': true,
      'songs': [
        {
          'id': 3,
          'filename': 'three.mp3',
          'original_filename': 'Three.mp3',
          'upload_date': DateTime(2024, 1, 3).toIso8601String(),
        },
      ],
      'has_more': false,
    };
  }

  @override
  Future<Map<String, dynamic>> getUserPlaylists({
    int limit = 50,
    int offset = 0,
    String search = '',
  }) async {
    playlistCalls.add({'limit': limit, 'offset': offset, 'search': search});
    return {
      'success': true,
      'playlists': [
        {
          'id': 9,
          'name': 'Favorites',
          'owner_id': 1,
          'created_at': DateTime(2024, 1, 1).toIso8601String(),
          'updated_at': DateTime(2024, 1, 1).toIso8601String(),
          'song_count': 2,
        },
      ],
      'has_more': false,
    };
  }

  @override
  Future<Map<String, dynamic>> getPlaylistSongs(
    int playlistId, {
    int limit = 50,
    int offset = 0,
    String search = '',
  }) async {
    playlistTrackCalls.add({
      'playlist_id': playlistId,
      'limit': limit,
      'offset': offset,
      'search': search,
    });
    if (offset == 0) {
      return {
        'success': true,
        'songs': [
          {
            'id': 21,
            'filename': 'p1.mp3',
            'original_filename': 'P1.mp3',
            'upload_date': DateTime(2024, 1, 4).toIso8601String(),
          },
        ],
        'has_more': true,
      };
    }
    return {
      'success': true,
      'songs': [
        {
          'id': 22,
          'filename': 'p2.mp3',
          'original_filename': 'P2.mp3',
          'upload_date': DateTime(2024, 1, 5).toIso8601String(),
        },
      ],
      'has_more': false,
    };
  }

  @override
  Future<Map<String, dynamic>> getStorageUsage() async {
    return {
      'success': true,
      'used_bytes': 1024,
      'quota_bytes': 4096,
      'remaining_bytes': 3072,
    };
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('CloudMusicProvider paginates user library', () async {
    final fakeApi = _FakeApiService();
    final provider = CloudMusicProvider(apiService: fakeApi);

    await provider.fetchUserLibrary(reset: true);
    expect(provider.tracks.length, 2);
    expect(provider.hasMoreTracks, isTrue);

    await provider.loadMoreUserLibrary();
    expect(provider.tracks.length, 3);
    expect(provider.hasMoreTracks, isFalse);
    expect(fakeApi.libraryCalls.length, 2);
    expect(fakeApi.libraryCalls.last['offset'], 2);
  });

  test('CloudMusicProvider resets list when search changes', () async {
    final fakeApi = _FakeApiService();
    final provider = CloudMusicProvider(apiService: fakeApi);

    await provider.fetchUserLibrary(reset: true);
    await provider.fetchUserLibrary(search: 'beatles');

    expect(provider.tracks.length, 2);
    expect(provider.tracksSearchQuery, 'beatles');
    expect(fakeApi.libraryCalls.last['offset'], 0);
    expect(fakeApi.libraryCalls.last['search'], 'beatles');
  });

  test('CloudMusicProvider paginates playlist tracks and loads storage', () async {
    final fakeApi = _FakeApiService();
    final provider = CloudMusicProvider(apiService: fakeApi);

    await provider.fetchPlaylistTracks(9, reset: true);
    expect(provider.getTracksForPlaylist(9).length, 1);
    expect(provider.hasMorePlaylistTracks(9), isTrue);

    await provider.loadMorePlaylistTracks(9);
    expect(provider.getTracksForPlaylist(9).length, 2);
    expect(provider.hasMorePlaylistTracks(9), isFalse);

    await provider.fetchStorageUsage();
    expect(provider.usedBytes, 1024);
    expect(provider.quotaBytes, 4096);
    expect(provider.remainingBytes, 3072);
  });
}
