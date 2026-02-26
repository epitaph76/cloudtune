package database

import (
	"fmt"
	"log"
)

// CreateTables creates all required tables in the database
func CreateTables() {
	createUsersTable()
	createSongsTable()
	createPlaylistsTable()
	createPlaylistSongsTable()
	createUserLibraryTable()
}

// createUsersTable creates the users table
func createUsersTable() {
	query := `
	CREATE TABLE IF NOT EXISTS users (
		id SERIAL PRIMARY KEY,
		email VARCHAR(255) UNIQUE NOT NULL,
		username VARCHAR(255) UNIQUE NOT NULL,
		password VARCHAR(255) NOT NULL,
		created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
		updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
	);
	`

	_, err := DB.Exec(query)
	if err != nil {
		log.Fatal("Failed to create users table:", err)
	}

	fmt.Println("Users table created successfully")
}

func createSongsTable() {
	query := `
	CREATE TABLE IF NOT EXISTS songs (
		id SERIAL PRIMARY KEY,
		filename VARCHAR(255) NOT NULL,
		original_filename VARCHAR(255) NOT NULL,
		filepath VARCHAR(500) NOT NULL,
		filesize BIGINT NOT NULL,
		content_hash VARCHAR(64),
		duration INTEGER,
		artist VARCHAR(255),
		title VARCHAR(255),
		album VARCHAR(255),
		genre VARCHAR(100),
		year INTEGER,
		mime_type VARCHAR(100),
		upload_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
		uploader_id INTEGER REFERENCES users(id) ON DELETE SET NULL
	);
	`

	_, err := DB.Exec(query)
	if err != nil {
		log.Fatal("Failed to create songs table:", err)
	}

	ensureSongsSchema()
	fmt.Println("Songs table created successfully")
}

func createPlaylistsTable() {
	query := `
	CREATE TABLE IF NOT EXISTS playlists (
		id SERIAL PRIMARY KEY,
		name VARCHAR(255) NOT NULL,
		description TEXT,
		owner_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
		is_public BOOLEAN DEFAULT FALSE,
		is_favorite BOOLEAN DEFAULT FALSE,
		created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
		updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
	);
	`

	_, err := DB.Exec(query)
	if err != nil {
		log.Fatal("Failed to create playlists table:", err)
	}

	ensurePlaylistsSchema()
	fmt.Println("Playlists table created successfully")
}

func createPlaylistSongsTable() {
	query := `
	CREATE TABLE IF NOT EXISTS playlist_songs (
		id SERIAL PRIMARY KEY,
		playlist_id INTEGER NOT NULL REFERENCES playlists(id) ON DELETE CASCADE,
		song_id INTEGER NOT NULL REFERENCES songs(id) ON DELETE CASCADE,
		position INTEGER NOT NULL,
		added_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
		UNIQUE(playlist_id, position),
		UNIQUE(playlist_id, song_id)
	);
	`

	_, err := DB.Exec(query)
	if err != nil {
		log.Fatal("Failed to create playlist_songs table:", err)
	}

	ensurePlaylistSongsSchema()
	fmt.Println("Playlist_songs table created successfully")
}

func createUserLibraryTable() {
	query := `
	CREATE TABLE IF NOT EXISTS user_library (
		id SERIAL PRIMARY KEY,
		user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
		song_id INTEGER NOT NULL REFERENCES songs(id) ON DELETE CASCADE,
		added_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
		UNIQUE(user_id, song_id)
	);
	`

	_, err := DB.Exec(query)
	if err != nil {
		log.Fatal("Failed to create user_library table:", err)
	}

	ensureUserLibrarySchema()
	fmt.Println("User_library table created successfully")
}

func ensureSongsSchema() {
	ensureTrigramExtension()

	if _, err := DB.Exec(`ALTER TABLE songs ADD COLUMN IF NOT EXISTS content_hash VARCHAR(64)`); err != nil {
		log.Fatal("Failed to ensure songs.content_hash column:", err)
	}

	if _, err := DB.Exec(`CREATE INDEX IF NOT EXISTS songs_content_hash_idx ON songs(content_hash)`); err != nil {
		log.Fatal("Failed to ensure songs content hash index:", err)
	}

	if _, err := DB.Exec(`CREATE INDEX IF NOT EXISTS songs_uploader_upload_date_idx ON songs(uploader_id, upload_date DESC)`); err != nil {
		log.Fatal("Failed to ensure songs uploader/upload_date index:", err)
	}

	if _, err := DB.Exec(`CREATE INDEX IF NOT EXISTS songs_library_search_trgm_idx ON songs USING gin ((lower(COALESCE(original_filename, '') || ' ' || COALESCE(filename, '') || ' ' || COALESCE(title, '') || ' ' || COALESCE(artist, '') || ' ' || COALESCE(album, '') || ' ' || COALESCE(genre, ''))) gin_trgm_ops)`); err != nil {
		log.Fatal("Failed to ensure songs library search trigram index:", err)
	}
}

func ensurePlaylistsSchema() {
	ensureTrigramExtension()

	if _, err := DB.Exec(`ALTER TABLE playlists ADD COLUMN IF NOT EXISTS is_favorite BOOLEAN DEFAULT FALSE`); err != nil {
		log.Fatal("Failed to ensure playlists.is_favorite column:", err)
	}

	if _, err := DB.Exec(`CREATE INDEX IF NOT EXISTS playlists_owner_normalized_name_idx ON playlists(owner_id, lower(name))`); err != nil {
		log.Fatal("Failed to ensure playlists normalized-name index:", err)
	}

	if _, err := DB.Exec(`CREATE UNIQUE INDEX IF NOT EXISTS playlists_owner_favorite_unique ON playlists(owner_id) WHERE is_favorite = TRUE`); err != nil {
		log.Fatal("Failed to ensure playlists favorite uniqueness index:", err)
	}

	if _, err := DB.Exec(`CREATE INDEX IF NOT EXISTS playlists_owner_favorite_created_idx ON playlists(owner_id, is_favorite DESC, created_at DESC, id DESC)`); err != nil {
		log.Fatal("Failed to ensure playlists owner/sort index:", err)
	}

	if _, err := DB.Exec(`CREATE INDEX IF NOT EXISTS playlists_search_trgm_idx ON playlists USING gin ((lower(COALESCE(name, '') || ' ' || COALESCE(description, ''))) gin_trgm_ops)`); err != nil {
		log.Fatal("Failed to ensure playlists search trigram index:", err)
	}
}

func ensurePlaylistSongsSchema() {
	if _, err := DB.Exec(`CREATE INDEX IF NOT EXISTS playlist_songs_playlist_position_idx ON playlist_songs(playlist_id, position)`); err != nil {
		log.Fatal("Failed to ensure playlist_songs playlist/position index:", err)
	}

	if _, err := DB.Exec(`CREATE INDEX IF NOT EXISTS playlist_songs_song_idx ON playlist_songs(song_id)`); err != nil {
		log.Fatal("Failed to ensure playlist_songs song index:", err)
	}
}

func ensureUserLibrarySchema() {
	if _, err := DB.Exec(`CREATE INDEX IF NOT EXISTS user_library_user_added_idx ON user_library(user_id, added_at DESC)`); err != nil {
		log.Fatal("Failed to ensure user_library user/added index:", err)
	}

	if _, err := DB.Exec(`CREATE INDEX IF NOT EXISTS user_library_user_added_song_idx ON user_library(user_id, added_at DESC, song_id)`); err != nil {
		log.Fatal("Failed to ensure user_library user/added/song index:", err)
	}

	if _, err := DB.Exec(`CREATE INDEX IF NOT EXISTS user_library_song_idx ON user_library(song_id)`); err != nil {
		log.Fatal("Failed to ensure user_library song index:", err)
	}
}

func ensureTrigramExtension() {
	if _, err := DB.Exec(`CREATE EXTENSION IF NOT EXISTS pg_trgm`); err != nil {
		log.Fatal("Failed to ensure pg_trgm extension:", err)
	}
}
