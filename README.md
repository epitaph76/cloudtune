# CloudTune — Cloud Music Player

![Go](https://img.shields.io/badge/Go-1.25+-00ADD8?logo=go)
![Gin](https://img.shields.io/badge/Gin_Framework-1.9.1-008000?logo=go)
![PostgreSQL](https://img.shields.io/badge/PostgreSQL-15-336791?logo=postgresql)
![React Native](https://img.shields.io/badge/React_Native-0.81.5-61DAFB?logo=react)
![Expo](https://img.shields.io/badge/Expo-~54.0.33-000000?logo=expo)

## 🎵 About

CloudTune is a personal cloud music player with cross-device synchronization. Upload your MP3 collection once — listen anywhere:

- 📱 Mobile app (React Native/Expo) for playlist management
- 💻 Cross-platform access with synchronized playback state
- 🔒 Self-hosted infrastructure — full control over your data
- ⚡ Lightweight Go backend optimized for audio streaming
- 🔐 Secure authentication with JWT tokens

> Built as a learning project to explore Go backend development, React Native frontend, and security-first architecture.

## 🛠 Tech Stack

| Layer | Technology |
|-------|------------|
| **Backend** | Go 1.25+ + Gin framework |
| **Database** | PostgreSQL (users, playlists, metadata) |
| **Frontend** | React Native + Expo (iOS/Android) |
| **Authentication** | JWT with bcrypt password hashing |
| **Infra** | Ubuntu 22.04, Nginx reverse proxy, Let's Encrypt SSL |
| **Hosting** | VPS in Netherlands (`api-mp3-player.ru`) |

## 🚀 Features

- **User Authentication**: Secure registration and login with JWT tokens
- **Responsive UI**: Clean interface with light/dark mode support
- **Cross-Platform**: Works on iOS and Android devices
- **Self-Hosted**: Full control over your music collection and data
- **Secure**: Password hashing, input validation, and SQL injection protection

## 🔐 Security

### Technologies
- **bcrypt** — password hashing (cost=12)
- **JWT** — stateless authentication
- **PostgreSQL** — secure user and token storage

### Security Measures
- Input validation for all requests
- Rate limiting to prevent brute force attacks
- Parameterized queries (SQL injection protection)
- HTTPS enforced (Let's Encrypt)
- CORS configuration for mobile application

### API Endpoints
- `POST /auth/register` — user registration
- `POST /auth/login` — user login
- `GET /api/profile` — user profile (requires authentication)

## 📁 Project Structure

```
cloudtune/
├── backend/                  # Go backend service
│   ├── cmd/
│   │   └── api/             # Application entry point
│   ├── internal/
│   │   ├── database/        # Database connection and setup
│   │   ├── handlers/        # HTTP request handlers
│   │   ├── middleware/      # Authentication and other middleware
│   │   ├── models/          # Data models
│   │   └── utils/           # Utility functions
│   ├── go.mod               # Go module dependencies
│   └── ...
├── frontend/
│   └── CloudTuneApp/        # React Native/Expo application
│       ├── app/             # Application screens and routes
│       ├── components/      # Reusable UI components
│       ├── lib/             # API and utility functions
│       ├── providers/       # Context providers (Auth, etc.)
│       ├── constants/       # Constants and themes
│       └── ...
└── README.md
```

## 🛠 Development Setup

### Backend (Go)

1. Install Go 1.25+
2. Navigate to the backend directory:
   ```bash
   cd backend
   ```
3. Install dependencies:
   ```bash
   go mod tidy
   ```
4. Set up environment variables:
   ```bash
   cp .env.example .env
   # Edit .env with your configuration
   ```
5. Run the application:
   ```bash
   cd cmd/api
   go run main.go
   ```

### Frontend (React Native/Expo)

1. Install Node.js (v18 or later)
2. Navigate to the frontend directory:
   ```bash
   cd frontend/CloudTuneApp
   ```
3. Install dependencies:
   ```bash
   npm install
   ```
4. Start the development server:
   ```bash
   npx expo start
   ```

## 🚀 Deployment

### Backend

The backend can be deployed using Docker:
```bash
cd backend
docker-compose up -d
```

### Production

For production deployment:
1. Configure your domain and SSL certificates
2. Set up environment variables securely
3. Deploy the backend service
4. Build and deploy the frontend application

## 🤝 Contributing

We welcome contributions! Please see our [Contributing Guide](CONTRIBUTING.md) for more details.

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🐳 Docker Support

The project includes Docker support for easy development and deployment:

```bash
# Build and run with Docker Compose
cd backend
docker-compose up -d

# Stop services
docker-compose down
```

## 🧪 Testing

Run backend tests:
```bash
cd backend
go test ./...
```

## 🌐 API Documentation

The backend provides a RESTful API for managing users and music collections. See individual service documentation for detailed endpoint information.