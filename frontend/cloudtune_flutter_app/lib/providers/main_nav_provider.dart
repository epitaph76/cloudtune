import 'package:flutter/foundation.dart';

class MainNavProvider with ChangeNotifier {
  int _selectedIndex = 0;
  String _selectedLocalPlaylistId = 'all';

  int get selectedIndex => _selectedIndex;
  String get selectedLocalPlaylistId => _selectedLocalPlaylistId;

  void setIndex(int index) {
    if (_selectedIndex == index) return;
    _selectedIndex = index;
    notifyListeners();
  }

  void setSelectedLocalPlaylistId(String playlistId) {
    if (_selectedLocalPlaylistId == playlistId) return;
    _selectedLocalPlaylistId = playlistId;
    notifyListeners();
  }
}
