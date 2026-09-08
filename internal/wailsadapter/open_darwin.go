//go:build darwin

package wailsadapter

import (
	"context"
	"os/exec"
)

type systemOutputOpener struct{}

func (systemOutputOpener) OpenFolder(ctx context.Context, output string) error {
	return exec.CommandContext(ctx, "open", "-R", output).Start()
}
