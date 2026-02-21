package monitoring

import (
	"sync/atomic"

	"github.com/gin-gonic/gin"
)

var activeHTTPRequests atomic.Int64
var totalHTTPRequests atomic.Uint64

// RequestMetricsMiddleware tracks basic HTTP request counters.
func RequestMetricsMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		activeHTTPRequests.Add(1)
		totalHTTPRequests.Add(1)
		defer activeHTTPRequests.Add(-1)
		c.Next()
	}
}

func getHTTPStats() (active int64, total uint64) {
	return activeHTTPRequests.Load(), totalHTTPRequests.Load()
}
