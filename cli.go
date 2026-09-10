package main

import (
	"bufio"
	"context"
	"errors"
	"flag"
	"fmt"
	"os"
	"os/signal"
	"strings"
	"time"

	"github.com/authenticmemory/gami-hash/internal/engine"
	"github.com/authenticmemory/gami-hash/internal/i18n"
	"github.com/authenticmemory/gami-hash/internal/ui"
)

// Exit codes of the command-line mode.
const (
	exitOK        = 0   // completed, every file hashed
	exitFatal     = 1   // could not run (bad arguments, output not writable, ...)
	exitFileError = 2   // completed, but some files could not be read (see error log)
	exitCanceled  = 130 // interrupted (Ctrl-C); progress saved, run again to resume
)

func runCLI(args []string) int {
	return runCLIWithIO(args, os.Stdin, os.Stdout, os.Stderr, isTerminal(os.Stdin))
}

func runCLIWithIO(args []string, stdin *os.File, stdout, stderr *os.File, interactive bool) int {
	fs := flag.NewFlagSet("gami-hash", flag.ContinueOnError)
	fs.SetOutput(stderr)
	root := fs.String("root", "", "folder to scan (required)")
	output := fs.String("output", "", "CSV file to write (required, must be outside -root)")
	workers := fs.Int("workers", engine.DefaultWorkers, "parallel hashing workers (1-2 for spinning disks, more for SSDs)")
	fresh := fs.Bool("fresh", false, "start over instead of resuming an interrupted run")
	rehashExisting := fs.Bool("rehash-existing", false, "on resume, verify all existing rows again")
	quiet := fs.Bool("quiet", false, "no progress output")
	version := fs.Bool("version", false, "print version and exit")
	fs.Usage = func() {
		fmt.Fprintf(stderr, `gami-hash %s — hashes every file in a folder and writes one CSV manifest.

Usage:
  gami-hash --root FOLDER --output FILE.csv [--workers N] [--fresh] [--rehash-existing] [--quiet]

%s

The scanned folder is only ever read. Output columns:
  %s
An interrupted run (Ctrl-C, crash, power loss) is resumed automatically when
called again with the same -root and -output.

Exit codes: 0 done · 1 fatal error · 2 done but some files unreadable · 130 interrupted

Flags:
`, engine.Version, cliNoArgsUsage, "relative_path,filename,size_bytes,sha256,mtime_utc")
		fs.PrintDefaults()
	}
	if err := fs.Parse(args); err != nil {
		if errors.Is(err, flag.ErrHelp) {
			return exitOK
		}
		return exitFatal
	}
	if *version {
		fmt.Fprintln(stdout, "gami-hash", engine.Version)
		return exitOK
	}
	if fs.NArg() != 0 {
		fmt.Fprintf(stderr, "error: unexpected argument %q\n", fs.Arg(0))
		return exitFatal
	}
	if *root == "" && *output == "" && len(args) == 0 && interactive {
		promptedRoot, promptedOutput, ok := promptCLI(stdin, stderr)
		if !ok {
			return exitCanceled
		}
		*root = promptedRoot
		*output = promptedOutput
	}
	if *root == "" || *output == "" {
		fs.Usage()
		return exitFatal
	}
	if *workers < 1 || *workers > 64 {
		fmt.Fprintln(stderr, "error: -workers must be between 1 and 64")
		return exitFatal
	}

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt)
	defer stop()

	t := i18n.T{}
	eta := ui.NewETA()
	var lastLine int
	printProgress := func(p engine.Progress) {
		if *quiet {
			return
		}
		var line string
		if p.Phase == engine.PhaseScan {
			line = fmt.Sprintf("counting files … %s files, %s", t.FormatInt(p.FilesTotal), t.FormatSize(p.BytesTotal))
		} else {
			pct := 0.0
			if p.BytesTotal > 0 {
				pct = float64(p.BytesDone) / float64(p.BytesTotal) * 100
			}
			if pct > 100 {
				pct = 100
			}
			etaStr := "--"
			if secs, ok := eta.Update(p.BytesDone, p.BytesTotal); ok {
				etaStr = t.FormatETA(secs)
			}
			line = fmt.Sprintf("%5.1f%% · %s / %s files · %s / %s · ETA %s",
				pct, t.FormatInt(p.FilesDone), t.FormatInt(p.FilesTotal),
				t.FormatSize(p.BytesDone), t.FormatSize(p.BytesTotal), etaStr)
		}
		// Overwrite the previous line (pad so leftovers are erased).
		if pad := lastLine - len(line); pad > 0 {
			line += strings.Repeat(" ", pad)
		}
		lastLine = len(line)
		fmt.Fprintf(stderr, "\r%s", line)
	}

	// Throttle terminal updates to 2/s.
	last := time.Time{}
	progressFn := func(p engine.Progress) {
		if time.Since(last) < 500*time.Millisecond {
			return
		}
		last = time.Now()
		printProgress(p)
	}

	res, err := engine.Run(ctx, engine.Options{
		Root:           *root,
		Output:         *output,
		Workers:        *workers,
		Fresh:          *fresh,
		RehashExisting: *rehashExisting,
	}, progressFn)
	if !*quiet {
		fmt.Fprintln(stderr)
	}
	if err != nil {
		fmt.Fprintln(stderr, "error:", err)
		return exitFatal
	}

	if res.Canceled {
		fmt.Fprintf(stderr, "interrupted — progress saved (%s files hashed this run).\n", t.FormatInt(res.FilesHashed))
		fmt.Fprintf(stderr, "run the same command again to resume.\n")
		return exitCanceled
	}

	fmt.Fprintf(stderr, "done: %s files (%s) recorded in %s\n",
		t.FormatInt(res.FilesHashed+res.FilesResumed), t.FormatSize(res.BytesTotal), res.Output)
	if res.FilesResumed > 0 {
		fmt.Fprintf(stderr, "      %s of these were already recorded by a previous run\n", t.FormatInt(res.FilesResumed))
	}
	if res.Skipped > 0 {
		fmt.Fprintf(stderr, "      %s non-regular entries skipped (symlinks etc.), see %s\n",
			t.FormatInt(res.Skipped), engine.ErrorLogPath(res.Output))
	}
	if res.FilesFailed > 0 {
		fmt.Fprintf(stderr, "warning: %s files could not be read, see %s\n",
			t.FormatInt(res.FilesFailed), engine.ErrorLogPath(res.Output))
		return exitFileError
	}
	return exitOK
}

func promptCLI(stdin *os.File, stderr *os.File) (string, string, bool) {
	reader := bufio.NewReader(stdin)
	fmt.Fprintln(stderr, "GAMI Hash interactive CLI")
	root, ok := promptLine(reader, stderr, "Enter root folder: ")
	if !ok {
		return "", "", false
	}
	output, ok := promptLine(reader, stderr, "Enter output CSV file: ")
	if !ok {
		return "", "", false
	}
	return root, output, true
}

func promptLine(reader *bufio.Reader, stderr *os.File, label string) (string, bool) {
	fmt.Fprint(stderr, label)
	value, err := reader.ReadString('\n')
	if err != nil && len(value) == 0 {
		fmt.Fprintln(stderr)
		return "", false
	}
	return strings.TrimSpace(value), true
}
