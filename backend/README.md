# CloudTune Backend

Backend часть CloudTune на Go (Gin + PostgreSQL).

## Функциональность

- Регистрация и вход пользователя (JWT).
- Загрузка аудиофайлов на сервер.
- Персональная облачная библиотека (`user_library`).
- Плейлисты: создание, список, добавление треков, просмотр треков.
- Скачивание треков с проверкой доступа.

## Стек

- Go `1.24`
- Gin
- PostgreSQL
- JWT (`github.com/golang-jwt/jwt/v5`)
- Docker / Docker Compose

## Структура

```text
backend/
  cmd/api/main.go
  internal/database/
  internal/handlers/
  internal/middleware/
  internal/models/
  internal/utils/
  docker-compose.yml
  Dockerfile.dev
```

## Запуск

```bash
cd backend
docker compose up --build
```

Сервис поднимется на `http://localhost:8080`.

## Переменные окружения

Используются:

- `DB_HOST` (default: `localhost`)
- `DB_PORT` (default: `5432`)
- `DB_USER` (default: `postgres`)
- `DB_PASSWORD` (default: `password`)
- `DB_NAME` (default: `cloudtune`)
- `JWT_SECRET` (обязательно задать надежное значение для продакшена)

## API

### Public

- `GET /health`
- `GET /api/status`
- `POST /auth/register`
- `POST /auth/login`

### Protected (`Authorization: Bearer <token>`)

#### Songs

- `POST /api/songs/upload`
- `GET /api/songs/library`
- `GET /api/songs/:id`
- `GET /api/songs/download/:id`

#### Playlists

- `POST /api/playlists`
- `GET /api/playlists`
- `POST /api/playlists/:playlist_id/songs/:song_id`
- `GET /api/playlists/:playlist_id/songs`

## Важно

- Таблицы БД создаются автоматически при старте.
- В текущей версии отсутствует эндпоинт `/api/profile`.
- Допустимые MIME-типы при загрузке: `audio/mpeg`, `audio/wav`, `audio/mp4`, `audio/flac`.
