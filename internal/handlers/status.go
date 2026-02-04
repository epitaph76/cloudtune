package handlers

import "github.com/gin-gonic/gin"

func Status(c *gin.Context) {
    c.JSON(200, gin.H{
        "service": "CloudTune API",
        "version": "0.1.0",
        "status":  "operational",
    })
}
