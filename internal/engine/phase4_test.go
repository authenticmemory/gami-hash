package engine

import (
	"context"
	"encoding/csv"
	"encoding/hex"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strconv"
	"strings"
	"testing"
	"time"
)

func TestPhase4EmptyFoldersAndZeroByteFiles(t *testing.T) {
	root := t.TempDir()
	if err := os.MkdirAll(filepath.Join(root, "empty", "nested"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(root, "zero.bin"), nil, 0o644); err != nil {
		t.Fatal(err)
	}
	out := filepath.Join(t.TempDir(), "manifest.csv")
	res := runFresh(t, root, out)
	rows := readRows(t, out)
	if res.FilesHashed != 1 || len(rows) != 1 {
		t.Fatalf("empty directories affected manifest: result=%+v rows=%v", res, rows)
	}
	if rows[0][0] != "zero.bin" || rows[0][2] != "0" || rows[0][3] != sha256hex("") {
		t.Fatalf("incorrect zero-byte row: %v", rows[0])
	}
}

func TestPhase4UnicodeNormalizationRemainsDistinct(t *testing.T) {
	files := map[string]string{
		"Überblick.txt":       "NFC",
		"U\u0308berblick.txt": "NFD",
		"資料-文件.txt":           "CJK",
		"archive-📁.txt":       "emoji",
	}
	root := buildTree(t, files)
	entries, err := os.ReadDir(root)
	if err != nil {
		t.Fatal(err)
	}
	if len(entries) != len(files) {
		t.Skipf("filesystem normalizes canonically equivalent Unicode names; cannot test NFC/NFD coexistence (created %d of %d names)", len(entries), len(files))
	}
	out := filepath.Join(t.TempDir(), "manifest.csv")
	res := runFresh(t, root, out)
	rows := rowMap(readRows(t, out))
	if int(res.FilesHashed) != len(files) || len(rows) != len(files) {
		t.Fatalf("distinct Unicode names collapsed: result=%+v rows=%v", res, rows)
	}
	for name, content := range files {
		if row := rows[name]; row == nil || row[3] != sha256hex(content) {
			t.Errorf("missing or incorrect Unicode row %q: %v", name, row)
		}
	}
}

func TestPhase4FileDeletedDuringHashIsOmitted(t *testing.T) {
	root := buildTree(t, map[string]string{"vanishing.bin": strings.Repeat("x", 1<<20)})
	out := filepath.Join(t.TempDir(), "manifest.csv")
	var removeErr error
	res, err := Run(context.Background(), Options{
		Root: root, Output: out, Fresh: true, Workers: 1,
		afterHashRead: func(path string) { removeErr = os.Remove(path) },
	}, nil)
	if removeErr != nil {
		t.Skipf("filesystem would not delete an open file: %v", removeErr)
	}
	if err != nil {
		t.Fatal(err)
	}
	if res.FilesFailed != 1 || len(readRows(t, out)) != 0 {
		t.Fatalf("deleted file was accepted: %+v", res)
	}
}

func TestPhase4DigestMatchesIndependentTool(t *testing.T) {
	root := buildTree(t, map[string]string{"sample.bin": "GAMI independent digest comparison\n"})
	path := filepath.Join(root, "sample.bin")
	out := filepath.Join(t.TempDir(), "manifest.csv")
	runFresh(t, root, out)
	want := rowMap(readRows(t, out))["sample.bin"][3]

	var cmd *exec.Cmd
	if runtime.GOOS == "windows" {
		cmd = exec.Command("powershell.exe", "-NoProfile", "-NonInteractive", "-Command",
			"(Get-FileHash -LiteralPath $args[0] -Algorithm SHA256).Hash", path)
	} else {
		cmd = exec.Command("sha256sum", "--", path)
	}
	b, err := cmd.Output()
	if err != nil {
		t.Skipf("independent hashing tool unavailable: %v", err)
	}
	fields := strings.Fields(string(b))
	if len(fields) == 0 {
		t.Fatal("independent hashing tool returned no digest")
	}
	got := strings.ToLower(fields[0])
	if _, err := hex.DecodeString(got); err != nil || len(got) != 64 {
		t.Fatalf("invalid independent digest %q", got)
	}
	if formatManifestHash(got) != want {
		t.Fatalf("digest mismatch: engine=%s independent=%s", want, got)
	}
}

func TestPhase4OptInFileCountScale(t *testing.T) {
	if os.Getenv("GAMI_RUN_STRESS") != "I_UNDERSTAND" {
		t.Skip("set GAMI_RUN_STRESS=I_UNDERSTAND and GAMI_STRESS_FILE_COUNT to opt in")
	}
	raw := os.Getenv("GAMI_STRESS_FILE_COUNT")
	if raw == "" {
		t.Fatal("GAMI_STRESS_FILE_COUNT is required when stress testing is enabled")
	}
	count, err := strconv.Atoi(raw)
	if err != nil || count < 1 || count > 5_000_000 {
		t.Fatalf("GAMI_STRESS_FILE_COUNT must be between 1 and 5000000, got %q", raw)
	}
	root := t.TempDir()
	outDir := t.TempDir()
	t.Logf("stress corpus: %s", root)
	t.Logf("stress artifacts: %s", outDir)
	createStarted := time.Now()
	createStep := max(1, count/20)
	for i := 0; i < count; i++ {
		dir := filepath.Join(root, fmt.Sprintf("d%05d", i/1000))
		if i%1000 == 0 {
			if err := os.MkdirAll(dir, 0o755); err != nil {
				t.Fatal(err)
			}
		}
		name := filepath.Join(dir, fmt.Sprintf("f%09d", i))
		if err := os.WriteFile(name, nil, 0o644); err != nil {
			t.Fatalf("create file %d: %v", i, err)
		}
		created := i + 1
		if created%createStep == 0 || created == count {
			t.Logf("create: %d/%d (%.1f%%), elapsed %s", created, count,
				100*float64(created)/float64(count), time.Since(createStarted).Round(time.Second))
		}
	}
	t.Logf("create complete: %s", time.Since(createStarted).Round(time.Millisecond))

	out := filepath.Join(outDir, "manifest.csv")
	hashStarted := time.Now()
	lastReport := time.Time{}
	res, err := Run(context.Background(), Options{Root: root, Output: out, Fresh: true}, func(p Progress) {
		now := time.Now()
		if !lastReport.IsZero() && now.Sub(lastReport) < 5*time.Second && p.FilesDone < p.FilesTotal {
			return
		}
		lastReport = now
		phase := "scan"
		if p.Phase == PhaseHash {
			phase = "hash"
		}
		percent := float64(0)
		if p.FilesTotal > 0 {
			percent = 100 * float64(p.FilesDone) / float64(p.FilesTotal)
		}
		t.Logf("%s: %d/%d files (%.1f%%), %d/%d bytes, elapsed %s",
			phase, p.FilesDone, p.FilesTotal, percent, p.BytesDone, p.BytesTotal,
			time.Since(hashStarted).Round(time.Second))
	})
	if err != nil {
		t.Fatal(err)
	}
	t.Logf("hash complete: %s", time.Since(hashStarted).Round(time.Millisecond))
	verifyStarted := time.Now()
	rows := countManifestRows(t, out)
	info, statErr := os.Stat(out)
	if statErr != nil {
		t.Fatal(statErr)
	}
	t.Logf("verify complete: %s; rows=%d; manifest_bytes=%d",
		time.Since(verifyStarted).Round(time.Millisecond), rows, info.Size())
	if res.FilesHashed != int64(count) || rows != count {
		t.Fatalf("scale result mismatch: result=%+v", res)
	}
}

func countManifestRows(t *testing.T, path string) int {
	t.Helper()
	f, err := os.Open(path)
	if err != nil {
		t.Fatal(err)
	}
	defer f.Close()
	if _, err := f.Seek(int64(len(utf8BOM)), io.SeekStart); err != nil {
		t.Fatal(err)
	}
	r := csv.NewReader(f)
	r.FieldsPerRecord = len(csvHeader)
	if header, err := r.Read(); err != nil || !sliceEqual(header, csvHeader) {
		t.Fatalf("invalid manifest header: %v (%v)", header, err)
	}
	count := 0
	for {
		if _, err := r.Read(); err == io.EOF {
			return count
		} else if err != nil {
			t.Fatalf("invalid manifest row %d: %v", count+1, err)
		}
		count++
	}
}
