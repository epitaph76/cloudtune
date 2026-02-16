package main

import (
	"cloudtune/internal/database"
	"cloudtune/internal/handlers"
	"cloudtune/internal/middleware"
	"log"

	"github.com/gin-gonic/gin"
)

func main() {
	// Инициализируем подключение к базе данных
	database.InitDB()
	defer database.CloseDB()

	// Создаём таблицы в базе данных
	database.CreateTables()

	// Создаём роутер Gin
	router := gin.Default()

	// Регистрируем эндпоинты
	router.GET("/health", handlers.HealthCheck)
	router.GET("/api/status", handlers.Status)

	// Группа маршрутов для аутентификации
	authRoutes := router.Group("/auth")
	{
		authRoutes.POST("/register", handlers.Register)
		authRoutes.POST("/login", handlers.Login)
	}

	// Защищенные маршруты (потребуется JWT токен)
	protectedRoutes := router.Group("/api")
	protectedRoutes.Use(middleware.AuthMiddleware()) // Middleware для аутентификации
	{
		// Маршруты для работы с песнями
		protectedRoutes.POST("/songs/upload", handlers.UploadSong)
		protectedRoutes.GET("/songs/library", handlers.GetUserLibrary)
		protectedRoutes.GET("/songs/:id", handlers.GetSongByID)
		protectedRoutes.GET("/songs/download/:id", handlers.DownloadSong)

		// Маршруты для работы с плейлистами
		protectedRoutes.POST("/playlists", handlers.CreatePlaylist)
		protectedRoutes.GET("/playlists", handlers.GetUserPlaylists)
		protectedRoutes.POST("/playlists/:playlist_id/songs/:song_id", handlers.AddSongToPlaylist)
		protectedRoutes.GET("/playlists/:playlist_id/songs", handlers.GetPlaylistSongs)
	}

	// Запускаем сервер
	log.Println("🚀 CloudTune API starting on :8080")
	if err := router.Run(":8080"); err != nil {
		log.Fatal("❌ Server failed to start:", err)
	}
}
