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
RUN_POST_DEPLOY_TESTS="${RUN_POST_DEPLOY_TESTS:-true}"
POST_DEPLOY_TEST_SCRIPT="${POST_DEPLOY_TEST_SCRIPT:-${APP_DIR}/backend/scripts/run_post_deploy_tests.py}"
POST_DEPLOY_TEST_API_BASE_URL="${POST_DEPLOY_TEST_API_BASE_URL:-http://127.0.0.1:8080}"
POST_DEPLOY_TEST_MAIN_LANDING_URL="${POST_DEPLOY_TEST_MAIN_LANDING_URL:-https://api-mp3-player.ru}"
POST_DEPLOY_TEST_RESUME_LANDING_URL="${POST_DEPLOY_TEST_RESUME_LANDING_URL:-https://resume.api-mp3-player.ru}"
POST_DEPLOY_TEST_TIMEOUT_SECONDS="${POST_DEPLOY_TEST_TIMEOUT_SECONDS:-20}"
ROLLBACK_ON_TEST_FAILURE="${ROLLBACK_ON_TEST_FAILURE:-true}"
ALLOW_DEPLOY_AS_ROOT="${ALLOW_DEPLOY_AS_ROOT:-false}"
DEPLOY_AUTOSTASH_LOCAL_CHANGES="${DEPLOY_AUTOSTASH_LOCAL_CHANGES:-true}"
DOCKER_PRUNE_AFTER_DEPLOY="${DOCKER_PRUNE_AFTER_DEPLOY:-true}"
DOCKER_PRUNE_UNTIL_HOURS="${DOCKER_PRUNE_UNTIL_HOURS:-240}"
DOCKER_PRUNE_VOLUMES="${DOCKER_PRUNE_VOLUMES:-false}"
JOURNAL_VACUUM_AFTER_DEPLOY="${JOURNAL_VACUUM_AFTER_DEPLOY:-false}"
JOURNAL_MAX_SIZE="${JOURNAL_MAX_SIZE:-500M}"
TRUNCATE_BTMP_AFTER_DEPLOY="${TRUNCATE_BTMP_AFTER_DEPLOY:-false}"
LOCAL_CHANGES_STASHED=false
LOCAL_STASH_TAG=""

is_true() {
  local value="${1:-}"
  case "${value,,}" in
    1|true|yes|on) return 0 ;;
    *) return 1 ;;
  esac
}

enforce_root_policy() {
  if [[ "$(id -u)" -eq 0 ]] && ! is_true "${ALLOW_DEPLOY_AS_ROOT}"; then
    echo "Refusing to deploy as root (ALLOW_DEPLOY_AS_ROOT=false)."
    echo "Use a dedicated deploy user with least privileges."
    exit 1
  fi
}

prepare_git_worktree() {
  if [[ -z "$(git -C "${APP_DIR}" status --porcelain)" ]]; then
    return 0
  fi

  if ! is_true "${DEPLOY_AUTOSTASH_LOCAL_CHANGES}"; then
    echo "Working tree contains local changes and DEPLOY_AUTOSTASH_LOCAL_CHANGES=false."
    echo "Commit or stash changes manually before deploy."
    git -C "${APP_DIR}" status --short || true
    exit 1
  fi

  LOCAL_STASH_TAG="deploy-autostash-$(date -u +%Y%m%dT%H%M%SZ)"
  echo "Detected local git changes in ${APP_DIR}. Creating stash: ${LOCAL_STASH_TAG}"
  git -C "${APP_DIR}" stash push --include-untracked --message "${LOCAL_STASH_TAG}" >/dev/null
  LOCAL_CHANGES_STASHED=true
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

deploy_backend() {
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
}

deploy_landing_assets() {
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
}

schedule_monitoring_restart() {
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
}

run_post_deploy_tests() {
  if ! is_true "${RUN_POST_DEPLOY_TESTS}"; then
    echo "Post-deploy tests are disabled."
    return 0
  fi

  if [[ ! -f "${POST_DEPLOY_TEST_SCRIPT}" ]]; then
    echo "Post-deploy test script not found: ${POST_DEPLOY_TEST_SCRIPT}"
    return 1
  fi

  if ! command -v python3 >/dev/null 2>&1; then
    echo "python3 is required for post-deploy tests"
    return 1
  fi

  echo "Running post-deploy smoke checks..."
  POST_DEPLOY_TEST_API_BASE_URL="${POST_DEPLOY_TEST_API_BASE_URL}" \
  POST_DEPLOY_TEST_MAIN_LANDING_URL="${POST_DEPLOY_TEST_MAIN_LANDING_URL}" \
  POST_DEPLOY_TEST_RESUME_LANDING_URL="${POST_DEPLOY_TEST_RESUME_LANDING_URL}" \
  POST_DEPLOY_TEST_TIMEOUT_SECONDS="${POST_DEPLOY_TEST_TIMEOUT_SECONDS}" \
  python3 "${POST_DEPLOY_TEST_SCRIPT}"
  echo "Post-deploy smoke checks passed."
}

cleanup_host_storage() {
  echo "Running post-deploy cleanup..."

  if is_true "${DOCKER_PRUNE_AFTER_DEPLOY}"; then
    docker image prune -af --filter "until=${DOCKER_PRUNE_UNTIL_HOURS}h" || true
    docker builder prune -af --filter "until=${DOCKER_PRUNE_UNTIL_HOURS}h" || true
    docker network prune -f || true

    if is_true "${DOCKER_PRUNE_VOLUMES}"; then
      docker volume prune -f || true
    fi
  fi

  if is_true "${JOURNAL_VACUUM_AFTER_DEPLOY}" && command -v journalctl >/dev/null 2>&1; then
    journalctl --vacuum-size="${JOURNAL_MAX_SIZE}" || true
  fi

  if is_true "${TRUNCATE_BTMP_AFTER_DEPLOY}"; then
    truncate -s 0 /var/log/btmp || true
  fi
}

if [[ -z "${REPO_URL}" ]]; then
  echo "REPO_URL is required"
  exit 1
fi

enforce_root_policy

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
  PREVIOUS_COMMIT="$(git -C "${APP_DIR}" rev-parse HEAD)"
  prepare_git_worktree
  git -C "${APP_DIR}" fetch --all
  git -C "${APP_DIR}" checkout "${BRANCH}"
  git -C "${APP_DIR}" pull --ff-only origin "${BRANCH}"
fi

CURRENT_COMMIT="$(git -C "${APP_DIR}" rev-parse HEAD)"
echo "Deploy target commit: ${CURRENT_COMMIT}"
if ${LOCAL_CHANGES_STASHED}; then
  echo "Local changes were stashed before deploy: ${LOCAL_STASH_TAG}"
fi

deploy_backend
deploy_landing_assets

if ! run_post_deploy_tests; then
  echo "Post-deploy tests failed."
  if is_true "${ROLLBACK_ON_TEST_FAILURE}" && [[ -n "${PREVIOUS_COMMIT:-}" ]] && [[ "${PREVIOUS_COMMIT}" != "${CURRENT_COMMIT}" ]]; then
    echo "Rolling back to previous commit: ${PREVIOUS_COMMIT}"
    git -C "${APP_DIR}" reset --hard "${PREVIOUS_COMMIT}"
    deploy_backend
    deploy_landing_assets
    cleanup_host_storage
    schedule_monitoring_restart
    echo "Rollback completed. Failure reason is above in test output."
  else
    cleanup_host_storage
    schedule_monitoring_restart
    echo "Rollback skipped."
  fi
  exit 1
fi

cleanup_host_storage
schedule_monitoring_restart
echo "Deploy completed: backend + landing + tests + monitoring restart."
