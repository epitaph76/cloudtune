import asyncio
import csv
import html
import io
import logging
import os
import re
import uuid
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
DEPLOY_ENABLED = parse_bool(os.getenv("DEPLOY_ENABLED", "true"), True)
DEPLOY_SCRIPT_PATH = os.getenv(
    "DEPLOY_SCRIPT_PATH",
    "/opt/cloudtune/backend/scripts/deploy-from-github.sh",
).strip()
DEPLOY_REPO_URL = os.getenv(
    "DEPLOY_REPO_URL",
    "https://github.com/epitaph76/cloudtune.git",
).strip()
DEPLOY_BRANCH = os.getenv("DEPLOY_BRANCH", "master").strip() or "master"
DEPLOY_APP_DIR = os.getenv("DEPLOY_APP_DIR", "/opt/cloudtune").strip() or "/opt/cloudtune"
DEPLOY_TIMEOUT_SECONDS = parse_int(os.getenv("DEPLOY_TIMEOUT_SECONDS", "1800"), 1800)
DEPLOY_ALLOWED_CHAT_IDS = parse_chat_ids(os.getenv("DEPLOY_ALLOWED_CHAT_IDS", ""))

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
MENU_BUTTON_DEPLOY = "🚀 Деплой"
MENU_BUTTON_HELP = "❓ Помощь"

MENU_KEYBOARD = ReplyKeyboardMarkup(
    [
        [MENU_BUTTON_STATUS, MENU_BUTTON_STORAGE],
        [MENU_BUTTON_CONNECTIONS, MENU_BUTTON_RUNTIME],
        [MENU_BUTTON_USERS, MENU_BUTTON_SNAPSHOT],
        [MENU_BUTTON_ALL, MENU_BUTTON_DEPLOY],
        [MENU_BUTTON_HELP],
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
USER_CALLBACK_PREFIX = "user:"
USER_TRACKS_PAGE_SIZE = 5
USER_PLAYLISTS_PAGE_SIZE = 5
DB_CONTAINER_NAME = os.getenv("DB_CONTAINER_NAME", "cloudtune-db").strip() or "cloudtune-db"
DB_NAME = os.getenv("DB_NAME", "cloudtune").strip() or "cloudtune"
DB_USER = os.getenv("DB_USER", "cloudtune").strip() or "cloudtune"
EMAIL_RE = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")


def is_chat_allowed(chat_id: int) -> bool:
    return not ALLOWED_CHAT_IDS or chat_id in ALLOWED_CHAT_IDS


def is_deploy_chat_allowed(chat_id: int) -> bool:
    allowed = DEPLOY_ALLOWED_CHAT_IDS or ALLOWED_CHAT_IDS
    return not allowed or chat_id in allowed


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


def looks_like_email(value: str) -> bool:
    return bool(EMAIL_RE.match(value.strip().lower()))


def _sql_quote(value: str) -> str:
    return value.replace("'", "''")


async def run_db_query(sql: str) -> list[dict[str, str]]:
    process = await asyncio.create_subprocess_exec(
        "docker",
        "exec",
        "-i",
        DB_CONTAINER_NAME,
        "psql",
        "-U",
        DB_USER,
        "-d",
        DB_NAME,
        "--csv",
        "-v",
        "ON_ERROR_STOP=1",
        "-P",
        "pager=off",
        "-c",
        sql,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE,
    )
    stdout, stderr = await process.communicate()
    if process.returncode != 0:
        raise RuntimeError(
            f"DB query failed ({process.returncode}): {stderr.decode('utf-8', errors='replace').strip()}"
        )

    text = stdout.decode("utf-8", errors="replace").strip()
    if not text:
        return []
    reader = csv.DictReader(io.StringIO(text))
    return list(reader)


async def get_user_by_email(email: str) -> Optional[dict[str, str]]:
    email_quoted = _sql_quote(email.strip().lower())
    rows = await run_db_query(
        "SELECT id, email, username, created_at "
        "FROM users "
        f"WHERE lower(email) = '{email_quoted}' "
        "LIMIT 1;"
    )
    return rows[0] if rows else None


async def get_user_storage_summary(user_id: int) -> dict[str, int]:
    rows = await run_db_query(
        "SELECT COALESCE(SUM(s.filesize), 0)::bigint AS used_bytes, "
        "COUNT(*)::int AS tracks_count "
        "FROM songs s "
        "JOIN user_library ul ON ul.song_id = s.id "
        f"WHERE ul.user_id = {user_id};"
    )
    if not rows:
        return {"used_bytes": 0, "tracks_count": 0}
    row = rows[0]
    return {
        "used_bytes": int(row.get("used_bytes", "0") or 0),
        "tracks_count": int(row.get("tracks_count", "0") or 0),
    }


async def get_user_tracks(user_id: int, page: int, limit: int) -> tuple[list[dict[str, str]], int]:
    offset = max(page - 1, 0) * max(limit, 1)
    count_rows = await run_db_query(
        "SELECT COUNT(*)::int AS total_tracks "
        "FROM songs s "
        "JOIN user_library ul ON ul.song_id = s.id "
        f"WHERE ul.user_id = {user_id};"
    )
    total_tracks = int(count_rows[0].get("total_tracks", "0")) if count_rows else 0

    rows = await run_db_query(
        "SELECT s.id, COALESCE(s.original_filename, s.filename) AS title, "
        "s.filesize::bigint AS filesize, s.upload_date "
        "FROM songs s "
        "JOIN user_library ul ON ul.song_id = s.id "
        f"WHERE ul.user_id = {user_id} "
        "ORDER BY s.upload_date DESC, s.id DESC "
        f"LIMIT {max(limit, 1)} OFFSET {offset};"
    )
    return rows, total_tracks


async def get_user_playlists(user_id: int, page: int, limit: int) -> tuple[list[dict[str, str]], int]:
    offset = max(page - 1, 0) * max(limit, 1)
    count_rows = await run_db_query(
        "SELECT COUNT(*)::int AS total_playlists "
        "FROM playlists "
        f"WHERE owner_id = {user_id};"
    )
    total_playlists = int(count_rows[0].get("total_playlists", "0")) if count_rows else 0

    rows = await run_db_query(
        "SELECT p.id, p.name, p.is_favorite, p.created_at, p.updated_at, "
        "COUNT(ps.song_id)::int AS song_count "
        "FROM playlists p "
        "LEFT JOIN playlist_songs ps ON ps.playlist_id = p.id "
        f"WHERE p.owner_id = {user_id} "
        "GROUP BY p.id, p.name, p.is_favorite, p.created_at, p.updated_at "
        "ORDER BY p.is_favorite DESC, p.created_at DESC "
        f"LIMIT {max(limit, 1)} OFFSET {offset};"
    )
    return rows, total_playlists


def get_user_sessions(application: Application) -> dict[str, str]:
    return application.bot_data.setdefault("user_sessions", {})


def create_user_session(application: Application, email: str) -> str:
    token = uuid.uuid4().hex[:10]
    sessions = get_user_sessions(application)
    sessions[token] = email.strip().lower()
    return token


def resolve_user_email_by_token(application: Application, token: str) -> Optional[str]:
    return get_user_sessions(application).get(token)


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


def truncate_output(value: str, limit: int = 3200) -> str:
    value = value.strip()
    if len(value) <= limit:
        return value
    return value[: limit - 1] + "…"


async def run_deploy_script(branch: str) -> tuple[int, str, str]:
    env = os.environ.copy()
    env["REPO_URL"] = DEPLOY_REPO_URL
    env["BRANCH"] = branch
    env["APP_DIR"] = DEPLOY_APP_DIR

    process = await asyncio.create_subprocess_exec(
        "bash",
        DEPLOY_SCRIPT_PATH,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE,
        env=env,
    )

    try:
        stdout, stderr = await asyncio.wait_for(
            process.communicate(),
            timeout=max(DEPLOY_TIMEOUT_SECONDS, 60),
        )
    except asyncio.TimeoutError:
        process.kill()
        await process.wait()
        raise RuntimeError(
            f"Deploy timed out after {max(DEPLOY_TIMEOUT_SECONDS, 60)} seconds"
        )

    return (
        process.returncode,
        stdout.decode("utf-8", errors="replace"),
        stderr.decode("utf-8", errors="replace"),
    )


def format_help_message() -> str:
    return (
        "🤖 <b>CloudTune Monitoring Bot</b>\n\n"
        "Доступные команды:\n"
        "• /status\n"
        "• /storage\n"
        "• /connections\n"
        "• /runtime\n"
        "• /users\n"
        "• /user &lt;email&gt;\n"
        "• /snapshot\n"
        "• /all\n"
        "• /deploy [branch]\n"
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


def build_user_home_keyboard(token: str) -> InlineKeyboardMarkup:
    return InlineKeyboardMarkup(
        [[InlineKeyboardButton("О пользователе", callback_data=f"{USER_CALLBACK_PREFIX}about:{token}")]]
    )


def build_user_about_keyboard(token: str) -> InlineKeyboardMarkup:
    return InlineKeyboardMarkup(
        [
            [
                InlineKeyboardButton("Домой", callback_data=f"{USER_CALLBACK_PREFIX}home:{token}"),
                InlineKeyboardButton("Файлы", callback_data=f"{USER_CALLBACK_PREFIX}files:{token}"),
                InlineKeyboardButton("Плейлисты", callback_data=f"{USER_CALLBACK_PREFIX}playlists:{token}"),
            ]
        ]
    )


def build_user_files_keyboard(token: str) -> InlineKeyboardMarkup:
    return InlineKeyboardMarkup(
        [
            [
                InlineKeyboardButton("Треки", callback_data=f"{USER_CALLBACK_PREFIX}tracks:{token}:1"),
                InlineKeyboardButton("Домой", callback_data=f"{USER_CALLBACK_PREFIX}about:{token}"),
            ]
        ]
    )


def build_user_playlists_keyboard(token: str) -> InlineKeyboardMarkup:
    return InlineKeyboardMarkup(
        [
            [
                InlineKeyboardButton("Список", callback_data=f"{USER_CALLBACK_PREFIX}playlist_items:{token}:1"),
                InlineKeyboardButton("Домой", callback_data=f"{USER_CALLBACK_PREFIX}about:{token}"),
            ]
        ]
    )


def build_user_list_pagination_keyboard(
    token: str,
    kind: str,
    page: int,
    total_pages: int,
) -> InlineKeyboardMarkup:
    if kind == "tracks":
        prefix = f"{USER_CALLBACK_PREFIX}tracks:{token}:"
    else:
        prefix = f"{USER_CALLBACK_PREFIX}playlist_items:{token}:"

    row: list[InlineKeyboardButton] = []
    if page > 1:
        row.append(InlineKeyboardButton("⬅️", callback_data=f"{prefix}{page - 1}"))
    row.append(InlineKeyboardButton("Домой", callback_data=f"{USER_CALLBACK_PREFIX}about:{token}"))
    if page < total_pages:
        row.append(InlineKeyboardButton("➡️", callback_data=f"{prefix}{page + 1}"))
    return InlineKeyboardMarkup([row])


def format_user_home_text(user: dict[str, str]) -> str:
    return (
        "👤 <b>Карточка пользователя</b>\n\n"
        f"📧 <code>{html.escape(str(user.get('email', '-')))}</code>\n"
        f"👤 Username: <b>{html.escape(str(user.get('username', '-')))}</b>\n"
        "Нажмите кнопку ниже для детальной сводки."
    )


def format_user_about_text(user: dict[str, str], summary: dict[str, int]) -> str:
    created_at = str(user.get("created_at", "-")).replace("T", " ").replace("Z", " UTC")
    tracks_count = int(summary.get("tracks_count", 0))
    used_bytes = int(summary.get("used_bytes", 0))
    return (
        "ℹ️ <b>О пользователе</b>\n\n"
        f"🆔 ID: <code>{html.escape(str(user.get('id', '-')))}</code>\n"
        f"📧 Email: <code>{html.escape(str(user.get('email', '-')))}</code>\n"
        f"👤 Username: <b>{html.escape(str(user.get('username', '-')))}</b>\n"
        f"🗓️ Регистрация: <code>{html.escape(created_at)}</code>\n\n"
        f"Всего треков в user_library: <b>{tracks_count}</b>\n"
        f"Занято: <code>{used_bytes:,}</code> байт (примерно <code>{format_bytes(used_bytes)}</code>)"
    )


def format_user_files_text(summary: dict[str, int]) -> str:
    tracks_count = int(summary.get("tracks_count", 0))
    used_bytes = int(summary.get("used_bytes", 0))
    return (
        "🎵 <b>Файлы пользователя</b>\n\n"
        f"Всего треков в user_library: <b>{tracks_count}</b>\n"
        f"Занято: <code>{used_bytes:,}</code> байт (примерно <code>{format_bytes(used_bytes)}</code>)\n\n"
        "Нажмите <b>Треки</b>, чтобы открыть список по 5 шт."
    )


def format_user_tracks_page_text(rows: list[dict[str, str]], page: int, total_pages: int, total: int) -> str:
    lines = [
        "🎧 <b>Треки пользователя</b>",
        f"Страница: <b>{page}/{max(total_pages, 1)}</b>",
        f"Всего треков: <b>{total}</b>",
        "",
    ]
    if not rows:
        lines.append("Треки не найдены.")
        return "\n".join(lines)

    start_idx = (page - 1) * USER_TRACKS_PAGE_SIZE
    for idx, row in enumerate(rows, start=1):
        number = start_idx + idx
        title = shorten(str(row.get("title", "-")), 80)
        size = int(row.get("filesize", "0") or 0)
        uploaded = str(row.get("upload_date", "-")).replace("T", " ").replace("Z", " UTC")
        lines.append(f"{number}. <b>{html.escape(title)}</b>")
        lines.append(f"   ID: <code>{html.escape(str(row.get('id', '-')))}</code>")
        lines.append(f"   Размер: <code>{format_bytes(size)}</code>")
        lines.append(f"   Дата: <code>{html.escape(uploaded)}</code>")
        lines.append("")
    return "\n".join(lines).rstrip()


def format_user_playlists_page_text(rows: list[dict[str, str]], page: int, total_pages: int, total: int) -> str:
    lines = [
        "📚 <b>Плейлисты пользователя</b>",
        f"Страница: <b>{page}/{max(total_pages, 1)}</b>",
        f"Всего плейлистов: <b>{total}</b>",
        "",
    ]
    if not rows:
        lines.append("Плейлисты не найдены.")
        return "\n".join(lines)

    start_idx = (page - 1) * USER_PLAYLISTS_PAGE_SIZE
    for idx, row in enumerate(rows, start=1):
        number = start_idx + idx
        name = shorten(str(row.get("name", "-")), 80)
        song_count = int(row.get("song_count", "0") or 0)
        is_favorite = str(row.get("is_favorite", "false")).lower() in {"t", "true", "1"}
        lines.append(f"{number}. <b>{html.escape(name)}</b>")
        lines.append(f"   ID: <code>{html.escape(str(row.get('id', '-')))}</code>")
        lines.append(f"   Треков: <code>{song_count}</code>")
        if is_favorite:
            lines.append("   Тип: <b>System favorites</b>")
        lines.append("")
    return "\n".join(lines).rstrip()


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


async def send_user_home(update: Update, context: ContextTypes.DEFAULT_TYPE, email: str) -> None:
    chat = update.effective_chat
    if chat is None or update.message is None:
        return

    if not is_chat_allowed(chat.id):
        await send_pretty_message(update, "⛔ <b>Доступ запрещен для этого чата</b>")
        return

    register_runtime_chat(context.application, chat.id)

    normalized_email = email.strip().lower()
    if not looks_like_email(normalized_email):
        await send_pretty_message(
            update,
            "⚠️ <b>Неверный формат email</b>\n"
            "Используйте: <code>/user user@example.com</code>",
        )
        return

    try:
        user = await get_user_by_email(normalized_email)
        if user is None:
            await send_pretty_message(
                update,
                "🔎 <b>Пользователь не найден</b>\n"
                f"Email: <code>{html.escape(normalized_email)}</code>",
            )
            return

        token = create_user_session(context.application, normalized_email)
        await update.message.reply_text(
            format_user_home_text(user),
            parse_mode=ParseMode.HTML,
            reply_markup=build_user_home_keyboard(token),
            disable_web_page_preview=True,
        )
    except Exception as exc:
        logger.exception("Ошибка загрузки карточки пользователя email=%s", normalized_email)
        await send_pretty_message(
            update,
            "🚨 <b>Ошибка загрузки пользователя</b>\n"
            f"<code>{html.escape(str(exc))}</code>",
        )


async def handle_user_callback(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
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

    parts = query.data.split(":")
    # Expected:
    # user:home:<token>
    # user:about:<token>
    # user:files:<token>
    # user:tracks:<token>:<page>
    # user:playlists:<token>
    # user:playlist_items:<token>:<page>
    if len(parts) < 3:
        await query.answer("Некорректная кнопка", show_alert=True)
        return

    _, action, token = parts[0], parts[1], parts[2]
    email = resolve_user_email_by_token(context.application, token)
    if not email:
        await query.answer("Сессия устарела. Выполните /user <email>", show_alert=True)
        return

    try:
        user = await get_user_by_email(email)
        if user is None:
            await query.edit_message_text(
                text=(
                    "🔎 <b>Пользователь не найден</b>\n"
                    f"Email: <code>{html.escape(email)}</code>"
                ),
                parse_mode=ParseMode.HTML,
                disable_web_page_preview=True,
            )
            await query.answer()
            return

        user_id = int(user["id"])

        if action == "home":
            await query.edit_message_text(
                text=format_user_home_text(user),
                parse_mode=ParseMode.HTML,
                reply_markup=build_user_home_keyboard(token),
                disable_web_page_preview=True,
            )
            await query.answer()
            return

        if action == "about":
            summary = await get_user_storage_summary(user_id)
            await query.edit_message_text(
                text=format_user_about_text(user, summary),
                parse_mode=ParseMode.HTML,
                reply_markup=build_user_about_keyboard(token),
                disable_web_page_preview=True,
            )
            await query.answer()
            return

        if action == "files":
            summary = await get_user_storage_summary(user_id)
            await query.edit_message_text(
                text=format_user_files_text(summary),
                parse_mode=ParseMode.HTML,
                reply_markup=build_user_files_keyboard(token),
                disable_web_page_preview=True,
            )
            await query.answer()
            return

        if action == "tracks":
            page = 1
            if len(parts) >= 4:
                try:
                    page = max(int(parts[3]), 1)
                except ValueError:
                    page = 1
            rows, total_tracks = await get_user_tracks(user_id, page, USER_TRACKS_PAGE_SIZE)
            total_pages = max((total_tracks + USER_TRACKS_PAGE_SIZE - 1) // USER_TRACKS_PAGE_SIZE, 1)
            page = min(page, total_pages)
            if page != 1 and not rows:
                rows, total_tracks = await get_user_tracks(user_id, page, USER_TRACKS_PAGE_SIZE)
            await query.edit_message_text(
                text=format_user_tracks_page_text(rows, page, total_pages, total_tracks),
                parse_mode=ParseMode.HTML,
                reply_markup=build_user_list_pagination_keyboard(token, "tracks", page, total_pages),
                disable_web_page_preview=True,
            )
            await query.answer()
            return

        if action == "playlists":
            total_rows, total_playlists = await get_user_playlists(user_id, 1, 1)
            _ = total_rows
            await query.edit_message_text(
                text=(
                    "📚 <b>Плейлисты пользователя</b>\n\n"
                    f"Всего плейлистов: <b>{total_playlists}</b>\n\n"
                    "Нажмите <b>Список</b>, чтобы открыть плейлисты по 5 шт."
                ),
                parse_mode=ParseMode.HTML,
                reply_markup=build_user_playlists_keyboard(token),
                disable_web_page_preview=True,
            )
            await query.answer()
            return

        if action == "playlist_items":
            page = 1
            if len(parts) >= 4:
                try:
                    page = max(int(parts[3]), 1)
                except ValueError:
                    page = 1
            rows, total_playlists = await get_user_playlists(user_id, page, USER_PLAYLISTS_PAGE_SIZE)
            total_pages = max((total_playlists + USER_PLAYLISTS_PAGE_SIZE - 1) // USER_PLAYLISTS_PAGE_SIZE, 1)
            page = min(page, total_pages)
            if page != 1 and not rows:
                rows, total_playlists = await get_user_playlists(user_id, page, USER_PLAYLISTS_PAGE_SIZE)
            await query.edit_message_text(
                text=format_user_playlists_page_text(rows, page, total_pages, total_playlists),
                parse_mode=ParseMode.HTML,
                reply_markup=build_user_list_pagination_keyboard(token, "playlists", page, total_pages),
                disable_web_page_preview=True,
            )
            await query.answer()
            return

        await query.answer("Неизвестное действие", show_alert=True)
    except Exception as exc:
        logger.exception("Ошибка user callback: %s", query.data)
        await query.answer("Ошибка загрузки", show_alert=True)
        if query.message is not None:
            await query.message.reply_text(
                "🚨 <b>Ошибка пользовательской сводки</b>\n"
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


async def cmd_user(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    if update.message is None:
        return
    if not context.args:
        await send_pretty_message(
            update,
            "Использование: <code>/user user@example.com</code>",
        )
        return
    email = " ".join(context.args).strip()
    await send_user_home(update, context, email)


async def cmd_snapshot(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    await send_snapshot(update, context)


async def cmd_all(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    await send_monitoring(update, context, "all", "/api/monitor/all")


async def cmd_deploy(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    chat = update.effective_chat
    if update.message is None or chat is None:
        return

    if not is_chat_allowed(chat.id):
        await send_pretty_message(update, "⛔ <b>Доступ запрещен для этого чата</b>")
        return

    if not is_deploy_chat_allowed(chat.id):
        await send_pretty_message(
            update,
            "⛔ <b>Деплой запрещен для этого чата</b>",
        )
        return

    register_runtime_chat(context.application, chat.id)

    if not DEPLOY_ENABLED:
        await send_pretty_message(update, "⚠️ <b>Деплой отключен (DEPLOY_ENABLED=false)</b>")
        return

    if not DEPLOY_REPO_URL:
        await send_pretty_message(
            update,
            "🚨 <b>DEPLOY_REPO_URL не задан</b>\n"
            "Задайте URL репозитория в .env бота.",
        )
        return

    branch = DEPLOY_BRANCH
    if context.args:
        candidate = context.args[0].strip()
        if candidate:
            branch = candidate

    lock = context.application.bot_data.setdefault("deploy_lock", asyncio.Lock())
    if lock.locked():
        await send_pretty_message(update, "⏳ <b>Деплой уже выполняется</b>")
        return

    await send_pretty_message(
        update,
        "🚀 <b>Запускаю деплой</b>\n"
        f"• branch: <code>{html.escape(branch)}</code>\n"
        f"• app_dir: <code>{html.escape(DEPLOY_APP_DIR)}</code>\n"
        f"• script: <code>{html.escape(DEPLOY_SCRIPT_PATH)}</code>",
    )

    async with lock:
        try:
            return_code, stdout, stderr = await run_deploy_script(branch)
            stdout_short = truncate_output(stdout)
            stderr_short = truncate_output(stderr)

            if return_code == 0:
                text = (
                    "✅ <b>Деплой завершен успешно</b>\n"
                    f"• branch: <code>{html.escape(branch)}</code>\n"
                )
                if stdout_short:
                    text += f"\n<b>stdout</b>\n<pre>{html.escape(stdout_short)}</pre>"
                if stderr_short:
                    text += f"\n<b>stderr</b>\n<pre>{html.escape(stderr_short)}</pre>"
                await send_pretty_message(update, text)
                return

            text = (
                "🚨 <b>Деплой завершился с ошибкой</b>\n"
                f"• code: <code>{return_code}</code>\n"
                f"• branch: <code>{html.escape(branch)}</code>\n"
            )
            if stdout_short:
                text += f"\n<b>stdout</b>\n<pre>{html.escape(stdout_short)}</pre>"
            if stderr_short:
                text += f"\n<b>stderr</b>\n<pre>{html.escape(stderr_short)}</pre>"
            await send_pretty_message(update, text)
        except Exception as exc:
            logger.exception("Ошибка deploy-команды")
            await send_pretty_message(
                update,
                "🚨 <b>Ошибка запуска деплоя</b>\n"
                f"<code>{html.escape(str(exc))}</code>",
            )


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

    if text == MENU_BUTTON_DEPLOY:
        await cmd_deploy(update, context)
        return

    if looks_like_email(text):
        await send_user_home(update, context, text)
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
    app.add_handler(CommandHandler("user", cmd_user))
    app.add_handler(CommandHandler("snapshot", cmd_snapshot))
    app.add_handler(CommandHandler("all", cmd_all))
    app.add_handler(CommandHandler("deploy", cmd_deploy))
    app.add_handler(CallbackQueryHandler(handle_users_page_callback, pattern=r"^users_page:\d+$"))
    app.add_handler(CallbackQueryHandler(handle_user_callback, pattern=r"^user:"))
    app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, handle_menu_buttons))

    logger.info("Запуск CloudTune monitoring bot")
    app.run_polling(allowed_updates=Update.ALL_TYPES)


if __name__ == "__main__":
    main()
