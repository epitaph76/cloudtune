package handlers

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/DATA-DOG/go-sqlmock"
	"github.com/gin-gonic/gin"
)

func TestGetUserPlaylistsPaginationAndSearch(t *testing.T) {
	gin.SetMode(gin.TestMode)
	_, mock, cleanup := setupMockDB(t)
	defer cleanup()

	userID := 11
	mock.
		ExpectQuery(`SELECT id FROM playlists WHERE owner_id = \$1 AND is_favorite = TRUE`).
		WithArgs(userID).
		WillReturnRows(sqlmock.NewRows([]string{"id"}).AddRow(50))

	mock.
		ExpectQuery(`SELECT COUNT\(\*\)`).
		WithArgs(userID, "%mix%").
		WillReturnRows(sqlmock.NewRows([]string{"count"}).AddRow(4))

	now := time.Now()
	mock.
		ExpectQuery(`SELECT p.id, p.name, p.description`).
		WithArgs(userID, "%mix%", 2, 0).
		WillReturnRows(
			sqlmock.NewRows(
				[]string{
					"id",
					"name",
					"description",
					"owner_id",
					"is_public",
					"is_favorite",
					"created_at",
					"updated_at",
					"song_count",
				},
			).
				AddRow(50, "Liked songs", "System", userID, false, true, now, now, 12).
				AddRow(80, "Road mix", "Drive", userID, false, false, now, now, 6),
		)

	router := gin.New()
	router.GET("/api/playlists", withTestUserID(userID), GetUserPlaylists)

	req := httptest.NewRequest(http.MethodGet, "/api/playlists?limit=2&offset=0&search=mix", nil)
	resp := httptest.NewRecorder()
	router.ServeHTTP(resp, req)

	expectHTTP200(t, resp.Code)

	var out map[string]any
	if err := json.Unmarshal(resp.Body.Bytes(), &out); err != nil {
		t.Fatalf("json.Unmarshal: %v", err)
	}
	if int(out["count"].(float64)) != 2 {
		t.Fatalf("expected count=2, got %#v", out["count"])
	}
	if int(out["total"].(float64)) != 4 {
		t.Fatalf("expected total=4, got %#v", out["total"])
	}
	if out["has_more"] != true {
		t.Fatalf("expected has_more=true")
	}

	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatalf("sql expectations: %v", err)
	}
}
