package handlers

import (
	"cloudtune/internal/database"
	"cloudtune/internal/models"
	"database/sql"
	"log"
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"
)

// CreatePlaylist creates a new playlist
func CreatePlaylist(c *gin.Context) {
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

	var req struct {
		Name        string  `json:"name" binding:"required"`
		Description *string `json:"description"`
		IsPublic    *bool   `json:"is_public"`
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid request body"})
		return
	}

	isPublic := false
	if req.IsPublic != nil {
		isPublic = *req.IsPublic
	}

	db := database.DB
	query := `INSERT INTO playlists (name, description, owner_id, is_public) 
			  VALUES ($1, $2, $3, $4) RETURNING id`
	
	var playlistID int
	err := db.QueryRow(query, req.Name, req.Description, userID, isPublic).Scan(&playlistID)
	if err != nil {
		log.Printf("Error creating playlist: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Error creating playlist"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"message":     "Playlist created successfully",
		"playlist_id": playlistID,
		"playlist": gin.H{
			"id":          playlistID,
			"name":        req.Name,
			"description": req.Description,
			"is_public":   isPublic,
			"owner_id":    userID,
		},
	})
}

// GetUserPlaylists returns user's playlists
func GetUserPlaylists(c *gin.Context) {
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
	
	query := `
		SELECT p.id, p.name, p.description, p.owner_id, p.is_public, p.created_at, p.updated_at,
		       COUNT(ps.song_id)::int AS song_count
		FROM playlists p
		LEFT JOIN playlist_songs ps ON ps.playlist_id = p.id
		WHERE p.owner_id = $1
		GROUP BY p.id, p.name, p.description, p.owner_id, p.is_public, p.created_at, p.updated_at
		ORDER BY p.created_at DESC
	`
	
	rows, err := db.Query(query, userID)
	if err != nil {
		log.Printf("Error retrieving playlists: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Error retrieving playlists"})
		return
	}
	defer rows.Close()

	playlists := make([]models.Playlist, 0)
	for rows.Next() {
		var playlist models.Playlist
		var description sql.NullString
		var songCount int
		
		err := rows.Scan(
			&playlist.ID,
			&playlist.Name,
			&description,
			&playlist.OwnerID,
			&playlist.IsPublic,
			&playlist.CreatedAt,
			&playlist.UpdatedAt,
			&songCount,
		)
		if err != nil {
			log.Printf("Error scanning playlist: %v", err)
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Error scanning playlist"})
			return
		}
		
		if description.Valid {
			playlist.Description = &description.String
		}
		playlist.SongCount = &songCount
		
		playlists = append(playlists, playlist)
	}

	c.JSON(http.StatusOK, gin.H{
		"playlists": playlists,
		"count":     len(playlists),
	})
}

// DeletePlaylist deletes user's playlist by id
func DeletePlaylist(c *gin.Context) {
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

	playlistID, err := strconv.Atoi(c.Param("playlist_id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid playlist ID"})
		return
	}

	db := database.DB

	var ownerID int
	checkQuery := `SELECT owner_id FROM playlists WHERE id = $1`
	err = db.QueryRow(checkQuery, playlistID).Scan(&ownerID)
	if err != nil {
		if err == sql.ErrNoRows {
			c.JSON(http.StatusNotFound, gin.H{"error": "Playlist not found"})
			return
		}
		log.Printf("Error checking playlist owner: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Error checking playlist"})
		return
	}

	if ownerID != userID {
		c.JSON(http.StatusForbidden, gin.H{"error": "You don't have permission to delete this playlist"})
		return
	}

	_, err = db.Exec(`DELETE FROM playlists WHERE id = $1`, playlistID)
	if err != nil {
		log.Printf("Error deleting playlist: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Error deleting playlist"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"message": "Playlist deleted successfully",
	})
}

// AddSongToPlaylist adds a song to a playlist
func AddSongToPlaylist(c *gin.Context) {
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

	playlistID, err := strconv.Atoi(c.Param("playlist_id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid playlist ID"})
		return
	}

	songID, err := strconv.Atoi(c.Param("song_id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid song ID"})
		return
	}

	// Проверяем, что пользователь является владельцем плейлиста
	db := database.DB
	var ownerID int
	query := `SELECT owner_id FROM playlists WHERE id = $1`
	err = db.QueryRow(query, playlistID).Scan(&ownerID)
	if err != nil {
		if err == sql.ErrNoRows {
			c.JSON(http.StatusNotFound, gin.H{"error": "Playlist not found"})
		} else {
			log.Printf("Error retrieving playlist owner: %v", err)
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Error retrieving playlist"})
		}
		return
	}

	if ownerID != userID {
		c.JSON(http.StatusForbidden, gin.H{"error": "You don't have permission to modify this playlist"})
		return
	}

	// Проверяем, что песня принадлежит пользователю или плейлист публичный
	var userHasSong bool
	checkSongQuery := `SELECT COUNT(*) > 0 FROM user_library WHERE user_id = $1 AND song_id = $2`
	err = db.QueryRow(checkSongQuery, userID, songID).Scan(&userHasSong)
	if err != nil {
		log.Printf("Error checking if user has song: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Error checking song ownership"})
		return
	}

	if !userHasSong {
		c.JSON(http.StatusForbidden, gin.H{"error": "You don't have permission to add this song to a playlist"})
		return
	}

	// Получаем максимальную позицию в плейлисте
	var maxPosition sql.NullInt64
	posQuery := `SELECT MAX(position) FROM playlist_songs WHERE playlist_id = $1`
	err = db.QueryRow(posQuery, playlistID).Scan(&maxPosition)
	if err != nil {
		log.Printf("Error getting playlist position: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Error getting playlist position"})
		return
	}

	newPosition := 1
	if maxPosition.Valid {
		newPosition = int(maxPosition.Int64) + 1
	}

	// Проверяем, что песня еще не добавлена в этот плейлист
	var existingCount int
	countQuery := `SELECT COUNT(*) FROM playlist_songs WHERE playlist_id = $1 AND song_id = $2`
	err = db.QueryRow(countQuery, playlistID, songID).Scan(&existingCount)
	if err != nil {
		log.Printf("Error checking if song exists in playlist: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Error checking if song exists in playlist"})
		return
	}

	if existingCount > 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Song already exists in this playlist"})
		return
	}

	// Добавляем песню в плейлист
	insertQuery := `INSERT INTO playlist_songs (playlist_id, song_id, position) VALUES ($1, $2, $3)`
	_, err = db.Exec(insertQuery, playlistID, songID, newPosition)
	if err != nil {
		log.Printf("Error adding song to playlist: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Error adding song to playlist"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"message":  "Song added to playlist successfully",
		"position": newPosition,
	})
}

// GetPlaylistSongs returns all songs in a specific playlist
func GetPlaylistSongs(c *gin.Context) {
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

	playlistID, err := strconv.Atoi(c.Param("playlist_id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid playlist ID"})
		return
	}

	// Проверяем, что пользователь имеет доступ к плейлисту (владелец или публичный)
	db := database.DB
	var ownerID int
	var isPublic bool
	query := `SELECT owner_id, is_public FROM playlists WHERE id = $1`
	err = db.QueryRow(query, playlistID).Scan(&ownerID, &isPublic)
	if err != nil {
		if err == sql.ErrNoRows {
			c.JSON(http.StatusNotFound, gin.H{"error": "Playlist not found"})
		} else {
			log.Printf("Error retrieving playlist: %v", err)
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Error retrieving playlist"})
		}
		return
	}

	// Пользователь должен быть владельцем или плейлист должен быть публичным
	if ownerID != userID && !isPublic {
		c.JSON(http.StatusForbidden, gin.H{"error": "You don't have permission to view this playlist"})
		return
	}

	// Получаем песни из плейлиста
	songsQuery := `
		SELECT s.id, s.filename, s.original_filename, s.filesize, s.artist, s.title, s.album, s.genre, s.year, s.mime_type, s.upload_date, ps.position
		FROM songs s
		JOIN playlist_songs ps ON s.id = ps.song_id
		WHERE ps.playlist_id = $1
		ORDER BY ps.position ASC
	`

	rows, err := db.Query(songsQuery, playlistID)
	if err != nil {
		log.Printf("Error retrieving playlist songs: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Error retrieving playlist songs"})
		return
	}
	defer rows.Close()

	type PlaylistSongWithDetails struct {
		models.Song
		Position int `json:"position"`
	}
	
	var songs []PlaylistSongWithDetails
	for rows.Next() {
		var song PlaylistSongWithDetails
		var artist, title, album, genre sql.NullString
		var year sql.NullInt64
		
		err := rows.Scan(&song.ID, &song.Filename, &song.OriginalFilename, &song.Filesize, 
						 &artist, &title, &album, &genre, &year, 
						 &song.MimeType, &song.UploadDate, &song.Position)
		if err != nil {
			log.Printf("Error scanning playlist song: %v", err)
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Error scanning playlist song"})
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
