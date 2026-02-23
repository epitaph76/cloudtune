package middleware

import (
	"cloudtune/internal/utils"
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"
)

// AuthMiddleware checks for a valid JWT token and injects user_id into context.
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

		tokenParts := strings.Fields(authHeader)
		if len(tokenParts) != 2 || !strings.EqualFold(tokenParts[0], "Bearer") {
			c.JSON(http.StatusUnauthorized, gin.H{
				"error": "Authorization header must be in the format 'Bearer {token}'",
			})
			c.Abort()
			return
		}

		claims, err := utils.ValidateToken(tokenParts[1])
		if err != nil {
			c.JSON(http.StatusUnauthorized, gin.H{
				"error": "Invalid token",
			})
			c.Abort()
			return
		}

		c.Set("user_id", claims.UserID)
		c.Next()
	}
}
