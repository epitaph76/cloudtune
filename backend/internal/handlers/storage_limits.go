package handlers

import (
	"database/sql"
	"os"
	"strconv"
	"strings"
)

const (
	defaultStorageQuotaBytes int64 = 3 * 1024 * 1024 * 1024 // 3 GB
	defaultMaxUploadSize     int64 = 100 * 1024 * 1024      // 100 MB
	defaultUploadsBasePath         = "./uploads"
)

func resolveStorageQuotaBytes() int64 {
	return resolvePositiveInt64Env("CLOUD_STORAGE_QUOTA_BYTES", defaultStorageQuotaBytes)
}

func resolveMaxUploadSizeBytes() int64 {
	return resolvePositiveInt64Env("CLOUD_MAX_UPLOAD_SIZE_BYTES", defaultMaxUploadSize)
}

func resolveUploadsBasePath() string {
	value := strings.TrimSpace(os.Getenv("CLOUD_UPLOADS_PATH"))
	if value == "" {
		return defaultUploadsBasePath
	}
	return value
}

func resolvePositiveInt64Env(key string, fallback int64) int64 {
	raw := strings.TrimSpace(os.Getenv(key))
	if raw == "" {
		return fallback
	}

	value, err := strconv.ParseInt(raw, 10, 64)
	if err != nil || value <= 0 {
		return fallback
	}

	return value
}

func getUserStorageUsageBytes(db *sql.DB, userID int) (int64, error) {
	var usedBytes int64
	query := `
		SELECT COALESCE(SUM(s.filesize), 0)
		FROM songs s
		JOIN user_library ul ON s.id = ul.song_id
		WHERE ul.user_id = $1
	`

	if err := db.QueryRow(query, userID).Scan(&usedBytes); err != nil {
		return 0, err
	}

	return usedBytes, nil
}

func canUserStoreAdditionalBytes(db *sql.DB, userID int, additionalBytes int64) (bool, int64, int64, error) {
	usedBytes, err := getUserStorageUsageBytes(db, userID)
	if err != nil {
		return false, 0, 0, err
	}

	quotaBytes := resolveStorageQuotaBytes()
	if additionalBytes <= 0 {
		return true, usedBytes, quotaBytes, nil
	}

	return usedBytes+additionalBytes <= quotaBytes, usedBytes, quotaBytes, nil
}
