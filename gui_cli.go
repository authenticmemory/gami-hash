//go:build cli

package main

import "errors"

func runGUI() error {
	return errors.New("this build contains the CLI only; run with --help for command-line usage")
}
