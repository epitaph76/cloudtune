package handlers

import (
	"cloudtune/internal/database"
	"cloudtune/internal/models"
	"database/sql"
	"log"
	"net/http"
	"strconv"
	"strings"

	"github.com/gin-gonic/gin"
)

const (
	defaultFavoritesPlaylistName        = "Liked songs"
	defaultFavoritesPlaylistDescription = "System favorites playlist"
)

func ensureFavoritesPlaylist(userID int) error {
	db := database.DB

	var existingID int
	err := db.QueryRow(
		`SELECT id FROM playlists WHERE owner_id = $1 AND is_favorite = TRUE ORDER BY id ASC LIMIT 1`,
		userID,
	).Scan(&existingID)
	if err == nil {
		return nil
	}
	if err != sql.ErrNoRows {
		return err
	}

	_, err = db.Exec(
		`INSERT INTO playlists (name, description, owner_id, is_public, is_favorite)
		 VALUES ($1, $2, $3, FALSE, TRUE)`,
		defaultFavoritesPlaylistName,
		defaultFavoritesPlaylistDescription,
		userID,
	)
	if err == nil {
		return nil
	}

	// Handle a possible race from another concurrent request.
	return db.QueryRow(
		`SELECT id FROM playlists WHERE owner_id = $1 AND is_favorite = TRUE ORDER BY id ASC LIMIT 1`,
		userID,
	).Scan(&existingID)
}

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
		Name            string  `json:"name"`
		Description     *string `json:"description"`
		IsPublic        *bool   `json:"is_public"`
		IsFavorite      *bool   `json:"is_favorite"`
		ReplaceExisting *bool   `json:"replace_existing"`
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid request body"})
		return
	}

	playlistName := strings.TrimSpace(req.Name)
	isPublic := false
	if req.IsPublic != nil {
		isPublic = *req.IsPublic
	}

	isFavorite := req.IsFavorite != nil && *req.IsFavorite
	replaceExisting := req.ReplaceExisting != nil && *req.ReplaceExisting

	if playlistName == "" && isFavorite {
		playlistName = defaultFavoritesPlaylistName
	}
	if playlistName == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Playlist name is required"})
		return
	}

	db := database.DB

	var existingPlaylistID int
	playlistExists := false

	if isFavorite {
		err := db.QueryRow(
			`SELECT id FROM playlists WHERE owner_id = $1 AND is_favorite = TRUE ORDER BY id ASC LIMIT 1`,
			userID,
		).Scan(&existingPlaylistID)
		if err != nil && err != sql.ErrNoRows {
			log.Printf("Error looking up favorite playlist: %v", err)
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Error checking existing playlist"})
			return
		}
		if err == nil {
			playlistExists = true
		}
	}

	if !playlistExists {
		err := db.QueryRow(
			`SELECT id
			 FROM playlists
			 WHERE owner_id = $1 AND lower(name) = lower($2)
			 ORDER BY id ASC
			 LIMIT 1`,
			userID,
			playlistName,
		).Scan(&existingPlaylistID)
		if err != nil && err != sql.ErrNoRows {
			log.Printf("Error looking up playlist by name: %v", err)
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Error checking existing playlist"})
			return
		}
		if err == nil {
			playlistExists = true
		}
	}

	var playlist models.Playlist
	var description sql.NullString

	if playlistExists {
		tx, err := db.Begin()
		if err != nil {
			log.Printf("Error starting playlist transaction: %v", err)
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Error updating playlist"})
			return
		}
		defer tx.Rollback()

		updateQuery := `
			UPDATE playlists
			SET
				name = $1,
				description = COALESCE($2, description),
				is_public = $3,
				is_favorite = is_favorite OR $4,
				updated_at = CURRENT_TIMESTAMP
			WHERE id = $5
			RETURNING id, name, description, owner_id, is_public, is_favorite, created_at, updated_at
		`
		err = tx.QueryRow(
			updateQuery,
			playlistName,
			req.Description,
			isPublic,
			isFavorite,
			existingPlaylistID,
		).Scan(
			&playlist.ID,
			&playlist.Name,
			&description,
			&playlist.OwnerID,
			&playlist.IsPublic,
			&playlist.IsFavorite,
			&playlist.CreatedAt,
			&playlist.UpdatedAt,
		)
		if err != nil {
			log.Printf("Error updating playlist: %v", err)
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Error updating playlist"})
			return
		}

		if replaceExisting {
			if _, err := tx.Exec(`DELETE FROM playlist_songs WHERE playlist_id = $1`, playlist.ID); err != nil {
				log.Printf("Error clearing existing playlist songs: %v", err)
				c.JSON(http.StatusInternalServerError, gin.H{"error": "Error replacing playlist songs"})
				return
			}
		}

		if err := tx.Commit(); err != nil {
			log.Printf("Error committing playlist transaction: %v", err)
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Error updating playlist"})
			return
		}
	} else {
		insertQuery := `
			INSERT INTO playlists (name, description, owner_id, is_public, is_favorite)
			VALUES ($1, $2, $3, $4, $5)
			RETURNING id, name, description, owner_id, is_public, is_favorite, created_at, updated_at
		`
		err := db.QueryRow(
			insertQuery,
			playlistName,
			req.Description,
			userID,
			isPublic,
			isFavorite,
		).Scan(
			&playlist.ID,
			&playlist.Name,
			&description,
			&playlist.OwnerID,
			&playlist.IsPublic,
			&playlist.IsFavorite,
			&playlist.CreatedAt,
			&playlist.UpdatedAt,
		)
		if err != nil {
			log.Printf("Error creating playlist: %v", err)
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Error creating playlist"})
			return
		}
	}

	if description.Valid {
		playlist.Description = &description.String
	}

	message := "Playlist created successfully"
	if playlistExists {
		message = "Playlist updated successfully"
	}

	c.JSON(http.StatusOK, gin.H{
		"message":     message,
		"playlist_id": playlist.ID,
		"created":     !playlistExists,
		"playlist": gin.H{
			"id":          playlist.ID,
			"name":        playlist.Name,
			"description": playlist.Description,
			"is_public":   playlist.IsPublic,
			"is_favorite": playlist.IsFavorite,
			"owner_id":    playlist.OwnerID,
			"created_at":  playlist.CreatedAt,
			"updated_at":  playlist.UpdatedAt,
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

	if err := ensureFavoritesPlaylist(userID); err != nil {
		log.Printf("Error ensuring favorites playlist: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Error ensuring favorites playlist"})
		return
	}

	countQuery := `
		SELECT COUNT(*)
		FROM playlists p
		WHERE p.owner_id = $1
		  AND (
			$2 = '' OR
			lower(p.name) LIKE $2 OR
			lower(COALESCE(p.description, '')) LIKE $2
		  )
	`

	var totalCount int
	if err := db.QueryRow(countQuery, userID, params.Pattern).Scan(&totalCount); err != nil {
		log.Printf("Error retrieving playlists count: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Error retrieving playlists"})
		return
	}

	query := `
		SELECT p.id, p.name, p.description, p.owner_id, p.is_public, p.is_favorite, p.created_at, p.updated_at,
		       COUNT(ps.song_id)::int AS song_count
		FROM playlists p
		LEFT JOIN playlist_songs ps ON ps.playlist_id = p.id
		WHERE p.owner_id = $1
		  AND (
			$2 = '' OR
			lower(p.name) LIKE $2 OR
			lower(COALESCE(p.description, '')) LIKE $2
		  )
		GROUP BY p.id, p.name, p.description, p.owner_id, p.is_public, p.is_favorite, p.created_at, p.updated_at
		ORDER BY p.is_favorite DESC, p.created_at DESC, p.id DESC
		LIMIT $3 OFFSET $4
	`

	rows, err := db.Query(query, userID, params.Pattern, params.Limit, params.Offset)
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
			&playlist.IsFavorite,
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

	pageCount := len(playlists)
	c.JSON(http.StatusOK, gin.H{
		"playlists": playlists,
		"count":     pageCount,
		"total":     totalCount,
		"limit":     params.Limit,
		"offset":    params.Offset,
		"has_more":  params.Offset+pageCount < totalCount,
		"next_offset": func() int {
			if params.Offset+pageCount < totalCount {
				return params.Offset + pageCount
			}
			return -1
		}(),
		"search": params.Search,
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
	var isFavorite bool
	checkQuery := `SELECT owner_id, is_favorite FROM playlists WHERE id = $1`
	err = db.QueryRow(checkQuery, playlistID).Scan(&ownerID, &isFavorite)
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

	if isFavorite {
		c.JSON(http.StatusBadRequest, gin.H{"error": "System favorites playlist cannot be deleted"})
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

	// userID already converted to int in middleware
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

	params := parseListQueryParams(
		c.Query("limit"),
		c.Query("offset"),
		c.Query("search"),
		defaultPageLimit,
		maxPageLimit,
	)

	// Check that the user can access the playlist (owner or public).
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

	if ownerID != userID && !isPublic {
		c.JSON(http.StatusForbidden, gin.H{"error": "You don't have permission to view this playlist"})
		return
	}

	countQuery := `
		SELECT COUNT(*)
		FROM songs s
		JOIN playlist_songs ps ON s.id = ps.song_id
		WHERE ps.playlist_id = $1
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
	if err := db.QueryRow(countQuery, playlistID, params.Pattern).Scan(&totalCount); err != nil {
		log.Printf("Error retrieving playlist songs count: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Error retrieving playlist songs"})
		return
	}

	songsQuery := `
		SELECT s.id, s.filename, s.original_filename, s.filesize, s.artist, s.title, s.album, s.genre, s.year, s.mime_type, s.upload_date, ps.position
		FROM songs s
		JOIN playlist_songs ps ON s.id = ps.song_id
		WHERE ps.playlist_id = $1
		  AND (
			$2 = '' OR
			lower(s.original_filename) LIKE $2 OR
			lower(s.filename) LIKE $2 OR
			lower(COALESCE(s.title, '')) LIKE $2 OR
			lower(COALESCE(s.artist, '')) LIKE $2 OR
			lower(COALESCE(s.album, '')) LIKE $2 OR
			lower(COALESCE(s.genre, '')) LIKE $2
		  )
		ORDER BY ps.position ASC
		LIMIT $3 OFFSET $4
	`

	rows, err := db.Query(songsQuery, playlistID, params.Pattern, params.Limit, params.Offset)
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
