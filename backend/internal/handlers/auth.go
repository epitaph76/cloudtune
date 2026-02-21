package handlers

import (
	"cloudtune/internal/database"
	"cloudtune/internal/models"
	"cloudtune/internal/utils"
	"database/sql"
	"log"
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"
)

// Register handles user registration
func Register(c *gin.Context) {
	var user models.User
	if err := c.ShouldBindJSON(&user); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid request body"})
		return
	}

	// Validate required fields
	if user.Email == "" || user.Username == "" || user.Password == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Email, username, and password are required"})
		return
	}

	// Hash the password
	hashedPassword, err := utils.HashPassword(user.Password)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Error hashing password"})
		return
	}
	user.Password = hashedPassword

	// Insert user into database
	db := database.DB
	query := `INSERT INTO users (email, username, password) VALUES ($1, $2, $3) RETURNING id`
	err = db.QueryRow(query, user.Email, user.Username, user.Password).Scan(&user.ID)
	if err != nil {
		log.Printf("Error inserting user: %v", err)
		if strings.Contains(err.Error(), "duplicate key value") {
			c.JSON(http.StatusConflict, gin.H{"error": "User with this email or username already exists"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Error creating user"})
		return
	}

	// Generate JWT token
	token, err := utils.GenerateToken(user.ID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Error generating token"})
		return
	}

	// Return success response with token
	c.JSON(http.StatusOK, gin.H{
		"message": "User registered successfully",
		"token":   token,
		"user": gin.H{
			"id":       user.ID,
			"email":    user.Email,
			"username": user.Username,
		},
	})
}

// Login handles user login
func Login(c *gin.Context) {
	var credentials struct {
		Email    string `json:"email" binding:"required"`
		Password string `json:"password" binding:"required"`
	}

	if err := c.ShouldBindJSON(&credentials); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Email and password are required"})
		return
	}

	// Get user from database
	db := database.DB
	var user models.User
	query := `SELECT id, email, username, password FROM users WHERE email=$1`
	err := db.QueryRow(query, credentials.Email).Scan(
		&user.ID,
		&user.Email,
		&user.Username,
		&user.Password,
	)

	if err != nil {
		if err == sql.ErrNoRows {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "Invalid credentials"})
			return
		}
		log.Printf("Error querying user: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Error logging in"})
		return
	}

	// Check password
	if !utils.CheckPasswordHash(credentials.Password, user.Password) {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Invalid credentials"})
		return
	}

	// Generate JWT token
	token, err := utils.GenerateToken(user.ID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Error generating token"})
		return
	}

	// Return success response with token
	c.JSON(http.StatusOK, gin.H{
		"message": "Login successful",
		"token":   token,
		"user": gin.H{
			"id":       user.ID,
			"email":    user.Email,
			"username": user.Username,
		},
	})
}
