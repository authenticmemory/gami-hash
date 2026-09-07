//go:build windows

package engine

import (
	"io/fs"

	"golang.org/x/sys/windows"
)

// entryLinkLike rejects every Windows reparse point, not only symbolic links.
// Junctions and other name-surrogate entries can otherwise escape or loop the
// selected tree.
func entryLinkLike(path string, _ fs.DirEntry) (bool, error) {
	p, err := windows.UTF16PtrFromString(path)
	if err != nil {
		return false, err
	}
	attrs, err := windows.GetFileAttributes(p)
	if err != nil {
		return false, err
	}
	return attrs&windows.FILE_ATTRIBUTE_REPARSE_POINT != 0, nil
}
