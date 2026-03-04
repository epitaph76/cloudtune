# CloudTune Backend

Go backend для CloudTune: REST API для auth, облачной библиотеки, плейлистов и monitoring API.

## Стек

- Go `1.24.0` (см. `go.mod`)
- Gin `1.9.1`
- PostgreSQL `15`
- JWT (`github.com/golang-jwt/jwt/v5`)
- Docker Compose (dev и prod конфиги)

> Примечание: Dockerfile собирает приложение в образе `golang:1.25`, при этом версия языка в `go.mod` — `1.24.0`.

## Структура

```text
backend/
  cmd/api/main.go
  internal/database/
  internal/handlers/
  internal/middleware/
  internal/monitoring/
  internal/models/
  internal/utils/
  scripts/deploy-from-github.sh
  scripts/run_post_deploy_tests.py
  docker-compose.yml
  docker-compose.prod.yml
```

## Локальный запуск

```bash
cd backend
docker compose up --build
```

API по умолчанию: `http://localhost:8080`.

## Production запуск

```bash
cd backend
cp .env.prod.example .env.prod
docker compose --env-file .env.prod -f docker-compose.prod.yml up -d --build
```

В `docker-compose.prod.yml` API публикуется на `127.0.0.1:8080` (под обратный прокси, например Nginx).

## Основные API эндпоинты

Публичные:
- `GET /health`
- `GET /api/status`
- `POST /auth/register`
- `POST /auth/login`

Защищенные (`Authorization: Bearer <token>`):
- `POST /api/songs/upload`
- `GET /api/songs/library` (поддерживает `limit`, `offset`, `search`)
- `GET /api/songs/:id`
- `DELETE /api/songs/:id`
- `GET /api/songs/download/:id`
- `GET /api/storage/usage`
- `DELETE /api/profile`
- `POST /api/playlists`
- `GET /api/playlists` (поддерживает `limit`, `offset`, `search`)
- `DELETE /api/playlists/:playlist_id`
- `POST /api/playlists/:playlist_id/songs/:song_id`
- `POST /api/playlists/:playlist_id/songs/bulk`
- `GET /api/playlists/:playlist_id/songs` (поддерживает `limit`, `offset`, `search`)

## Monitoring API

Для всех monitoring-маршрутов обязателен заголовок:

`X-Monitoring-Key: <MONITORING_API_KEY>`

Маршруты:
- `GET /api/monitor/status`
- `GET /api/monitor/storage`
- `GET /api/monitor/connections`
- `GET /api/monitor/users`
- `GET /api/monitor/users/list?page=1&limit=8`
- `GET /api/monitor/files?page=1&limit=10`
- `GET /api/monitor/runtime`
- `GET /api/monitor/snapshot`
- `GET /api/monitor/all`
- `DELETE /api/monitor/users/delete?email=user@example.com`
- `DELETE /api/monitor/users/purge-all`

## Переменные окружения приложения

База данных:
- `DB_HOST` (default: `localhost`)
- `DB_PORT` (default: `5432`)
- `DB_USER` (default: `postgres`)
- `DB_PASSWORD` (default: `password`)
- `DB_NAME` (default: `cloudtune`)
- `DB_SSLMODE` (default: `disable`)
- `DB_MAX_OPEN_CONNS` (default: `25`)
- `DB_MAX_IDLE_CONNS` (default: `25`)
- `DB_CONN_MAX_IDLE_MINUTES` (default: `5`)
- `DB_CONN_MAX_LIFETIME_MINUTES` (default: `30`)

Auth и monitoring:
- `JWT_SECRET` (обязателен, минимум 32 символа)
- `MONITORING_API_KEY` (ключ для monitoring API)

Хранилище и upload:
- `CLOUD_UPLOADS_PATH` (default: `./uploads`)
- `CLOUD_STORAGE_QUOTA_BYTES` (default: `3221225472`, 3 GB)
- `CLOUD_MAX_UPLOAD_SIZE_BYTES` (default: `104857600`, 100 MB)
- `CLOUD_MAX_PARALLEL_UPLOADS` (default: `4`)
- `X_ACCEL_REDIRECT_ENABLED` (default: `false`)
- `X_ACCEL_REDIRECT_PREFIX` (default: `/internal_uploads`)

## Deploy script

Скрипт: `backend/scripts/deploy-from-github.sh`.

Что делает:
- обновляет код из Git;
- деплоит backend (`docker compose`);
- деплоит main/resume лендинги;
- запускает post-deploy smoke тесты;
- при падении тестов может откатить на предыдущий commit;
- может перезапустить monitoring bot.

Ключевые переменные скрипта:
- `REPO_URL` (обязательная)
- `BRANCH` (default: `master`)
- `APP_DIR` (default: `/opt/cloudtune`)
- `DEPLOY_MAIN_LANDING`, `DEPLOY_RESUME_LANDING`
- `MAIN_LANDING_SRC`, `MAIN_LANDING_DST`
- `RESUME_LANDING_SRC`, `RESUME_LANDING_DST`
- `DEPLOY_ARTIFACTS_TO_MAIN`
- `RUN_POST_DEPLOY_TESTS`, `ROLLBACK_ON_TEST_FAILURE`
- `POST_DEPLOY_TEST_SCRIPT`, `POST_DEPLOY_TEST_API_BASE_URL`
- `POST_DEPLOY_TEST_MAIN_LANDING_URL`, `POST_DEPLOY_TEST_RESUME_LANDING_URL`
- `POST_DEPLOY_TEST_TIMEOUT_SECONDS`, `POST_DEPLOY_TEST_HEALTH_PATH`
- `POST_DEPLOY_TEST_POLL_ATTEMPTS`, `POST_DEPLOY_TEST_POLL_SLEEP_SECONDS`
- `ALLOW_DEPLOY_AS_ROOT` (по умолчанию `false`)
- `DEPLOY_AUTOSTASH_LOCAL_CHANGES` (по умолчанию `true`)
- `RESTART_MONITORING_BOT`, `MONITORING_SERVICE_NAME`, `MONITORING_RESTART_DELAY_SECONDS`
- `DOCKER_PRUNE_AFTER_DEPLOY`, `DOCKER_PRUNE_UNTIL_HOURS`, `DOCKER_PRUNE_VOLUMES`
- `JOURNAL_VACUUM_AFTER_DEPLOY`, `JOURNAL_MAX_SIZE`
- `TRUNCATE_BTMP_AFTER_DEPLOY`

## Релиз и откат

- Чеклист релиза: `backend/docs/release-checklist.md`
- Post-deploy тесты: `backend/scripts/run_post_deploy_tests.py`
- При `ROLLBACK_ON_TEST_FAILURE=true` скрипт выполняет rollback на предыдущий commit, если smoke-тесты не прошли.
