package handlers

import (
	"cloudtune/internal/database"
	"database/sql"
	"log"
	"net/http"
	"strconv"
	"strings"

	"github.com/gin-gonic/gin"
	"github.com/lib/pq"
)

type addSongsToPlaylistBulkRequest struct {
	SongIDs []int `json:"song_ids"`
}

func normalizeUniqueSongIDs(raw []int) []int {
	out := make([]int, 0, len(raw))
	seen := make(map[int]struct{}, len(raw))
	for _, id := range raw {
		if id <= 0 {
			continue
		}
		if _, exists := seen[id]; exists {
			continue
		}
		seen[id] = struct{}{}
		out = append(out, id)
	}
	return out
}

func verifyPlaylistOwner(db *sql.DB, playlistID int, userID int) (bool, error) {
	var ownerID int
	err := db.QueryRow(`SELECT owner_id FROM playlists WHERE id = $1`, playlistID).Scan(&ownerID)
	if err != nil {
		if err == sql.ErrNoRows {
			return false, nil
		}
		return false, err
	}
	return ownerID == userID, nil
}

func fetchAllowedSongIDsInOrder(db *sql.DB, userID int, uniqueSongIDs []int) ([]int, error) {
	if len(uniqueSongIDs) == 0 {
		return []int{}, nil
	}

	rows, err := db.Query(
		`SELECT song_id FROM user_library WHERE user_id = $1 AND song_id = ANY($2)`,
		userID,
		pq.Array(uniqueSongIDs),
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	allowedSet := make(map[int]struct{}, len(uniqueSongIDs))
	for rows.Next() {
		var songID int
		if scanErr := rows.Scan(&songID); scanErr != nil {
			return nil, scanErr
		}
		allowedSet[songID] = struct{}{}
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}

	allowedInOrder := make([]int, 0, len(allowedSet))
	for _, songID := range uniqueSongIDs {
		if _, ok := allowedSet[songID]; ok {
			allowedInOrder = append(allowedInOrder, songID)
		}
	}
	return allowedInOrder, nil
}

func fetchExistingPlaylistSongIDs(db *sql.DB, playlistID int, songIDs []int) (map[int]struct{}, error) {
	out := make(map[int]struct{})
	if len(songIDs) == 0 {
		return out, nil
	}

	rows, err := db.Query(
		`SELECT song_id FROM playlist_songs WHERE playlist_id = $1 AND song_id = ANY($2)`,
		playlistID,
		pq.Array(songIDs),
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	for rows.Next() {
		var songID int
		if scanErr := rows.Scan(&songID); scanErr != nil {
			return nil, scanErr
		}
		out[songID] = struct{}{}
	}

	if err := rows.Err(); err != nil {
		return nil, err
	}

	return out, nil
}

func AddSongsToPlaylistBulk(c *gin.Context) {
	userIDValue, exists := c.Get("user_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Unauthorized"})
		return
	}
	userID, ok := userIDValue.(int)
	if !ok {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Invalid user ID"})
		return
	}

	playlistID, err := strconv.Atoi(strings.TrimSpace(c.Param("playlist_id")))
	if err != nil || playlistID <= 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid playlist ID"})
		return
	}

	var req addSongsToPlaylistBulkRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid request body"})
		return
	}

	uniqueSongIDs := normalizeUniqueSongIDs(req.SongIDs)
	if len(uniqueSongIDs) == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "song_ids must contain at least one positive integer"})
		return
	}

	db := database.DB

	isOwner, ownerErr := verifyPlaylistOwner(db, playlistID, userID)
	if ownerErr != nil {
		log.Printf("Error validating playlist owner: %v", ownerErr)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Error validating playlist owner"})
		return
	}
	if !isOwner {
		c.JSON(http.StatusForbidden, gin.H{"error": "You don't have permission to modify this playlist"})
		return
	}

	allowedInOrder, err := fetchAllowedSongIDsInOrder(db, userID, uniqueSongIDs)
	if err != nil {
		log.Printf("Error loading allowed songs for bulk add: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Error validating songs ownership"})
		return
	}

	if len(allowedInOrder) == 0 {
		c.JSON(http.StatusForbidden, gin.H{"error": "None of the songs belong to your library"})
		return
	}

	existingSet, err := fetchExistingPlaylistSongIDs(db, playlistID, allowedInOrder)
	if err != nil {
		log.Printf("Error loading existing playlist songs for bulk add: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Error loading existing playlist songs"})
		return
	}

	toInsert := make([]int, 0, len(allowedInOrder))
	for _, songID := range allowedInOrder {
		if _, exists := existingSet[songID]; exists {
			continue
		}
		toInsert = append(toInsert, songID)
	}

	addedCount := 0
	firstPosition := 0
	lastPosition := 0

	if len(toInsert) > 0 {
		tx, err := db.Begin()
		if err != nil {
			log.Printf("Error starting bulk add transaction: %v", err)
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Error creating transaction"})
			return
		}
		defer tx.Rollback()

		if _, err := tx.Exec(`SELECT id FROM playlists WHERE id = $1 FOR UPDATE`, playlistID); err != nil {
			log.Printf("Error locking playlist for bulk add: %v", err)
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Error locking playlist"})
			return
		}

		var maxPosition int
		if err := tx.QueryRow(
			`SELECT COALESCE(MAX(position), 0) FROM playlist_songs WHERE playlist_id = $1`,
			playlistID,
		).Scan(&maxPosition); err != nil {
			log.Printf("Error loading max playlist position: %v", err)
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Error loading playlist position"})
			return
		}

		insertRows, err := tx.Query(
			`WITH input AS (
				SELECT * FROM unnest($1::int[]) WITH ORDINALITY AS t(song_id, ord)
			  )
			  INSERT INTO playlist_songs (playlist_id, song_id, position)
			  SELECT $2, input.song_id, $3 + ROW_NUMBER() OVER (ORDER BY input.ord)
			  FROM input
			  ORDER BY input.ord
			  RETURNING position`,
			pq.Array(toInsert),
			playlistID,
			maxPosition,
		)
		if err != nil {
			log.Printf("Error inserting songs into playlist in bulk: %v", err)
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Error adding songs to playlist"})
			return
		}
		defer insertRows.Close()

		positions := make([]int, 0, len(toInsert))
		for insertRows.Next() {
			var pos int
			if scanErr := insertRows.Scan(&pos); scanErr != nil {
				log.Printf("Error scanning inserted playlist position: %v", scanErr)
				c.JSON(http.StatusInternalServerError, gin.H{"error": "Error reading inserted rows"})
				return
			}
			positions = append(positions, pos)
		}
		if err := insertRows.Err(); err != nil {
			log.Printf("Error iterating inserted playlist positions: %v", err)
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Error finalizing inserted rows"})
			return
		}

		addedCount = len(positions)
		if addedCount > 0 {
			firstPosition = positions[0]
			lastPosition = positions[len(positions)-1]
		}

		if err := tx.Commit(); err != nil {
			log.Printf("Error committing bulk add transaction: %v", err)
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Error committing changes"})
			return
		}
	}

	skippedNotOwned := len(uniqueSongIDs) - len(allowedInOrder)
	skippedExisting := len(allowedInOrder) - len(toInsert)

	c.JSON(http.StatusOK, gin.H{
		"message":                "Songs processed successfully",
		"requested_count":        len(req.SongIDs),
		"unique_count":           len(uniqueSongIDs),
		"allowed_count":          len(allowedInOrder),
		"added_count":            addedCount,
		"skipped_not_in_library": skippedNotOwned,
		"skipped_existing":       skippedExisting,
		"first_position":         firstPosition,
		"last_position":          lastPosition,
	})
}
