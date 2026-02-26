package handlers

import (
	"cloudtune/internal/database"
	"database/sql"
	"errors"
	"log"
	"net/http"
	"os"
	"strconv"
	"strings"

	"github.com/gin-gonic/gin"
	"github.com/lib/pq"
)

type deleteUserSummary struct {
	UserID             int   `json:"user_id"`
	CandidateSongs     int   `json:"candidate_songs"`
	DeletedSongs       int   `json:"deleted_songs"`
	DeletedFiles       int   `json:"deleted_files"`
	FileDeleteErrors   int   `json:"file_delete_errors"`
	DeletedPlaylists   int64 `json:"deleted_playlists"`
	DeletedLibraryRows int64 `json:"deleted_library_rows"`
}

func collectSongCandidates(tx *sql.Tx, userID int) (map[int]string, error) {
	rows, err := tx.Query(
		`SELECT DISTINCT s.id, s.filepath
		 FROM songs s
		 WHERE s.uploader_id = $1
		    OR EXISTS (
				SELECT 1
				FROM user_library ul
				WHERE ul.user_id = $1 AND ul.song_id = s.id
			)`,
		userID,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	out := make(map[int]string)
	for rows.Next() {
		var songID int
		var filePath string
		if scanErr := rows.Scan(&songID, &filePath); scanErr != nil {
			return nil, scanErr
		}
		out[songID] = filePath
	}

	return out, rows.Err()
}

func deleteUnusedCandidateSongs(tx *sql.Tx, candidateSongIDs []int) (map[string]struct{}, int, error) {
	if len(candidateSongIDs) == 0 {
		return map[string]struct{}{}, 0, nil
	}

	rows, err := tx.Query(
		`DELETE FROM songs
		 WHERE id = ANY($1)
		   AND NOT EXISTS (
				SELECT 1
				FROM user_library ul
				WHERE ul.song_id = songs.id
			)
		 RETURNING filepath`,
		pq.Array(candidateSongIDs),
	)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()

	filePaths := make(map[string]struct{})
	deletedSongs := 0
	for rows.Next() {
		var path string
		if scanErr := rows.Scan(&path); scanErr != nil {
			return nil, 0, scanErr
		}
		if strings.TrimSpace(path) != "" {
			filePaths[path] = struct{}{}
		}
		deletedSongs++
	}
	if err := rows.Err(); err != nil {
		return nil, 0, err
	}

	return filePaths, deletedSongs, nil
}

func removeFilesFromDisk(paths map[string]struct{}) (deletedFiles int, deleteErrors int) {
	for filePath := range paths {
		if err := os.Remove(filePath); err != nil {
			if os.IsNotExist(err) {
				continue
			}
			deleteErrors++
			log.Printf("Error deleting file %s: %v", filePath, err)
			continue
		}
		deletedFiles++
	}
	return deletedFiles, deleteErrors
}

func deleteUserAndRelatedData(db *sql.DB, userID int) (deleteUserSummary, error) {
	summary := deleteUserSummary{UserID: userID}

	tx, err := db.Begin()
	if err != nil {
		return summary, err
	}
	defer tx.Rollback()

	var existingUserID int
	if err := tx.QueryRow(`SELECT id FROM users WHERE id = $1`, userID).Scan(&existingUserID); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return summary, sql.ErrNoRows
		}
		return summary, err
	}

	candidatesByID, err := collectSongCandidates(tx, userID)
	if err != nil {
		return summary, err
	}

	candidateSongIDs := make([]int, 0, len(candidatesByID))
	for songID := range candidatesByID {
		candidateSongIDs = append(candidateSongIDs, songID)
	}
	summary.CandidateSongs = len(candidateSongIDs)

	var deletedPlaylists int64
	if err := tx.QueryRow(`SELECT COUNT(*) FROM playlists WHERE owner_id = $1`, userID).Scan(&deletedPlaylists); err != nil {
		return summary, err
	}
	summary.DeletedPlaylists = deletedPlaylists

	var deletedLibraryRows int64
	if err := tx.QueryRow(`SELECT COUNT(*) FROM user_library WHERE user_id = $1`, userID).Scan(&deletedLibraryRows); err != nil {
		return summary, err
	}
	summary.DeletedLibraryRows = deletedLibraryRows

	result, err := tx.Exec(`DELETE FROM users WHERE id = $1`, userID)
	if err != nil {
		return summary, err
	}
	rowsAffected, err := result.RowsAffected()
	if err != nil {
		return summary, err
	}
	if rowsAffected == 0 {
		return summary, sql.ErrNoRows
	}

	filesToDelete, deletedSongs, err := deleteUnusedCandidateSongs(tx, candidateSongIDs)
	if err != nil {
		return summary, err
	}
	summary.DeletedSongs = deletedSongs

	if err := tx.Commit(); err != nil {
		return summary, err
	}

	summary.DeletedFiles, summary.FileDeleteErrors = removeFilesFromDisk(filesToDelete)
	return summary, nil
}

func DeleteProfile(c *gin.Context) {
	userIDInterface, exists := c.Get("user_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Unauthorized"})
		return
	}

	userID, ok := userIDInterface.(int)
	if !ok || userID <= 0 {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Invalid user ID"})
		return
	}

	summary, err := deleteUserAndRelatedData(database.DB, userID)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			c.JSON(http.StatusNotFound, gin.H{"error": "User not found"})
			return
		}
		log.Printf("Error deleting profile for user_id=%d: %v", userID, err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Error deleting profile"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"message": "Profile deleted successfully",
		"summary": summary,
	})
}

func MonitorDeleteUserByEmail(c *gin.Context) {
	if !checkMonitoringToken(c) {
		return
	}

	email := strings.ToLower(strings.TrimSpace(c.Query("email")))
	if email == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "email query parameter is required"})
		return
	}

	var userID int
	if err := database.DB.QueryRow(`SELECT id FROM users WHERE lower(email) = $1`, email).Scan(&userID); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			c.JSON(http.StatusNotFound, gin.H{"error": "User not found"})
			return
		}
		log.Printf("Error finding user by email=%s: %v", email, err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Error looking up user"})
		return
	}

	summary, err := deleteUserAndRelatedData(database.DB, userID)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			c.JSON(http.StatusNotFound, gin.H{"error": "User not found"})
			return
		}
		log.Printf("Error deleting user by monitoring email=%s user_id=%d: %v", email, userID, err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Error deleting user"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"message": "User deleted successfully",
		"email":   email,
		"user_id": strconv.Itoa(userID),
		"summary": summary,
	})
}
