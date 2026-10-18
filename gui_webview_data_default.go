//go:build !cli && !windows_appcontainer

package main

func webViewUserDataPath() string { return "" }
