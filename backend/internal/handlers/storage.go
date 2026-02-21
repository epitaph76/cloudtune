package handlers

import (
	"cloudtune/internal/database"
	"net/http"
	"os"
	"strconv"

	"github.com/gin-gonic/gin"
)

const defaultStorageQuotaBytes int64 = 10 * 1024 * 1024 * 1024 // 10 GB

func resolveStorageQuotaBytes() int64 {
	raw := os.Getenv("CLOUD_STORAGE_QUOTA_BYTES")
	if raw == "" {
		return defaultStorageQuotaBytes
	}

	value, err := strconv.ParseInt(raw, 10, 64)
	if err != nil || value <= 0 {
		return defaultStorageQuotaBytes
	}

	return value
}

// GetStorageUsage returns cloud storage usage for current user.
func GetStorageUsage(c *gin.Context) {
	userIDInterface, exists := c.Get("user_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Unauthorized"})
		return
	}

	userID, ok := userIDInterface.(int)
	if !ok {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Invalid user ID"})
		return
	}

	db := database.DB
	var usedBytes int64
	query := `
		SELECT COALESCE(SUM(s.filesize), 0)
		FROM songs s
		JOIN user_library ul ON s.id = ul.song_id
		WHERE ul.user_id = $1
	`
	if err := db.QueryRow(query, userID).Scan(&usedBytes); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Error calculating storage usage"})
		return
	}

	quotaBytes := resolveStorageQuotaBytes()
	remainingBytes := quotaBytes - usedBytes
	if remainingBytes < 0 {
		remainingBytes = 0
	}

	c.JSON(http.StatusOK, gin.H{
		"used_bytes":      usedBytes,
		"quota_bytes":     quotaBytes,
		"remaining_bytes": remainingBytes,
	})
}
