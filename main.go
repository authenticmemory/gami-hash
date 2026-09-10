// gami-hash walks a folder tree, hashes every file (SHA-256) and writes one
// CSV manifest. Double-click (no arguments) starts the graphical wizard;
// any argument switches to command-line mode.
//
// The program is strictly read-only towards the scanned folder, needs no
// installation and no admin rights, and contains no networking code at all.
package main

import (
	"os"
)

func main() {
	if len(os.Args) > 1 || cliHandlesNoArgs() {
		attachConsole() // no-op except on Windows GUI-subsystem builds
		os.Exit(runCLI(os.Args[1:]))
	}
	if err := runGUI(); err != nil {
		os.Exit(1)
	}
}
