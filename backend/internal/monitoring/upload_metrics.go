package monitoring

import (
	"fmt"
	"strings"
	"sync"
	"sync/atomic"
	"time"
)

var uploadRequestsTotal atomic.Uint64
var uploadRequestsFailed atomic.Uint64
var uploadBytesTotal atomic.Int64
var uploadDurationMicrosTotal atomic.Uint64
var uploadFailureReasonsMu sync.Mutex
var uploadFailureReasons = map[string]uint64{}
var uploadStatusClassTotalsMu sync.Mutex
var uploadStatusClassTotals = map[string]uint64{
	"2xx":   0,
	"4xx":   0,
	"5xx":   0,
	"other": 0,
}

type UploadStats struct {
	RequestsTotal       uint64
	FailedTotal         uint64
	BytesTotal          int64
	AvgDurationMS       float64
	FailureByReason     map[string]uint64
	StatusClassTotals   map[string]uint64
	ClientErrorRatePct  float64
	ServerErrorRatePct  float64
	TopFailureReason    string
	TopFailureReasonCnt uint64
}

func RecordUpload(bytes int64, duration time.Duration, success bool, failureReason string, statusCode int) {
	uploadRequestsTotal.Add(1)

	statusClass := normalizeStatusClass(statusCode)
	uploadStatusClassTotalsMu.Lock()
	uploadStatusClassTotals[statusClass]++
	uploadStatusClassTotalsMu.Unlock()

	if !success {
		uploadRequestsFailed.Add(1)
		reason := normalizeFailureReason(failureReason)
		uploadFailureReasonsMu.Lock()
		uploadFailureReasons[reason]++
		uploadFailureReasonsMu.Unlock()
	}
	if bytes > 0 {
		uploadBytesTotal.Add(bytes)
	}
	if duration > 0 {
		uploadDurationMicrosTotal.Add(uint64(duration / time.Microsecond))
	}
}

func normalizeFailureReason(raw string) string {
	reason := strings.ToLower(strings.TrimSpace(raw))
	if reason == "" {
		return "unknown"
	}
	if len(reason) > 96 {
		return reason[:96]
	}
	return reason
}

func normalizeStatusClass(statusCode int) string {
	switch {
	case statusCode >= 200 && statusCode <= 299:
		return "2xx"
	case statusCode >= 400 && statusCode <= 499:
		return "4xx"
	case statusCode >= 500 && statusCode <= 599:
		return "5xx"
	default:
		if statusCode <= 0 {
			return "other"
		}
		return fmt.Sprintf("%dxx", statusCode/100)
	}
}

func cloneUint64Map(src map[string]uint64) map[string]uint64 {
	out := make(map[string]uint64, len(src))
	for key, value := range src {
		out[key] = value
	}
	return out
}

func topMapEntry(src map[string]uint64) (string, uint64) {
	var bestKey string
	var bestValue uint64
	for key, value := range src {
		if value <= bestValue {
			continue
		}
		bestKey = key
		bestValue = value
	}
	return bestKey, bestValue
}

func getUploadStats() UploadStats {
	total := uploadRequestsTotal.Load()
	totalDurationMicros := uploadDurationMicrosTotal.Load()
	avgDurationMS := 0.0
	if total > 0 {
		avgDurationMS = float64(totalDurationMicros) / float64(total) / 1000.0
	}

	uploadFailureReasonsMu.Lock()
	failureByReason := cloneUint64Map(uploadFailureReasons)
	uploadFailureReasonsMu.Unlock()

	uploadStatusClassTotalsMu.Lock()
	statusClassTotals := cloneUint64Map(uploadStatusClassTotals)
	uploadStatusClassTotalsMu.Unlock()

	clientErrors := statusClassTotals["4xx"]
	serverErrors := statusClassTotals["5xx"]
	clientErrorRatePct := 0.0
	serverErrorRatePct := 0.0
	if total > 0 {
		clientErrorRatePct = (float64(clientErrors) / float64(total)) * 100
		serverErrorRatePct = (float64(serverErrors) / float64(total)) * 100
	}

	topFailureReason, topFailureReasonCount := topMapEntry(failureByReason)
	if topFailureReason == "" {
		topFailureReason = "n/a"
	}

	return UploadStats{
		RequestsTotal:       total,
		FailedTotal:         uploadRequestsFailed.Load(),
		BytesTotal:          uploadBytesTotal.Load(),
		AvgDurationMS:       avgDurationMS,
		FailureByReason:     failureByReason,
		StatusClassTotals:   statusClassTotals,
		ClientErrorRatePct:  clientErrorRatePct,
		ServerErrorRatePct:  serverErrorRatePct,
		TopFailureReason:    topFailureReason,
		TopFailureReasonCnt: topFailureReasonCount,
	}
}
