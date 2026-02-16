class Track {
  final int id;
  final String filename;
  final String? originalFilename;
  final int? filesize;
  final String? artist;
  final String? title;
  final String? album;
  final String? genre;
  final int? year;
  final String? mimeType;
  final DateTime uploadDate;

  Track({
    required this.id,
    required this.filename,
    this.originalFilename,
    this.filesize,
    this.artist,
    this.title,
    this.album,
    this.genre,
    this.year,
    this.mimeType,
    required this.uploadDate,
  });

  factory Track.fromJson(Map<String, dynamic> json) {
    return Track(
      id: json['id'] ?? 0,
      filename: json['filename'] ?? '',
      originalFilename: json['original_filename'],
      filesize: json['filesize'],
      artist: json['artist'],
      title: json['title'],
      album: json['album'],
      genre: json['genre'],
      year: json['year'],
      mimeType: json['mime_type'],
      uploadDate: DateTime.parse(json['upload_date'] ?? DateTime.now().toIso8601String()),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'filename': filename,
      'original_filename': originalFilename,
      'filesize': filesize,
      'artist': artist,
      'title': title,
      'album': album,
      'genre': genre,
      'year': year,
      'mime_type': mimeType,
      'upload_date': uploadDate.toIso8601String(),
    };
  }
}