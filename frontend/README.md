# CloudTune Frontend

Папка `frontend/` содержит Flutter-приложение `cloudtune_flutter_app`.

## Где основной код

- Приложение: `frontend/cloudtune_flutter_app/`
- Точка входа: `frontend/cloudtune_flutter_app/lib/main.dart`

## Возможности в текущей версии

- Логин/регистрация через backend API.
- Локальная библиотека (выбор файлов, сохранение списка путей).
- Облачная библиотека и плейлисты.
- Скачивание треков из облака в постоянную директорию приложения (`CloudTune`).
- Аудиоплеер с фоновым режимом через `audio_service`.
- Управление воспроизведением в UI и в Android уведомлении.

## Запуск

```bash
cd frontend/cloudtune_flutter_app
flutter pub get
flutter run
```

## Настройка API

Базовый URL задается в `lib/utils/constants.dart`.

По умолчанию:

- `https://api-mp3-player.ru`

При необходимости можно переопределить URL при запуске/сборке:

```bash
flutter run --dart-define=API_BASE_URL=https://api.your-domain.com
```

## Дополнительно

Подробная документация по приложению: `frontend/cloudtune_flutter_app/README.md`.
