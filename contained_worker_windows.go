//go:build windows

package main

import (
	"context"
	"fmt"
	"os"

	"github.com/authenticmemory/gami-hash/internal/containedworker"
)

func runContainedWorkerIfRequested(args []string) (bool, int) {
	if len(args) != 1 || args[0] != "--contained-worker" {
		return false, 0
	}
	if _, err := containedworker.Run(context.Background(), os.Stdin, os.Stdout); err != nil {
		// stdout is the framed protocol. Diagnostics belong only on the broker
		// supplied stderr handle and must never corrupt protocol framing.
		_, _ = fmt.Fprintln(os.Stderr, "contained worker:", err)
		return true, 1
	}
	return true, 0
}
