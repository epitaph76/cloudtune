# CloudTune Backend

Backend часть приложения CloudTune - REST API сервис для управления облачными ресурсами.

## Технологии

- **Go** (версия 1.25+)
- **Gin Framework** - веб-фреймворк
- **Air** - инструмент для горячей перезагрузки во время разработки

## Структура проекта

```
backend/
├── cmd/
│   └── api/
│       └── main.go          # Точка входа в приложение
├── internal/
│   ├── handlers/            # Обработчики HTTP запросов
│   │   ├── health.go        # Эндпоинт проверки состояния
│   │   └── status.go        # Эндпоинт получения статуса
│   └── ...
├── pkg/                     # Общие пакеты
├── go.mod                   # Зависимости Go модуля
├── go.sum                   # Чек-суммы зависимостей
├── .air.toml                # Конфигурация Air
├── Dockerfile.dev           # Dockerfile для разработки
└── ...
```

## Установка и запуск

### Локальная разработка

1. Убедитесь, что у вас установлена Go версии 1.25+
2. Установите Air для горячей перезагрузки:
   ```bash
   go install github.com/air-verse/air@latest
   ```
3. Установите зависимости:
   ```bash
   go mod tidy
   ```
4. Запустите приложение:
   ```bash
   cd cmd/api
   go run main.go
   ```
   
   Или используйте Air для автоматической перезагрузки:
   ```bash
   air
   ```

### Через Docker

1. Сборка образа:
   ```bash
   docker build -f Dockerfile.dev -t cloudtune-backend .
   ```

2. Запуск контейнера:
   ```bash
   docker run -d -p 8080:8080 --name cloudtune-backend-container cloudtune-backend
   ```

### Через Docker Compose (с PostgreSQL)

1. Убедитесь, что у вас установлен Docker и Docker Compose

2. Запустите сервисы:
   ```bash
   docker-compose up -d
   ```

3. При первом запуске приложение может потребовать время на установку зависимостей

4. Для остановки сервисов:
   ```bash
   docker-compose down
   ```

## API Эндпоинты

- `GET /health` - проверка состояния сервера
- `GET /api/status` - получение статуса приложения
- `POST /auth/register` - регистрация нового пользователя
- `POST /auth/login` - вход пользователя
- `GET /api/profile` - получение профиля пользователя (требует авторизации)

### Примеры использования аутентификации

#### Регистрация пользователя
```bash
curl -X POST http://localhost:8080/auth/register \
  -H "Content-Type: application/json" \
  -d '{"email":"user@example.com","username":"username","password":"password"}'
```

#### Вход пользователя
```bash
curl -X POST http://localhost:8080/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"user@example.com","password":"password"}'
```

#### Доступ к защищенному ресурсу
```bash
curl -X GET http://localhost:8080/api/profile \
  -H "Authorization: Bearer YOUR_JWT_TOKEN_HERE"
```

## Переменные окружения

Создайте файл `.env` на основе `.env.example` и укажите необходимые переменные окружения:

```bash
# Копируем пример конфигурации
cp .env.example .env

# Редактируем .env файл и указываем свои значения
```

Основные переменные:
- `DB_HOST` - хост базы данных (по умолчанию: localhost)
- `DB_PORT` - порт базы данных (по умолчанию: 5432)
- `DB_USER` - имя пользователя базы данных (по умолчанию: postgres)
- `DB_PASSWORD` - пароль для базы данных (по умолчанию: password)
- `DB_NAME` - имя базы данных (по умолчанию: cloudtune)
- `JWT_SECRET` - секретный ключ для JWT токенов (обязательно измените в продакшене!)

## Разработка

При разработке рекомендуется использовать Air для горячей перезагрузки. Конфигурация находится в файле `.air.toml`.

## Тестирование

Для запуска тестов:
```bash
go test ./...
```

## Контрибьютинг

1. Форкните репозиторий
2. Создайте ветку для новой фичи (`git checkout -b feature/new-feature`)
3. Сделайте коммит ваших изменений (`git commit -m 'Add new feature'`)
4. Запушьте изменения (`git push origin feature/new-feature`)
5. Создайте Pull Request