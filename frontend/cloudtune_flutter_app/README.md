# CloudTune Flutter App

Flutter-клиент для CloudTune.

## Что умеет сейчас

- Аутентификация: регистрация и вход.
- Локальная библиотека:
  - выбор аудиофайлов с устройства;
  - хранение списка треков в `SharedPreferences`;
  - восстановление списка после перезапуска приложения.
- Облачная библиотека:
  - загрузка файла в облако;
  - просмотр треков и плейлистов;
  - скачивание трека в постоянную папку приложения `CloudTune`.
- Аудиоплеер:
  - `play/pause/seek`;
  - `next/previous` по очереди;
  - фоновое воспроизведение (`audio_service` + `just_audio`);
  - Android media notification с кнопками управления.

## Архитектура

```text
lib/
  main.dart
  models/
  providers/
  screens/
  services/
  utils/
```

Слои:

- `screens` - UI
- `providers` - состояние и orchestration
- `services` - API/аудио/инфраструктура
- `models` - DTO/модели

## Важные файлы

- `lib/main.dart` - инициализация приложения и `AudioService`.
- `lib/services/audio_handler.dart` - обработчик фонового аудио.
- `lib/providers/audio_player_provider.dart` - синхронизация UI с playback state.
- `lib/screens/home_screen.dart` - локальный плеер и список треков.
- `lib/screens/server_music_screen.dart` - облачные треки и скачивание.
- `lib/services/api_service.dart` - запросы к backend API.

## Конфиг API

`lib/utils/constants.dart`

По умолчанию:

- `baseUrl = https://api-mp3-player.ru`

Для сервера используйте `--dart-define`:

```bash
flutter run --dart-define=API_BASE_URL=https://api.your-domain.com
```

Для release build:

```bash
flutter build apk --release --dart-define=API_BASE_URL=https://api.your-domain.com
```

## Запуск

```bash
flutter pub get
flutter run
```

## Android требования

В `AndroidManifest.xml` уже добавлены необходимые разрешения для фонового аудио и работы с файлами.

`MainActivity` использует `AudioServiceActivity`, что обязательно для `audio_service`.

## Известные ограничения

- Скачанные треки сохраняются в app-specific директорию (`.../files/CloudTune`), а не в публичную `Download`.
- Эмулятор Android может давать нестабильное аудио поведение; для финальной проверки лучше использовать физическое устройство.
