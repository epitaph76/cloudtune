import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'screens/home_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/local_music_screen.dart';
import 'screens/server_music_screen.dart';
import 'screens/register_screen.dart';
import 'screens/api_tester.dart';
import 'screens/login_screen.dart';
import 'providers/auth_provider.dart';
import 'providers/local_music_provider.dart';
import 'providers/audio_player_provider.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (context) => AuthProvider()),
        ChangeNotifierProvider(create: (context) => LocalMusicProvider()),
        ChangeNotifierProxyProvider<LocalMusicProvider, AudioPlayerProvider>(
          create: (context) => AudioPlayerProvider(context.read<LocalMusicProvider>()),
          update: (context, localMusicProvider, audioPlayerProvider) {
            return audioPlayerProvider!..updateLocalMusicProvider(localMusicProvider);
          },
        ),
      ],
      child: MaterialApp(
        title: 'CloudTune',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
          useMaterial3: true,
        ),
        home: const MainScreen(),
        routes: {
          '/register': (context) => const RegisterScreen(),
          '/api_test': (context) => const ApiTester(),
          '/login': (context) => const LoginScreen(),
        },
      ),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({Key? key}) : super(key: key);

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;

  final List<Widget> _screens = [
    const HomeScreen(),
    const ProfileScreen(),
    const LocalMusicScreen(),
    const ServerMusicScreen(),
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(
            icon: Icon(Icons.home),
            label: 'Главная',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person),
            label: 'Профиль',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.music_note),
            label: 'Локальная музыка',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.cloud),
            label: 'Серверная музыка',
          ),
        ],
        currentIndex: _selectedIndex,
        selectedItemColor: Colors.blue,
        unselectedItemColor: Colors.grey,
        onTap: _onItemTapped,
        type: BottomNavigationBarType.fixed,
      ),
    );
  }
}