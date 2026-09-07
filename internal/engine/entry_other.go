//go:build !windows

package engine

import "io/fs"

func entryLinkLike(_ string, entry fs.DirEntry) (bool, error) {
	return entry.Type()&fs.ModeSymlink != 0, nil
}
