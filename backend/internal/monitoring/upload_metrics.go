package monitoring

import (
	"sync/atomic"
	"time"
)

var uploadRequestsTotal atomic.Uint64
var uploadRequestsFailed atomic.Uint64
var uploadBytesTotal atomic.Int64
var uploadDurationMicrosTotal atomic.Uint64

type UploadStats struct {
	RequestsTotal uint64
	FailedTotal   uint64
	BytesTotal    int64
	AvgDurationMS float64
}

func RecordUpload(bytes int64, duration time.Duration, success bool) {
	uploadRequestsTotal.Add(1)
	if !success {
		uploadRequestsFailed.Add(1)
	}
	if bytes > 0 {
		uploadBytesTotal.Add(bytes)
	}
	if duration > 0 {
		uploadDurationMicrosTotal.Add(uint64(duration / time.Microsecond))
	}
}

func getUploadStats() UploadStats {
	total := uploadRequestsTotal.Load()
	totalDurationMicros := uploadDurationMicrosTotal.Load()
	avgDurationMS := 0.0
	if total > 0 {
		avgDurationMS = float64(totalDurationMicros) / float64(total) / 1000.0
	}

	return UploadStats{
		RequestsTotal: total,
		FailedTotal:   uploadRequestsFailed.Load(),
		BytesTotal:    uploadBytesTotal.Load(),
		AvgDurationMS: avgDurationMS,
	}
}
