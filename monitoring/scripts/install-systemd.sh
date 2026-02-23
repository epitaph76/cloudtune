#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   APP_DIR=/opt/cloudtune ./monitoring/scripts/install-systemd.sh

APP_DIR="${APP_DIR:-/opt/cloudtune}"
BOT_DIR="${APP_DIR}/monitoring"
SERVICE_NAME="cloudtune-monitoring-bot.service"

if [[ ! -f "${BOT_DIR}/src/bot.py" ]]; then
  echo "bot.py not found in ${BOT_DIR}/src"
  exit 1
fi

if [[ ! -f "${BOT_DIR}/requirements.txt" ]]; then
  echo "requirements.txt not found in ${BOT_DIR}"
  exit 1
fi

if [[ ! -f "${BOT_DIR}/.env" ]]; then
  echo ".env not found in ${BOT_DIR}. Create it before install."
  exit 1
fi

python3 -m venv "${BOT_DIR}/.venv"
"${BOT_DIR}/.venv/bin/pip" install --upgrade pip
"${BOT_DIR}/.venv/bin/pip" install -r "${BOT_DIR}/requirements.txt"

install -m 644 "${BOT_DIR}/systemd/${SERVICE_NAME}" "/etc/systemd/system/${SERVICE_NAME}"

systemctl daemon-reload
systemctl enable --now "${SERVICE_NAME}"
systemctl status "${SERVICE_NAME}" --no-pager

echo "Systemd service installed and started: ${SERVICE_NAME}"
