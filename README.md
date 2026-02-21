# 🎵 CloudTune

![Go](https://img.shields.io/badge/Go-1.24-00ADD8?logo=go&logoColor=white)
![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter&logoColor=white)
![Dart](https://img.shields.io/badge/Dart-3.11+-0175C2?logo=dart&logoColor=white)
![Python](https://img.shields.io/badge/Python-3.12-3776AB?logo=python&logoColor=white)
![PostgreSQL](https://img.shields.io/badge/PostgreSQL-15-4169E1?logo=postgresql&logoColor=white)
![Docker](https://img.shields.io/badge/Docker-Compose-2496ED?logo=docker&logoColor=white)

CloudTune — fullstack-сервис для музыки с локальной библиотекой, облачным хранением и Telegram-мониторингом сервера.

## ✨ Что есть в проекте

- 🔐 Авторизация пользователей (`register/login`, JWT)
- ☁️ Загрузка и скачивание треков из облака
- 📚 Локальная библиотека с сохранением между запусками
- 🗂️ Локальные и облачные плейлисты
- 🎧 Фоновый плеер (`audio_service` + `just_audio`)
- 🤖 Telegram-бот мониторинга backend

## 🧩 Модули репозитория

- `backend/` — API на Go + PostgreSQL
- `frontend/cloudtune_flutter_app/` — мобильный клиент на Flutter
- `monitoring/` — Python Telegram-бот для мониторинга

## 🗺️ Схема системы

```mermaid
flowchart LR
    A[📱 Flutter приложение] -->|REST API| B[🛠️ CloudTune Backend]
    B -->|SQL| C[(🐘 PostgreSQL)]
    B -->|Файлы| D[(💾 uploads)]
    E[🤖 Monitoring Bot] -->|Monitoring API| B
    E -->|Уведомления и команды| F[📲 Telegram]
```

## 🚀 Быстрый старт

1. Запуск backend:

```bash
cd backend
docker compose --env-file .env.prod -f docker-compose.prod.yml up -d --build
```

2. Запуск Flutter приложения:

```bash
cd frontend/cloudtune_flutter_app
flutter pub get
flutter run --dart-define=API_BASE_URL=https://api.your-domain.com
```

3. Запуск monitoring-бота:

```bash
cd monitoring
python -m venv .venv
.venv\Scripts\activate
pip install -r requirements.txt
python src/bot.py
```

## 📘 Документация по папкам

- `backend/README.md`
- `frontend/README.md`
- `frontend/cloudtune_flutter_app/README.md`
- `monitoring/README.md`

## 🧪 Текущее состояние

Проект уже можно использовать как MVP: backend и мониторинг развёрнуты в Docker, приложение устанавливается как APK и поддерживает обновление при подписи тем же keystore.
