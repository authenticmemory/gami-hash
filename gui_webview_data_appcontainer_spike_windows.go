//go:build !cli && windows && appcontainer_webview2_spike

package main

import (
	"log"
	"os"
	"path/filepath"
)

// webViewUserDataPath gives WebView2 an explicitly writable location inside
// the package's redirected per-user data. The spike must not rely on writing
// beside its installed executable, which is read-only after MSIX installation.
func webViewUserDataPath() string {
	root, err := os.UserCacheDir()
	if err != nil {
		log.Printf("[AppContainer WebView2 spike] resolve user cache: %v", err)
		return ""
	}
	path := filepath.Join(root, "AuthenticMemory", "GAMIHashWebView2Spike", "WebView2")
	if err := os.MkdirAll(path, 0o700); err != nil {
		log.Printf("[AppContainer WebView2 spike] create user data folder %q: %v", path, err)
		return ""
	}
	log.Printf("[AppContainer WebView2 spike] user data folder: %s", path)
	return path
}
