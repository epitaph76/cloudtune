[Лендинг проекта: https://api-mp3-player.ru](https://api-mp3-player.ru)

# CloudTune

CloudTune — fullstack-проект музыкального плеера:
- Flutter-клиент (Android + Windows desktop shell);
- Go backend (Gin + PostgreSQL);
- Telegram-бот мониторинга;
- статические лендинги (main + resume).

## Текущая версия

- Flutter-клиент: `1.8.6+8` (из `frontend/cloudtune_flutter_app/pubspec.yaml`).
- Артефакты релиза в корне репозитория:
  - `cloudtune_andr.apk`
  - `cloudtune_win/`
  - `cloudtune_win.zip`

## Структура репозитория

- `backend/` — REST API, БД, monitoring endpoints, deploy-скрипты.
- `frontend/cloudtune_flutter_app/` — исходники Flutter-приложения.
- `monitoring/` — Telegram-бот мониторинга и удаленного деплоя.
- `landing/` — основной статический лендинг.
- `landing/resume/` — отдельный resume-лендинг.

## Быстрый старт

### Backend (local dev)

```bash
cd backend
docker compose up --build
```

API по умолчанию: `http://localhost:8080`.

### Backend (production compose)

```bash
cd backend
cp .env.prod.example .env.prod
docker compose --env-file .env.prod -f docker-compose.prod.yml up -d --build
```

### Flutter app

```bash
cd frontend/cloudtune_flutter_app
flutter pub get
flutter run
```

Для своего backend:

```bash
flutter run --dart-define=API_BASE_URL=https://api.your-domain.com
```

### Monitoring bot

```bash
cd monitoring
python -m venv .venv
.venv\Scripts\activate
pip install -r requirements.txt
python src/bot.py
```

## Сборка и обновление артефактов в корне

Сборка (из `frontend/cloudtune_flutter_app`):

```bash
flutter build apk --release
flutter build windows --release
```

Копирование артефактов (из корня репозитория):

```powershell
Copy-Item frontend/cloudtune_flutter_app/build/app/outputs/flutter-apk/app-release.apk cloudtune_andr.apk -Force
New-Item -ItemType Directory -Path cloudtune_win -Force | Out-Null
Copy-Item frontend/cloudtune_flutter_app/build/windows/x64/runner/Release/* cloudtune_win -Recurse -Force
Compress-Archive -Path cloudtune_win\* -DestinationPath cloudtune_win.zip -Force
```

## Проверка

```bash
cd frontend/cloudtune_flutter_app
flutter analyze
flutter test
```

## Документация по модулям

- `backend/README.md`
- `frontend/README.md`
- `frontend/cloudtune_flutter_app/README.md`
- `monitoring/README.md`
- `landing/README.md`
- `landing/resume/README.md`
