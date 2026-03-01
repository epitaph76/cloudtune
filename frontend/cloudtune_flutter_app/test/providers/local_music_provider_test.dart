import 'dart:io';

import 'package:cloudtune_flutter_app/providers/local_music_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _flushAsyncState() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('upsertPlaylistByName merges tracks for download flow', () async {
    final provider = LocalMusicProvider();
    await _flushAsyncState();

    await provider.addFiles(<File>[
      File('one.mp3'),
      File('two.mp3'),
      File('three.mp3'),
    ]);

    final createdId = await provider.upsertPlaylistByName(
      name: 'Cloud playlist',
      trackPaths: <String>{'one.mp3', 'two.mp3'},
    );

    final mergedId = await provider.upsertPlaylistByName(
      name: 'cloud playlist',
      trackPaths: <String>{'three.mp3'},
      replaceExisting: false,
    );

    expect(mergedId, createdId);
    final playlist = provider.playlists.singleWhere(
      (item) => item.id == createdId,
    );
    expect(
      playlist.trackPaths,
      equals(<String>{'one.mp3', 'two.mp3', 'three.mp3'}),
    );
  });

  test('upsertPlaylistByName replaces tracks for sync flow', () async {
    final provider = LocalMusicProvider();
    await _flushAsyncState();

    await provider.addFiles(<File>[
      File('old.mp3'),
      File('stale.mp3'),
      File('fresh.mp3'),
    ]);

    final createdId = await provider.upsertPlaylistByName(
      name: 'Sync playlist',
      trackPaths: <String>{'old.mp3', 'stale.mp3'},
    );

    final syncedId = await provider.upsertPlaylistByName(
      name: 'sync playlist',
      trackPaths: <String>{'fresh.mp3'},
      replaceExisting: true,
    );

    expect(syncedId, createdId);
    final playlist = provider.playlists.singleWhere(
      (item) => item.id == createdId,
    );
    expect(playlist.trackPaths, equals(<String>{'fresh.mp3'}));
  });
}
