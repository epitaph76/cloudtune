#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   REPO_URL=https://github.com/<user>/<repo>.git \
#   BRANCH=master \
#   APP_DIR=/opt/cloudtune \
#   ./backend/scripts/deploy-from-github.sh

REPO_URL="${REPO_URL:-}"
BRANCH="${BRANCH:-master}"
APP_DIR="${APP_DIR:-/opt/cloudtune}"

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

echo "Deploy completed."
