//go:build linux

package wailsadapter

import (
	"context"
	"os/exec"
	"path/filepath"
)

type systemOutputOpener struct{}

func (systemOutputOpener) OpenFolder(ctx context.Context, output string) error {
	return exec.CommandContext(ctx, "xdg-open", filepath.Dir(output)).Start()
}
