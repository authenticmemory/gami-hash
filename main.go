// gami-hash walks a folder tree, hashes every file (SHA-256) and writes one
// CSV manifest. Double-click (no arguments) starts the graphical wizard;
// any argument switches to command-line mode.
//
// The hashing engine opens source files read-only. Windows uses the native WPF
// frontend; Linux and macOS use the Wails frontend.
package main

import (
	"log"
	"os"
)

func main() {
	if handled, code := runNativeUIWorkerIfRequested(os.Args[1:], os.Stdin, os.Stdout); handled {
		os.Exit(code)
	}
	if len(os.Args) > 1 || cliHandlesNoArgs() {
		attachConsole() // no-op except on Windows GUI-subsystem builds
		os.Exit(runCLI(os.Args[1:]))
	}
	if err := runGUI(); err != nil {
		log.Printf("GUI stopped: %v", err)
		os.Exit(1)
	}
}
