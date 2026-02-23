package main

import (
	"cloudtune/internal/database"
	"cloudtune/internal/handlers"
	"cloudtune/internal/middleware"
	"cloudtune/internal/monitoring"
	"cloudtune/internal/utils"
	"log"
	"time"

	"github.com/gin-gonic/gin"
)

func main() {
	if err := utils.EnsureJWTReady(); err != nil {
		log.Fatal("JWT configuration error:", err)
	}

	database.InitDB()
	defer database.CloseDB()

	database.CreateTables()

	router := gin.Default()
	router.Use(monitoring.RequestMetricsMiddleware())

	monitoringService := monitoring.NewService(time.Now())
	handlers.SetMonitoringService(monitoringService)

	router.GET("/health", handlers.HealthCheck)
	router.GET("/api/status", handlers.Status)
	router.GET("/api/monitor/status", handlers.MonitorStatus)
	router.GET("/api/monitor/storage", handlers.MonitorStorage)
	router.GET("/api/monitor/connections", handlers.MonitorConnections)
	router.GET("/api/monitor/users", handlers.MonitorUsers)
	router.GET("/api/monitor/users/list", handlers.MonitorUsersList)
	router.GET("/api/monitor/runtime", handlers.MonitorRuntime)
	router.GET("/api/monitor/snapshot", handlers.MonitorSnapshot)
	router.GET("/api/monitor/all", handlers.MonitorAll)

	authRoutes := router.Group("/auth")
	{
		authRoutes.POST("/register", handlers.Register)
		authRoutes.POST("/login", handlers.Login)
	}

	protectedRoutes := router.Group("/api")
	protectedRoutes.Use(middleware.AuthMiddleware())
	{
		protectedRoutes.POST("/songs/upload", handlers.UploadSong)
		protectedRoutes.GET("/songs/library", handlers.GetUserLibrary)
		protectedRoutes.GET("/songs/:id", handlers.GetSongByID)
		protectedRoutes.DELETE("/songs/:id", handlers.DeleteSong)
		protectedRoutes.GET("/songs/download/:id", handlers.DownloadSong)
		protectedRoutes.GET("/storage/usage", handlers.GetStorageUsage)

		protectedRoutes.POST("/playlists", handlers.CreatePlaylist)
		protectedRoutes.GET("/playlists", handlers.GetUserPlaylists)
		protectedRoutes.DELETE("/playlists/:playlist_id", handlers.DeletePlaylist)
		protectedRoutes.POST("/playlists/:playlist_id/songs/:song_id", handlers.AddSongToPlaylist)
		protectedRoutes.POST("/playlists/:playlist_id/songs/bulk", handlers.AddSongsToPlaylistBulk)
		protectedRoutes.GET("/playlists/:playlist_id/songs", handlers.GetPlaylistSongs)
	}

	log.Println("CloudTune API starting on :8080")
	if err := router.Run(":8080"); err != nil {
		log.Fatal("Server failed to start:", err)
	}
}
