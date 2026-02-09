# CloudTune Backend

The backend service for CloudTune - a REST API for managing cloud music resources with secure user authentication.

## 🛠 Technologies

- **Go** (version 1.25+)
- **Gin Framework** - web framework
- **PostgreSQL** - database
- **Air** - hot reload tool for development
- **JWT** - authentication tokens
- **bcrypt** - password hashing

## 📁 Project Structure

```
backend/
├── cmd/
│   └── api/
│       └── main.go          # Application entry point
├── internal/
│   ├── database/            # Database connection and setup
│   │   ├── connection.go    # Database connection logic
│   │   └── migrations.go    # Schema creation
│   ├── handlers/            # HTTP request handlers
│   │   ├── auth.go          # Authentication endpoints
│   │   ├── health.go        # Health check endpoint
│   │   └── status.go        # Status endpoint
│   ├── middleware/          # Authentication and other middleware
│   │   └── auth.go          # JWT authentication middleware
│   ├── models/              # Data models
│   │   └── user.go          # User model
│   └── utils/               # Utility functions
│       ├── password.go      # Password hashing utilities
│       └── jwt.go           # JWT token utilities
├── pkg/                     # Shared packages
├── go.mod                   # Go module dependencies
├── go.sum                   # Dependency checksums
├── .air.toml                # Air configuration
├── Dockerfile.dev           # Development Dockerfile
├── docker-compose.yml       # Docker Compose configuration
└── .env.example            # Environment variables example
```

## 🚀 Getting Started

### Prerequisites

- Go 1.25+
- PostgreSQL (for development)
- Docker and Docker Compose (optional, for containerized development)

### Local Development

1. Ensure you have Go version 1.25+ installed
2. Install Air for hot reloading:
   ```bash
   go install github.com/air-verse/air@latest
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

   Or use Air for automatic reloading:
   ```bash
   air
   ```

### Using Docker

1. Build the image:
   ```bash
   docker build -f Dockerfile.dev -t cloudtune-backend .
   ```

2. Run the container:
   ```bash
   docker run -d -p 8080:8080 --name cloudtune-backend-container cloudtune-backend
   ```

### Using Docker Compose (with PostgreSQL)

1. Ensure you have Docker and Docker Compose installed

2. Start the services:
   ```bash
   docker-compose up -d
   ```

3. On first run, the application may take time to install dependencies

4. To stop the services:
   ```bash
   docker-compose down
   ```

## 🌐 API Endpoints

### Health Check
- `GET /health` - server health status

### Authentication
- `POST /auth/register` - user registration
- `POST /auth/login` - user login

### Protected Routes
- `GET /api/profile` - user profile (requires authentication)

### Example Requests

#### User Registration
```bash
curl -X POST http://localhost:8080/auth/register \
  -H "Content-Type: application/json" \
  -d '{"email":"user@example.com","username":"username","password":"password"}'
```

#### User Login
```bash
curl -X POST http://localhost:8080/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"user@example.com","password":"password"}'
```

#### Accessing Protected Resources
```bash
curl -X GET http://localhost:8080/api/profile \
  -H "Authorization: Bearer YOUR_JWT_TOKEN_HERE"
```

## 🔐 Environment Variables

Create a `.env` file based on `.env.example` and set the required environment variables:

```bash
# Copy the example configuration
cp .env.example .env

# Edit the .env file with your values
```

Key variables:
- `DB_HOST` - database host (default: localhost)
- `DB_PORT` - database port (default: 5432)
- `DB_USER` - database username (default: postgres)
- `DB_PASSWORD` - database password (default: password)
- `DB_NAME` - database name (default: cloudtune)
- `JWT_SECRET` - secret key for JWT tokens (change this in production!)

## 🛡️ Security Features

- Password hashing with bcrypt (cost=12)
- JWT-based authentication
- Input validation for all requests
- Parameterized queries to prevent SQL injection
- Secure token handling

## 🧪 Testing

To run tests:
```bash
go test ./...
```

## 🚧 Development

During development, it's recommended to use Air for hot reloading. The configuration is located in the `.air.toml` file.

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Make your changes
4. Commit your changes (`git commit -m 'Add amazing feature'`)
5. Push to the branch (`git push origin feature/amazing-feature`)
6. Open a Pull Request

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](../LICENSE) file for details.

## 🐳 Docker Compose Configuration

The project includes a comprehensive Docker Compose configuration for easy development setup:

```yaml
version: '3.8'

services:
  # Application service
  app:
    build:
      context: .
      dockerfile: Dockerfile.dev
    ports:
      - "8080:8080"
    environment:
      - DB_HOST=db
      - DB_PORT=5432
      - DB_USER=postgres
      - DB_PASSWORD=password
      - DB_NAME=cloudtune
      - JWT_SECRET=your-secret-key-change-this-in-production
    depends_on:
      - db
    volumes:
      - .:/app
    command: air

  # PostgreSQL database service
  db:
    image: postgres:15
    environment:
      - POSTGRES_DB=cloudtune
      - POSTGRES_USER=postgres
      - POSTGRES_PASSWORD=password
    ports:
      - "5432:5432"
    volumes:
      - postgres_data:/var/lib/postgresql/data

volumes:
  postgres_data:
```

This configuration sets up both the application and database containers with proper networking and persistence.