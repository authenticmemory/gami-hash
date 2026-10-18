//go:build windows && appcontainer_webview2_spike

package main

import "syscall"

func exitProcess(code int) {
	dll := syscall.NewLazyDLL("GamiHashStorageBridge.dll")
	dll.NewProc("GamiTerminateHost").Call(uintptr(code))
}
