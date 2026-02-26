package middleware

import (
	"crypto/rand"
	"encoding/hex"
	"log"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
)

const (
	requestIDContextKey = "request_id"
	requestIDHeaderName = "X-Request-ID"
)

// RequestIDFromContext returns a request ID or an empty string when unavailable.
func RequestIDFromContext(c *gin.Context) string {
	value, ok := c.Get(requestIDContextKey)
	if !ok {
		return ""
	}
	requestID, ok := value.(string)
	if !ok {
		return ""
	}
	return requestID
}

// RequestIDMiddleware injects request IDs into context/headers and logs every request with the ID.
func RequestIDMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		startedAt := time.Now()
		requestID := normalizeRequestID(c.GetHeader(requestIDHeaderName))
		if requestID == "" {
			requestID = generateRequestID()
		}

		c.Set(requestIDContextKey, requestID)
		c.Writer.Header().Set(requestIDHeaderName, requestID)

		c.Next()

		log.Printf(
			"request_id=%s method=%s path=%s status=%d latency_ms=%.2f client_ip=%s",
			requestID,
			c.Request.Method,
			c.FullPath(),
			c.Writer.Status(),
			float64(time.Since(startedAt).Microseconds())/1000.0,
			c.ClientIP(),
		)
	}
}

func normalizeRequestID(raw string) string {
	candidate := strings.TrimSpace(raw)
	if candidate == "" {
		return ""
	}
	if len(candidate) > 128 {
		candidate = candidate[:128]
	}
	return candidate
}

func generateRequestID() string {
	var b [16]byte
	if _, err := rand.Read(b[:]); err != nil {
		return time.Now().UTC().Format("20060102150405.000000000")
	}
	return hex.EncodeToString(b[:])
}
