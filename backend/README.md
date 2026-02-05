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

## API Эндпоинты

- `GET /health` - проверка состояния сервера
- `GET /api/status` - получение статуса приложения

## Переменные окружения

Создайте файл `.env` на основе `.env.example` и укажите необходимые переменные окружения.

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