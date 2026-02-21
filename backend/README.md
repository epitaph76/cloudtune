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
  Dockerfile
  docker-compose.yml
  docker-compose.prod.yml
  Dockerfile.dev
```

## Запуск

```bash
cd backend
docker compose up --build
```

Сервис поднимется на `http://localhost:8080`.

## Production Deploy (VDS + Docker)

1. Подготовьте переменные:

```bash
cd backend
cp .env.prod.example .env.prod
```

2. Заполните `.env.prod` сильными значениями.

3. Запуск production-сборки:

```bash
cd backend
docker compose --env-file .env.prod -f docker-compose.prod.yml up -d --build
```

API будет слушать `127.0.0.1:8080` (удобно проксировать через Nginx).

4. Автодеплой из GitHub:

```bash
REPO_URL=https://github.com/<user>/<repo>.git \
BRANCH=master \
APP_DIR=/opt/cloudtune \
bash backend/scripts/deploy-from-github.sh
```

## Переменные окружения

Используются:

- `DB_HOST` (default: `localhost`)
- `DB_PORT` (default: `5432`)
- `DB_USER` (default: `postgres`)
- `DB_PASSWORD` (default: `password`)
- `DB_NAME` (default: `cloudtune`)
- `JWT_SECRET` (обязательно задать надежное значение для продакшена)
- `MONITORING_API_KEY` (включает защищенные monitoring endpoints)
- `CLOUD_UPLOADS_PATH` (опционально, путь до папки uploads, default `./uploads`)

## Monitoring API

При заданном `MONITORING_API_KEY` доступны диагностические эндпоинты:

- `GET /api/monitor/status`
- `GET /api/monitor/storage`
- `GET /api/monitor/connections`
- `GET /api/monitor/users`
- `GET /api/monitor/users/list?page=1&limit=8`
- `GET /api/monitor/all`

Все запросы требуют заголовок `X-Monitoring-Key: <MONITORING_API_KEY>`.
Telegram-бот вынесен в отдельный сервис: `../monitoring`.

## API

### Public

- `GET /health`
- `GET /api/status`
- `GET /api/monitor/status` (requires `X-Monitoring-Key`)
- `GET /api/monitor/storage` (requires `X-Monitoring-Key`)
- `GET /api/monitor/connections` (requires `X-Monitoring-Key`)
- `GET /api/monitor/users` (requires `X-Monitoring-Key`)
- `GET /api/monitor/users/list?page=1&limit=8` (requires `X-Monitoring-Key`)
- `GET /api/monitor/all` (requires `X-Monitoring-Key`)
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
