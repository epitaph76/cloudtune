package utils

import (
	"errors"
	"fmt"
	"os"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

const (
	jwtIssuer         = "cloudtune-api"
	minJWTSecretBytes = 32
	tokenTTL          = 7 * 24 * time.Hour
)

type Claims struct {
	UserID int `json:"user_id"`
	jwt.RegisteredClaims
}

var (
	jwtSecret     []byte
	jwtSecretErr  error
	jwtSecretOnce sync.Once
)

func EnsureJWTReady() error {
	_, err := getJWTSecret()
	return err
}

func getJWTSecret() ([]byte, error) {
	jwtSecretOnce.Do(func() {
		raw := strings.TrimSpace(os.Getenv("JWT_SECRET"))
		if raw == "" {
			jwtSecretErr = errors.New("JWT_SECRET is required")
			return
		}
		if len(raw) < minJWTSecretBytes {
			jwtSecretErr = fmt.Errorf("JWT_SECRET must be at least %d characters", minJWTSecretBytes)
			return
		}
		jwtSecret = []byte(raw)
	})

	if jwtSecretErr != nil {
		return nil, jwtSecretErr
	}
	return jwtSecret, nil
}

// GenerateToken generates a new JWT token for a user.
func GenerateToken(userID int) (string, error) {
	if userID <= 0 {
		return "", errors.New("invalid user ID")
	}

	secret, err := getJWTSecret()
	if err != nil {
		return "", err
	}

	now := time.Now()
	claims := Claims{
		UserID: userID,
		RegisteredClaims: jwt.RegisteredClaims{
			Subject:   strconv.Itoa(userID),
			Issuer:    jwtIssuer,
			IssuedAt:  jwt.NewNumericDate(now),
			NotBefore: jwt.NewNumericDate(now),
			ExpiresAt: jwt.NewNumericDate(now.Add(tokenTTL)),
		},
	}

	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	return token.SignedString(secret)
}

// ValidateToken validates the JWT token and returns the claims.
func ValidateToken(tokenString string) (*Claims, error) {
	if strings.TrimSpace(tokenString) == "" {
		return nil, errors.New("token is empty")
	}

	secret, err := getJWTSecret()
	if err != nil {
		return nil, err
	}

	claims := &Claims{}
	token, err := jwt.ParseWithClaims(tokenString, claims, func(token *jwt.Token) (interface{}, error) {
		if token.Method == nil || token.Method.Alg() != jwt.SigningMethodHS256.Alg() {
			return nil, fmt.Errorf("unexpected signing method: %v", token.Header["alg"])
		}
		return secret, nil
	})

	if err != nil {
		return nil, err
	}

	if !token.Valid {
		return nil, errors.New("invalid token")
	}

	if claims.UserID <= 0 {
		return nil, errors.New("invalid token user")
	}

	if claims.Issuer != jwtIssuer {
		return nil, errors.New("invalid token issuer")
	}

	if claims.Subject != strconv.Itoa(claims.UserID) {
		return nil, errors.New("invalid token subject")
	}

	return claims, nil
}
