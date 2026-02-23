package monitoring

import (
	"cloudtune/internal/database"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"time"
)

const defaultUploadsPath = "./uploads"

// Service holds runtime context for monitoring and reporting.
type Service struct {
	startedAt time.Time
}

type Snapshot struct {
	TimestampUTC        string `json:"timestamp_utc"`
	UptimeSeconds       int64  `json:"uptime_seconds"`
	HTTPActiveRequests  int64  `json:"http_active_requests"`
	HTTPTotalRequests   uint64 `json:"http_total_requests"`
	DBOpenConnections   int    `json:"db_open_connections"`
	DBInUseConnections  int    `json:"db_in_use_connections"`
	DBWaitCount         int64  `json:"db_wait_count"`
	Goroutines          int    `json:"goroutines"`
	GoMemoryAllocBytes  uint64 `json:"go_memory_alloc_bytes"`
	GoMemorySysBytes    uint64 `json:"go_memory_sys_bytes"`
	GoHeapInUseBytes    uint64 `json:"go_heap_in_use_bytes"`
	GoGCCount           uint32 `json:"go_gc_count"`
	UsersTotal          int64  `json:"users_total"`
	SongsTotal          int64  `json:"songs_total"`
	PlaylistsTotal      int64  `json:"playlists_total"`
	SongsTotalSizeBytes int64  `json:"songs_total_size_bytes"`
	DBSizeBytes         int64  `json:"db_size_bytes"`
	UploadsSizeBytes    int64  `json:"uploads_size_bytes"`
	UploadsFilesCount   int64  `json:"uploads_files_count"`
	UploadsFSTotalBytes uint64 `json:"uploads_fs_total_bytes"`
	UploadsFSFreeBytes  uint64 `json:"uploads_fs_free_bytes"`
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
		fmt.Sprintf("Go goroutines: %d", runtime.NumGoroutine()),
	}, "\n")
}

func (s *Service) StorageText() string {
	var songsBytes int64
	_ = database.DB.QueryRow(`SELECT COALESCE(SUM(filesize), 0) FROM songs`).Scan(&songsBytes)

	var dbSizeBytes int64
	_ = database.DB.QueryRow(`SELECT COALESCE(pg_database_size(current_database()), 0)`).Scan(&dbSizeBytes)

	uploadsDir := getUploadsDir()
	uploadsBytes := dirSize(uploadsDir)
	uploadsFiles := dirFileCount(uploadsDir)
	uploadsTotal, uploadsFree := fsUsage(uploadsDir)

	return strings.Join([]string{
		"CloudTune Storage",
		fmt.Sprintf("Songs total size (DB): %s", formatBytes(songsBytes)),
		fmt.Sprintf("PostgreSQL DB size: %s", formatBytes(dbSizeBytes)),
		fmt.Sprintf("Uploads folder size (%s): %s", uploadsDir, formatBytes(uploadsBytes)),
		fmt.Sprintf("Uploads files count: %d", uploadsFiles),
		fmt.Sprintf("Uploads disk free: %s", formatBytes(int64(uploadsFree))),
		fmt.Sprintf("Uploads disk total: %s", formatBytes(int64(uploadsTotal))),
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

func (s *Service) RuntimeText() string {
	var memory runtime.MemStats
	runtime.ReadMemStats(&memory)

	return strings.Join([]string{
		"CloudTune Runtime",
		fmt.Sprintf("Go version: %s", runtime.Version()),
		fmt.Sprintf("CPU cores: %d", runtime.NumCPU()),
		fmt.Sprintf("Goroutines: %d", runtime.NumGoroutine()),
		fmt.Sprintf("Memory alloc: %s", formatBytes(int64(memory.Alloc))),
		fmt.Sprintf("Memory sys: %s", formatBytes(int64(memory.Sys))),
		fmt.Sprintf("Heap in use: %s", formatBytes(int64(memory.HeapInuse))),
		fmt.Sprintf("GC cycles: %d", memory.NumGC),
	}, "\n")
}

func (s *Service) Snapshot() Snapshot {
	stats := database.DB.Stats()
	activeHTTP, totalHTTP := getHTTPStats()
	uploadsDir := getUploadsDir()
	uploadsTotal, uploadsFree := fsUsage(uploadsDir)

	var memory runtime.MemStats
	runtime.ReadMemStats(&memory)

	snap := Snapshot{
		TimestampUTC:        time.Now().UTC().Format(time.RFC3339),
		UptimeSeconds:       int64(time.Since(s.startedAt).Seconds()),
		HTTPActiveRequests:  activeHTTP,
		HTTPTotalRequests:   totalHTTP,
		DBOpenConnections:   stats.OpenConnections,
		DBInUseConnections:  stats.InUse,
		DBWaitCount:         int64(stats.WaitCount),
		Goroutines:          runtime.NumGoroutine(),
		GoMemoryAllocBytes:  memory.Alloc,
		GoMemorySysBytes:    memory.Sys,
		GoHeapInUseBytes:    memory.HeapInuse,
		GoGCCount:           memory.NumGC,
		UploadsSizeBytes:    dirSize(uploadsDir),
		UploadsFilesCount:   dirFileCount(uploadsDir),
		UploadsFSTotalBytes: uploadsTotal,
		UploadsFSFreeBytes:  uploadsFree,
	}

	_ = database.DB.QueryRow(`SELECT COUNT(*) FROM users`).Scan(&snap.UsersTotal)
	_ = database.DB.QueryRow(`SELECT COUNT(*) FROM songs`).Scan(&snap.SongsTotal)
	_ = database.DB.QueryRow(`SELECT COUNT(*) FROM playlists`).Scan(&snap.PlaylistsTotal)
	_ = database.DB.QueryRow(`SELECT COALESCE(SUM(filesize), 0) FROM songs`).Scan(&snap.SongsTotalSizeBytes)
	_ = database.DB.QueryRow(`SELECT COALESCE(pg_database_size(current_database()), 0)`).Scan(&snap.DBSizeBytes)

	return snap
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
		s.RuntimeText(),
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

func dirFileCount(path string) int64 {
	var total int64
	_ = filepath.WalkDir(path, func(_ string, d fs.DirEntry, err error) error {
		if err != nil || d.IsDir() {
			return nil
		}
		total++
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
