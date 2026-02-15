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
		created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
		updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
	);
	`

	_, err := DB.Exec(query)
	if err != nil {
		log.Fatal("Failed to create playlists table:", err)
	}

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

	fmt.Println("User_library table created successfully")
}