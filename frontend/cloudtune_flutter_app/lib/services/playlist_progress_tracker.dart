class PlaylistProgressTracker {
  final Map<String, ({int uploaded, int total})> _progressBySyncKey =
      <String, ({int uploaded, int total})>{};

  ({int uploaded, int total})? bySyncKey(String syncKey) {
    return _progressBySyncKey[syncKey];
  }

  void setProgress(
    String syncKey, {
    required int uploaded,
    required int total,
  }) {
    _progressBySyncKey[syncKey] = (uploaded: uploaded, total: total);
  }

  void clear(String syncKey) {
    _progressBySyncKey.remove(syncKey);
  }

  void clearAll() {
    _progressBySyncKey.clear();
  }

  String counterLabel({
    required String syncKey,
    required int trackCount,
    required String tracksLabel,
  }) {
    final progress = _progressBySyncKey[syncKey];
    if (progress != null) {
      return '${progress.uploaded}/${progress.total} $tracksLabel';
    }
    return '$trackCount $tracksLabel';
  }
}
