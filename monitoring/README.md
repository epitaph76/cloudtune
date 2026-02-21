# CloudTune Monitoring Bot (Python)

Standalone Telegram bot for CloudTune monitoring via backend API (Go).

## Features

- Telegram keyboard buttons for quick actions.
- Formatted messages with emojis and HTML styling.
- Monitoring commands: `/status`, `/storage`, `/connections`, `/users`, `/all`, `/help`.
- `/users` shows paginated user list with email, username, used storage and created date.
- Inline arrow buttons (`⬅️`/`➡️`) for users list paging.
- Automatic backend health check every 5 minutes (configurable).
- Auto-alerts to Telegram when backend goes DOWN and when it RECOVERS.

## Environment variables

- `TELEGRAM_BOT_TOKEN` - Telegram bot token.
- `TELEGRAM_ALLOWED_CHAT_IDS` - comma-separated chat IDs allowed to use the bot.
- `ALERT_RECIPIENT_CHAT_IDS` - comma-separated chat IDs for auto-alerts.
  - If empty, bot uses `TELEGRAM_ALLOWED_CHAT_IDS`.
  - If both are empty, alerts go only to chats that already interacted with bot.
- `BACKEND_BASE_URL` - backend API URL, for example `http://localhost:8080`.
- `BACKEND_MONITORING_API_KEY` - key used in `X-Monitoring-Key` header for `/api/monitor/*` endpoints.
- `BACKEND_HEALTH_PATH` - health endpoint for watchdog checks (default: `/health`).
- `REQUEST_TIMEOUT` - HTTP timeout in seconds.
- `ALERTS_ENABLED` - `true/false`, enable background watchdog.
- `ALERT_NOTIFY_ON_START` - `true/false`, send startup status alert.
- `ALERT_CHECK_INTERVAL_SECONDS` - watchdog interval in seconds (default: `300`).
- `USERS_PAGE_SIZE` - users per page for `/users` (default: `8`).

## Local run

```bash
cd monitoring
python -m venv .venv
source .venv/bin/activate  # Windows: .venv\\Scripts\\activate
pip install -r requirements.txt
cp .env.example .env
python src/bot.py
```

## Docker run

```bash
cd monitoring
docker build -t cloudtune-monitoring-bot .
docker run --rm --env-file .env cloudtune-monitoring-bot
```

## Docker Compose

```bash
cd monitoring
docker compose up --build -d
```
