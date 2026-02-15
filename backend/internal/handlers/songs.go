package handlers

import (
	"cloudtune/internal/database"
	"cloudtune/internal/models"
	"database/sql"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/gabriel-vasile/mimetype"
)

// UploadSong handles uploading a new song
func UploadSong(c *gin.Context) {
	// Получаем ID пользователя из контекста
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

	// Получаем загруженный файл
	file, header, err := c.Request.FormFile("file")
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "File is required"})
		return
	}
	defer file.Close()

	// Проверяем тип файла
	buffer := make([]byte, 512)
	_, err = file.Read(buffer)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Error reading file"})
		return
	}

	// Сбросим указатель файла обратно к началу
	_, err = file.Seek(0, 0)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Error resetting file pointer"})
		return
	}

	mimeType := mimetype.Detect(buffer).String()
	if mimeType != "audio/mpeg" && mimeType != "audio/wav" && mimeType != "audio/mp4" && mimeType != "audio/flac" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Only audio files (MP3, WAV, MP4, FLAC) are allowed"})
		return
	}

	// Создаем директорию для хранения файлов, если не существует
	uploadDir := "./uploads/songs/"
	err = os.MkdirAll(uploadDir, os.ModePerm)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Error creating upload directory"})
		return
	}

	// Генерируем уникальное имя файла
	timestamp := time.Now().Unix()
	extension := filepath.Ext(header.Filename)
	uniqueFilename := fmt.Sprintf("%d_%d%s", userID, timestamp, extension)
	filePath := filepath.Join(uploadDir, uniqueFilename)

	// Сохраняем файл на диск
	out, err := os.Create(filePath)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Error saving file"})
		return
	}
	defer out.Close()

	_, err = io.Copy(out, file)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Error copying file"})
		return
	}

	// Сохраняем информацию о песне в базе данных
	song := models.Song{
		Filename:         uniqueFilename,
		OriginalFilename: header.Filename,
		Filepath:         filePath,
		Filesize:         header.Size,
		MimeType:         mimeType,
		UploaderID:       &userID,
		UploadDate:       time.Now(),
	}

	// Вставка в базу данных
	db := database.DB
	query := `INSERT INTO songs (filename, original_filename, filepath, filesize, mime_type, uploader_id) 
			  VALUES ($1, $2, $3, $4, $5, $6) RETURNING id`
	
	var songID int
	err = db.QueryRow(query, song.Filename, song.OriginalFilename, song.Filepath, 
					 song.Filesize, song.MimeType, song.UploaderID).Scan(&songID)
	
	if err != nil {
		log.Printf("Error inserting song: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Error saving song"})
		// Удаляем файл, если не удалось сохранить в базу
		os.Remove(filePath)
		return
	}

	// Добавляем песню в библиотеку пользователя
	addToUserLibraryQuery := `INSERT INTO user_library (user_id, song_id) VALUES ($1, $2)`
	_, err = db.Exec(addToUserLibraryQuery, userID, songID)
	if err != nil {
		log.Printf("Error adding song to user library: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Error adding song to user library"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"message": "Song uploaded successfully",
		"song_id": songID,
		"song": gin.H{
			"id":               songID,
			"filename":         song.Filename,
			"original_filename": song.OriginalFilename,
			"filesize":         song.Filesize,
			"mime_type":        song.MimeType,
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
	songID, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid song ID"})
		return
	}

	db := database.DB
	var song models.Song
	
	query := `SELECT id, filename, original_filename, filepath, filesize, artist, title, album, genre, year, mime_type, upload_date 
			  FROM songs WHERE id = $1`
	
	var artist, title, album, genre sql.NullString
	var year sql.NullInt64
	
	err = db.QueryRow(query, songID).Scan(&song.ID, &song.Filename, &song.OriginalFilename, 
										  &song.Filepath, &song.Filesize, &artist, 
										  &title, &album, &genre, &year, 
										  &song.MimeType, &song.UploadDate)
	
	if err != nil {
		log.Printf("Error retrieving song: %v", err)
		c.JSON(http.StatusNotFound, gin.H{"error": "Song not found"})
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

	c.JSON(http.StatusOK, gin.H{"song": song})
}