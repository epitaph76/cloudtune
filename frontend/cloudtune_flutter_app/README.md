# CloudTune Flutter App

Flutter-клиент CloudTune для локального и облачного прослушивания.

## Версия и стек

- Версия приложения: `1.8.6+8`
- Dart SDK: `^3.11.0`
- Flutter: 3.x
- Ключевые пакеты:
  - `provider`
  - `dio`
  - `just_audio`
  - `audio_service`
  - `flutter_secure_storage`
  - `shared_preferences`
  - `flutter_local_notifications`

## Актуальный функционал

- auth: регистрация/логин/логаут, хранение токена;
- local storage: локальные треки, плейлисты, лайки;
- cloud storage: загрузка треков, библиотека, плейлисты, квота;
- sync сценарии между local/cloud;
- импорт из Яндекс Диска (OAuth, сканирование, выбор и скачивание файлов);
- фоновый плеер с очередью, shuffle и repeat-one;
- отдельная desktop-компоновка для Windows;
- локализация интерфейса: русский, английский, испанский;
- настраиваемая тема/акцент.

## Структура проекта

```text
frontend/cloudtune_flutter_app/
  lib/
    main.dart
    models/
    providers/
    screens/
    services/
    theme/
    utils/
    widgets/
  assets/branding/
  android/
  ios/
  windows/
  test/
```

## Важные файлы

- `lib/main.dart` — инициализация приложения, provider-ов и audio service.
- `lib/services/api_service.dart` — API запросы к backend.
- `lib/services/backend_client.dart` — выбор базового URL и повтор запросов.
- `lib/utils/constants.dart` — `API_BASE_URL`, fallback URL, параметры OAuth Yandex.
- `lib/screens/server_music_screen.dart` — local/cloud экран и импорт из Яндекс Диска.
- `lib/screens/windows_desktop_shell.dart` — desktop UI для Windows.
- `lib/services/audio_handler.dart` — фоновое аудио-воспроизведение.

## Запуск

```bash
cd frontend/cloudtune_flutter_app
flutter pub get
flutter run
```

## Настройка backend URL

По умолчанию:

- `API_BASE_URL=https://api-mp3-player.ru`

Для запуска на своем backend:

```bash
flutter run --dart-define=API_BASE_URL=https://api.your-domain.com
```

Fallback URL:
- В release fallback всегда отключен.
- В debug fallback включается только флагом `API_ENABLE_FALLBACK_URLS=true`.

```bash
flutter run --dart-define=API_BASE_URL=https://api.your-domain.com --dart-define=API_ENABLE_FALLBACK_URLS=true
```

## Яндекс Диск OAuth (опционально)

Можно переопределить через `--dart-define`:

```bash
flutter run \
  --dart-define=YANDEX_OAUTH_CLIENT_ID=your_client_id
```

`YANDEX_OAUTH_REDIRECT_URI` фиксирован в приложении:
`https://oauth.yandex.ru/verification_code`.

## Сборки

APK:

```bash
flutter build apk --release --dart-define=API_BASE_URL=https://api.your-domain.com
```

Windows:

```bash
flutter build windows --release --dart-define=API_BASE_URL=https://api.your-domain.com
```

## Проверка качества

```bash
flutter analyze
flutter test
```

## Платформенные заметки

- Android min SDK: `21`.
- Для desktop-аудио используется `just_audio_media_kit` + `media_kit_libs_windows_audio`.
- При ширине окна `>= 920px` автоматически используется desktop-shell.
