package main

import (
	"bytes"
	"encoding/csv"
	"io"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/authenticmemory/gami-hash/internal/app"
)

func TestCLIWritesManifestAndHonorsQuietMode(t *testing.T) {
	root := buildCLITree(t, map[string]string{
		"a.txt":        "abc",
		"nested/b.txt": "hello",
	})
	out := filepath.Join(t.TempDir(), "manifest.csv")

	code, stdout, stderr := captureCLI(t, "--root", root, "--output", out, "--quiet")
	if code != exitOK {
		t.Fatalf("exit=%d stdout=%q stderr=%q", code, stdout, stderr)
	}
	if stdout != "" {
		t.Fatalf("quiet CLI wrote stdout: %q", stdout)
	}
	if strings.Contains(stderr, "ETA") || strings.Contains(stderr, "%") {
		t.Fatalf("quiet CLI printed progress: %q", stderr)
	}
	if !strings.Contains(stderr, "done: 2 files") {
		t.Fatalf("quiet CLI did not print completion summary: %q", stderr)
	}

	rows := readCLIManifest(t, out)
	if len(rows) != 2 {
		t.Fatalf("rows=%d, want 2", len(rows))
	}
	for _, row := range rows {
		if !strings.HasPrefix(row[2], "sha256:") {
			t.Fatalf("hash is missing sha256 prefix: %v", row)
		}
	}
}

func TestCLIHelpExitsSuccessfully(t *testing.T) {
	code, stdout, stderr := captureCLI(t, "--help")
	if code != exitOK {
		t.Fatalf("exit=%d, want %d; stdout=%q stderr=%q", code, exitOK, stdout, stderr)
	}
	if stdout != "" {
		t.Fatalf("help wrote stdout: %q", stdout)
	}
	if !strings.Contains(stderr, "Usage:") {
		t.Fatalf("help did not print usage: %q", stderr)
	}
	if !strings.Contains(stderr, cliNoArgsUsage) {
		t.Fatalf("help did not include build-specific no-args guidance: %q", stderr)
	}
	if !strings.Contains(stderr, `--root "D:\Archive Drive\Collection A"`) {
		t.Fatalf("help did not explain quoting paths with spaces: %q", stderr)
	}
}

func TestCLIInteractiveNoArgsPromptsForPaths(t *testing.T) {
	root := buildCLITree(t, map[string]string{"a.txt": "abc"})
	out := filepath.Join(t.TempDir(), "manifest.csv")
	code, stdout, stderr := captureCLIInteractive(t, root+"\n"+out+"\n")
	if code != exitOK {
		t.Fatalf("exit=%d stdout=%q stderr=%q", code, stdout, stderr)
	}
	if !strings.Contains(stderr, "Enter root folder:") || !strings.Contains(stderr, "Enter output CSV file:") {
		t.Fatalf("interactive prompts missing: %q", stderr)
	}
	rows := readCLIManifest(t, out)
	if len(rows) != 1 {
		t.Fatalf("rows=%d, want 1", len(rows))
	}
}

func TestCLIInteractiveNoArgsAddsCSVExtension(t *testing.T) {
	root := buildCLITree(t, map[string]string{"a.txt": "abc"})
	out := filepath.Join(t.TempDir(), "manifest")
	code, stdout, stderr := captureCLIInteractive(t, root+"\n"+out+"\n")
	if code != exitOK {
		t.Fatalf("exit=%d stdout=%q stderr=%q", code, stdout, stderr)
	}
	_, reported, found := strings.Cut(stderr, " recorded in ")
	reported = strings.TrimSpace(reported)
	if !found || filepath.Ext(reported) != ".csv" {
		t.Fatalf("completion did not use .csv output path: %q", stderr)
	}
	// Windows canonicalization can expand short names or change path casing.
	// Verify file identity rather than requiring the original spelling.
	expectedInfo, err := os.Stat(out + ".csv")
	if err != nil {
		t.Fatal(err)
	}
	reportedInfo, err := os.Stat(reported)
	if err != nil {
		t.Fatalf("cannot stat reported output %q: %v", reported, err)
	}
	if !os.SameFile(expectedInfo, reportedInfo) {
		t.Fatalf("reported output %q is not the requested manifest %q", reported, out+".csv")
	}
	readCLIManifest(t, out+".csv")
}

func TestCLINonInteractiveNoArgsDoesNotHang(t *testing.T) {
	code, stdout, stderr := captureCLIWithInput(t, "", false)
	if code != exitFatal {
		t.Fatalf("exit=%d, want %d; stdout=%q stderr=%q", code, exitFatal, stdout, stderr)
	}
	if strings.Contains(stderr, "Enter root folder:") {
		t.Fatalf("non-interactive CLI prompted: %q", stderr)
	}
}

func TestCLIRejectsBadArgumentsWithStableExitCode(t *testing.T) {
	root := t.TempDir()
	code, _, stderr := captureCLI(t, "--root", root, "--output", filepath.Join(root, "manifest.csv"), "--quiet")
	if code != exitFatal {
		t.Fatalf("exit=%d, want %d; stderr=%q", code, exitFatal, stderr)
	}
	if !strings.Contains(stderr, "error:") {
		t.Fatalf("fatal diagnostic missing: %q", stderr)
	}

	code, _, stderr = captureCLI(t, "--root", root, "--output", filepath.Join(t.TempDir(), "manifest.csv"), "--workers", "65", "--quiet")
	if code != exitFatal {
		t.Fatalf("exit=%d, want %d; stderr=%q", code, exitFatal, stderr)
	}
	if !strings.Contains(stderr, "-workers must be between 1 and 64") {
		t.Fatalf("worker diagnostic missing: %q", stderr)
	}

	code, _, stderr = captureCLI(t, "--root", root, "--output", filepath.Join(t.TempDir(), "manifest.xlsx"), "--quiet")
	if code != exitFatal {
		t.Fatalf("exit=%d, want %d; stderr=%q", code, exitFatal, stderr)
	}
	if !strings.Contains(stderr, "output file must end with .csv") {
		t.Fatalf("CSV-extension diagnostic missing: %q", stderr)
	}
}

func TestCLIWorkerOverrideProducesEquivalentManifest(t *testing.T) {
	root := buildCLITree(t, map[string]string{
		"1.txt": "one",
		"2.txt": "two",
		"3.txt": "three",
		"4.txt": "four",
	})
	out1 := filepath.Join(t.TempDir(), "one.csv")
	out4 := filepath.Join(t.TempDir(), "four.csv")

	if code, _, stderr := captureCLI(t, "--root", root, "--output", out1, "--workers", "1", "--quiet"); code != exitOK {
		t.Fatalf("workers=1 exit=%d stderr=%q", code, stderr)
	}
	if code, _, stderr := captureCLI(t, "--root", root, "--output", out4, "--workers", "4", "--quiet"); code != exitOK {
		t.Fatalf("workers=4 exit=%d stderr=%q", code, stderr)
	}
	if !bytes.Equal(readFile(t, out1), readFile(t, out4)) {
		t.Fatal("worker override changed manifest bytes")
	}
}

func TestCLIAndGUIBoundaryProduceEquivalentManifest(t *testing.T) {
	root := buildCLITree(t, map[string]string{
		"a.txt":        "abc",
		"nested/b.txt": "hello",
	})
	cliOut := filepath.Join(t.TempDir(), "cli.csv")
	guiOut := filepath.Join(t.TempDir(), "gui.csv")

	if code, _, stderr := captureCLI(t, "--root", root, "--output", cliOut, "--quiet"); code != exitOK {
		t.Fatalf("CLI exit=%d stderr=%q", code, stderr)
	}

	svc := app.NewService(nil, nil)
	if err := svc.Start(app.RunRequest{Root: root, Output: guiOut, Workers: 2, Mode: app.ModeFresh}); err != nil {
		t.Fatal(err)
	}
	event := waitCLITerminal(t, svc.Events())
	if event.Kind != app.EventResult || event.Result == nil {
		t.Fatalf("GUI service failed: %+v", event)
	}
	if !bytes.Equal(readFile(t, cliOut), readFile(t, guiOut)) {
		t.Fatal("CLI and GUI service manifests differ")
	}
}

func captureCLI(t *testing.T, args ...string) (int, string, string) {
	t.Helper()
	return captureCLIWithArgsAndInput(t, args, "", false)
}

func captureCLIInteractive(t *testing.T, input string) (int, string, string) {
	t.Helper()
	return captureCLIWithArgsAndInput(t, nil, input, true)
}

func captureCLIWithInput(t *testing.T, input string, interactive bool) (int, string, string) {
	t.Helper()
	return captureCLIWithArgsAndInput(t, nil, input, interactive)
}

func captureCLIWithArgsAndInput(t *testing.T, args []string, input string, interactive bool) (int, string, string) {
	t.Helper()

	oldStdout, oldStderr := os.Stdout, os.Stderr
	in := tempInput(t, input)
	defer in.Close()
	outR, outW, err := os.Pipe()
	if err != nil {
		t.Fatal(err)
	}
	errR, errW, err := os.Pipe()
	if err != nil {
		t.Fatal(err)
	}
	os.Stdout, os.Stderr = outW, errW
	defer func() {
		os.Stdout, os.Stderr = oldStdout, oldStderr
	}()

	outDone := make(chan string)
	errDone := make(chan string)
	go readPipe(outR, outDone)
	go readPipe(errR, errDone)

	code := runCLIWithIO(args, in, outW, errW, interactive)
	outW.Close()
	errW.Close()

	return code, <-outDone, <-errDone
}

func tempInput(t *testing.T, input string) *os.File {
	t.Helper()
	f, err := os.CreateTemp(t.TempDir(), "stdin-*.txt")
	if err != nil {
		t.Fatal(err)
	}
	if _, err := f.WriteString(input); err != nil {
		t.Fatal(err)
	}
	if _, err := f.Seek(0, io.SeekStart); err != nil {
		t.Fatal(err)
	}
	return f
}

func readPipe(r *os.File, done chan<- string) {
	var b bytes.Buffer
	_, _ = io.Copy(&b, r)
	_ = r.Close()
	done <- b.String()
}

func buildCLITree(t *testing.T, files map[string]string) string {
	t.Helper()
	root := t.TempDir()
	for rel, content := range files {
		abs := filepath.Join(root, filepath.FromSlash(rel))
		if err := os.MkdirAll(filepath.Dir(abs), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(abs, []byte(content), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	return root
}

func readCLIManifest(t *testing.T, output string) [][]string {
	t.Helper()
	data := readFile(t, output)
	if !bytes.HasPrefix(data, []byte{0xEF, 0xBB, 0xBF}) {
		t.Fatal("manifest is missing UTF-8 BOM")
	}
	r := csv.NewReader(bytes.NewReader(data[3:]))
	rows, err := r.ReadAll()
	if err != nil {
		t.Fatal(err)
	}
	if len(rows) == 0 || strings.Join(rows[0], ",") != "relative_path,size_bytes,sha256,mtime_utc,source_record_id" {
		t.Fatalf("bad manifest header: %v", rows)
	}
	return rows[1:]
}

func readFile(t *testing.T, path string) []byte {
	t.Helper()
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	return data
}

func waitCLITerminal(t *testing.T, events <-chan app.Event) app.Event {
	t.Helper()
	timer := time.NewTimer(10 * time.Second)
	defer timer.Stop()
	for {
		select {
		case event := <-events:
			if event.Kind == app.EventResult || event.Kind == app.EventFatal {
				return event
			}
		case <-timer.C:
			t.Fatal("timed out waiting for GUI service result")
		}
	}
}
