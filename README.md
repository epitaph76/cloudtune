# CloudTune

CloudTune is a fullstack music project with:
- Flutter client (Android + Windows desktop shell)
- Go backend (Gin + PostgreSQL)
- Telegram monitoring bot
- Static landing pages

## Repository Layout

- `backend/` - REST API, DB schema/init, monitoring endpoints, deploy scripts.
- `frontend/cloudtune_flutter_app/` - Flutter app source code.
- `monitoring/` - Telegram bot for health/snapshot/deploy commands.
- `landing/` - static site and resume landing pages.
- `cloudtune_andr.apk` - latest Android artifact in repo root.
- `cloudtune_win/` and `cloudtune_win.zip` - latest Windows artifact in repo root.

## Current App Behavior (Important)

- Cloud storage is refreshed:
  - on the first open of the Cloud tab after app launch/auth success
  - on manual pull-to-refresh
- Cloud playlist actions are separated:
  - `Download to local` adds/merges tracks into local playlist and must not remove existing local tracks
  - `Sync` can fully align local playlist with cloud (including removals)

## Quick Start

### Backend

```bash
cd backend
docker compose --env-file .env.prod -f docker-compose.prod.yml up -d --build
```

### Flutter App

```bash
cd frontend/cloudtune_flutter_app
flutter pub get
flutter run --dart-define=API_BASE_URL=https://api.your-domain.com
```

### Monitoring Bot

```bash
cd monitoring
python -m venv .venv
.venv\Scripts\activate
pip install -r requirements.txt
python src/bot.py
```

## Build and Update Root Artifacts

Run from `frontend/cloudtune_flutter_app`:

```bash
flutter build apk --release
flutter build windows --release
```

Then update root artifacts (from repo root):

```powershell
Copy-Item frontend/cloudtune_flutter_app/build/app/outputs/flutter-apk/app-release.apk cloudtune_andr.apk -Force
Copy-Item frontend/cloudtune_flutter_app/build/windows/x64/runner/Release/* cloudtune_win -Recurse -Force
Compress-Archive -Path cloudtune_win\* -DestinationPath cloudtune_win.zip -Force
```

## Verification

From `frontend/cloudtune_flutter_app`:

```bash
flutter analyze
flutter test
```

## Additional Docs

- `backend/README.md`
- `frontend/README.md`
- `frontend/cloudtune_flutter_app/README.md`
- `monitoring/README.md`
- `landing/README.md`
