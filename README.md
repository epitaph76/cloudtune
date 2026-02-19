# CloudTune

CloudTune - fullstack проект музыкального плеера с локальной и облачной библиотекой.

## Состав репозитория

- `backend/` - API на Go + PostgreSQL (авторизация, загрузка треков, библиотека, плейлисты, скачивание).
- `frontend/cloudtune_flutter_app/` - Flutter-приложение (Android/iOS/Web/Desktop scaffold).

## Текущее состояние

Реализовано:

- JWT авторизация (`register/login`).
- Загрузка аудио в облако.
- Облачная библиотека пользователя.
- Плейлисты (создание, список, добавление треков, просмотр треков плейлиста).
- Скачивание треков из облака в постоянную папку приложения (`CloudTune`).
- Локальная библиотека с сохранением списка файлов между запусками.
- Фоновое воспроизведение через `audio_service` с уведомлением и `play/pause/next/prev`.

Ограничения:

- Публичная папка `Download/CloudTune` пока не используется, сохранение идет в app-specific storage.
- В backend нет эндпоинта `/api/profile`.

## Быстрый старт

### Backend

```bash
cd backend
docker compose up --build
```

API по умолчанию: `http://localhost:8080`

### Frontend

```bash
cd frontend/cloudtune_flutter_app
flutter pub get
flutter run
```

Для Android-эмулятора базовый URL уже настроен как `http://10.0.2.2:8080`.

## Документация по модулям

- `backend/README.md`
- `frontend/README.md`
- `frontend/cloudtune_flutter_app/README.md`
