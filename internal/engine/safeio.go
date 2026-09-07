package engine

import (
	"errors"
	"fmt"
	"io"
	"io/fs"
	"os"
	"path/filepath"
)

// resolveExisting resolves links and aliases for a path that must exist.
func resolveExisting(path string) (string, error) {
	abs, err := filepath.Abs(path)
	if err != nil {
		return "", err
	}
	resolved, err := canonicalExisting(abs)
	if err != nil {
		return "", err
	}
	return filepath.Clean(resolved), nil
}

// resolveOutput resolves the existing output directory, but not the final
// filename. The final file may not exist yet and must never be followed when
// it is replaced.
func resolveOutput(path string) (string, error) {
	abs, err := filepath.Abs(path)
	if err != nil {
		return "", err
	}
	dir, err := resolveExisting(filepath.Dir(abs))
	if err != nil {
		return "", fmt.Errorf("cannot resolve output folder: %w", err)
	}
	return filepath.Join(dir, filepath.Base(abs)), nil
}

// detachForAppend replaces an existing alias/hard link with an independent
// regular file containing the same bytes, then opens that file for append.
// It is used only after the existing data has been validated.
func detachForAppend(path string, perm fs.FileMode) (*os.File, error) {
	src, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	tmp, err := os.CreateTemp(filepath.Dir(path), ".gami-detach-*")
	if err != nil {
		src.Close()
		return nil, err
	}
	tmpName := tmp.Name()
	ok := false
	defer func() {
		src.Close()
		tmp.Close()
		if !ok {
			os.Remove(tmpName)
		}
	}()
	if _, err = io.Copy(tmp, src); err != nil {
		return nil, err
	}
	if err = tmp.Sync(); err != nil {
		return nil, err
	}
	if err = tmp.Close(); err != nil {
		return nil, err
	}
	if err = src.Close(); err != nil {
		return nil, err
	}
	if err = os.Chmod(tmpName, perm); err != nil {
		return nil, err
	}
	if err = os.Remove(path); err != nil {
		return nil, err
	}
	if err = os.Rename(tmpName, path); err != nil {
		return nil, err
	}
	ok = true
	return os.OpenFile(path, os.O_WRONLY|os.O_APPEND, perm)
}

// atomicWriteFile writes a sidecar without ever truncating an existing target
// in place. This also makes checkpoint updates resilient to torn writes.
func atomicWriteFile(path string, data []byte, perm fs.FileMode) error {
	tmp, err := os.CreateTemp(filepath.Dir(path), ".gami-sidecar-*")
	if err != nil {
		return err
	}
	name := tmp.Name()
	ok := false
	defer func() {
		tmp.Close()
		if !ok {
			os.Remove(name)
		}
	}()
	if err := tmp.Chmod(perm); err != nil {
		return err
	}
	if _, err := tmp.Write(data); err != nil {
		return err
	}
	if err := tmp.Sync(); err != nil {
		return err
	}
	if err := tmp.Close(); err != nil {
		return err
	}
	if err := os.Remove(path); err != nil && !errors.Is(err, fs.ErrNotExist) {
		return err
	}
	if err := os.Rename(name, path); err != nil {
		return err
	}
	ok = true
	return nil
}

// publishFile replaces only the destination directory entry. If it was a
// symlink or hard link, its target remains untouched.
func publishFile(workPath, finalPath string) error {
	if err := os.Remove(finalPath); err != nil && !errors.Is(err, fs.ErrNotExist) {
		return err
	}
	return os.Rename(workPath, finalPath)
}
