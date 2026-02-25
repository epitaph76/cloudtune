#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   REPO_URL=https://github.com/<user>/<repo>.git \
#   BRANCH=master \
#   APP_DIR=/opt/cloudtune \
#   DEPLOY_MAIN_LANDING=true \
#   DEPLOY_RESUME_LANDING=true \
#   RESTART_MONITORING_BOT=true \
#   ./backend/scripts/deploy-from-github.sh

REPO_URL="${REPO_URL:-}"
BRANCH="${BRANCH:-master}"
APP_DIR="${APP_DIR:-/opt/cloudtune}"
DEPLOY_MAIN_LANDING="${DEPLOY_MAIN_LANDING:-true}"
DEPLOY_RESUME_LANDING="${DEPLOY_RESUME_LANDING:-true}"
MAIN_LANDING_SRC="${MAIN_LANDING_SRC:-${APP_DIR}/landing}"
MAIN_LANDING_DST="${MAIN_LANDING_DST:-/var/www/api-mp3-player.ru/html}"
RESUME_LANDING_SRC="${RESUME_LANDING_SRC:-${APP_DIR}/landing/resume}"
RESUME_LANDING_DST="${RESUME_LANDING_DST:-/var/www/resume.api-mp3-player.ru/html}"
DEPLOY_ARTIFACTS_TO_MAIN="${DEPLOY_ARTIFACTS_TO_MAIN:-true}"
RESTART_MONITORING_BOT="${RESTART_MONITORING_BOT:-true}"
MONITORING_SERVICE_NAME="${MONITORING_SERVICE_NAME:-cloudtune-monitoring-bot}"
MONITORING_RESTART_DELAY_SECONDS="${MONITORING_RESTART_DELAY_SECONDS:-3}"

is_true() {
  local value="${1:-}"
  case "${value,,}" in
    1|true|yes|on) return 0 ;;
    *) return 1 ;;
  esac
}

sync_dir() {
  local src="$1"
  local dst="$2"
  mkdir -p "${dst}"
  if command -v rsync >/dev/null 2>&1; then
    rsync -a --delete "${src}/" "${dst}/"
  else
    rm -rf "${dst:?}/"*
    cp -a "${src}/." "${dst}/"
  fi
}

if [[ -z "${REPO_URL}" ]]; then
  echo "REPO_URL is required"
  exit 1
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "Docker is not installed"
  exit 1
fi

if docker compose version >/dev/null 2>&1; then
  COMPOSE_CMD="docker compose"
elif command -v docker-compose >/dev/null 2>&1; then
  COMPOSE_CMD="docker-compose"
else
  echo "Docker Compose is not installed"
  exit 1
fi

if [[ ! -d "${APP_DIR}/.git" ]]; then
  git clone --branch "${BRANCH}" "${REPO_URL}" "${APP_DIR}"
else
  git -C "${APP_DIR}" fetch --all
  git -C "${APP_DIR}" checkout "${BRANCH}"
  git -C "${APP_DIR}" pull --ff-only origin "${BRANCH}"
fi

cd "${APP_DIR}/backend"

if [[ ! -f ".env.prod" ]]; then
  if [[ -f ".env.prod.example" ]]; then
    cp .env.prod.example .env.prod
  else
    echo ".env.prod not found"
    exit 1
  fi
fi

${COMPOSE_CMD} --env-file .env.prod -f docker-compose.prod.yml up -d --build

if is_true "${DEPLOY_MAIN_LANDING}"; then
  if [[ ! -d "${MAIN_LANDING_SRC}" ]]; then
    echo "Main landing source not found: ${MAIN_LANDING_SRC}"
    exit 1
  fi
  sync_dir "${MAIN_LANDING_SRC}" "${MAIN_LANDING_DST}"
  if is_true "${DEPLOY_ARTIFACTS_TO_MAIN}"; then
    [[ -f "${APP_DIR}/cloudtune_win.zip" ]] && cp -f "${APP_DIR}/cloudtune_win.zip" "${MAIN_LANDING_DST}/cloudtune_win.zip"
    [[ -f "${APP_DIR}/cloudtune_andr.apk" ]] && cp -f "${APP_DIR}/cloudtune_andr.apk" "${MAIN_LANDING_DST}/cloudtune_andr.apk"
  fi
fi

if is_true "${DEPLOY_RESUME_LANDING}"; then
  if [[ ! -d "${RESUME_LANDING_SRC}" ]]; then
    echo "Resume landing source not found: ${RESUME_LANDING_SRC}"
    exit 1
  fi
  sync_dir "${RESUME_LANDING_SRC}" "${RESUME_LANDING_DST}"
fi

if command -v chown >/dev/null 2>&1; then
  [[ -d "${MAIN_LANDING_DST}" ]] && chown -R www-data:www-data "${MAIN_LANDING_DST}" || true
  [[ -d "${RESUME_LANDING_DST}" ]] && chown -R www-data:www-data "${RESUME_LANDING_DST}" || true
fi

if is_true "${RESTART_MONITORING_BOT}"; then
  if command -v systemctl >/dev/null 2>&1; then
    (
      sleep "${MONITORING_RESTART_DELAY_SECONDS}"
      systemctl restart "${MONITORING_SERVICE_NAME}"
    ) >/dev/null 2>&1 &
  else
    echo "systemctl is unavailable, monitoring bot restart skipped."
  fi
fi

echo "Deploy completed: backend + landing + monitoring restart."
