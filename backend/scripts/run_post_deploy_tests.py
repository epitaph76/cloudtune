#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import sys
import tempfile
import time
import uuid
import wave
from dataclasses import dataclass
from typing import Any
from urllib import error, parse, request


@dataclass
class Config:
    api_base_url: str
    main_landing_url: str
    resume_landing_url: str
    timeout_seconds: int
    health_path: str
    poll_attempts: int
    poll_sleep_seconds: float


class TestFailure(RuntimeError):
    pass


def env_bool(name: str, default: bool) -> bool:
    raw = os.getenv(name, "")
    if not raw:
        return default
    return raw.strip().lower() in {"1", "true", "yes", "on"}


def log_step(message: str) -> None:
    print(f"[STEP] {message}")


def log_ok(message: str) -> None:
    print(f"[OK] {message}")


def fail(message: str) -> None:
    raise TestFailure(message)


def read_json(resp_bytes: bytes, context: str) -> dict[str, Any]:
    try:
        payload = json.loads(resp_bytes.decode("utf-8", errors="replace"))
    except Exception as exc:
        fail(f"{context}: invalid JSON: {exc}")
    if not isinstance(payload, dict):
        fail(f"{context}: JSON is not an object")
    return payload


def http_request(
    method: str,
    url: str,
    *,
    headers: dict[str, str] | None = None,
    data: bytes | None = None,
    timeout: int = 20,
) -> tuple[int, bytes, dict[str, str]]:
    req = request.Request(url=url, method=method, data=data, headers=headers or {})
    try:
        with request.urlopen(req, timeout=timeout) as resp:
            return int(resp.status), resp.read(), dict(resp.headers)
    except error.HTTPError as exc:
        return int(exc.code), exc.read(), dict(exc.headers)
    except Exception as exc:
        fail(f"HTTP {method} {url} failed: {exc}")


def json_request(
    method: str,
    url: str,
    payload: dict[str, Any],
    *,
    headers: dict[str, str] | None = None,
    timeout: int = 20,
) -> tuple[int, dict[str, Any]]:
    merged_headers = {"Content-Type": "application/json"}
    if headers:
        merged_headers.update(headers)
    status, body, _ = http_request(
        method,
        url,
        headers=merged_headers,
        data=json.dumps(payload).encode("utf-8"),
        timeout=timeout,
    )
    return status, read_json(body, f"{method} {url}")


def multipart_file_request(
    url: str,
    *,
    file_path: str,
    field_name: str,
    file_name: str,
    headers: dict[str, str] | None = None,
    timeout: int = 60,
) -> tuple[int, dict[str, Any]]:
    boundary = f"----cloudtune-{uuid.uuid4().hex}"
    with open(file_path, "rb") as f:
        file_bytes = f.read()

    parts = []
    parts.append(f"--{boundary}\r\n".encode("utf-8"))
    parts.append(
        (
            f'Content-Disposition: form-data; name="{field_name}"; filename="{file_name}"\r\n'
            f"Content-Type: audio/wav\r\n\r\n"
        ).encode("utf-8")
    )
    parts.append(file_bytes)
    parts.append(b"\r\n")
    parts.append(f"--{boundary}--\r\n".encode("utf-8"))
    body = b"".join(parts)

    merged_headers = {
        "Content-Type": f"multipart/form-data; boundary={boundary}",
        "Content-Length": str(len(body)),
    }
    if headers:
        merged_headers.update(headers)

    status, resp_body, _ = http_request(
        "POST",
        url,
        headers=merged_headers,
        data=body,
        timeout=timeout,
    )
    return status, read_json(resp_body, f"POST {url}")


def ensure_status(status: int, expected: int, context: str, payload: dict[str, Any] | None = None) -> None:
    if status != expected:
        detail = ""
        if payload is not None:
            detail = f" payload={json.dumps(payload, ensure_ascii=False)}"
        fail(f"{context}: expected HTTP {expected}, got {status}.{detail}")


def token_headers(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


def create_test_wav(path: str) -> None:
    with wave.open(path, "wb") as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(16000)
        # 0.25s of silence
        wav.writeframes(b"\x00\x00" * 4000)


def expect_dict_key(payload: dict[str, Any], key: str, context: str) -> Any:
    if key not in payload:
        fail(f"{context}: missing key '{key}' in payload={json.dumps(payload, ensure_ascii=False)}")
    return payload[key]


def poll_health(cfg: Config) -> None:
    health_url = f"{cfg.api_base_url}{cfg.health_path}"
    for i in range(cfg.poll_attempts):
        status, body, _ = http_request("GET", health_url, timeout=cfg.timeout_seconds)
        if status == 200:
            log_ok(f"health check is up (attempt {i + 1}/{cfg.poll_attempts})")
            return
        time.sleep(cfg.poll_sleep_seconds)
    fail(f"health check did not become healthy: {health_url}")


def run() -> None:
    cfg = Config(
        api_base_url=os.getenv("POST_DEPLOY_TEST_API_BASE_URL", "http://127.0.0.1:8080").rstrip("/"),
        main_landing_url=os.getenv("POST_DEPLOY_TEST_MAIN_LANDING_URL", "https://api-mp3-player.ru").rstrip("/"),
        resume_landing_url=os.getenv(
            "POST_DEPLOY_TEST_RESUME_LANDING_URL",
            "https://resume.api-mp3-player.ru",
        ).rstrip("/"),
        timeout_seconds=int(os.getenv("POST_DEPLOY_TEST_TIMEOUT_SECONDS", "20")),
        health_path=os.getenv("POST_DEPLOY_TEST_HEALTH_PATH", "/health").strip() or "/health",
        poll_attempts=max(int(os.getenv("POST_DEPLOY_TEST_POLL_ATTEMPTS", "20")), 1),
        poll_sleep_seconds=max(float(os.getenv("POST_DEPLOY_TEST_POLL_SLEEP_SECONDS", "2")), 0.2),
    )

    log_step("poll health endpoint until backend is ready")
    poll_health(cfg)

    log_step("check /api/status")
    status, raw, _ = http_request("GET", f"{cfg.api_base_url}/api/status", timeout=cfg.timeout_seconds)
    ensure_status(status, 200, "GET /api/status")
    status_payload = read_json(raw, "GET /api/status")
    if not isinstance(status_payload.get("status"), str):
        fail(f"GET /api/status: missing textual 'status' field: {json.dumps(status_payload, ensure_ascii=False)}")
    log_ok("status endpoint responds with valid payload")

    unique = uuid.uuid4().hex[:10]
    email = f"deploy.check.{unique}@example.com"
    username = f"deploy_check_{unique}"
    password = "DeployCheck_123!"

    log_step("register a fresh test user")
    status, payload = json_request(
        "POST",
        f"{cfg.api_base_url}/auth/register",
        {"email": email, "username": username, "password": password},
        timeout=cfg.timeout_seconds,
    )
    ensure_status(status, 200, "POST /auth/register", payload)
    reg_token = expect_dict_key(payload, "token", "POST /auth/register")
    if not isinstance(reg_token, str) or not reg_token:
        fail("POST /auth/register: token is empty or invalid")
    log_ok("register flow works")

    log_step("login with created credentials")
    status, payload = json_request(
        "POST",
        f"{cfg.api_base_url}/auth/login",
        {"email": email, "password": password},
        timeout=cfg.timeout_seconds,
    )
    ensure_status(status, 200, "POST /auth/login", payload)
    token = expect_dict_key(payload, "token", "POST /auth/login")
    if not isinstance(token, str) or not token:
        fail("POST /auth/login: token is empty or invalid")
    log_ok("login flow works")

    log_step("check protected storage endpoint")
    status, raw, _ = http_request(
        "GET",
        f"{cfg.api_base_url}/api/storage/usage",
        headers=token_headers(token),
        timeout=cfg.timeout_seconds,
    )
    ensure_status(status, 200, "GET /api/storage/usage")
    storage_payload = read_json(raw, "GET /api/storage/usage")
    for k in ("used_bytes", "quota_bytes", "remaining_bytes"):
        if k not in storage_payload:
            fail(f"GET /api/storage/usage: missing key '{k}'")
    log_ok("storage endpoint works")

    with tempfile.TemporaryDirectory(prefix="cloudtune-postdeploy-") as temp_dir:
        wav_path = os.path.join(temp_dir, "test.wav")
        create_test_wav(wav_path)

        log_step("upload a WAV file")
        status, payload = multipart_file_request(
            f"{cfg.api_base_url}/api/songs/upload",
            file_path=wav_path,
            field_name="file",
            file_name="test.wav",
            headers=token_headers(token),
            timeout=max(cfg.timeout_seconds, 60),
        )
        ensure_status(status, 200, "POST /api/songs/upload", payload)
        song_id_raw = expect_dict_key(payload, "song_id", "POST /api/songs/upload")
        try:
            song_id = int(song_id_raw)
        except Exception:
            fail(f"POST /api/songs/upload: invalid song_id={song_id_raw}")
        log_ok(f"upload works, song_id={song_id}")

        log_step("validate library contains uploaded song")
        status, raw, _ = http_request(
            "GET",
            f"{cfg.api_base_url}/api/songs/library",
            headers=token_headers(token),
            timeout=cfg.timeout_seconds,
        )
        ensure_status(status, 200, "GET /api/songs/library")
        lib_payload = read_json(raw, "GET /api/songs/library")
        songs = lib_payload.get("songs")
        if not isinstance(songs, list):
            fail("GET /api/songs/library: 'songs' is not a list")
        if not any(str(item.get("id")) == str(song_id) for item in songs if isinstance(item, dict)):
            fail("GET /api/songs/library: uploaded song not found")
        log_ok("library contains uploaded song")

        log_step("fetch uploaded song details")
        status, raw, _ = http_request(
            "GET",
            f"{cfg.api_base_url}/api/songs/{song_id}",
            headers=token_headers(token),
            timeout=cfg.timeout_seconds,
        )
        ensure_status(status, 200, "GET /api/songs/:id")
        song_payload = read_json(raw, "GET /api/songs/:id")
        if "song" not in song_payload:
            fail("GET /api/songs/:id: missing 'song'")
        log_ok("song details endpoint works")

        log_step("create playlist")
        playlist_name = f"Deploy Test {unique}"
        status, payload = json_request(
            "POST",
            f"{cfg.api_base_url}/api/playlists",
            {"name": playlist_name},
            headers=token_headers(token),
            timeout=cfg.timeout_seconds,
        )
        ensure_status(status, 200, "POST /api/playlists", payload)
        playlist_id = int(expect_dict_key(payload, "playlist_id", "POST /api/playlists"))
        log_ok(f"playlist created, playlist_id={playlist_id}")

        log_step("add song to playlist")
        status, raw, _ = http_request(
            "POST",
            f"{cfg.api_base_url}/api/playlists/{playlist_id}/songs/{song_id}",
            headers=token_headers(token),
            timeout=cfg.timeout_seconds,
        )
        ensure_status(status, 200, "POST /api/playlists/:playlist_id/songs/:song_id")
        log_ok("song added to playlist")

        log_step("validate playlist songs endpoint")
        status, raw, _ = http_request(
            "GET",
            f"{cfg.api_base_url}/api/playlists/{playlist_id}/songs",
            headers=token_headers(token),
            timeout=cfg.timeout_seconds,
        )
        ensure_status(status, 200, "GET /api/playlists/:playlist_id/songs")
        pl_payload = read_json(raw, "GET /api/playlists/:playlist_id/songs")
        pl_songs = pl_payload.get("songs")
        if not isinstance(pl_songs, list):
            fail("GET /api/playlists/:playlist_id/songs: 'songs' is not a list")
        if not any(str(item.get("id")) == str(song_id) for item in pl_songs if isinstance(item, dict)):
            fail("GET /api/playlists/:playlist_id/songs: uploaded song not found in playlist")
        log_ok("playlist contains uploaded song")

        log_step("download uploaded song")
        status, body, headers = http_request(
            "GET",
            f"{cfg.api_base_url}/api/songs/download/{song_id}",
            headers=token_headers(token),
            timeout=max(cfg.timeout_seconds, 60),
        )
        ensure_status(status, 200, "GET /api/songs/download/:id")
        if len(body) < 128:
            fail("GET /api/songs/download/:id: response body too small")
        content_type = headers.get("Content-Type", "")
        if "audio" not in content_type and "octet-stream" not in content_type:
            fail(f"GET /api/songs/download/:id: unexpected content-type '{content_type}'")
        log_ok("download endpoint works")

        log_step("delete uploaded song")
        status, raw, _ = http_request(
            "DELETE",
            f"{cfg.api_base_url}/api/songs/{song_id}",
            headers=token_headers(token),
            timeout=cfg.timeout_seconds,
        )
        ensure_status(status, 200, "DELETE /api/songs/:id")
        log_ok("song deletion works")

        log_step("verify deleted song is inaccessible")
        status, _, _ = http_request(
            "GET",
            f"{cfg.api_base_url}/api/songs/{song_id}",
            headers=token_headers(token),
            timeout=cfg.timeout_seconds,
        )
        if status not in {403, 404}:
            fail(f"GET deleted /api/songs/:id: expected 403/404, got {status}")
        log_ok("deleted song is not accessible")

    log_step("check main landing URL")
    status, _, _ = http_request("GET", cfg.main_landing_url, timeout=cfg.timeout_seconds)
    ensure_status(status, 200, f"GET {cfg.main_landing_url}")
    log_ok("main landing is reachable")

    log_step("check resume landing URL")
    status, _, _ = http_request("GET", cfg.resume_landing_url, timeout=cfg.timeout_seconds)
    ensure_status(status, 200, f"GET {cfg.resume_landing_url}")
    log_ok("resume landing is reachable")

    print("POST_DEPLOY_TESTS_PASSED")


if __name__ == "__main__":
    try:
        run()
    except TestFailure as exc:
        print(f"POST_DEPLOY_TESTS_FAILED: {exc}")
        sys.exit(1)
    except Exception as exc:  # pragma: no cover
        print(f"POST_DEPLOY_TESTS_FAILED_UNEXPECTED: {exc}")
        sys.exit(1)
