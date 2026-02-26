package handlers

import (
	"cloudtune/internal/database"
	"database/sql"
	"net/http"
	"os"
	"testing"

	"github.com/DATA-DOG/go-sqlmock"
	"github.com/gin-gonic/gin"
)

const testJWTSecret = "cloudtune_test_jwt_secret_key_1234567890"

func TestMain(m *testing.M) {
	_ = os.Setenv("JWT_SECRET", testJWTSecret)
	code := m.Run()
	os.Exit(code)
}

func setupMockDB(t *testing.T) (*sql.DB, sqlmock.Sqlmock, func()) {
	t.Helper()
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatalf("sqlmock.New: %v", err)
	}

	previousDB := database.DB
	database.DB = db

	cleanup := func() {
		database.DB = previousDB
		_ = db.Close()
	}

	return db, mock, cleanup
}

func withTestUserID(userID int) gin.HandlerFunc {
	return func(c *gin.Context) {
		c.Set("user_id", userID)
		c.Next()
	}
}

func mustStatus(t *testing.T, actual int, expected int) {
	t.Helper()
	if actual != expected {
		t.Fatalf("expected status %d, got %d", expected, actual)
	}
}

func expectHTTP200(t *testing.T, status int) {
	t.Helper()
	mustStatus(t, status, http.StatusOK)
}
