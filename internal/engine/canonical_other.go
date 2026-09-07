//go:build !windows

package engine

import "path/filepath"

func canonicalExisting(path string) (string, error) {
	return filepath.EvalSymlinks(path)
}
