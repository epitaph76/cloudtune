# CloudTune — Cloud Music Player

![Go](https://img.shields.io/badge/Go-1.21.6-00ADD8?logo=go)
![Gin](https://img.shields.io/badge/Gin_Framework-1.9.1-008000?logo=go)
![PostgreSQL](https://img.shields.io/badge/PostgreSQL-14-336791?logo=postgresql)
![React Native](https://img.shields.io/badge/React_Native-0.72-61DAFB?logo=react)

## 🎵 About

CloudTune is a personal cloud music player with cross-device synchronization. Upload your MP3 collection once — listen anywhere:

- 📱 Mobile app (React Native) for playlist management
- 💻 Web/desktop access with synced playback state
- 🔒 Self-hosted infrastructure — full control over your data
- ⚡ Lightweight Go backend optimized for audio streaming

> Built as a learning project to explore Go backend development and security-first architecture.

## 🛠 Tech Stack

| Layer | Technology |
|-------|------------|
| **Backend** | Go 1.21.6 + Gin framework |
| **Database** | PostgreSQL (users, playlists, metadata) |
| **Frontend** | React Native (iOS/Android) |
| **Infra** | Ubuntu 22.04, Nginx reverse proxy, Let's Encrypt SSL |
| **Hosting** | VPS in Netherlands (`api-mp3-player.ru`) |

## 🔐 Аутентификация и безопасность

### Технологии
- **bcrypt** — хеширование паролей (cost=12)
- **JWT** — stateless аутентификация
- **PostgreSQL** — хранение пользователей и токенов

### Безопасность
- Валидация всех входных данных
- Rate limiting для защиты от брутфорса
- Параметризованные запросы (защита от SQL инъекций)
- HTTPS только (Let's Encrypt)
- CORS настройки для мобильного приложения

### Эндпоинты
- `POST /api/auth/register` — регистрация
- `POST /api/auth/login` — вход
- `POST /api/auth/refresh` — обновление токена
- `POST /api/auth/logout` — выход

### Project Structure