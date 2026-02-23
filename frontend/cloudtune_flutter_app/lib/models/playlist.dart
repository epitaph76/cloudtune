class Playlist {
  final int id;
  final String name;
  final String? description;
  final int ownerID;
  final bool isPublic;
  final bool isFavorite;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int? songCount;

  Playlist({
    required this.id,
    required this.name,
    this.description,
    required this.ownerID,
    this.isPublic = false,
    this.isFavorite = false,
    required this.createdAt,
    required this.updatedAt,
    this.songCount,
  });

  factory Playlist.fromJson(Map<String, dynamic> json) {
    return Playlist(
      id: json['id'] ?? 0,
      name: json['name'] ?? '',
      description: json['description'],
      ownerID: json['owner_id'] ?? 0,
      isPublic: json['is_public'] ?? false,
      isFavorite: json['is_favorite'] ?? false,
      createdAt: DateTime.parse(
        json['created_at'] ?? DateTime.now().toIso8601String(),
      ),
      updatedAt: DateTime.parse(
        json['updated_at'] ?? DateTime.now().toIso8601String(),
      ),
      songCount: json['song_count'], // Может быть null, если не передается
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'owner_id': ownerID,
      'is_public': isPublic,
      'is_favorite': isFavorite,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'song_count': songCount,
    };
  }
}
