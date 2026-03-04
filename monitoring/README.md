# CloudTune Monitoring Bot

Telegram-бот для мониторинга CloudTune backend и запуска удаленного деплоя.

## Стек

- Python `3.10+`
- `python-telegram-bot==22.3`
- `httpx==0.28.1`
- `python-dotenv==1.1.1`

## Возможности

- запрос метрик backend через Monitoring API;
- кнопочное меню + команды;
- пагинация пользователей и серверных файлов;
- просмотр карточки пользователя по email;
- удаление пользователя и массовая очистка пользователей;
- watchdog `/health` и авто-алерты;
- запуск deploy-скрипта с выводом stdout/stderr и результатом post-deploy тестов.

## Команды

- `/start`
- `/help`
- `/status`
- `/storage`
- `/connections`
- `/runtime`
- `/users`
- `/files`
- `/user <email>`
- `/delete_user <email>`
- `/purge_all_users CONFIRM`
- `/snapshot`
- `/all`
- `/deploy [branch]`

## Переменные окружения

Обязательные:
- `TELEGRAM_BOT_TOKEN`
- `BACKEND_MONITORING_API_KEY`

Базовая конфигурация:
- `BACKEND_BASE_URL` (default: `http://localhost:8080`)
- `BACKEND_HEALTH_PATH` (default: `/health`)
- `REQUEST_TIMEOUT` (default: `10`)
- `TELEGRAM_ALLOWED_CHAT_IDS`
- `ALERT_RECIPIENT_CHAT_IDS`
- `USERS_PAGE_SIZE` (default: `8`)

Watchdog и алерты:
- `ALERTS_ENABLED` (default: `true`)
- `ALERT_NOTIFY_ON_START` (default: `true`)
- `ALERT_CHECK_INTERVAL_SECONDS` (default: `300`)
- `ALERT_MAX_ACTIVE_HTTP_REQUESTS` (default: `300`)
- `ALERT_MAX_DB_IN_USE_CONNECTIONS` (default: `50`)
- `ALERT_MAX_GOROUTINES` (default: `500`)
- `ALERT_MAX_GO_MEMORY_MB` (default: `512`)
- `ALERT_MIN_UPLOADS_DISK_FREE_MB` (default: `512`)
- `ALERT_MIN_UPLOAD_REQUESTS_FOR_RATE` (default: `20`)
- `ALERT_MAX_UPLOAD_4XX_RATE_PCT` (default: `30`)
- `ALERT_MAX_UPLOAD_5XX_RATE_PCT` (default: `10`)
- `ALERT_MAX_UPLOAD_4XX_TOTAL` (default: `100`)
- `ALERT_MAX_UPLOAD_5XX_TOTAL` (default: `30`)

Deploy управление в боте:
- `DEPLOY_ENABLED` (default: `true`)
- `DEPLOY_SCRIPT_PATH` (default: `/opt/cloudtune/backend/scripts/deploy-from-github.sh`)
- `DEPLOY_REPO_URL` (default: `https://github.com/epitaph76/cloudtune.git`)
- `DEPLOY_BRANCH` (default: `master`)
- `DEPLOY_APP_DIR` (default: `/opt/cloudtune`)
- `DEPLOY_TIMEOUT_SECONDS` (default: `1800`)
- `DEPLOY_ALLOWED_CHAT_IDS`
- `DEPLOY_OUTPUT_CHUNK_SIZE` (default: `3000`)
- `DEPLOY_OUTPUT_MAX_CHUNKS` (default: `20`)

Проксируются в `deploy-from-github.sh` через окружение процесса:
- `DEPLOY_MAIN_LANDING`, `DEPLOY_RESUME_LANDING`
- `MAIN_LANDING_SRC`, `MAIN_LANDING_DST`
- `RESUME_LANDING_SRC`, `RESUME_LANDING_DST`
- `DEPLOY_ARTIFACTS_TO_MAIN`
- `RESTART_MONITORING_BOT`, `MONITORING_SERVICE_NAME`, `MONITORING_RESTART_DELAY_SECONDS`
- `RUN_POST_DEPLOY_TESTS`, `POST_DEPLOY_TEST_SCRIPT`
- `POST_DEPLOY_TEST_API_BASE_URL`, `POST_DEPLOY_TEST_MAIN_LANDING_URL`, `POST_DEPLOY_TEST_RESUME_LANDING_URL`
- `POST_DEPLOY_TEST_TIMEOUT_SECONDS`
- `ROLLBACK_ON_TEST_FAILURE`
- `DEPLOY_AUTOSTASH_LOCAL_CHANGES`

Сессии просмотра пользователей:
- `USER_SESSION_TTL_SECONDS` (default: `3600`)
- `USER_SESSION_CLEANUP_INTERVAL_SECONDS` (default: `300`)
- `USER_SESSION_MAX_ENTRIES` (default: `2000`)

Параметры для SQL-запросов в контейнер Postgres:
- `DB_CONTAINER_NAME` (default: `cloudtune-db`)
- `DB_NAME` (default: `cloudtune`)
- `DB_USER` (default: `cloudtune`)

## Локальный запуск

Windows:

```powershell
cd monitoring
python -m venv .venv
.venv\Scripts\activate
pip install -r requirements.txt
Copy-Item .env.example .env
python src/bot.py
```

Linux/macOS:

```bash
cd monitoring
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env
python src/bot.py
```

## Запуск через systemd (рекомендуется для сервера)

```bash
cd /opt/cloudtune
cp monitoring/.env.example monitoring/.env
bash monitoring/scripts/install-systemd.sh
```

Проверка:

```bash
systemctl status cloudtune-monitoring-bot --no-pager
journalctl -u cloudtune-monitoring-bot -f
```

## Docker режим (опционально)

```bash
cd monitoring
docker compose up --build -d
```
