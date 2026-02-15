package middleware

import (
	"cloudtune/internal/utils"
	"net/http"
	"strconv"
	"strings"

	"github.com/gin-gonic/gin"
)

// AuthMiddleware is a middleware that checks for a valid JWT token
func AuthMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		authHeader := c.GetHeader("Authorization")
		
		if authHeader == "" {
			c.JSON(http.StatusUnauthorized, gin.H{
				"error": "Authorization header is required",
			})
			c.Abort()
			return
		}

		// Check if the authorization header has the correct format
		tokenParts := strings.Split(authHeader, " ")
		if len(tokenParts) != 2 || tokenParts[0] != "Bearer" {
			c.JSON(http.StatusUnauthorized, gin.H{
				"error": "Authorization header must be in the format 'Bearer {token}'",
			})
			c.Abort()
			return
		}

		tokenString := tokenParts[1]

		// Validate the token
		claims, err := utils.ValidateToken(tokenString)
		if err != nil {
			c.JSON(http.StatusUnauthorized, gin.H{
				"error": "Invalid token",
			})
			c.Abort()
			return
		}

		// Add user ID to the context for use in handlers
		// Convert user_id to int before storing in context
		var userID int
		switch v := claims["user_id"].(type) {
		case float64:
			userID = int(v)
		case string:
			// Если user_id приходит как строка, нужно преобразовать
			parsedID, err := strconv.Atoi(v)
			if err != nil {
				c.JSON(http.StatusInternalServerError, gin.H{
					"error": "Invalid user ID format",
				})
				c.Abort()
				return
			}
			userID = parsedID
		default:
			c.JSON(http.StatusInternalServerError, gin.H{
				"error": "Invalid user ID format",
			})
			c.Abort()
			return
		}
		c.Set("user_id", userID)
		c.Next()
	}
}