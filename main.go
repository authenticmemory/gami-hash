// gami-hash walks a folder tree, hashes every file (SHA-256) and writes one
// CSV manifest. Double-click (no arguments) starts the graphical wizard;
// any argument switches to command-line mode.
//
// The hashing engine opens source files read-only. The current desktop GUI
// uses a WebView runtime whose network behavior is documented separately;
// source-code inspection alone does not establish a network-silent process.
package main

import (
	"log"
	"os"
)

func main() {
	if handled, code := runNativeUIWorkerIfRequested(os.Args[1:], os.Stdin, os.Stdout); handled {
		os.Exit(code)
	}
	if handled, code := runAppContainerNetworkProbeIfRequested(os.Args[1:]); handled {
		exitProcess(code)
	}
	if handled, code := runContainedWorkerIfRequested(os.Args[1:]); handled {
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
