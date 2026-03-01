# CloudTune Monitoring Bot

Telegram-бот для мониторинга CloudTune backend через защищенные Monitoring API-эндпоинты.

## Что умеет
- Команды: `/status`, `/storage`, `/connections`, `/runtime`, `/users`, `/user <email>`, `/delete_user <email>`, `/snapshot`, `/all`, `/deploy [branch]`, `/help`.
- Кнопочное меню в Telegram.
- Пагинация пользователей через inline-кнопки.
- Watchdog backend по `/health`.
- Авто-алерты:
- backend down / recovered;
- пороговые алерты по snapshot (HTTP, DB, goroutines, память, свободный диск).

## Переменные окружения
- `TELEGRAM_BOT_TOKEN` - токен Telegram-бота.
- `TELEGRAM_ALLOWED_CHAT_IDS` - белый список chat id через запятую.
- `ALERT_RECIPIENT_CHAT_IDS` - chat id для алертов.
- `BACKEND_BASE_URL` - базовый URL backend.
- `BACKEND_MONITORING_API_KEY` - ключ мониторинга (должен совпадать с backend).
- `BACKEND_HEALTH_PATH` - путь health-check (по умолчанию `/health`).
- `REQUEST_TIMEOUT` - таймаут HTTP-запросов.
- `ALERTS_ENABLED` - включить/выключить watchdog (`true/false`).
- `ALERT_NOTIFY_ON_START` - отправлять стартовое уведомление (`true/false`).
- `ALERT_CHECK_INTERVAL_SECONDS` - интервал проверок.
- `USERS_PAGE_SIZE` - размер страницы `/users`.
- `DB_CONTAINER_NAME` - имя контейнера postgres для запросов user-сводки (по умолчанию `cloudtune-db`).
- `DB_NAME` - имя базы (по умолчанию `cloudtune`).
- `DB_USER` - пользователь базы (по умолчанию `cloudtune`).
- `ALERT_MAX_ACTIVE_HTTP_REQUESTS` - порог active HTTP requests.
- `ALERT_MAX_DB_IN_USE_CONNECTIONS` - порог DB in_use.
- `ALERT_MAX_GOROUTINES` - порог goroutines.
- `ALERT_MAX_GO_MEMORY_MB` - порог Go alloc памяти в MB.
- `ALERT_MIN_UPLOADS_DISK_FREE_MB` - минимально свободное место (uploads FS) в MB.
- `DEPLOY_ENABLED` - включить/выключить команду `/deploy` (`true/false`).
- `DEPLOY_SCRIPT_PATH` - путь до deploy-скрипта (по умолчанию `/opt/cloudtune/backend/scripts/deploy-from-github.sh`).
- `DEPLOY_REPO_URL` - URL git-репозитория для деплоя.
- `DEPLOY_BRANCH` - ветка по умолчанию для `/deploy` (если без аргумента).
- `DEPLOY_APP_DIR` - директория проекта на сервере (по умолчанию `/opt/cloudtune`).
- `DEPLOY_TIMEOUT_SECONDS` - таймаут деплоя в секундах.
- `DEPLOY_ALLOWED_CHAT_IDS` - chat id, которым разрешен `/deploy` (если пусто, используется `TELEGRAM_ALLOWED_CHAT_IDS`).
- `DEPLOY_MAIN_LANDING` - деплоить основной лендинг в web-root (`true/false`).
- `DEPLOY_RESUME_LANDING` - деплоить resume-лендинг (`true/false`).
- `MAIN_LANDING_SRC` - исходная папка основного лендинга в репозитории.
- `MAIN_LANDING_DST` - целевая папка основного лендинга на сервере.
- `RESUME_LANDING_SRC` - исходная папка resume-лендинга в репозитории.
- `RESUME_LANDING_DST` - целевая папка resume-лендинга на сервере.
- `DEPLOY_ARTIFACTS_TO_MAIN` - копировать `cloudtune_win.zip` и `cloudtune_andr.apk` в основной web-root (`true/false`).
- `RESTART_MONITORING_BOT` - перезапускать systemd-сервис бота после деплоя (`true/false`).
- `MONITORING_SERVICE_NAME` - имя systemd-сервиса бота.
- `MONITORING_RESTART_DELAY_SECONDS` - задержка перед рестартом бота, чтобы `/deploy` успел вернуть результат.
- `RUN_POST_DEPLOY_TESTS` - запускать post-deploy автотесты (`true/false`).
- `POST_DEPLOY_TEST_SCRIPT` - путь до post-deploy тест-скрипта.
- `POST_DEPLOY_TEST_API_BASE_URL` - base URL API для post-deploy тестов.
- `POST_DEPLOY_TEST_MAIN_LANDING_URL` - URL проверки основного лендинга.
- `POST_DEPLOY_TEST_RESUME_LANDING_URL` - URL проверки resume-лендинга.
- `POST_DEPLOY_TEST_TIMEOUT_SECONDS` - таймаут HTTP-запросов post-deploy тестов.
- `ROLLBACK_ON_TEST_FAILURE` - откатывать деплой на предыдущий commit при падении тестов (`true/false`).
- `DEPLOY_AUTOSTASH_LOCAL_CHANGES` - при локальных изменениях в git-репозитории на сервере автоматически делать `git stash --include-untracked` перед `git pull` (`true/false`, по умолчанию `true`).

По умолчанию `/deploy` теперь обновляет backend, основной лендинг, resume-лендинг, запускает подробные post-deploy тесты и при их падении откатывает на предыдущий commit с повторным деплоем.

## Локальный запуск
```bash
cd monitoring
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
cp .env.example .env
.venv/bin/python src/bot.py
```

## Запуск вне Docker (systemd, рекомендуется)
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

## Запуск через Docker (опционально)
```bash
cd monitoring
docker compose up --build -d
```

## Upload Spike Alerts

Snapshot now includes upload error diagnostics:

- `upload_failed_by_reason`
- `upload_status_class_total`
- `upload_4xx_total`
- `upload_5xx_total`
- `upload_4xx_rate_pct`
- `upload_5xx_rate_pct`

Additional bot thresholds:

- `ALERT_MIN_UPLOAD_REQUESTS_FOR_RATE`
- `ALERT_MAX_UPLOAD_4XX_RATE_PCT`
- `ALERT_MAX_UPLOAD_5XX_RATE_PCT`
- `ALERT_MAX_UPLOAD_4XX_TOTAL`
- `ALERT_MAX_UPLOAD_5XX_TOTAL`
