//go:build !appcontainer_webview2_spike

package main

import "os"

func exitProcess(code int) { os.Exit(code) }
