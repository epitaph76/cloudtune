package handlers

import (
	"cloudtune/internal/database"
	"cloudtune/internal/models"
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
	"time"

	"github.com/gabriel-vasile/mimetype"
	"github.com/gin-gonic/gin"
)

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

// UploadSong handles uploading a new song
func UploadSong(c *gin.Context) {
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

	file, header, err := c.Request.FormFile("file")
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "File is required"})
		return
	}
	defer file.Close()

	maxUploadBytes := resolveMaxUploadSizeBytes()
	if header.Size > 0 && header.Size > maxUploadBytes {
		c.JSON(http.StatusRequestEntityTooLarge, gin.H{
			"error":            "File is too large",
			"max_upload_bytes": maxUploadBytes,
		})
		return
	}

	buffer := make([]byte, 512)
	bytesRead, err := file.Read(buffer)
	if err != nil && err != io.EOF {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Error reading file"})
		return
	}
	if bytesRead == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "File is empty"})
		return
	}

	_, err = file.Seek(0, 0)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Error resetting file pointer"})
		return
	}

	mimeType := mimetype.Detect(buffer[:bytesRead]).String()
	if mimeType != "audio/mpeg" && mimeType != "audio/wav" && mimeType != "audio/mp4" && mimeType != "audio/flac" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Only audio files (MP3, WAV, MP4, FLAC) are allowed"})
		return
	}

	// Hash the content first. If the song already exists on server, only grant access.
	hasher := sha256.New()
	fileSize, err := io.Copy(hasher, file)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Error reading file for deduplication"})
		return
	}
	if fileSize <= 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "File is empty"})
		return
	}
	if fileSize > maxUploadBytes {
		c.JSON(http.StatusRequestEntityTooLarge, gin.H{
			"error":            "File is too large",
			"max_upload_bytes": maxUploadBytes,
		})
		return
	}
	contentHash := hex.EncodeToString(hasher.Sum(nil))

	_, err = file.Seek(0, 0)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Error resetting file pointer"})
		return
	}

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
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Error validating song ownership"})
			return
		}
		if !alreadyInLibrary {
			allowed, usedBytes, quotaBytes, quotaErr := canUserStoreAdditionalBytes(db, userID, existingSong.Filesize)
			if quotaErr != nil {
				log.Printf("Error checking user quota before linking existing song: %v", quotaErr)
				c.JSON(http.StatusInternalServerError, gin.H{"error": "Error checking storage quota"})
				return
			}
			if !allowed {
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
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Error linking song to user library"})
			return
		}

		message := "Song already exists on server. Access granted"
		if !addedToLibrary {
			message = "Song already exists in your library"
		}

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
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Error validating song ownership"})
			return
		}
		if !alreadyInLibrary {
			allowed, usedBytes, quotaBytes, quotaErr := canUserStoreAdditionalBytes(db, userID, candidate.Filesize)
			if quotaErr != nil {
				log.Printf("Error checking user quota before linking legacy song: %v", quotaErr)
				c.JSON(http.StatusInternalServerError, gin.H{"error": "Error checking storage quota"})
				return
			}
			if !allowed {
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
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Error linking song to user library"})
			return
		}

		message := "Song already exists on server. Access granted"
		if !addedToLibrary {
			message = "Song already exists in your library"
		}

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
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Error checking legacy songs"})
		return
	}

	allowed, usedBytes, quotaBytes, quotaErr := canUserStoreAdditionalBytes(db, userID, fileSize)
	if quotaErr != nil {
		log.Printf("Error checking user quota before upload: %v", quotaErr)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Error checking storage quota"})
		return
	}
	if !allowed {
		c.JSON(http.StatusInsufficientStorage, gin.H{
			"error":       "Storage quota exceeded",
			"used_bytes":  usedBytes,
			"quota_bytes": quotaBytes,
		})
		return
	}

	uploadDir := filepath.Join(resolveUploadsBasePath(), "songs")
	err = os.MkdirAll(uploadDir, 0o755)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Error creating upload directory"})
		return
	}

	timestamp := time.Now().UnixNano()
	extension := filepath.Ext(header.Filename)
	uniqueFilename := fmt.Sprintf("%d_%d%s", userID, timestamp, extension)
	filePath := filepath.Join(uploadDir, uniqueFilename)

	out, err := os.Create(filePath)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Error saving file"})
		return
	}
	defer out.Close()

	if _, err = io.Copy(out, file); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Error copying file"})
		return
	}

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
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Error saving song"})
		_ = os.Remove(filePath)
		return
	}

	_, err = linkSongToUserLibrary(db, userID, songID)
	if err != nil {
		log.Printf("Error adding song to user library: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Error adding song to user library"})
		return
	}

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

	// userID уже преобразован в int в middleware
	userID, ok := userIDInterface.(int)
	if !ok {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Invalid user ID"})
		return
	}

	db := database.DB

	// Получаем песни из библиотеки пользователя
	query := `
		SELECT s.id, s.filename, s.original_filename, s.filesize, s.artist, s.title, s.album, s.genre, s.year, s.mime_type, s.upload_date
		FROM songs s
		JOIN user_library ul ON s.id = ul.song_id
		WHERE ul.user_id = $1
		ORDER BY ul.added_at DESC
	`

	rows, err := db.Query(query, userID)
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

		songs = append(songs, song)
	}

	c.JSON(http.StatusOK, gin.H{
		"songs": songs,
		"count": len(songs),
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
	c.FileAttachment(song.Filepath, fileName)
}
