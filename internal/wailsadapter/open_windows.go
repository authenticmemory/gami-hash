//go:build windows

package wailsadapter

import (
	"context"
	"os/exec"
)

type systemOutputOpener struct{}

func (systemOutputOpener) OpenFolder(ctx context.Context, output string) error {
	return exec.CommandContext(ctx, "explorer.exe", "/select,"+output).Start()
}
