import asyncio
import html
import logging
import os
from datetime import datetime, timezone
from typing import Any, Optional, Set, Tuple

import httpx
from dotenv import load_dotenv
from telegram import InlineKeyboardButton, InlineKeyboardMarkup, ReplyKeyboardMarkup, Update
from telegram.constants import ParseMode
from telegram.ext import (
    Application,
    CallbackQueryHandler,
    CommandHandler,
    ContextTypes,
    MessageHandler,
    filters,
)


load_dotenv()

logging.basicConfig(
    format="%(asctime)s | %(levelname)s | %(name)s | %(message)s",
    level=logging.INFO,
)
logger = logging.getLogger("cloudtune-monitoring-bot")


def parse_bool(raw: str, default: bool) -> bool:
    value = raw.strip().lower() if raw else ""
    if value in {"1", "true", "yes", "on"}:
        return True
    if value in {"0", "false", "no", "off"}:
        return False
    return default


def parse_chat_ids(raw: str) -> Set[int]:
    out: Set[int] = set()
    for value in raw.split(","):
        value = value.strip()
        if not value:
            continue
        try:
            out.add(int(value))
        except ValueError:
            logger.warning("Пропускаю некорректный chat id: %s", value)
    return out


def parse_int(raw: str, default: int) -> int:
    try:
        value = int(raw)
        return value if value > 0 else default
    except Exception:
        return default


TELEGRAM_BOT_TOKEN = os.getenv("TELEGRAM_BOT_TOKEN", "").strip()
BACKEND_BASE_URL = os.getenv("BACKEND_BASE_URL", "http://localhost:8080").rstrip("/")
BACKEND_MONITORING_API_KEY = os.getenv("BACKEND_MONITORING_API_KEY", "").strip()
REQUEST_TIMEOUT = float(os.getenv("REQUEST_TIMEOUT", "10"))
BACKEND_HEALTH_PATH = os.getenv("BACKEND_HEALTH_PATH", "/health").strip() or "/health"
ALERT_CHECK_INTERVAL_SECONDS = int(os.getenv("ALERT_CHECK_INTERVAL_SECONDS", "300"))
ALERTS_ENABLED = parse_bool(os.getenv("ALERTS_ENABLED", "true"), True)
ALERT_NOTIFY_ON_START = parse_bool(os.getenv("ALERT_NOTIFY_ON_START", "true"), True)
ALLOWED_CHAT_IDS = parse_chat_ids(os.getenv("TELEGRAM_ALLOWED_CHAT_IDS", ""))
ALERT_RECIPIENT_CHAT_IDS = parse_chat_ids(os.getenv("ALERT_RECIPIENT_CHAT_IDS", ""))
USERS_PAGE_SIZE = int(os.getenv("USERS_PAGE_SIZE", "8"))

# Пороговые алерты
ALERT_MAX_ACTIVE_HTTP_REQUESTS = parse_int(os.getenv("ALERT_MAX_ACTIVE_HTTP_REQUESTS", "300"), 300)
ALERT_MAX_DB_IN_USE_CONNECTIONS = parse_int(os.getenv("ALERT_MAX_DB_IN_USE_CONNECTIONS", "50"), 50)
ALERT_MAX_GOROUTINES = parse_int(os.getenv("ALERT_MAX_GOROUTINES", "500"), 500)
ALERT_MAX_GO_MEMORY_MB = parse_int(os.getenv("ALERT_MAX_GO_MEMORY_MB", "512"), 512)
ALERT_MIN_UPLOADS_DISK_FREE_MB = parse_int(os.getenv("ALERT_MIN_UPLOADS_DISK_FREE_MB", "512"), 512)


MENU_BUTTON_STATUS = "📊 Статус"
MENU_BUTTON_STORAGE = "💾 Хранилище"
MENU_BUTTON_CONNECTIONS = "🔌 Подключения"
MENU_BUTTON_RUNTIME = "⚙️ Рантайм"
MENU_BUTTON_USERS = "👥 Пользователи"
MENU_BUTTON_SNAPSHOT = "🧪 Снимок"
MENU_BUTTON_ALL = "🧾 Полный отчет"
MENU_BUTTON_HELP = "❓ Помощь"

MENU_KEYBOARD = ReplyKeyboardMarkup(
    [
        [MENU_BUTTON_STATUS, MENU_BUTTON_STORAGE],
        [MENU_BUTTON_CONNECTIONS, MENU_BUTTON_RUNTIME],
        [MENU_BUTTON_USERS, MENU_BUTTON_SNAPSHOT],
        [MENU_BUTTON_ALL, MENU_BUTTON_HELP],
    ],
    resize_keyboard=True,
    is_persistent=True,
    input_field_placeholder="Выберите метрику",
)

BUTTON_TO_QUERY = {
    MENU_BUTTON_STATUS: ("status", "/api/monitor/status"),
    MENU_BUTTON_STORAGE: ("storage", "/api/monitor/storage"),
    MENU_BUTTON_CONNECTIONS: ("connections", "/api/monitor/connections"),
    MENU_BUTTON_RUNTIME: ("runtime", "/api/monitor/runtime"),
    MENU_BUTTON_ALL: ("all", "/api/monitor/all"),
}

USERS_CALLBACK_PREFIX = "users_page:"


def is_chat_allowed(chat_id: int) -> bool:
    return not ALLOWED_CHAT_IDS or chat_id in ALLOWED_CHAT_IDS


def register_runtime_chat(application: Application, chat_id: int) -> None:
    runtime_chat_ids = application.bot_data.setdefault("runtime_chat_ids", set())
    runtime_chat_ids.add(chat_id)


def resolve_alert_recipients(application: Application) -> Set[int]:
    if ALERT_RECIPIENT_CHAT_IDS:
        return set(ALERT_RECIPIENT_CHAT_IDS)
    if ALLOWED_CHAT_IDS:
        return set(ALLOWED_CHAT_IDS)
    return set(application.bot_data.get("runtime_chat_ids", set()))


async def fetch_monitoring_json(path: str, params: Optional[dict[str, Any]] = None) -> dict[str, Any]:
    url = f"{BACKEND_BASE_URL}{path}"
    headers = {"X-Monitoring-Key": BACKEND_MONITORING_API_KEY}

    async with httpx.AsyncClient(timeout=REQUEST_TIMEOUT) as client:
        response = await client.get(url, headers=headers, params=params)

    if response.status_code != 200:
        raise RuntimeError(f"Backend вернул {response.status_code}: {response.text}")

    payload = response.json()
    if not isinstance(payload, dict):
        raise RuntimeError("Некорректный формат ответа backend")
    return payload


async def fetch_monitoring_text(path: str) -> str:
    payload = await fetch_monitoring_json(path)
    text = payload.get("text")
    if not isinstance(text, str):
        raise RuntimeError("Некорректный формат ответа backend")
    return text


async def fetch_snapshot() -> dict[str, Any]:
    return await fetch_monitoring_json("/api/monitor/snapshot")


async def check_backend_health() -> Tuple[bool, str]:
    url = f"{BACKEND_BASE_URL}{BACKEND_HEALTH_PATH}"
    try:
        async with httpx.AsyncClient(timeout=REQUEST_TIMEOUT) as client:
            response = await client.get(url)
        if 200 <= response.status_code < 300:
            return True, f"HTTP {response.status_code}"
        return False, f"HTTP {response.status_code}: {response.text[:120]}"
    except Exception as exc:
        return False, str(exc)


def format_help_message() -> str:
    return (
        "🤖 <b>CloudTune Monitoring Bot</b>\n\n"
        "Доступные команды:\n"
        "• /status\n"
        "• /storage\n"
        "• /connections\n"
        "• /runtime\n"
        "• /users\n"
        "• /snapshot\n"
        "• /all\n"
        "• /help\n\n"
        f"⏱️ Автопроверка backend каждые {max(ALERT_CHECK_INTERVAL_SECONDS, 60)} сек."
    )


def format_monitoring_message(kind: str, raw_text: str) -> str:
    titles = {
        "status": "📊 Состояние сервера",
        "storage": "💾 Хранилище",
        "connections": "🔌 Подключения",
        "runtime": "⚙️ Рантайм",
        "users": "👥 Пользователи",
        "all": "🧾 Полный отчет",
    }
    title = titles.get(kind, "📌 Мониторинг")

    lines = []
    for raw_line in raw_text.splitlines():
        line = raw_line.strip()
        if not line:
            continue

        if kind == "all" and ":" not in line:
            lines.append(f"\n<b>{html.escape(line)}</b>")
            continue

        if ":" in line:
            key, value = line.split(":", 1)
            lines.append(
                f"• <b>{html.escape(key.strip())}:</b> <code>{html.escape(value.strip())}</code>"
            )
        else:
            lines.append(f"• {html.escape(line)}")

    body = "\n".join(lines) if lines else "• Нет данных"
    return f"{title}\n\n{body}"


def format_bytes(size: int) -> str:
    units = ["B", "KB", "MB", "GB", "TB"]
    value = float(max(size, 0))
    unit_idx = 0
    while value >= 1024 and unit_idx < len(units) - 1:
        value /= 1024
        unit_idx += 1
    if unit_idx == 0:
        return f"{int(value)} {units[unit_idx]}"
    return f"{value:.2f} {units[unit_idx]}"


def shorten(value: str, limit: int = 48) -> str:
    if len(value) <= limit:
        return value
    return value[: limit - 1] + "…"


def build_users_keyboard(page: int, total_pages: int) -> Optional[InlineKeyboardMarkup]:
    if total_pages <= 1:
        return None

    buttons: list[InlineKeyboardButton] = []
    if page > 1:
        buttons.append(
            InlineKeyboardButton("⬅️", callback_data=f"{USERS_CALLBACK_PREFIX}{page - 1}")
        )
    if page < total_pages:
        buttons.append(
            InlineKeyboardButton("➡️", callback_data=f"{USERS_CALLBACK_PREFIX}{page + 1}")
        )

    if not buttons:
        return None

    return InlineKeyboardMarkup([buttons])


def format_users_page(payload: dict[str, Any]) -> tuple[str, Optional[InlineKeyboardMarkup]]:
    total_users = int(payload.get("total_users", 0))
    page = int(payload.get("page", 1))
    total_pages = int(payload.get("total_pages", 1))
    users = payload.get("users", [])

    lines = [
        "👥 <b>Пользователи CloudTune</b>",
        f"Всего пользователей: <b>{total_users}</b>",
        f"Страница: <b>{page}/{max(total_pages, 1)}</b>",
        "",
    ]

    if not users:
        lines.append("Пользователи не найдены.")
    else:
        for idx, user in enumerate(users, start=1):
            email = shorten(str(user.get("email", "-")))
            username = shorten(str(user.get("username", "-")))
            used_bytes = int(user.get("used_bytes", 0))
            created_at = str(user.get("created_at", "-")).replace("T", " ").replace("Z", " UTC")

            lines.append(
                f"{idx}. 📧 <code>{html.escape(email)}</code> | "
                f"👤 <b>{html.escape(username)}</b>"
            )
            lines.append(f"   💽 Занято: <code>{html.escape(format_bytes(used_bytes))}</code>")
            lines.append(f"   🗓️ Регистрация: <code>{html.escape(created_at)}</code>")
            lines.append("")

    text = "\n".join(lines).rstrip()
    keyboard = build_users_keyboard(page, total_pages)
    return text, keyboard


def format_snapshot(payload: dict[str, Any]) -> str:
    lines = [
        "🧪 <b>Технический снимок</b>",
        f"🕒 <code>{html.escape(str(payload.get('timestamp_utc', '-')))}</code>",
        f"⏱️ Uptime: <code>{payload.get('uptime_seconds', 0)} сек</code>",
        "",
        f"🌐 HTTP active: <code>{payload.get('http_active_requests', 0)}</code>",
        f"🌐 HTTP total: <code>{payload.get('http_total_requests', 0)}</code>",
        f"🧵 Goroutines: <code>{payload.get('goroutines', 0)}</code>",
        "",
        f"🗄️ DB open: <code>{payload.get('db_open_connections', 0)}</code>",
        f"🗄️ DB in_use: <code>{payload.get('db_in_use_connections', 0)}</code>",
        f"🗄️ DB wait_count: <code>{payload.get('db_wait_count', 0)}</code>",
        "",
        f"🧠 Go alloc: <code>{format_bytes(int(payload.get('go_memory_alloc_bytes', 0)))}</code>",
        f"🧠 Go heap_in_use: <code>{format_bytes(int(payload.get('go_heap_in_use_bytes', 0)))}</code>",
        f"🧠 Go sys: <code>{format_bytes(int(payload.get('go_memory_sys_bytes', 0)))}</code>",
        "",
        f"💾 Uploads size: <code>{format_bytes(int(payload.get('uploads_size_bytes', 0)))}</code>",
        f"💾 Uploads free: <code>{format_bytes(int(payload.get('uploads_fs_free_bytes', 0)))}</code>",
        f"💾 Uploads files: <code>{payload.get('uploads_files_count', 0)}</code>",
        "",
        f"👥 Users: <code>{payload.get('users_total', 0)}</code>",
        f"🎵 Songs: <code>{payload.get('songs_total', 0)}</code>",
        f"📚 Playlists: <code>{payload.get('playlists_total', 0)}</code>",
    ]
    return "\n".join(lines)


def build_threshold_issues(snapshot: dict[str, Any]) -> dict[str, str]:
    issues: dict[str, str] = {}

    http_active = int(snapshot.get("http_active_requests", 0))
    db_in_use = int(snapshot.get("db_in_use_connections", 0))
    goroutines = int(snapshot.get("goroutines", 0))
    mem_alloc_mb = int(snapshot.get("go_memory_alloc_bytes", 0)) // (1024 * 1024)
    uploads_free_mb = int(snapshot.get("uploads_fs_free_bytes", 0)) // (1024 * 1024)

    if http_active > ALERT_MAX_ACTIVE_HTTP_REQUESTS:
        issues["http_active"] = (
            f"HTTP active requests: {http_active} > {ALERT_MAX_ACTIVE_HTTP_REQUESTS}"
        )
    if db_in_use > ALERT_MAX_DB_IN_USE_CONNECTIONS:
        issues["db_in_use"] = f"DB in_use: {db_in_use} > {ALERT_MAX_DB_IN_USE_CONNECTIONS}"
    if goroutines > ALERT_MAX_GOROUTINES:
        issues["goroutines"] = f"Goroutines: {goroutines} > {ALERT_MAX_GOROUTINES}"
    if mem_alloc_mb > ALERT_MAX_GO_MEMORY_MB:
        issues["memory"] = f"Go alloc: {mem_alloc_mb} MB > {ALERT_MAX_GO_MEMORY_MB} MB"
    if uploads_free_mb < ALERT_MIN_UPLOADS_DISK_FREE_MB:
        issues["disk_free"] = (
            f"Uploads free: {uploads_free_mb} MB < {ALERT_MIN_UPLOADS_DISK_FREE_MB} MB"
        )

    return issues


async def send_pretty_message(update: Update, text: str) -> None:
    if update.message is None:
        return
    await update.message.reply_text(
        text,
        parse_mode=ParseMode.HTML,
        reply_markup=MENU_KEYBOARD,
        disable_web_page_preview=True,
    )


async def send_monitoring(update: Update, context: ContextTypes.DEFAULT_TYPE, kind: str, path: str) -> None:
    chat = update.effective_chat
    if chat is None or update.message is None:
        return

    if not is_chat_allowed(chat.id):
        await send_pretty_message(update, "⛔ <b>Доступ запрещен для этого чата</b>")
        return

    register_runtime_chat(context.application, chat.id)

    try:
        text = await fetch_monitoring_text(path)
        await send_pretty_message(update, format_monitoring_message(kind, text))
    except Exception as exc:
        logger.exception("Ошибка получения метрик")
        await send_pretty_message(
            update,
            "🚨 <b>Ошибка мониторинга</b>\n"
            f"<code>{html.escape(str(exc))}</code>",
        )


async def send_snapshot(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    chat = update.effective_chat
    if chat is None or update.message is None:
        return

    if not is_chat_allowed(chat.id):
        await send_pretty_message(update, "⛔ <b>Доступ запрещен для этого чата</b>")
        return

    register_runtime_chat(context.application, chat.id)
    try:
        payload = await fetch_snapshot()
        await send_pretty_message(update, format_snapshot(payload))
    except Exception as exc:
        logger.exception("Ошибка получения snapshot")
        await send_pretty_message(
            update,
            "🚨 <b>Ошибка загрузки snapshot</b>\n"
            f"<code>{html.escape(str(exc))}</code>",
        )


async def send_users_page(update: Update, context: ContextTypes.DEFAULT_TYPE, page: int) -> None:
    chat = update.effective_chat
    if chat is None or update.message is None:
        return

    if not is_chat_allowed(chat.id):
        await send_pretty_message(update, "⛔ <b>Доступ запрещен для этого чата</b>")
        return

    register_runtime_chat(context.application, chat.id)

    try:
        payload = await fetch_monitoring_json(
            "/api/monitor/users/list",
            params={"page": max(page, 1), "limit": max(USERS_PAGE_SIZE, 1)},
        )
        text, keyboard = format_users_page(payload)
        await update.message.reply_text(
            text,
            parse_mode=ParseMode.HTML,
            reply_markup=keyboard,
            disable_web_page_preview=True,
        )
    except Exception as exc:
        logger.exception("Ошибка получения списка пользователей")
        await send_pretty_message(
            update,
            "🚨 <b>Ошибка загрузки списка пользователей</b>\n"
            f"<code>{html.escape(str(exc))}</code>",
        )


async def handle_users_page_callback(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    query = update.callback_query
    if query is None or query.data is None:
        return

    chat = query.message.chat if query.message else None
    if chat is None:
        await query.answer()
        return

    if not is_chat_allowed(chat.id):
        await query.answer("Доступ запрещен", show_alert=True)
        return

    register_runtime_chat(context.application, chat.id)

    page_raw = query.data.replace(USERS_CALLBACK_PREFIX, "", 1)
    try:
        page = max(int(page_raw), 1)
    except ValueError:
        page = 1

    try:
        payload = await fetch_monitoring_json(
            "/api/monitor/users/list",
            params={"page": page, "limit": max(USERS_PAGE_SIZE, 1)},
        )
        text, keyboard = format_users_page(payload)
        await query.edit_message_text(
            text=text,
            parse_mode=ParseMode.HTML,
            reply_markup=keyboard,
            disable_web_page_preview=True,
        )
        await query.answer()
    except Exception as exc:
        logger.exception("Ошибка переключения страницы пользователей")
        await query.answer("Ошибка загрузки страницы", show_alert=True)
        if query.message is not None:
            await query.message.reply_text(
                "🚨 <b>Ошибка загрузки страницы пользователей</b>\n"
                f"<code>{html.escape(str(exc))}</code>",
                parse_mode=ParseMode.HTML,
                reply_markup=MENU_KEYBOARD,
            )


async def cmd_start(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    chat = update.effective_chat
    if update.message is None or chat is None:
        return

    if not is_chat_allowed(chat.id):
        await send_pretty_message(update, "⛔ <b>Доступ запрещен для этого чата</b>")
        return

    register_runtime_chat(context.application, chat.id)
    await send_pretty_message(update, format_help_message())


async def cmd_help(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    await cmd_start(update, context)


async def cmd_status(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    await send_monitoring(update, context, "status", "/api/monitor/status")


async def cmd_storage(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    await send_monitoring(update, context, "storage", "/api/monitor/storage")


async def cmd_connections(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    await send_monitoring(update, context, "connections", "/api/monitor/connections")


async def cmd_runtime(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    await send_monitoring(update, context, "runtime", "/api/monitor/runtime")


async def cmd_users(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    await send_users_page(update, context, 1)


async def cmd_snapshot(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    await send_snapshot(update, context)


async def cmd_all(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    await send_monitoring(update, context, "all", "/api/monitor/all")


async def handle_menu_buttons(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    if update.message is None or update.message.text is None:
        return

    chat = update.effective_chat
    if chat is None:
        return

    if not is_chat_allowed(chat.id):
        await send_pretty_message(update, "⛔ <b>Доступ запрещен для этого чата</b>")
        return

    register_runtime_chat(context.application, chat.id)

    text = update.message.text.strip()
    if text == MENU_BUTTON_HELP:
        await send_pretty_message(update, format_help_message())
        return

    if text == MENU_BUTTON_USERS:
        await send_users_page(update, context, 1)
        return

    if text == MENU_BUTTON_SNAPSHOT:
        await send_snapshot(update, context)
        return

    mapping = BUTTON_TO_QUERY.get(text)
    if mapping is None:
        await send_pretty_message(
            update,
            "🤔 <b>Не понял команду</b>\n"
            "Используйте кнопки ниже или /help",
        )
        return

    kind, path = mapping
    await send_monitoring(update, context, kind, path)


async def broadcast_alert(application: Application, text: str) -> None:
    recipients = resolve_alert_recipients(application)
    if not recipients:
        logger.warning("Не заданы получатели для алертов")
        return

    for chat_id in recipients:
        try:
            await application.bot.send_message(
                chat_id=chat_id,
                text=text,
                parse_mode=ParseMode.HTML,
                disable_web_page_preview=True,
            )
        except Exception:
            logger.exception("Не удалось отправить алерт chat_id=%s", chat_id)


def now_utc() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")


async def watchdog_loop(application: Application) -> None:
    previous_backend_state: Optional[bool] = None
    previous_issue_states: dict[str, str] = {}

    while True:
        is_up, detail = await check_backend_health()
        application.bot_data["backend_is_up"] = is_up
        application.bot_data["backend_health_detail"] = detail

        if previous_backend_state is None:
            if ALERT_NOTIFY_ON_START:
                startup_text = (
                    "✅ <b>Мониторинг запущен</b>\n"
                    f"🕒 <code>{now_utc()}</code>\n"
                    f"🔎 Проверка: <code>{html.escape(BACKEND_HEALTH_PATH)}</code>\n"
                    f"📡 Статус backend: <b>{'UP' if is_up else 'DOWN'}</b>\n"
                    f"ℹ️ Детали: <code>{html.escape(detail)}</code>"
                )
                await broadcast_alert(application, startup_text)
        elif previous_backend_state and not is_up:
            alert_text = (
                "🚨 <b>CloudTune Alert: BACKEND НЕДОСТУПЕН</b>\n"
                f"🕒 <code>{now_utc()}</code>\n"
                f"🔎 Проверка: <code>{html.escape(BACKEND_HEALTH_PATH)}</code>\n"
                f"ℹ️ Детали: <code>{html.escape(detail)}</code>"
            )
            await broadcast_alert(application, alert_text)
        elif not previous_backend_state and is_up:
            recovery_text = (
                "✅ <b>CloudTune Alert: BACKEND ВОССТАНОВЛЕН</b>\n"
                f"🕒 <code>{now_utc()}</code>\n"
                f"🔎 Проверка: <code>{html.escape(BACKEND_HEALTH_PATH)}</code>\n"
                f"ℹ️ Детали: <code>{html.escape(detail)}</code>"
            )
            await broadcast_alert(application, recovery_text)

        previous_backend_state = is_up

        # Пороговые алерты доступны, только если backend сейчас отвечает.
        if is_up:
            try:
                snapshot = await fetch_snapshot()
                current_issues = build_threshold_issues(snapshot)

                for issue_key, issue_text in current_issues.items():
                    prev_text = previous_issue_states.get(issue_key)
                    if prev_text != issue_text:
                        await broadcast_alert(
                            application,
                            "⚠️ <b>Порог мониторинга превышен</b>\n"
                            f"🕒 <code>{now_utc()}</code>\n"
                            f"ℹ️ <code>{html.escape(issue_text)}</code>",
                        )

                for recovered_key in set(previous_issue_states.keys()) - set(current_issues.keys()):
                    await broadcast_alert(
                        application,
                        "✅ <b>Порог мониторинга восстановлен</b>\n"
                        f"🕒 <code>{now_utc()}</code>\n"
                        f"ℹ️ <code>{html.escape(recovered_key)}</code>",
                    )

                previous_issue_states = current_issues
            except Exception as exc:
                logger.exception("Ошибка получения snapshot в watchdog")
                await broadcast_alert(
                    application,
                    "⚠️ <b>Ошибка расширенного мониторинга</b>\n"
                    f"🕒 <code>{now_utc()}</code>\n"
                    f"ℹ️ <code>{html.escape(str(exc))}</code>",
                )
                previous_issue_states = {}
        else:
            previous_issue_states = {}

        await asyncio.sleep(max(ALERT_CHECK_INTERVAL_SECONDS, 60))


async def on_startup(application: Application) -> None:
    if not ALERTS_ENABLED:
        logger.info("Алерты отключены: ALERTS_ENABLED=false")
        return

    task = asyncio.create_task(watchdog_loop(application))
    application.bot_data["watchdog_task"] = task
    logger.info("Watchdog запущен: interval=%s сек", ALERT_CHECK_INTERVAL_SECONDS)


async def on_shutdown(application: Application) -> None:
    task = application.bot_data.get("watchdog_task")
    if task is None:
        return

    task.cancel()
    try:
        await task
    except asyncio.CancelledError:
        pass


def validate_config() -> Optional[str]:
    if not TELEGRAM_BOT_TOKEN:
        return "TELEGRAM_BOT_TOKEN is required"
    if not BACKEND_MONITORING_API_KEY:
        return "BACKEND_MONITORING_API_KEY is required"
    return None


def main() -> None:
    config_error = validate_config()
    if config_error:
        raise RuntimeError(config_error)

    app = (
        Application.builder()
        .token(TELEGRAM_BOT_TOKEN)
        .post_init(on_startup)
        .post_shutdown(on_shutdown)
        .build()
    )

    app.add_handler(CommandHandler("start", cmd_start))
    app.add_handler(CommandHandler("help", cmd_help))
    app.add_handler(CommandHandler("status", cmd_status))
    app.add_handler(CommandHandler("storage", cmd_storage))
    app.add_handler(CommandHandler("connections", cmd_connections))
    app.add_handler(CommandHandler("runtime", cmd_runtime))
    app.add_handler(CommandHandler("users", cmd_users))
    app.add_handler(CommandHandler("snapshot", cmd_snapshot))
    app.add_handler(CommandHandler("all", cmd_all))
    app.add_handler(CallbackQueryHandler(handle_users_page_callback, pattern=r"^users_page:\d+$"))
    app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, handle_menu_buttons))

    logger.info("Запуск CloudTune monitoring bot")
    app.run_polling(allowed_updates=Update.ALL_TYPES)


if __name__ == "__main__":
    main()
