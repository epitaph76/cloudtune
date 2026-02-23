# CloudTune Monitoring Bot

Telegram-бот для мониторинга CloudTune backend через защищенные Monitoring API-эндпоинты.

## Что умеет
- Команды: `/status`, `/storage`, `/connections`, `/runtime`, `/users`, `/snapshot`, `/all`, `/help`.
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
- `ALERT_MAX_ACTIVE_HTTP_REQUESTS` - порог active HTTP requests.
- `ALERT_MAX_DB_IN_USE_CONNECTIONS` - порог DB in_use.
- `ALERT_MAX_GOROUTINES` - порог goroutines.
- `ALERT_MAX_GO_MEMORY_MB` - порог Go alloc памяти в MB.
- `ALERT_MIN_UPLOADS_DISK_FREE_MB` - минимально свободное место (uploads FS) в MB.

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
