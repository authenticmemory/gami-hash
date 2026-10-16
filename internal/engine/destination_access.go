package engine

import (
	"os"
	"path/filepath"
)

// destinationAccess collects the operations that may mutate the selected
// output folder. A contained adapter must bind every name to that folder and
// reject source aliases before creating any work or sidecar file.
type destinationAccess interface {
	CreateWork(output string) (*os.File, error)
	OpenExisting(path string, writable bool) (*os.File, error)
	OpenErrorLog(path string) (*os.File, error)
	WriteSidecar(path string, data []byte) error
	Publish(workPath, finalPath string) error
	Remove(path string) error
}

type osDestinationAccess struct{}

func (osDestinationAccess) CreateWork(output string) (*os.File, error) {
	return os.CreateTemp(filepath.Dir(output), ".gami-manifest-*")
}
func (osDestinationAccess) OpenExisting(path string, writable bool) (*os.File, error) {
	flags := os.O_RDONLY
	if writable {
		flags = os.O_RDWR
	}
	return os.OpenFile(path, flags, 0)
}
func (osDestinationAccess) OpenErrorLog(path string) (*os.File, error) {
	return os.OpenFile(path, os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0o644)
}
func (osDestinationAccess) WriteSidecar(path string, data []byte) error {
	return atomicWriteFile(path, data, 0o644)
}
func (osDestinationAccess) Publish(workPath, finalPath string) error {
	return publishFile(workPath, finalPath)
}
func (osDestinationAccess) Remove(path string) error { return os.Remove(path) }
