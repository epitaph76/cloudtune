//go:build !linux && !darwin && !freebsd && !netbsd && !openbsd

package monitoring

func fsUsage(path string) (totalBytes uint64, freeBytes uint64) {
	_ = path
	return 0, 0
}
