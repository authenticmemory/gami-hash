//go:build !cli && windows && windows_appcontainer

package main

import (
	"log"
	"os"
	"path/filepath"
	"unsafe"

	"golang.org/x/sys/windows"
)

var appContainerLog *os.File
var appContainerJob windows.Handle

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
	if err := ownProcessTree(); err != nil {
		log.Printf("[GAMI Hash AppContainer] process-tree job unavailable: %v", err)
	} else {
		log.Printf("[GAMI Hash AppContainer] process-tree job active")
	}
}

// ownProcessTree makes WebView2 and every other descendant die when the host
// exits. Without this, WebView2 processes can outlive a forced Wails shutdown,
// retain the package deployment lock, and block both relaunch and upgrade.
func ownProcessTree() error {
	job, err := windows.CreateJobObject(nil, nil)
	if err != nil {
		return err
	}
	info := windows.JOBOBJECT_EXTENDED_LIMIT_INFORMATION{}
	info.BasicLimitInformation.LimitFlags = windows.JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE
	if _, err = windows.SetInformationJobObject(
		job,
		windows.JobObjectExtendedLimitInformation,
		uintptr(unsafe.Pointer(&info)),
		uint32(unsafe.Sizeof(info)),
	); err != nil {
		windows.CloseHandle(job)
		return err
	}
	process, err := windows.GetCurrentProcess()
	if err != nil {
		windows.CloseHandle(job)
		return err
	}
	if err = windows.AssignProcessToJobObject(job, process); err != nil {
		windows.CloseHandle(job)
		return err
	}
	appContainerJob = job
	return nil
}
