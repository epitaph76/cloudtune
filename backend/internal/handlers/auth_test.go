package handlers

import (
	"bytes"
	"cloudtune/internal/utils"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"regexp"
	"testing"

	"github.com/DATA-DOG/go-sqlmock"
	"github.com/gin-gonic/gin"
)

func TestRegisterSuccess(t *testing.T) {
	gin.SetMode(gin.TestMode)
	_, mock, cleanup := setupMockDB(t)
	defer cleanup()

	mock.
		ExpectQuery(regexp.QuoteMeta(`INSERT INTO users (email, username, password) VALUES ($1, $2, $3) RETURNING id`)).
		WithArgs("user@example.com", "demo_user", sqlmock.AnyArg()).
		WillReturnRows(sqlmock.NewRows([]string{"id"}).AddRow(101))

	router := gin.New()
	router.POST("/auth/register", Register)

	body := map[string]string{
		"email":    "User@example.com",
		"username": "demo_user",
		"password": "Secret123",
	}
	payload, _ := json.Marshal(body)
	req := httptest.NewRequest(http.MethodPost, "/auth/register", bytes.NewReader(payload))
	req.Header.Set("Content-Type", "application/json")
	resp := httptest.NewRecorder()

	router.ServeHTTP(resp, req)
	expectHTTP200(t, resp.Code)

	var out map[string]any
	if err := json.Unmarshal(resp.Body.Bytes(), &out); err != nil {
		t.Fatalf("json.Unmarshal: %v", err)
	}
	token, _ := out["token"].(string)
	if token == "" {
		t.Fatalf("expected non-empty token")
	}

	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatalf("sql expectations: %v", err)
	}
}

func TestLoginSuccess(t *testing.T) {
	gin.SetMode(gin.TestMode)
	_, mock, cleanup := setupMockDB(t)
	defer cleanup()

	hashed, err := utils.HashPassword("Secret123")
	if err != nil {
		t.Fatalf("HashPassword: %v", err)
	}

	mock.
		ExpectQuery(regexp.QuoteMeta(`SELECT id, email, username, password FROM users WHERE email=$1`)).
		WithArgs("user@example.com").
		WillReturnRows(
			sqlmock.NewRows([]string{"id", "email", "username", "password"}).
				AddRow(101, "user@example.com", "demo_user", hashed),
		)

	router := gin.New()
	router.POST("/auth/login", Login)

	body := map[string]string{
		"email":    "User@example.com",
		"password": "Secret123",
	}
	payload, _ := json.Marshal(body)
	req := httptest.NewRequest(http.MethodPost, "/auth/login", bytes.NewReader(payload))
	req.Header.Set("Content-Type", "application/json")
	resp := httptest.NewRecorder()

	router.ServeHTTP(resp, req)
	expectHTTP200(t, resp.Code)

	var out map[string]any
	if err := json.Unmarshal(resp.Body.Bytes(), &out); err != nil {
		t.Fatalf("json.Unmarshal: %v", err)
	}
	token, _ := out["token"].(string)
	if token == "" {
		t.Fatalf("expected non-empty token")
	}

	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatalf("sql expectations: %v", err)
	}
}
