//go:build windows && windows_appcontainer

package main

import "syscall"

func exitProcess(code int) {
	dll := syscall.NewLazyDLL("GamiHashStorageBridge.dll")
	dll.NewProc("GamiTerminateHost").Call(uintptr(code))
}
