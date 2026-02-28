package handlers

import (
	"cloudtune/internal/database"
	"cloudtune/internal/monitoring"
	"io/fs"
	"math"
	"net/http"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
)

var monitoringService *monitoring.Service

// SetMonitoringService registers runtime monitoring service for handlers.
func SetMonitoringService(service *monitoring.Service) {
	monitoringService = service
}

func getMonitoringService() *monitoring.Service {
	if monitoringService == nil {
		monitoringService = monitoring.NewService(time.Now())
	}
	return monitoringService
}

func checkMonitoringToken(c *gin.Context) bool {
	expected := strings.TrimSpace(os.Getenv("MONITORING_API_KEY"))
	if expected == "" {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Monitoring API is disabled"})
		return false
	}

	provided := strings.TrimSpace(c.GetHeader("X-Monitoring-Key"))
	if provided == "" || provided != expected {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Invalid monitoring key"})
		return false
	}
	return true
}

func MonitorStatus(c *gin.Context) {
	if !checkMonitoringToken(c) {
		return
	}
	c.JSON(http.StatusOK, gin.H{"text": getMonitoringService().StatusText()})
}

func MonitorStorage(c *gin.Context) {
	if !checkMonitoringToken(c) {
		return
	}
	c.JSON(http.StatusOK, gin.H{"text": getMonitoringService().StorageText()})
}

func MonitorConnections(c *gin.Context) {
	if !checkMonitoringToken(c) {
		return
	}
	c.JSON(http.StatusOK, gin.H{"text": getMonitoringService().ConnectionsText()})
}

func MonitorUsers(c *gin.Context) {
	if !checkMonitoringToken(c) {
		return
	}
	c.JSON(http.StatusOK, gin.H{"text": getMonitoringService().UsersText()})
}

func MonitorAll(c *gin.Context) {
	if !checkMonitoringToken(c) {
		return
	}
	c.JSON(http.StatusOK, gin.H{"text": getMonitoringService().AllText()})
}

func MonitorRuntime(c *gin.Context) {
	if !checkMonitoringToken(c) {
		return
	}
	c.JSON(http.StatusOK, gin.H{"text": getMonitoringService().RuntimeText()})
}

func MonitorSnapshot(c *gin.Context) {
	if !checkMonitoringToken(c) {
		return
	}
	c.JSON(http.StatusOK, getMonitoringService().Snapshot())
}

func MonitorUsersList(c *gin.Context) {
	if !checkMonitoringToken(c) {
		return
	}

	page := parsePositiveInt(c.Query("page"), 1)
	limit := parsePositiveInt(c.Query("limit"), 8)
	if limit > 50 {
		limit = 50
	}
	offset := (page - 1) * limit

	var totalUsers int
	if err := database.DB.QueryRow(`SELECT COUNT(*) FROM users`).Scan(&totalUsers); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to load users count"})
		return
	}

	rows, err := database.DB.Query(`
		SELECT
			u.id,
			u.email,
			u.username,
			u.created_at,
			COALESCE(SUM(s.filesize), 0) AS used_bytes
		FROM users u
		LEFT JOIN user_library ul ON ul.user_id = u.id
		LEFT JOIN songs s ON s.id = ul.song_id
		GROUP BY u.id, u.email, u.username, u.created_at
		ORDER BY u.created_at DESC
		LIMIT $1 OFFSET $2
	`, limit, offset)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to load users list"})
		return
	}
	defer rows.Close()

	type monitorUserItem struct {
		ID        int       `json:"id"`
		Email     string    `json:"email"`
		Username  string    `json:"username"`
		UsedBytes int64     `json:"used_bytes"`
		CreatedAt time.Time `json:"created_at"`
	}

	users := make([]monitorUserItem, 0)
	for rows.Next() {
		var item monitorUserItem
		if scanErr := rows.Scan(&item.ID, &item.Email, &item.Username, &item.CreatedAt, &item.UsedBytes); scanErr != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to scan users list"})
			return
		}
		users = append(users, item)
	}

	totalPages := 0
	if totalUsers > 0 {
		totalPages = int(math.Ceil(float64(totalUsers) / float64(limit)))
	}

	c.JSON(http.StatusOK, gin.H{
		"page":        page,
		"limit":       limit,
		"total_users": totalUsers,
		"total_pages": totalPages,
		"users":       users,
	})
}

type monitorFileItem struct {
	Name         string    `json:"name"`
	RelativePath string    `json:"relative_path"`
	SizeBytes    int64     `json:"size_bytes"`
	ModifiedAt   time.Time `json:"modified_at"`
}

func MonitorFilesList(c *gin.Context) {
	if !checkMonitoringToken(c) {
		return
	}

	page := parsePositiveInt(c.Query("page"), 1)
	limit := parsePositiveInt(c.Query("limit"), 10)
	if limit > 50 {
		limit = 50
	}

	rootPath := filepath.Clean(resolveUploadsBasePath())
	absRootPath, err := filepath.Abs(rootPath)
	if err == nil {
		rootPath = absRootPath
	}

	files := make([]monitorFileItem, 0)
	_ = filepath.WalkDir(rootPath, func(path string, d fs.DirEntry, walkErr error) error {
		if walkErr != nil || d.IsDir() {
			return nil
		}

		info, infoErr := d.Info()
		if infoErr != nil {
			return nil
		}

		relativePath, relErr := filepath.Rel(rootPath, path)
		if relErr != nil {
			relativePath = d.Name()
		}

		files = append(files, monitorFileItem{
			Name:         d.Name(),
			RelativePath: filepath.ToSlash(relativePath),
			SizeBytes:    info.Size(),
			ModifiedAt:   info.ModTime().UTC(),
		})
		return nil
	})

	sort.Slice(files, func(left, right int) bool {
		if files[left].SizeBytes == files[right].SizeBytes {
			if files[left].ModifiedAt.Equal(files[right].ModifiedAt) {
				return files[left].RelativePath < files[right].RelativePath
			}
			return files[left].ModifiedAt.After(files[right].ModifiedAt)
		}
		return files[left].SizeBytes > files[right].SizeBytes
	})

	totalFiles := len(files)
	totalPages := 0
	if totalFiles > 0 {
		totalPages = int(math.Ceil(float64(totalFiles) / float64(limit)))
	}

	if totalPages > 0 && page > totalPages {
		page = totalPages
	}
	offset := 0
	if totalPages > 0 {
		offset = (page - 1) * limit
	}

	pagedFiles := make([]monitorFileItem, 0)
	if totalFiles > 0 && offset < totalFiles {
		end := offset + limit
		if end > totalFiles {
			end = totalFiles
		}
		pagedFiles = files[offset:end]
	}

	c.JSON(http.StatusOK, gin.H{
		"page":        page,
		"limit":       limit,
		"total_files": totalFiles,
		"total_pages": totalPages,
		"root_path":   rootPath,
		"files":       pagedFiles,
	})
}

func parsePositiveInt(raw string, fallback int) int {
	value, err := strconv.Atoi(raw)
	if err != nil || value <= 0 {
		return fallback
	}
	return value
}
