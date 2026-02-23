import 'package:audio_service/audio_service.dart';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:provider/provider.dart';

import 'providers/audio_player_provider.dart';
import 'providers/auth_provider.dart';
import 'providers/cloud_music_provider.dart';
import 'providers/language_provider.dart';
import 'providers/local_music_provider.dart';
import 'providers/main_nav_provider.dart';
import 'providers/theme_provider.dart';
import 'screens/api_tester.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/register_screen.dart';
import 'screens/server_music_screen.dart';
import 'screens/windows_desktop_shell.dart';
import 'services/audio_handler.dart';
import 'utils/app_localizations.dart';
import 'widgets/now_playing_wave_background.dart';

late final MyAudioHandler audioHandler;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
    JustAudioMediaKit.ensureInitialized(
      windows: true,
      linux: true,
      macOS: true,
    );
  }

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
        ChangeNotifierProvider(create: (_) => LanguageProvider()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => MainNavProvider()),
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
      child: Consumer2<ThemeProvider, LanguageProvider>(
        builder: (context, themeProvider, languageProvider, child) {
          return MaterialApp(
            title: 'Cloudtune',
            debugShowCheckedModeBanner: false,
            theme: themeProvider.lightTheme,
            darkTheme: themeProvider.darkTheme,
            themeMode: themeProvider.themeMode,
            locale: languageProvider.locale,
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
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
  static const _navIcons = [Icons.music_note_rounded, Icons.storage_rounded];

  static const List<Widget> _screens = [HomeScreen(), ServerMusicScreen()];

  late final PageController _pageController;
  MainNavProvider? _navProvider;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final navProvider = context.read<MainNavProvider>();
    if (_navProvider == navProvider) return;

    _navProvider?.removeListener(_handleNavChanged);
    _navProvider = navProvider;
    _navProvider!.addListener(_handleNavChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_pageController.hasClients) return;
      _pageController.jumpToPage(_navProvider!.selectedIndex);
    });
  }

  void _handleNavChanged() {
    if (!mounted || !_pageController.hasClients || _navProvider == null) return;
    final targetIndex = _navProvider!.selectedIndex;
    final currentPage = (_pageController.page ?? 0).round();
    if (currentPage == targetIndex) return;

    _pageController.animateToPage(
      targetIndex,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    _navProvider?.removeListener(_handleNavChanged);
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final navProvider = context.watch<MainNavProvider>();
    final isNowPlaying = context.select<AudioPlayerProvider, bool>(
      (provider) => provider.playing,
    );
    final selectedIndex = navProvider.selectedIndex;
    String t(String key) => AppLocalizations.text(context, key);
    final labels = [t('player_tab'), t('storage_tab')];
    final navItems = List.generate(
      _navIcons.length,
      (index) => _MainNavItem(icon: _navIcons[index], label: labels[index]),
    );
    final useWindowsLayout = _useWindowsLayout(context);

    if (useWindowsLayout) {
      return const WindowsDesktopShell();
    }

    return Scaffold(
      body: NowPlayingWaveBackground(
        isActive: isNowPlaying,
        child: _buildPageView(),
      ),
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
              navItems.length,
              (index) => Expanded(
                child: _BottomNavButton(
                  item: navItems[index],
                  selected: selectedIndex == index,
                  onTap: () => navProvider.setIndex(index),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  bool _useWindowsLayout(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return defaultTargetPlatform == TargetPlatform.windows && width >= 920;
  }

  Widget _buildPageView() {
    return PageView(
      controller: _pageController,
      physics: const NeverScrollableScrollPhysics(),
      onPageChanged: (index) {
        final provider = context.read<MainNavProvider>();
        if (provider.selectedIndex != index) {
          provider.setIndex(index);
        }
      },
      children: _screens,
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
