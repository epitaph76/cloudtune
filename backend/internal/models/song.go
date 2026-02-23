package models

import (
	"time"
)

type Song struct {
	ID               int       `json:"id" db:"id"`
	Filename         string    `json:"filename" db:"filename"`
	OriginalFilename string    `json:"original_filename" db:"original_filename"`
	Filepath         string    `json:"filepath" db:"filepath"`
	Filesize         int64     `json:"filesize" db:"filesize"`
	ContentHash      *string   `json:"content_hash,omitempty" db:"content_hash"`
	Duration         *int      `json:"duration,omitempty" db:"duration"`
	Artist           *string   `json:"artist,omitempty" db:"artist"`
	Title            *string   `json:"title,omitempty" db:"title"`
	Album            *string   `json:"album,omitempty" db:"album"`
	Genre            *string   `json:"genre,omitempty" db:"genre"`
	Year             *int      `json:"year,omitempty" db:"year"`
	MimeType         string    `json:"mime_type" db:"mime_type"`
	UploadDate       time.Time `json:"upload_date" db:"upload_date"`
	UploaderID       *int      `json:"uploader_id,omitempty" db:"uploader_id"`
}

type Playlist struct {
	ID          int       `json:"id" db:"id"`
	Name        string    `json:"name" db:"name"`
	Description *string   `json:"description,omitempty" db:"description"`
	OwnerID     int       `json:"owner_id" db:"owner_id"`
	IsPublic    bool      `json:"is_public" db:"is_public"`
	IsFavorite  bool      `json:"is_favorite" db:"is_favorite"`
	CreatedAt   time.Time `json:"created_at" db:"created_at"`
	UpdatedAt   time.Time `json:"updated_at" db:"updated_at"`
	SongCount   *int      `json:"song_count,omitempty" db:"song_count"`
}

type PlaylistSong struct {
	ID         int       `json:"id" db:"id"`
	PlaylistID int       `json:"playlist_id" db:"playlist_id"`
	SongID     int       `json:"song_id" db:"song_id"`
	Position   int       `json:"position" db:"position"`
	AddedAt    time.Time `json:"added_at" db:"added_at"`
}

type UserLibrary struct {
	ID      int       `json:"id" db:"id"`
	UserID  int       `json:"user_id" db:"user_id"`
	SongID  int       `json:"song_id" db:"song_id"`
	AddedAt time.Time `json:"added_at" db:"added_at"`
}
