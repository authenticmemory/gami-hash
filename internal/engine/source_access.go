package engine

import (
	"io"
	"io/fs"
	"os"
	"path/filepath"
)

// readFile is the minimum file handle the hashing loop needs. The Windows
// AppContainer adapter can satisfy it with a broker-granted read-only handle.
type readFile interface {
	io.Reader
	io.Closer
	Stat() (fs.FileInfo, error)
}

type sourceEntry interface {
	fs.DirEntry
	Ref() string
	LinkLike() (bool, error)
}

type sourceDirectory interface {
	ReadDir(n int) ([]sourceEntry, error)
	Close() error
}

// sourceAccess isolates source enumeration, read-only opens, and identity
// checks from destination mutations. Broker references may be opaque strings.
type sourceAccess interface {
	OpenDir(ref string) (sourceDirectory, error)
	OpenRead(ref string) (readFile, error)
	Lstat(ref string) (fs.FileInfo, error)
	SameFile(before, current fs.FileInfo) bool
	IsExcluded(ref, output string) bool
}

type osSourceAccess struct{}

type osSourceDirectory struct {
	file   *os.File
	parent string
}

type osSourceEntry struct {
	fs.DirEntry
	ref string
}

func (e osSourceEntry) Ref() string { return e.ref }
func (e osSourceEntry) LinkLike() (bool, error) {
	return entryLinkLike(e.ref, e.DirEntry)
}

func (d osSourceDirectory) ReadDir(n int) ([]sourceEntry, error) {
	entries, err := d.file.ReadDir(n)
	result := make([]sourceEntry, 0, len(entries))
	for _, entry := range entries {
		result = append(result, osSourceEntry{DirEntry: entry, ref: filepath.Join(d.parent, entry.Name())})
	}
	return result, err
}

func (d osSourceDirectory) Close() error { return d.file.Close() }

func (osSourceAccess) OpenDir(ref string) (sourceDirectory, error) {
	file, err := os.Open(ref)
	if err != nil {
		return nil, err
	}
	return osSourceDirectory{file: file, parent: ref}, nil
}
func (osSourceAccess) OpenRead(ref string) (readFile, error) { return os.Open(ref) }
func (osSourceAccess) Lstat(ref string) (fs.FileInfo, error) { return os.Lstat(ref) }
func (osSourceAccess) SameFile(before, current fs.FileInfo) bool {
	return os.SameFile(before, current)
}
func (osSourceAccess) IsExcluded(ref, output string) bool {
	for _, path := range []string{output, CheckpointPath(output), ErrorLogPath(output)} {
		if SameRoot(ref, path) {
			return true
		}
	}
	return false
}
