package handlers

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/DATA-DOG/go-sqlmock"
	"github.com/gin-gonic/gin"
)

func TestAddSongsToPlaylistBulkSuccess(t *testing.T) {
	gin.SetMode(gin.TestMode)
	_, mock, cleanup := setupMockDB(t)
	defer cleanup()

	userID := 5
	playlistID := 10

	mock.
		ExpectQuery(`SELECT owner_id FROM playlists WHERE id = \$1`).
		WithArgs(playlistID).
		WillReturnRows(sqlmock.NewRows([]string{"owner_id"}).AddRow(userID))

	mock.
		ExpectQuery(`SELECT song_id FROM user_library WHERE user_id = \$1 AND song_id = ANY\(\$2\)`).
		WithArgs(userID, sqlmock.AnyArg()).
		WillReturnRows(
			sqlmock.NewRows([]string{"song_id"}).
				AddRow(1).
				AddRow(3),
		)

	mock.
		ExpectQuery(`SELECT song_id FROM playlist_songs WHERE playlist_id = \$1 AND song_id = ANY\(\$2\)`).
		WithArgs(playlistID, sqlmock.AnyArg()).
		WillReturnRows(sqlmock.NewRows([]string{"song_id"}).AddRow(3))

	mock.ExpectBegin()
	mock.
		ExpectExec(`SELECT id FROM playlists WHERE id = \$1 FOR UPDATE`).
		WithArgs(playlistID).
		WillReturnResult(sqlmock.NewResult(0, 1))
	mock.
		ExpectQuery(`SELECT COALESCE\(MAX\(position\), 0\) FROM playlist_songs WHERE playlist_id = \$1`).
		WithArgs(playlistID).
		WillReturnRows(sqlmock.NewRows([]string{"max"}).AddRow(7))
	mock.
		ExpectQuery(`INSERT INTO playlist_songs`).
		WithArgs(sqlmock.AnyArg(), playlistID, 7).
		WillReturnRows(sqlmock.NewRows([]string{"song_id", "position"}).AddRow(1, 8))
	mock.ExpectCommit()

	router := gin.New()
	router.POST(
		"/api/playlists/:playlist_id/songs/bulk",
		withTestUserID(userID),
		AddSongsToPlaylistBulk,
	)

	body := map[string]any{
		"song_ids": []int{1, 2, 2, 3},
	}
	payload, _ := json.Marshal(body)
	req := httptest.NewRequest(
		http.MethodPost,
		"/api/playlists/10/songs/bulk",
		bytes.NewReader(payload),
	)
	req.Header.Set("Content-Type", "application/json")
	resp := httptest.NewRecorder()
	router.ServeHTTP(resp, req)

	expectHTTP200(t, resp.Code)

	var out map[string]any
	if err := json.Unmarshal(resp.Body.Bytes(), &out); err != nil {
		t.Fatalf("json.Unmarshal: %v", err)
	}
	if int(out["added_count"].(float64)) != 1 {
		t.Fatalf("expected added_count=1, got %#v", out["added_count"])
	}
	if int(out["skipped_not_in_library"].(float64)) != 1 {
		t.Fatalf(
			"expected skipped_not_in_library=1, got %#v",
			out["skipped_not_in_library"],
		)
	}
	if int(out["skipped_existing"].(float64)) != 1 {
		t.Fatalf("expected skipped_existing=1, got %#v", out["skipped_existing"])
	}

	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatalf("sql expectations: %v", err)
	}
}
