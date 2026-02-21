package monitoring

import (
	"cloudtune/internal/database"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"strings"
	"time"
)

const defaultUploadsPath = "./uploads"

// Service holds runtime context for monitoring and reporting.
type Service struct {
	startedAt time.Time
}

func NewService(startedAt time.Time) *Service {
	return &Service{startedAt: startedAt}
}

func (s *Service) StatusText() string {
	dbState := "ok"
	if err := database.DB.Ping(); err != nil {
		dbState = "error: " + err.Error()
	}

	uptime := time.Since(s.startedAt).Round(time.Second)
	activeHTTP, totalHTTP := getHTTPStats()
	generic := database.DB.Stats()

	return strings.Join([]string{
		"CloudTune Server Status",
		fmt.Sprintf("Uptime: %s", uptime),
		fmt.Sprintf("DB: %s", dbState),
		fmt.Sprintf("HTTP active requests: %d", activeHTTP),
		fmt.Sprintf("HTTP total requests: %d", totalHTTP),
		fmt.Sprintf("DB open connections: %d", generic.OpenConnections),
	}, "\n")
}

func (s *Service) StorageText() string {
	var songsBytes int64
	_ = database.DB.QueryRow(`SELECT COALESCE(SUM(filesize), 0) FROM songs`).Scan(&songsBytes)

	var dbSizeBytes int64
	_ = database.DB.QueryRow(`SELECT COALESCE(pg_database_size(current_database()), 0)`).Scan(&dbSizeBytes)

	uploadsDir := getUploadsDir()
	uploadsBytes := dirSize(uploadsDir)

	return strings.Join([]string{
		"CloudTune Storage",
		fmt.Sprintf("Songs total size (DB): %s", formatBytes(songsBytes)),
		fmt.Sprintf("PostgreSQL DB size: %s", formatBytes(dbSizeBytes)),
		fmt.Sprintf("Uploads folder size (%s): %s", uploadsDir, formatBytes(uploadsBytes)),
	}, "\n")
}

func (s *Service) ConnectionsText() string {
	stats := database.DB.Stats()
	activeHTTP, totalHTTP := getHTTPStats()

	return strings.Join([]string{
		"CloudTune Connections",
		fmt.Sprintf("DB MaxOpenConnections: %d", stats.MaxOpenConnections),
		fmt.Sprintf("DB OpenConnections: %d", stats.OpenConnections),
		fmt.Sprintf("DB InUse: %d", stats.InUse),
		fmt.Sprintf("DB Idle: %d", stats.Idle),
		fmt.Sprintf("DB WaitCount: %d", stats.WaitCount),
		fmt.Sprintf("HTTP active requests: %d", activeHTTP),
		fmt.Sprintf("HTTP total requests: %d", totalHTTP),
	}, "\n")
}

func (s *Service) UsersText() string {
	var usersTotal int64
	_ = database.DB.QueryRow(`SELECT COUNT(*) FROM users`).Scan(&usersTotal)

	var usersNew24h int64
	_ = database.DB.QueryRow(`SELECT COUNT(*) FROM users WHERE created_at >= NOW() - INTERVAL '24 hours'`).Scan(&usersNew24h)

	var songsTotal int64
	_ = database.DB.QueryRow(`SELECT COUNT(*) FROM songs`).Scan(&songsTotal)

	var playlistsTotal int64
	_ = database.DB.QueryRow(`SELECT COUNT(*) FROM playlists`).Scan(&playlistsTotal)

	return strings.Join([]string{
		"CloudTune Users",
		fmt.Sprintf("Users total: %d", usersTotal),
		fmt.Sprintf("Users created in 24h: %d", usersNew24h),
		fmt.Sprintf("Songs total: %d", songsTotal),
		fmt.Sprintf("Playlists total: %d", playlistsTotal),
	}, "\n")
}

func (s *Service) HelpText() string {
	return strings.Join([]string{
		"CloudTune monitor commands:",
		"/status - server status",
		"/storage - storage metrics",
		"/connections - DB and HTTP connections",
		"/users - users and content stats",
		"/all - full report",
		"/help - this help",
	}, "\n")
}

func (s *Service) AllText() string {
	return strings.Join([]string{
		s.StatusText(),
		"",
		s.StorageText(),
		"",
		s.ConnectionsText(),
		"",
		s.UsersText(),
	}, "\n")
}

func getUploadsDir() string {
	value := os.Getenv("CLOUD_UPLOADS_PATH")
	if value == "" {
		return defaultUploadsPath
	}
	return value
}

func dirSize(path string) int64 {
	var total int64
	_ = filepath.WalkDir(path, func(_ string, d fs.DirEntry, err error) error {
		if err != nil || d.IsDir() {
			return nil
		}
		info, infoErr := d.Info()
		if infoErr != nil {
			return nil
		}
		total += info.Size()
		return nil
	})
	return total
}

func formatBytes(value int64) string {
	units := []string{"B", "KB", "MB", "GB", "TB"}
	size := float64(value)
	unit := 0

	for size >= 1024 && unit < len(units)-1 {
		size /= 1024
		unit++
	}

	if unit == 0 {
		return fmt.Sprintf("%d %s", value, units[unit])
	}
	return fmt.Sprintf("%.2f %s", size, units[unit])
}
