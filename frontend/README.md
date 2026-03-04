# CloudTune Frontend

Папка `frontend/` содержит Flutter-клиент CloudTune.

## Актуальная версия

- Приложение: `1.8.6+8` (`frontend/cloudtune_flutter_app/pubspec.yaml`).

## Где код

- Основной проект: `frontend/cloudtune_flutter_app/`
- Точка входа: `frontend/cloudtune_flutter_app/lib/main.dart`

## Что умеет клиент

- регистрация/вход в облако CloudTune;
- локальная библиотека и локальные плейлисты;
- облачная библиотека и облачные плейлисты;
- загрузка треков в облако и скачивание в локальную библиотеку;
- синхронизация плейлистов между local/cloud;
- импорт музыки из Яндекс Диска (OAuth + выбор файлов);
- фоновое воспроизведение (`audio_service` + `just_audio`);
- темы и локализация (`ru`, `en`, `es`);
- desktop-shell для Windows.

## Запуск

```bash
cd frontend/cloudtune_flutter_app
flutter pub get
flutter run
```

## Настройка API

По умолчанию клиент использует:

- `API_BASE_URL=https://api-mp3-player.ru`

Для своего backend:

```bash
flutter run --dart-define=API_BASE_URL=https://api.your-domain.com
```

### Fallback host'ы

- В release fallback URL отключены всегда.
- В debug можно включить только явно:

```bash
flutter run --dart-define=API_BASE_URL=https://api.your-domain.com --dart-define=API_ENABLE_FALLBACK_URLS=true
```

## Сборки

APK:

```bash
flutter build apk --release --dart-define=API_BASE_URL=https://api.your-domain.com
```

Windows:

```bash
flutter build windows --release --dart-define=API_BASE_URL=https://api.your-domain.com
```

## Проверка

```bash
flutter analyze
flutter test
```

## Подробная документация

- `frontend/cloudtune_flutter_app/README.md`
