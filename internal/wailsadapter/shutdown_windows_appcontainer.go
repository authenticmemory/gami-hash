//go:build windows && windows_appcontainer

package wailsadapter

import (
	"log"
	"syscall"
)

// The Wails Windows loop remains alive after OnShutdown returns in the
// packaged AppContainer host. Exit only after broker cancellation and adapter
// cleanup have completed; otherwise later package activations are blocked by
// the stale host's single-instance lock.
func terminateAfterShutdown() {
	log.Printf("[Wails adapter] terminating packaged host")
	dll := syscall.NewLazyDLL("GamiHashStorageBridge.dll")
	dll.NewProc("GamiTerminateHost").Call(0)
}
