package handlers

import (
	"cloudtune/internal/database"
	"net/http"

	"github.com/gin-gonic/gin"
)

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
	usedBytes, err := getUserStorageUsageBytes(db, userID)
	if err != nil {
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
