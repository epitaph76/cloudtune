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

func TestGetUserLibraryPaginationAndSearch(t *testing.T) {
	gin.SetMode(gin.TestMode)
	_, mock, cleanup := setupMockDB(t)
	defer cleanup()

	mock.
		ExpectQuery(`SELECT COUNT\(\*\)`).
		WithArgs(7, "%beatles%").
		WillReturnRows(sqlmock.NewRows([]string{"count"}).AddRow(3))

	now := time.Now()
	mock.
		ExpectQuery(`SELECT s.id, s.filename, s.original_filename`).
		WithArgs(7, "%beatles%", 2, 0).
		WillReturnRows(
			sqlmock.NewRows(
				[]string{
					"id",
					"filename",
					"original_filename",
					"filesize",
					"artist",
					"title",
					"album",
					"genre",
					"year",
					"mime_type",
					"upload_date",
				},
			).
				AddRow(1, "song1.mp3", "The Beatles - One.mp3", 1234, "The Beatles", "One", "Album", "Rock", 1969, "audio/mpeg", now).
				AddRow(2, "song2.mp3", "The Beatles - Two.mp3", 2234, "The Beatles", "Two", "Album", "Rock", 1970, "audio/mpeg", now),
		)

	router := gin.New()
	router.GET("/api/songs/library", withTestUserID(7), GetUserLibrary)

	req := httptest.NewRequest(http.MethodGet, "/api/songs/library?limit=2&offset=0&search=Beatles", nil)
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
	if int(out["total"].(float64)) != 3 {
		t.Fatalf("expected total=3, got %#v", out["total"])
	}
	if out["has_more"] != true {
		t.Fatalf("expected has_more=true")
	}

	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatalf("sql expectations: %v", err)
	}
}
