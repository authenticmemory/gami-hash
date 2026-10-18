//go:build !cli && windows && windows_appcontainer

package main

import (
	"log"
	"os"
	"path/filepath"
)

// webViewUserDataPath gives WebView2 an explicitly writable location inside
// the package's redirected per-user data. The app must not rely on writing
// beside its installed executable, which is read-only after MSIX installation.
func webViewUserDataPath() string {
	root, err := os.UserCacheDir()
	if err != nil {
		log.Printf("[GAMI Hash AppContainer] resolve user cache: %v", err)
		return ""
	}
	path := filepath.Join(root, "AuthenticMemory", "GAMIHash", "WebView2")
	if err := os.MkdirAll(path, 0o700); err != nil {
		log.Printf("[GAMI Hash AppContainer] create user data folder %q: %v", path, err)
		return ""
	}
	log.Printf("[GAMI Hash AppContainer] user data folder: %s", path)
	return path
}
