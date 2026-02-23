class User {
  final String id;
  final String email;
  final String username;

  User({required this.id, required this.email, required this.username});

  factory User.fromJson(Map<String, dynamic> json) {
    final rawId = json['id'];
    return User(
      id: rawId == null ? '' : rawId.toString(),
      email: json['email'] ?? '',
      username: json['username'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {'id': id, 'email': email, 'username': username};
  }
}
