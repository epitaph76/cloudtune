import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'providers/audio_player_provider.dart';
import 'providers/auth_provider.dart';
import 'providers/cloud_music_provider.dart';
import 'providers/local_music_provider.dart';
import 'providers/theme_provider.dart';
import 'screens/api_tester.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/register_screen.dart';
import 'screens/server_music_screen.dart';
import 'services/audio_handler.dart';

late final MyAudioHandler audioHandler;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  audioHandler = await AudioService.init(
    builder: () => MyAudioHandler(),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.cloudtune.audio',
      androidNotificationChannelName: 'CloudTune Playback',
      androidNotificationOngoing: true,
    ),
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => LocalMusicProvider()),
        ChangeNotifierProvider(create: (_) => CloudMusicProvider()),
        ChangeNotifierProxyProvider<LocalMusicProvider, AudioPlayerProvider>(
          create: (context) => AudioPlayerProvider(
            context.read<LocalMusicProvider>(),
            audioHandler,
          ),
          update: (context, localMusicProvider, audioPlayerProvider) {
            audioPlayerProvider!.updateLocalMusicProvider(localMusicProvider);
            return audioPlayerProvider;
          },
        ),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, child) {
          return MaterialApp(
            title: 'CloudTune',
            debugShowCheckedModeBanner: false,
            theme: themeProvider.lightTheme,
            darkTheme: themeProvider.darkTheme,
            themeMode: themeProvider.themeMode,
            home: const MainScreen(),
            routes: {
              '/register': (context) => const RegisterScreen(),
              '/api_test': (context) => const ApiTester(),
              '/login': (context) => const LoginScreen(),
            },
          );
        },
      ),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;

  static const _navItems = [
    _MainNavItem(icon: Icons.music_note_rounded, label: 'Player'),
    _MainNavItem(icon: Icons.storage_rounded, label: 'Storage'),
  ];

  final List<Widget> _screens = const [HomeScreen(), ServerMusicScreen()];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: IndexedStack(index: _selectedIndex, children: _screens),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          margin: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: colorScheme.outline),
          ),
          child: Row(
            children: List.generate(
              _navItems.length,
              (index) => Expanded(
                child: _BottomNavButton(
                  item: _navItems[index],
                  selected: _selectedIndex == index,
                  onTap: () => _onItemTapped(index),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MainNavItem {
  const _MainNavItem({required this.icon, required this.label});

  final IconData icon;
  final String label;
}

class _BottomNavButton extends StatelessWidget {
  const _BottomNavButton({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final _MainNavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: selected ? colorScheme.primary : Colors.transparent,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              item.icon,
              size: 20,
              color: selected
                  ? colorScheme.onPrimary
                  : colorScheme.onSurface.withValues(alpha: 0.7),
            ),
            const SizedBox(height: 4),
            Text(
              item.label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: selected
                    ? colorScheme.onPrimary
                    : colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
