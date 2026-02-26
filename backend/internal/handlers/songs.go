package handlers

import (
	"cloudtune/internal/database"
	"cloudtune/internal/models"
	"cloudtune/internal/monitoring"
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/gabriel-vasile/mimetype"
	"github.com/gin-gonic/gin"
)

var (
	uploadLimiterOnce sync.Once
	uploadLimiter     chan struct{}

	supportedUploadMimeTypes = map[string]struct{}{
		"audio/mpeg":      {},
		"audio/mp3":       {},
		"audio/wav":       {},
		"audio/x-wav":     {},
		"audio/wave":      {},
		"audio/flac":      {},
		"audio/x-flac":    {},
		"audio/mp4":       {},
		"audio/x-m4a":     {},
		"audio/aac":       {},
		"audio/x-aac":     {},
		"audio/ogg":       {},
		"application/ogg": {},
		"audio/opus":      {},
		"audio/vorbis":    {},
	}
)

func normalizeMimeType(raw string) string {
	normalized := strings.ToLower(strings.TrimSpace(raw))
	if separator := strings.Index(normalized, ";"); separator >= 0 {
		normalized = strings.TrimSpace(normalized[:separator])
	}
	return normalized
}

func isSupportedUploadMimeType(raw string) bool {
	_, ok := supportedUploadMimeTypes[normalizeMimeType(raw)]
	return ok
}

func linkSongToUserLibrary(db *sql.DB, userID int, songID int) (bool, error) {
	result, err := db.Exec(
		`INSERT INTO user_library (user_id, song_id)
		 VALUES ($1, $2)
		 ON CONFLICT (user_id, song_id) DO NOTHING`,
		userID,
		songID,
	)
	if err != nil {
		return false, err
	}

	rowsAffected, err := result.RowsAffected()
	if err != nil {
		return false, nil
	}

	return rowsAffected > 0, nil
}

func userHasSongInLibrary(db *sql.DB, userID int, songID int) (bool, error) {
	var exists bool
	err := db.QueryRow(
		`SELECT EXISTS(SELECT 1 FROM user_library WHERE user_id = $1 AND song_id = $2)`,
		userID,
		songID,
	).Scan(&exists)
	if err != nil {
		return false, err
	}

	return exists, nil
}

func computeFileSHA256(path string) (string, error) {
	file, err := os.Open(path)
	if err != nil {
		return "", err
	}
	defer file.Close()

	hasher := sha256.New()
	if _, err := io.Copy(hasher, file); err != nil {
		return "", err
	}

	return hex.EncodeToString(hasher.Sum(nil)), nil
}

func getUploadLimiter() chan struct{} {
	uploadLimiterOnce.Do(func() {
		uploadLimiter = make(chan struct{}, resolveMaxParallelUploads())
	})
	return uploadLimiter
}

func tryAcquireUploadSlot() bool {
	select {
	case getUploadLimiter() <- struct{}{}:
		return true
	default:
		return false
	}
}

func releaseUploadSlot() {
	select {
	case <-getUploadLimiter():
	default:
	}
}

// UploadSong handles uploading a new song
func UploadSong(c *gin.Context) {
	startedAt := time.Now()
	var uploadedBytes int64
	uploadSuccess := false
	uploadFailureReason := "unknown"
	defer func() {
		statusCode := c.Writer.Status()
		if uploadSuccess {
			uploadFailureReason = ""
		}
		monitoring.RecordUpload(uploadedBytes, time.Since(startedAt), uploadSuccess, uploadFailureReason, statusCode)
	}()

	userIDInterface, exists := c.Get("user_id")
	if !exists {
		uploadFailureReason = "unauthorized"
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Unauthorized"})
		return
	}

	userID, ok := userIDInterface.(int)
	if !ok {
		uploadFailureReason = "invalid_user_id"
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Invalid user ID"})
		return
	}

	if !tryAcquireUploadSlot() {
		uploadFailureReason = "parallel_upload_limit"
		c.JSON(http.StatusTooManyRequests, gin.H{
			"error": "Too many concurrent uploads. Please retry shortly",
		})
		return
	}
	defer releaseUploadSlot()

	file, header, err := c.Request.FormFile("file")
	if err != nil {
		uploadFailureReason = "file_missing"
		c.JSON(http.StatusBadRequest, gin.H{"error": "File is required"})
		return
	}
	defer file.Close()

	maxUploadBytes := resolveMaxUploadSizeBytes()
	if header.Size > 0 && header.Size > maxUploadBytes {
		uploadFailureReason = "file_too_large"
		c.JSON(http.StatusRequestEntityTooLarge, gin.H{
			"error":            "File is too large",
			"max_upload_bytes": maxUploadBytes,
		})
		return
	}

	buffer := make([]byte, 512)
	bytesRead, err := file.Read(buffer)
	if err != nil && err != io.EOF {
		uploadFailureReason = "file_read_error"
		c.JSON(http.StatusBadRequest, gin.H{"error": "Error reading file"})
		return
	}
	if bytesRead == 0 {
		uploadFailureReason = "file_empty"
		c.JSON(http.StatusBadRequest, gin.H{"error": "File is empty"})
		return
	}

	_, err = file.Seek(0, 0)
	if err != nil {
		uploadFailureReason = "file_seek_error"
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Error resetting file pointer"})
		return
	}

	mimeType := normalizeMimeType(mimetype.Detect(buffer[:bytesRead]).String())
	if !isSupportedUploadMimeType(mimeType) {
		uploadFailureReason = "unsupported_mime"
		c.JSON(http.StatusBadRequest, gin.H{
			"error":           fmt.Sprintf("Unsupported audio format (%s). Allowed: mp3, wav, flac, m4a/mp4, aac, ogg, opus", mimeType),
			"detected_mime":   mimeType,
			"original_name":   header.Filename,
			"allowed_formats": []string{"mp3", "wav", "flac", "m4a", "mp4", "aac", "ogg", "opus"},
		})
		return
	}

	uploadDir := filepath.Join(resolveUploadsBasePath(), "songs")
	if err := os.MkdirAll(uploadDir, 0o755); err != nil {
		uploadFailureReason = "upload_dir_error"
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Error creating upload directory"})
		return
	}

	tempFile, err := os.CreateTemp(uploadDir, ".incoming-*"+filepath.Ext(header.Filename))
	if err != nil {
		uploadFailureReason = "temp_file_create_error"
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Error preparing upload file"})
		return
	}

	tempPath := tempFile.Name()
	defer func() {
		if tempPath != "" {
			_ = os.Remove(tempPath)
		}
	}()

	hasher := sha256.New()
	fileSize, err := io.Copy(io.MultiWriter(tempFile, hasher), file)
	if err != nil {
		_ = tempFile.Close()
		uploadFailureReason = "uploaded_file_read_error"
		c.JSON(http.StatusBadRequest, gin.H{"error": "Error reading uploaded file"})
		return
	}
	if closeErr := tempFile.Close(); closeErr != nil {
		uploadFailureReason = "uploaded_file_finalize_error"
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Error finalizing uploaded file"})
		return
	}
	uploadedBytes = fileSize

	if fileSize <= 0 {
		uploadFailureReason = "file_empty"
		c.JSON(http.StatusBadRequest, gin.H{"error": "File is empty"})
		return
	}
	if fileSize > maxUploadBytes {
		uploadFailureReason = "file_too_large"
		c.JSON(http.StatusRequestEntityTooLarge, gin.H{
			"error":            "File is too large",
			"max_upload_bytes": maxUploadBytes,
		})
		return
	}
	contentHash := hex.EncodeToString(hasher.Sum(nil))

	db := database.DB
	var existingSong models.Song
	existingSongQuery := `
		SELECT id, filename, original_filename, filepath, filesize, mime_type
		FROM songs
		WHERE content_hash = $1
		ORDER BY id ASC
		LIMIT 1
	`
	err = db.QueryRow(existingSongQuery, contentHash).Scan(
		&existingSong.ID,
		&existingSong.Filename,
		&existingSong.OriginalFilename,
		&existingSong.Filepath,
		&existingSong.Filesize,
		&existingSong.MimeType,
	)
	if err == nil {
		alreadyInLibrary, existsErr := userHasSongInLibrary(db, userID, existingSong.ID)
		if existsErr != nil {
			log.Printf("Error checking existing library ownership: %v", existsErr)
			uploadFailureReason = "library_ownership_check_error"
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Error validating song ownership"})
			return
		}
		if !alreadyInLibrary {
			allowed, usedBytes, quotaBytes, quotaErr := canUserStoreAdditionalBytes(db, userID, existingSong.Filesize)
			if quotaErr != nil {
				log.Printf("Error checking user quota before linking existing song: %v", quotaErr)
				uploadFailureReason = "storage_quota_check_error"
				c.JSON(http.StatusInternalServerError, gin.H{"error": "Error checking storage quota"})
				return
			}
			if !allowed {
				uploadFailureReason = "storage_quota_exceeded"
				c.JSON(http.StatusInsufficientStorage, gin.H{
					"error":       "Storage quota exceeded",
					"used_bytes":  usedBytes,
					"quota_bytes": quotaBytes,
				})
				return
			}
		}

		addedToLibrary, linkErr := linkSongToUserLibrary(db, userID, existingSong.ID)
		if linkErr != nil {
			log.Printf("Error linking existing song to user library: %v", linkErr)
			uploadFailureReason = "link_existing_song_error"
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Error linking song to user library"})
			return
		}

		message := "Song already exists on server. Access granted"
		if !addedToLibrary {
			message = "Song already exists in your library"
		}

		uploadSuccess = true
		c.JSON(http.StatusOK, gin.H{
			"message":      message,
			"song_id":      existingSong.ID,
			"deduplicated": true,
			"song": gin.H{
				"id":                existingSong.ID,
				"filename":          existingSong.Filename,
				"original_filename": existingSong.OriginalFilename,
				"filesize":          existingSong.Filesize,
				"mime_type":         existingSong.MimeType,
			},
		})
		return
	}
	if err != sql.ErrNoRows {
		log.Printf("Error checking song deduplication: %v", err)
		uploadFailureReason = "dedupe_lookup_error"
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Error checking existing song"})
		return
	}

	// Fallback for legacy rows where content_hash is still empty.
	legacyRows, err := db.Query(
		`SELECT id, filename, original_filename, filepath, filesize, mime_type, COALESCE(content_hash, '')
		 FROM songs
		 WHERE filesize = $1
		 ORDER BY id ASC`,
		fileSize,
	)
	if err != nil {
		log.Printf("Error loading legacy dedupe candidates: %v", err)
		uploadFailureReason = "legacy_dedupe_query_error"
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Error checking legacy songs"})
		return
	}
	defer legacyRows.Close()

	legacyFound := false
	for legacyRows.Next() {
		var candidate models.Song
		var candidateHash string

		if err := legacyRows.Scan(
			&candidate.ID,
			&candidate.Filename,
			&candidate.OriginalFilename,
			&candidate.Filepath,
			&candidate.Filesize,
			&candidate.MimeType,
			&candidateHash,
		); err != nil {
			log.Printf("Error scanning legacy dedupe candidate: %v", err)
			continue
		}

		if candidateHash == "" {
			computedHash, hashErr := computeFileSHA256(candidate.Filepath)
			if hashErr != nil {
				log.Printf("Error hashing legacy file %s: %v", candidate.Filepath, hashErr)
				continue
			}
			candidateHash = computedHash
			_, _ = db.Exec(`UPDATE songs SET content_hash = $1 WHERE id = $2`, candidateHash, candidate.ID)
		}

		if candidateHash != contentHash {
			continue
		}

		alreadyInLibrary, existsErr := userHasSongInLibrary(db, userID, candidate.ID)
		if existsErr != nil {
			log.Printf("Error checking legacy library ownership: %v", existsErr)
			uploadFailureReason = "legacy_library_ownership_check_error"
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Error validating song ownership"})
			return
		}
		if !alreadyInLibrary {
			allowed, usedBytes, quotaBytes, quotaErr := canUserStoreAdditionalBytes(db, userID, candidate.Filesize)
			if quotaErr != nil {
				log.Printf("Error checking user quota before linking legacy song: %v", quotaErr)
				uploadFailureReason = "storage_quota_check_error"
				c.JSON(http.StatusInternalServerError, gin.H{"error": "Error checking storage quota"})
				return
			}
			if !allowed {
				uploadFailureReason = "storage_quota_exceeded"
				c.JSON(http.StatusInsufficientStorage, gin.H{
					"error":       "Storage quota exceeded",
					"used_bytes":  usedBytes,
					"quota_bytes": quotaBytes,
				})
				return
			}
		}

		addedToLibrary, linkErr := linkSongToUserLibrary(db, userID, candidate.ID)
		if linkErr != nil {
			log.Printf("Error linking legacy song to user library: %v", linkErr)
			uploadFailureReason = "link_existing_song_error"
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Error linking song to user library"})
			return
		}

		message := "Song already exists on server. Access granted"
		if !addedToLibrary {
			message = "Song already exists in your library"
		}

		uploadSuccess = true
		c.JSON(http.StatusOK, gin.H{
			"message":      message,
			"song_id":      candidate.ID,
			"deduplicated": true,
			"song": gin.H{
				"id":                candidate.ID,
				"filename":          candidate.Filename,
				"original_filename": candidate.OriginalFilename,
				"filesize":          candidate.Filesize,
				"mime_type":         candidate.MimeType,
			},
		})
		legacyFound = true
		break
	}
	if legacyFound {
		return
	}
	if err := legacyRows.Err(); err != nil {
		log.Printf("Error iterating legacy dedupe candidates: %v", err)
		uploadFailureReason = "legacy_dedupe_iteration_error"
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Error checking legacy songs"})
		return
	}

	allowed, usedBytes, quotaBytes, quotaErr := canUserStoreAdditionalBytes(db, userID, fileSize)
	if quotaErr != nil {
		log.Printf("Error checking user quota before upload: %v", quotaErr)
		uploadFailureReason = "storage_quota_check_error"
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Error checking storage quota"})
		return
	}
	if !allowed {
		uploadFailureReason = "storage_quota_exceeded"
		c.JSON(http.StatusInsufficientStorage, gin.H{
			"error":       "Storage quota exceeded",
			"used_bytes":  usedBytes,
			"quota_bytes": quotaBytes,
		})
		return
	}

	timestamp := time.Now().UnixNano()
	extension := filepath.Ext(header.Filename)
	uniqueFilename := fmt.Sprintf("%d_%d%s", userID, timestamp, extension)
	filePath := filepath.Join(uploadDir, uniqueFilename)

	if err := os.Rename(tempPath, filePath); err != nil {
		uploadFailureReason = "uploaded_file_move_error"
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Error moving uploaded file"})
		return
	}
	if err := os.Chmod(filePath, 0o644); err != nil {
		log.Printf("Error setting uploaded file permissions: %v", err)
		_ = os.Remove(filePath)
		uploadFailureReason = "uploaded_file_finalize_error"
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Error finalizing uploaded file"})
		return
	}
	tempPath = ""

	song := models.Song{
		Filename:         uniqueFilename,
		OriginalFilename: header.Filename,
		Filepath:         filePath,
		Filesize:         fileSize,
		ContentHash:      &contentHash,
		MimeType:         mimeType,
		UploaderID:       &userID,
		UploadDate:       time.Now(),
	}

	insertSongQuery := `
		INSERT INTO songs (filename, original_filename, filepath, filesize, content_hash, mime_type, uploader_id)
		VALUES ($1, $2, $3, $4, $5, $6, $7)
		RETURNING id
	`

	var songID int
	err = db.QueryRow(
		insertSongQuery,
		song.Filename,
		song.OriginalFilename,
		song.Filepath,
		song.Filesize,
		song.ContentHash,
		song.MimeType,
		song.UploaderID,
	).Scan(&songID)
	if err != nil {
		log.Printf("Error inserting song: %v", err)
		uploadFailureReason = "db_insert_song_error"
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Error saving song"})
		_ = os.Remove(filePath)
		return
	}

	_, err = linkSongToUserLibrary(db, userID, songID)
	if err != nil {
		log.Printf("Error adding song to user library: %v", err)
		uploadFailureReason = "link_uploaded_song_error"
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Error adding song to user library"})
		return
	}

	uploadSuccess = true
	c.JSON(http.StatusOK, gin.H{
		"message": "Song uploaded successfully",
		"song_id": songID,
		"song": gin.H{
			"id":                songID,
			"filename":          song.Filename,
			"original_filename": song.OriginalFilename,
			"filesize":          song.Filesize,
			"mime_type":         song.MimeType,
		},
	})
}

// GetUserLibrary returns user's song library
func GetUserLibrary(c *gin.Context) {
	userIDInterface, exists := c.Get("user_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Unauthorized"})
		return
	}

	// userID already converted to int in middleware
	userID, ok := userIDInterface.(int)
	if !ok {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Invalid user ID"})
		return
	}

	db := database.DB
	params := parseListQueryParams(
		c.Query("limit"),
		c.Query("offset"),
		c.Query("search"),
		defaultPageLimit,
		maxPageLimit,
	)

	countQuery := `
		SELECT COUNT(*)
		FROM songs s
		JOIN user_library ul ON s.id = ul.song_id
		WHERE ul.user_id = $1
		  AND (
			$2 = '' OR
			lower(s.original_filename) LIKE $2 OR
			lower(s.filename) LIKE $2 OR
			lower(COALESCE(s.title, '')) LIKE $2 OR
			lower(COALESCE(s.artist, '')) LIKE $2 OR
			lower(COALESCE(s.album, '')) LIKE $2 OR
			lower(COALESCE(s.genre, '')) LIKE $2
		  )
	`

	var totalCount int
	if err := db.QueryRow(countQuery, userID, params.Pattern).Scan(&totalCount); err != nil {
		log.Printf("Error retrieving user library count: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Error retrieving user library"})
		return
	}

	query := `
		SELECT s.id, s.filename, s.original_filename, s.filesize, s.artist, s.title, s.album, s.genre, s.year, s.mime_type, s.upload_date
		FROM songs s
		JOIN user_library ul ON s.id = ul.song_id
		WHERE ul.user_id = $1
		  AND (
			$2 = '' OR
			lower(s.original_filename) LIKE $2 OR
			lower(s.filename) LIKE $2 OR
			lower(COALESCE(s.title, '')) LIKE $2 OR
			lower(COALESCE(s.artist, '')) LIKE $2 OR
			lower(COALESCE(s.album, '')) LIKE $2 OR
			lower(COALESCE(s.genre, '')) LIKE $2
		  )
		ORDER BY ul.added_at DESC, ul.song_id DESC
		LIMIT $3 OFFSET $4
	`

	rows, err := db.Query(query, userID, params.Pattern, params.Limit, params.Offset)
	if err != nil {
		log.Printf("Error retrieving user library: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Error retrieving user library"})
		return
	}
	defer rows.Close()

	var songs []models.Song
	for rows.Next() {
		var song models.Song
		var artist, title, album, genre sql.NullString
		var year sql.NullInt64

		err := rows.Scan(&song.ID, &song.Filename, &song.OriginalFilename, &song.Filesize,
			&artist, &title, &album, &genre, &year,
			&song.MimeType, &song.UploadDate)
		if err != nil {
			log.Printf("Error scanning song: %v", err)
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Error scanning song"})
			return
		}

		if artist.Valid {
			song.Artist = &artist.String
		}
		if title.Valid {
			song.Title = &title.String
		}
		if album.Valid {
			song.Album = &album.String
		}
		if genre.Valid {
			song.Genre = &genre.String
		}
		if year.Valid {
			yearVal := int(year.Int64)
			song.Year = &yearVal
		}

		songs = append(songs, song)
	}

	pageCount := len(songs)
	c.JSON(http.StatusOK, gin.H{
		"songs":    songs,
		"count":    pageCount,
		"total":    totalCount,
		"limit":    params.Limit,
		"offset":   params.Offset,
		"has_more": params.Offset+pageCount < totalCount,
		"next_offset": func() int {
			if params.Offset+pageCount < totalCount {
				return params.Offset + pageCount
			}
			return -1
		}(),
		"search": params.Search,
	})
}

// GetSongByID returns a specific song by ID
func GetSongByID(c *gin.Context) {
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

	songID, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid song ID"})
		return
	}

	db := database.DB
	var song models.Song

	query := `
		SELECT s.id, s.filename, s.original_filename, s.filesize, s.artist, s.title, s.album, s.genre, s.year, s.mime_type, s.upload_date
		FROM songs s
		JOIN user_library ul ON ul.song_id = s.id
		WHERE s.id = $1 AND ul.user_id = $2
	`

	var artist, title, album, genre sql.NullString
	var year sql.NullInt64

	err = db.QueryRow(query, songID, userID).Scan(&song.ID, &song.Filename, &song.OriginalFilename,
		&song.Filesize, &artist,
		&title, &album, &genre, &year,
		&song.MimeType, &song.UploadDate)

	if err != nil {
		if err == sql.ErrNoRows {
			c.JSON(http.StatusNotFound, gin.H{"error": "Song not found in your library"})
			return
		}
		log.Printf("Error retrieving song: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Error retrieving song"})
		return
	}

	// Устанавливаем значения, если они не равны NULL
	if artist.Valid {
		song.Artist = &artist.String
	}
	if title.Valid {
		song.Title = &title.String
	}
	if album.Valid {
		song.Album = &album.String
	}
	if genre.Valid {
		song.Genre = &genre.String
	}
	if year.Valid {
		yearVal := int(year.Int64)
		song.Year = &yearVal
	}

	c.JSON(http.StatusOK, gin.H{
		"song": gin.H{
			"id":                song.ID,
			"filename":          song.Filename,
			"original_filename": song.OriginalFilename,
			"filesize":          song.Filesize,
			"artist":            song.Artist,
			"title":             song.Title,
			"album":             song.Album,
			"genre":             song.Genre,
			"year":              song.Year,
			"mime_type":         song.MimeType,
			"upload_date":       song.UploadDate,
		},
	})
}

// DeleteSong removes song from user's cloud library and deletes file if unused.
func DeleteSong(c *gin.Context) {
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

	songID, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid song ID"})
		return
	}

	db := database.DB
	tx, err := db.Begin()
	if err != nil {
		log.Printf("Error starting transaction: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Transaction error"})
		return
	}
	defer tx.Rollback()

	var filePath string
	err = tx.QueryRow(
		`SELECT s.filepath
		 FROM songs s
		 JOIN user_library ul ON ul.song_id = s.id
		 WHERE s.id = $1 AND ul.user_id = $2`,
		songID,
		userID,
	).Scan(&filePath)
	if err != nil {
		if err == sql.ErrNoRows {
			c.JSON(http.StatusNotFound, gin.H{"error": "Song not found in your library"})
			return
		}
		log.Printf("Error checking song access: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Error checking song access"})
		return
	}

	_, err = tx.Exec(
		`DELETE FROM playlist_songs ps
		 USING playlists p
		 WHERE ps.playlist_id = p.id AND p.owner_id = $1 AND ps.song_id = $2`,
		userID,
		songID,
	)
	if err != nil {
		log.Printf("Error deleting song from user playlists: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Error deleting song from playlists"})
		return
	}

	_, err = tx.Exec(`DELETE FROM user_library WHERE user_id = $1 AND song_id = $2`, userID, songID)
	if err != nil {
		log.Printf("Error deleting song from user library: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Error deleting song from library"})
		return
	}

	var usageCount int
	err = tx.QueryRow(`SELECT COUNT(*) FROM user_library WHERE song_id = $1`, songID).Scan(&usageCount)
	if err != nil {
		log.Printf("Error checking song usage count: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Error checking song usage"})
		return
	}

	if usageCount == 0 {
		_, err = tx.Exec(`DELETE FROM songs WHERE id = $1`, songID)
		if err != nil {
			log.Printf("Error deleting song record: %v", err)
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Error deleting song"})
			return
		}
	}

	if err := tx.Commit(); err != nil {
		log.Printf("Error committing transaction: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Commit error"})
		return
	}

	if usageCount == 0 {
		if removeErr := os.Remove(filePath); removeErr != nil && !os.IsNotExist(removeErr) {
			log.Printf("Error deleting song file %s: %v", filePath, removeErr)
		}
	}

	c.JSON(http.StatusOK, gin.H{
		"message": "Song deleted successfully",
	})
}

func sanitizeHeaderFilename(name string) string {
	safe := strings.TrimSpace(strings.ReplaceAll(strings.ReplaceAll(name, "\r", ""), "\n", ""))
	safe = strings.ReplaceAll(safe, `"`, "")
	if safe == "" {
		return "file"
	}
	return safe
}

func buildXAccelRedirectPath(songFilePath string) (string, bool) {
	uploadsRoot := filepath.Clean(resolveUploadsBasePath())
	cleanSongPath := filepath.Clean(songFilePath)

	if absRoot, err := filepath.Abs(uploadsRoot); err == nil {
		uploadsRoot = absRoot
	}
	if absSong, err := filepath.Abs(cleanSongPath); err == nil {
		cleanSongPath = absSong
	}

	relative, err := filepath.Rel(uploadsRoot, cleanSongPath)
	if err != nil {
		return "", false
	}
	if relative == "." || strings.HasPrefix(relative, "..") {
		return "", false
	}

	prefix := strings.TrimRight(resolveXAccelPrefix(), "/")
	relative = filepath.ToSlash(relative)
	return prefix + "/" + relative, true
}

// DownloadSong handles downloading a song by ID
func DownloadSong(c *gin.Context) {
	// Получаем ID пользователя из контекста
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

	songID, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid song ID"})
		return
	}

	db := database.DB
	var song models.Song

	// Проверяем, что пользователь имеет доступ к этой песне (через user_library)
	query := `SELECT s.id, s.filename, s.original_filename, s.filepath, s.filesize, s.mime_type, s.upload_date
			  FROM songs s
			  JOIN user_library ul ON s.id = ul.song_id
			  WHERE s.id = $1 AND ul.user_id = $2`

	err = db.QueryRow(query, songID, userID).Scan(&song.ID, &song.Filename, &song.OriginalFilename,
		&song.Filepath, &song.Filesize, &song.MimeType, &song.UploadDate)

	if err != nil {
		if err == sql.ErrNoRows {
			c.JSON(http.StatusForbidden, gin.H{"error": "Access denied to this song"})
			return
		}
		log.Printf("Error retrieving song for download: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Error retrieving song"})
		return
	}

	// Проверяем, что файл существует
	if _, err := os.Stat(song.Filepath); os.IsNotExist(err) {
		log.Printf("File does not exist: %s", song.Filepath)
		c.JSON(http.StatusNotFound, gin.H{"error": "File not found"})
		return
	}

	// Отправляем файл пользователю
	fileName := filepath.Base(song.OriginalFilename)
	if fileName == "." || fileName == string(filepath.Separator) || fileName == "" {
		fileName = song.Filename
	}

	c.Header("X-Content-Type-Options", "nosniff")
	if resolveXAccelEnabled() {
		if internalPath, ok := buildXAccelRedirectPath(song.Filepath); ok {
			contentType := strings.TrimSpace(song.MimeType)
			if contentType == "" {
				contentType = "application/octet-stream"
			}
			c.Header("Content-Type", contentType)
			c.Header("Content-Disposition", fmt.Sprintf(`attachment; filename="%s"`, sanitizeHeaderFilename(fileName)))
			c.Header("X-Accel-Redirect", internalPath)
			c.Status(http.StatusOK)
			return
		}
	}
	c.FileAttachment(song.Filepath, fileName)
}
