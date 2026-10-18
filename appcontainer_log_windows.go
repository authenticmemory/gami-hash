//go:build !cli && windows && windows_appcontainer

package main

import (
	"log"
	"os"
	"path/filepath"
)

var appContainerLog *os.File

// init runs before Wails initializes so WebView2 environment/controller and
// lifecycle failures survive a GUI-subsystem exit.
func init() {
	root, err := os.UserCacheDir()
	if err != nil {
		return
	}
	dir := filepath.Join(root, "AuthenticMemory", "GAMIHash", "Logs")
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return
	}
	appContainerLog, err = os.OpenFile(filepath.Join(dir, "app.log"), os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0o600)
	if err != nil {
		return
	}
	log.SetOutput(appContainerLog)
	log.SetFlags(log.Ldate | log.Ltime | log.Lmicroseconds | log.LUTC)
	log.Printf("[GAMI Hash AppContainer] process start pid=%d", os.Getpid())
}
