//go:build !cli && windows && appcontainer_webview2_spike

package main

import (
	"log"
	"os"
	"path/filepath"
)

var appContainerSpikeLog *os.File

// init runs before Wails initializes so go-webview2 environment/controller
// failures survive a GUI-subsystem exit. This is prototype diagnostics only.
func init() {
	root, err := os.UserCacheDir()
	if err != nil {
		return
	}
	dir := filepath.Join(root, "AuthenticMemory", "GAMIHashWebView2Spike")
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return
	}
	appContainerSpikeLog, err = os.OpenFile(filepath.Join(dir, "spike.log"), os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0o600)
	if err != nil {
		return
	}
	log.SetOutput(appContainerSpikeLog)
	log.SetFlags(log.Ldate | log.Ltime | log.Lmicroseconds | log.LUTC)
	log.Printf("[AppContainer WebView2 spike] process start pid=%d", os.Getpid())
}
