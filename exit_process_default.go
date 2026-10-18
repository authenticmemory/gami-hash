//go:build !windows_appcontainer

package main

import "os"

func exitProcess(code int) { os.Exit(code) }
