package main

import (
    "cloudtune/internal/handlers"
    "log"

    "github.com/gin-gonic/gin"
)

func main() {
    // Создаём роутер Gin
    router := gin.Default()

    // Регистрируем эндпоинты
    router.GET("/health", handlers.HealthCheck)
    router.GET("/api/status", handlers.Status)

    // Запускаем сервер
    log.Println("🚀 CloudTune API starting on :8080")
    if err := router.Run(":8080"); err != nil {
        log.Fatal("❌ Server failed to start:", err)
    }
}
