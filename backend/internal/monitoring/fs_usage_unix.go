//go:build linux || darwin || freebsd || netbsd || openbsd

package monitoring

import "golang.org/x/sys/unix"

func fsUsage(path string) (totalBytes uint64, freeBytes uint64) {
	var stat unix.Statfs_t
	if err := unix.Statfs(path, &stat); err != nil {
		return 0, 0
	}
	total := stat.Blocks * uint64(stat.Bsize)
	free := stat.Bavail * uint64(stat.Bsize)
	return total, free
}
