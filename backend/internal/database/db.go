package database

import (
	"database/sql"
	"fmt"
	"log"
	"os"
	"strconv"
	"strings"
	"time"

	_ "github.com/lib/pq"
)

var DB *sql.DB

// InitDB initializes the database connection
func InitDB() {
	var err error

	// Get database connection parameters from environment variables
	host := getEnvOrDefault("DB_HOST", "localhost")
	port := getEnvOrDefault("DB_PORT", "5432")
	user := getEnvOrDefault("DB_USER", "postgres")
	password := getEnvOrDefault("DB_PASSWORD", "password")
	dbName := getEnvOrDefault("DB_NAME", "cloudtune")
	sslMode := getEnvOrDefault("DB_SSLMODE", "disable")

	log.Printf("Connecting to database: host=%s port=%s user=%s db=%s sslmode=%s", host, port, user, dbName, sslMode)

	connStr := fmt.Sprintf("host=%s port=%s user=%s password=%s dbname=%s sslmode=%s",
		host, port, user, password, dbName, sslMode)

	DB, err = sql.Open("postgres", connStr)
	if err != nil {
		log.Fatal("Failed to connect to database:", err)
	}

	DB.SetMaxOpenConns(getIntEnvOrDefault("DB_MAX_OPEN_CONNS", 25))
	DB.SetMaxIdleConns(getIntEnvOrDefault("DB_MAX_IDLE_CONNS", 25))
	DB.SetConnMaxIdleTime(time.Duration(getIntEnvOrDefault("DB_CONN_MAX_IDLE_MINUTES", 5)) * time.Minute)
	DB.SetConnMaxLifetime(time.Duration(getIntEnvOrDefault("DB_CONN_MAX_LIFETIME_MINUTES", 30)) * time.Minute)

	if err = DB.Ping(); err != nil {
		log.Fatal("Failed to ping database:", err)
	}

	log.Println("Connected to database successfully")
}

// getEnvOrDefault returns the value of an environment variable or a default value
func getEnvOrDefault(key, defaultValue string) string {
	value := strings.TrimSpace(os.Getenv(key))
	if value != "" {
		return value
	}
	return defaultValue
}

func getIntEnvOrDefault(key string, defaultValue int) int {
	raw := strings.TrimSpace(os.Getenv(key))
	if raw == "" {
		return defaultValue
	}

	value, err := strconv.Atoi(raw)
	if err != nil || value <= 0 {
		log.Printf("Invalid %s=%q, using default %d", key, raw, defaultValue)
		return defaultValue
	}

	return value
}

// CloseDB closes the database connection
func CloseDB() {
	if DB != nil {
		DB.Close()
	}
}
