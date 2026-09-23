package engine

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/csv"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
	"time"
)

// buildTree creates files (path -> content) under a fresh temp root.
func buildTree(t *testing.T, files map[string]string) string {
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

func runFresh(t *testing.T, root, output string) Result {
	t.Helper()
	res, err := Run(context.Background(), Options{Root: root, Output: output, Fresh: true}, nil)
	if err != nil {
		t.Fatalf("Run failed: %v", err)
	}
	return res
}

// readRows parses the manifest and returns data rows (header checked).
func readRows(t *testing.T, output string) [][]string {
	t.Helper()
	data, err := os.ReadFile(output)
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.HasPrefix(data, utf8BOM) {
		t.Fatalf("output is missing the UTF-8 BOM")
	}
	r := csv.NewReader(bytes.NewReader(data[3:]))
	r.FieldsPerRecord = len(csvHeader)
	all, err := r.ReadAll()
	if err != nil {
		t.Fatalf("output is not valid CSV: %v", err)
	}
	if len(all) == 0 || !sliceEqual(all[0], csvHeader) {
		t.Fatalf("bad header: %v", all)
	}
	return all[1:]
}

func rowMap(rows [][]string) map[string][]string {
	m := map[string][]string{}
	for _, r := range rows {
		m[r[0]] = r
	}
	return m
}

func sha256hex(s string) string {
	sum := sha256.Sum256([]byte(s))
	return formatManifestHash(hex.EncodeToString(sum[:]))
}

func TestBasicRun(t *testing.T) {
	root := buildTree(t, map[string]string{
		"a.txt":            "abc",
		"empty.bin":        "",
		"sub/nested/b.dat": "hello world\n",
	})
	out := filepath.Join(t.TempDir(), "manifest.csv")
	res := runFresh(t, root, out)

	if res.FilesHashed != 3 || res.FilesFailed != 0 || res.Canceled {
		t.Fatalf("unexpected result: %+v", res)
	}
	rows := readRows(t, out)
	if len(rows) != 3 {
		t.Fatalf("want 3 rows, got %d", len(rows))
	}
	m := rowMap(rows)
	for path, row := range m {
		if row[4] != path {
			t.Errorf("source_record_id must equal relative_path: %v", row)
		}
	}

	// Known SHA-256 vectors.
	if m["a.txt"][2] != "sha256:ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad" {
		t.Errorf("wrong hash for a.txt: %s", m["a.txt"][2])
	}
	if m["empty.bin"][2] != "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855" {
		t.Errorf("wrong hash for empty file: %s", m["empty.bin"][2])
	}
	if m["sub/nested/b.dat"][2] != sha256hex("hello world\n") {
		t.Errorf("wrong hash for nested file")
	}
	// Columns: relative path uses forward slashes; size; hash; mtime UTC.
	if m["sub/nested/b.dat"][1] != "12" {
		t.Errorf("bad row: %v", m["sub/nested/b.dat"])
	}
	if ts := m["a.txt"][3]; !strings.HasSuffix(ts, "Z") {
		t.Errorf("mtime not UTC RFC3339: %s", ts)
	} else if _, err := time.Parse(time.RFC3339, ts); err != nil {
		t.Errorf("mtime unparsable: %s", ts)
	}
	// Checkpoint must be gone after a successful run.
	if fileExists(CheckpointPath(out)) {
		t.Error("checkpoint not removed after success")
	}
	// No error log for a clean run.
	if fileExists(ErrorLogPath(out)) {
		t.Error("unexpected error log")
	}
}

func TestSpecialFilenames(t *testing.T) {
	files := map[string]string{
		"Bericht_Über_Grüße.pdf":       "umlauts NFC",
		"Bericht_Über (NFD) Kopie.md": "umlauts NFD",
		"comma, file.txt":              "punctuation",
		"emoji 📁 name.bin":             "emoji",
		"日本語ファイル.txt":                  "cjk",
		" leading space.txt":           "space",
		"-leading-dash.txt":            "dash",
	}
	// Control characters in names are recorded percent-encoded so the
	// manifest stays one line per file.
	encoded := map[string]string{}
	if runtime.GOOS != "windows" {
		files["comma, quote\" file.txt"] = "quoted punctuation"
		encoded["tab\tname.txt"] = "tab%09name.txt"
		encoded["new\nline.txt"] = "new%0Aline.txt"
	}
	for raw, enc := range encoded {
		files[raw] = "control char " + enc
	}
	root := buildTree(t, files)
	out := filepath.Join(t.TempDir(), "m.csv")
	res := runFresh(t, root, out)
	if int(res.FilesHashed) != len(files) {
		t.Fatalf("hashed %d of %d files", res.FilesHashed, len(files))
	}
	m := rowMap(readRows(t, out))
	for rel, content := range files {
		if enc, ok := encoded[rel]; ok {
			rel = enc
		}
		row, ok := m[rel]
		if !ok {
			t.Errorf("missing row for %q", rel)
			continue
		}
		if row[2] != sha256hex(content) {
			t.Errorf("wrong hash for %q", rel)
		}
	}
	// No row may contain a line break: one line per file, always.
	for rel := range m {
		if strings.ContainsAny(rel, "\n\r\t") {
			t.Errorf("unencoded control character in %q", rel)
		}
	}
}

func TestInvalidUTF8Filename(t *testing.T) {
	if runtime.GOOS != "linux" {
		t.Skip("invalid-UTF-8 names are a POSIX phenomenon")
	}
	root := t.TempDir()
	name := string([]byte{0xE4}) + "bc.txt" // latin1 'ä' — not valid UTF-8
	if err := os.WriteFile(filepath.Join(root, name), []byte("x"), 0o644); err != nil {
		t.Skip("filesystem refuses invalid UTF-8 names")
	}
	out := filepath.Join(t.TempDir(), "m.csv")
	res := runFresh(t, root, out)
	if res.FilesHashed != 1 || res.FilesFailed != 0 {
		t.Fatalf("unexpected: %+v", res)
	}
	rows := readRows(t, out)
	// The invalid byte must be recorded percent-encoded so the CSV stays
	// valid UTF-8, and the raw name must be documented in the error log.
	if rows[0][0] != "%E4bc.txt" || rows[0][1] != "%E4bc.txt" {
		t.Errorf("invalid byte not percent-encoded: %v", rows[0])
	}
	if rows[0][2] != sha256hex("x") {
		t.Error("wrong hash for invalid-UTF-8 name")
	}
	log, err := os.ReadFile(ErrorLogPath(out))
	if err != nil || !strings.Contains(string(log), `\xe4`) {
		t.Errorf("raw name not documented in error log: %s", log)
	}
}

func TestEncodeNameSpecials(t *testing.T) {
	cases := []struct{ in, want string }{
		{"normal.txt", "normal.txt"},
		{"Grüße.pdf", "Grüße.pdf"},           // valid UTF-8 untouched
		{"gru\xdf.txt", "gru%DF.txt"},        // latin1 ß
		{"\xe4bc.txt", "%E4bc.txt"},          // latin1 ä
		{"a\xff\xfeb", "a%FF%FEb"},           // multiple invalid bytes
		{"50%rabatt.txt", "50%25rabatt.txt"}, // literal % is escaped to keep encoding injective
		{"new\nline", "new%0Aline"},          // newline
		{"tab\there", "tab%09here"},          // tab
		{"cr\rhere", "cr%0Dhere"},            // carriage return
		{"del\x7fhere", "del%7Fhere"},        // DEL
	}
	for _, c := range cases {
		if got := encodeNameSpecials(c.in); got != c.want {
			t.Errorf("encodeNameSpecials(%q) = %q, want %q", c.in, got, c.want)
		}
	}
	// Truncated multi-byte sequence: each invalid byte encoded, valid rest kept.
	if got := encodeNameSpecials("ok\xc3\x28bad"); got != "ok%C3(bad" {
		t.Errorf("truncated sequence: %q", got)
	}
}

func TestDeterministicOutput(t *testing.T) {
	root := buildTree(t, map[string]string{
		"z.txt": "1", "a.txt": "2", "m/x.txt": "3", "m/a.txt": "4", "b/b.txt": "5",
	})
	out1 := filepath.Join(t.TempDir(), "one.csv")
	out2 := filepath.Join(t.TempDir(), "two.csv")
	// More workers than files to stress the reordering writer.
	if _, err := Run(context.Background(), Options{Root: root, Output: out1, Workers: 8, Fresh: true}, nil); err != nil {
		t.Fatal(err)
	}
	if _, err := Run(context.Background(), Options{Root: root, Output: out2, Workers: 1, Fresh: true}, nil); err != nil {
		t.Fatal(err)
	}
	b1, _ := os.ReadFile(out1)
	b2, _ := os.ReadFile(out2)
	if !bytes.Equal(b1, b2) {
		t.Error("output differs between runs / worker counts")
	}
	rows := readRows(t, out1)
	want := []string{"a.txt", "b/b.txt", "m/a.txt", "m/x.txt", "z.txt"}
	for i, w := range want {
		if rows[i][0] != w {
			t.Fatalf("row %d = %q, want %q (order not deterministic)", i, rows[i][0], w)
		}
	}
}

func TestOrderingIsGlobalEncodedPathOrder(t *testing.T) {
	root := buildTree(t, map[string]string{
		"a/child.txt": "1", "a.txt": "2", "a-/child.txt": "3", "a%.txt": "4", "z.txt": "5",
	})
	out := filepath.Join(t.TempDir(), "manifest.csv")
	runFresh(t, root, out)
	rows := readRows(t, out)
	for i := 1; i < len(rows); i++ {
		if rows[i-1][0] >= rows[i][0] {
			t.Fatalf("rows not globally sorted: %q before %q", rows[i-1][0], rows[i][0])
		}
	}
}

func TestUnreadableFileAndDirDoNotAbort(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("chmod does not remove read access on Windows")
	}
	if os.Getuid() == 0 {
		t.Skip("running as root, permissions are not enforced")
	}
	root := buildTree(t, map[string]string{
		"ok1.txt":         "fine",
		"secret.txt":      "nope",
		"okdir/ok2.txt":   "fine too",
		"baddir/lost.txt": "invisible",
	})
	if err := os.Chmod(filepath.Join(root, "secret.txt"), 0); err != nil {
		t.Fatal(err)
	}
	if err := os.Chmod(filepath.Join(root, "baddir"), 0); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		os.Chmod(filepath.Join(root, "secret.txt"), 0o644)
		os.Chmod(filepath.Join(root, "baddir"), 0o755)
	})

	out := filepath.Join(t.TempDir(), "m.csv")
	res := runFresh(t, root, out)
	if res.FilesHashed != 2 {
		t.Errorf("want 2 hashed, got %d", res.FilesHashed)
	}
	if res.FilesFailed != 2 { // the file and the directory
		t.Errorf("want 2 failures, got %d", res.FilesFailed)
	}
	if res.ErrorLog == "" || !fileExists(res.ErrorLog) {
		t.Fatal("error log missing")
	}
	log, _ := os.ReadFile(res.ErrorLog)
	if !strings.Contains(string(log), "secret.txt") || !strings.Contains(string(log), "baddir") {
		t.Errorf("error log incomplete:\n%s", log)
	}
	m := rowMap(readRows(t, out))
	if _, ok := m["secret.txt"]; ok {
		t.Error("unreadable file must not appear in the manifest")
	}
}

func TestSymlinksSkippedNotFollowed(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("symlink creation needs privileges on Windows")
	}
	root := buildTree(t, map[string]string{"real.txt": "data"})
	// Link to a file outside the tree, and a directory cycle.
	outside := filepath.Join(t.TempDir(), "outside.txt")
	os.WriteFile(outside, []byte("outside"), 0o644)
	os.Symlink(outside, filepath.Join(root, "link.txt"))
	os.Symlink(root, filepath.Join(root, "cycle"))

	out := filepath.Join(t.TempDir(), "m.csv")
	res := runFresh(t, root, out)
	if res.FilesHashed != 1 || res.Skipped != 2 {
		t.Fatalf("want 1 hashed / 2 skipped, got %+v", res)
	}
	m := rowMap(readRows(t, out))
	if _, ok := m["link.txt"]; ok {
		t.Error("symlink target was hashed — links must not be followed")
	}
}

func TestOutputInsideRootRejected(t *testing.T) {
	root := buildTree(t, map[string]string{"a.txt": "x"})
	_, err := Run(context.Background(), Options{Root: root, Output: filepath.Join(root, "m.csv")}, nil)
	if err == nil {
		t.Fatal("output inside root must be rejected")
	}
	// Sibling with a common name prefix must NOT be rejected (prefix trap).
	sibling := root + "-manifest.csv"
	defer os.Remove(sibling)
	defer os.Remove(CheckpointPath(sibling))
	if _, err := Run(context.Background(), Options{Root: root, Output: sibling, Fresh: true}, nil); err != nil {
		t.Fatalf("sibling path wrongly rejected: %v", err)
	}
}

func TestOutputMustBeCSV(t *testing.T) {
	root := buildTree(t, map[string]string{"a.txt": "x"})
	for _, name := range []string{"manifest", "manifest.txt", "manifest.xlsx"} {
		out := filepath.Join(t.TempDir(), name)
		if _, err := Run(context.Background(), Options{Root: root, Output: out}, nil); err == nil {
			t.Fatalf("output %q was accepted; only .csv should be valid", name)
		}
		if fileExists(out) {
			t.Fatalf("invalid output %q was created", out)
		}
	}

	out := filepath.Join(t.TempDir(), "manifest.CSV")
	if _, err := Run(context.Background(), Options{Root: root, Output: out}, nil); err != nil {
		t.Fatalf("uppercase .CSV should be accepted: %v", err)
	}
}

func TestScannedTreeNeverModified(t *testing.T) {
	root := buildTree(t, map[string]string{"a/x.txt": "1", "b/y.txt": "22"})
	// Read-only tree: hashing must still work, and nothing may be created.
	for _, p := range []string{filepath.Join(root, "a"), filepath.Join(root, "b"), root} {
		if err := os.Chmod(p, 0o555); err != nil {
			t.Fatal(err)
		}
	}
	t.Cleanup(func() {
		for _, p := range []string{root, filepath.Join(root, "a"), filepath.Join(root, "b")} {
			os.Chmod(p, 0o755)
		}
	})
	before := snapshotTree(t, root)
	out := filepath.Join(t.TempDir(), "m.csv")
	res := runFresh(t, root, out)
	if res.FilesHashed != 2 || res.FilesFailed != 0 {
		t.Fatalf("read-only tree not handled: %+v", res)
	}
	if after := snapshotTree(t, root); before != after {
		t.Fatalf("scanned tree changed!\nbefore: %s\nafter:  %s", before, after)
	}
}

func snapshotTree(t *testing.T, root string) string {
	t.Helper()
	var sb strings.Builder
	filepath.Walk(root, func(p string, info os.FileInfo, err error) error {
		if err != nil {
			return err
		}
		fmt.Fprintf(&sb, "%s|%d|%s|%v\n", p, info.Size(), info.Mode(), info.ModTime().UnixNano())
		return nil
	})
	return sb.String()
}

func TestResumeSkipsCompletedRows(t *testing.T) {
	files := map[string]string{}
	for i := 0; i < 50; i++ {
		files[fmt.Sprintf("dir%d/file%02d.txt", i%5, i)] = strings.Repeat("x", i*10)
	}
	root := buildTree(t, files)
	outDir := t.TempDir()
	ref := filepath.Join(outDir, "ref.csv")
	runFresh(t, root, ref)
	refRows := readRows(t, ref)

	// Simulate an interrupted run: manifest with only the first 20 rows plus
	// the checkpoint marker.
	out := filepath.Join(outDir, "resume.csv")
	writePartialCopy(t, ref, out, 20)
	writeCheckpoint(t, out, root)

	res, err := Run(context.Background(), Options{Root: root, Output: out}, nil)
	if err != nil {
		t.Fatal(err)
	}
	if res.FilesResumed != 20 {
		t.Errorf("want 20 resumed, got %d", res.FilesResumed)
	}
	if res.FilesHashed != 30 {
		t.Errorf("want 30 hashed, got %d", res.FilesHashed)
	}
	assertSameRowSet(t, refRows, readRows(t, out))
	if fileExists(CheckpointPath(out)) {
		t.Error("checkpoint not removed after completed resume")
	}
}

func TestResumeRepairsTruncatedTail(t *testing.T) {
	root := buildTree(t, map[string]string{"a.txt": "1", "b.txt": "2", "c.txt": "3"})
	outDir := t.TempDir()
	ref := filepath.Join(outDir, "ref.csv")
	runFresh(t, root, ref)
	refRows := readRows(t, ref)

	out := filepath.Join(outDir, "crash.csv")
	writePartialCopy(t, ref, out, 1)
	// A crash mid-write leaves a torn final line.
	f, _ := os.OpenFile(out, os.O_APPEND|os.O_WRONLY, 0)
	f.WriteString(`b.txt,b.txt,1,"deadbeefcafe`) // no closing quote, no newline
	f.Close()
	writeCheckpoint(t, out, root)

	res, err := Run(context.Background(), Options{Root: root, Output: out}, nil)
	if err != nil {
		t.Fatal(err)
	}
	if res.FilesResumed != 1 || res.FilesHashed != 2 {
		t.Errorf("resumed=%d hashed=%d, want 1/2", res.FilesResumed, res.FilesHashed)
	}
	assertSameRowSet(t, refRows, readRows(t, out))
}

func TestResumeRootMismatchRequiresExplicitDecision(t *testing.T) {
	root := buildTree(t, map[string]string{"a.txt": "1"})
	out := filepath.Join(t.TempDir(), "m.csv")
	runFresh(t, root, out)
	writeCheckpoint(t, out, "/somewhere/else")

	st := CheckResume(out)
	if !st.Resumable || SameRoot(st.Root, root) {
		t.Fatalf("unexpected state: %+v", st)
	}
	// The engine must not silently overwrite or append. A GUI confirmation
	// sets AllowRootMismatch; an intentional replacement sets Fresh.
	if _, err := Run(context.Background(), Options{Root: root, Output: out}, nil); err == nil {
		t.Fatal("resume across different roots must require an explicit decision")
	}
}

func TestResumeWithRootMismatchAllowed(t *testing.T) {
	// The external-drive case: same folder content, new mount point /
	// drive letter. Relative paths still match, so resume must work when
	// the user confirms it.
	files := map[string]string{"a.txt": "1", "b.txt": "2", "c.txt": "3"}
	root := buildTree(t, files)
	out := filepath.Join(t.TempDir(), "m.csv")
	runFresh(t, root, out)
	refRows := readRows(t, out)

	// Keep only 1 row, mark as interrupted under the OLD path.
	crash := filepath.Join(t.TempDir(), "crash.csv")
	writePartialCopy(t, out, crash, 1)
	writeCheckpoint(t, crash, "/old/mount/point")

	res, err := Run(context.Background(), Options{Root: root, Output: crash, AllowRootMismatch: true}, nil)
	if err != nil {
		t.Fatal(err)
	}
	if res.FilesResumed != 1 || res.FilesHashed != 2 {
		t.Fatalf("resumed=%d hashed=%d, want 1/2", res.FilesResumed, res.FilesHashed)
	}
	assertSameRowSet(t, refRows, readRows(t, crash))
}

func TestCheckResumeOnForeignCSV(t *testing.T) {
	dir := t.TempDir()
	out := filepath.Join(dir, "foreign.csv")
	os.WriteFile(out, []byte("some,other,file\n1,2,3\n"), 0o644)
	writeCheckpoint(t, out, dir)
	if st := CheckResume(out); st.Resumable {
		t.Fatal("foreign CSV must not be resumable")
	}
}

func TestCancelKeepsCheckpointAndResumes(t *testing.T) {
	// Enough data that cancellation lands mid-run: 40 files x 1 MiB.
	files := map[string]string{}
	blob := strings.Repeat("A", 1<<20)
	for i := 0; i < 40; i++ {
		files[fmt.Sprintf("f%02d.bin", i)] = blob
	}
	root := buildTree(t, files)
	out := filepath.Join(t.TempDir(), "m.csv")

	ctx, cancel := context.WithCancel(context.Background())
	var canceled bool
	progress := func(p Progress) {
		if p.Phase == PhaseHash && p.FilesDone >= 5 && !canceled {
			canceled = true
			cancel()
		}
	}
	res, err := Run(ctx, Options{Root: root, Output: out, Workers: 1, Fresh: true}, progress)
	if err != nil {
		t.Fatal(err)
	}
	if !res.Canceled {
		t.Skip("run finished before cancellation could take effect")
	}
	if !fileExists(CheckpointPath(out)) {
		t.Fatal("checkpoint must survive a cancelled run")
	}

	res2, err := Run(context.Background(), Options{Root: root, Output: out}, nil)
	if err != nil {
		t.Fatal(err)
	}
	if res2.Canceled || res2.FilesHashed+res2.FilesResumed != 40 {
		t.Fatalf("resume incomplete: %+v", res2)
	}
	rows := readRows(t, out)
	if len(rows) != 40 {
		t.Fatalf("want 40 rows, got %d", len(rows))
	}
	seen := map[string]bool{}
	for _, r := range rows {
		if seen[r[0]] {
			t.Fatalf("duplicate row for %q", r[0])
		}
		seen[r[0]] = true
		if r[2] != sha256hex(blob) {
			t.Fatalf("wrong hash for %q", r[0])
		}
	}
}

func TestEmptyTree(t *testing.T) {
	root := t.TempDir()
	out := filepath.Join(t.TempDir(), "m.csv")
	res := runFresh(t, root, out)
	if res.FilesHashed != 0 || res.FilesFailed != 0 || res.Canceled {
		t.Fatalf("unexpected: %+v", res)
	}
	if len(readRows(t, out)) != 0 {
		t.Fatal("expected empty manifest")
	}
}

func TestFilesAddedBetweenRunsAreAppendedOnResume(t *testing.T) {
	root := buildTree(t, map[string]string{"a.txt": "1"})
	out := filepath.Join(t.TempDir(), "m.csv")
	runFresh(t, root, out)

	// New file arrives; an interrupted-run marker exists.
	os.WriteFile(filepath.Join(root, "new.txt"), []byte("fresh"), 0o644)
	writeCheckpoint(t, out, root)

	res, err := Run(context.Background(), Options{Root: root, Output: out}, nil)
	if err != nil {
		t.Fatal(err)
	}
	if res.FilesResumed != 1 || res.FilesHashed != 1 {
		t.Fatalf("unexpected: %+v", res)
	}
	m := rowMap(readRows(t, out))
	if m["new.txt"][2] != sha256hex("fresh") {
		t.Fatal("new file missing or wrong")
	}
}

func TestLargeFileStreaming(t *testing.T) {
	// A sparse 64 MiB file must stream through the fixed 1 MiB buffer.
	root := t.TempDir()
	f, err := os.Create(filepath.Join(root, "big.bin"))
	if err != nil {
		t.Fatal(err)
	}
	const size = 64 << 20
	if err := f.Truncate(size); err != nil {
		t.Fatal(err)
	}
	f.Close()

	out := filepath.Join(t.TempDir(), "m.csv")
	res := runFresh(t, root, out)
	if res.FilesHashed != 1 || res.BytesHashed != size {
		t.Fatalf("unexpected: %+v", res)
	}
	// Reference: hash of 64 MiB of zeros.
	h := sha256.New()
	io.CopyN(h, zeroReader{}, size)
	want := formatManifestHash(hex.EncodeToString(h.Sum(nil)))
	if rows := readRows(t, out); rows[0][2] != want {
		t.Fatalf("hash mismatch for sparse file")
	}
}

func TestFreshOutputHardLinkCannotTruncateSource(t *testing.T) {
	root := buildTree(t, map[string]string{"precious.bin": "irreplaceable"})
	source := filepath.Join(root, "precious.bin")
	out := filepath.Join(t.TempDir(), "manifest.csv")
	if err := os.Link(source, out); err != nil {
		t.Skipf("hard links unavailable: %v", err)
	}

	res := runFresh(t, root, out)
	if res.FilesHashed != 1 {
		t.Fatalf("unexpected result: %+v", res)
	}
	data, err := os.ReadFile(source)
	if err != nil || string(data) != "irreplaceable" {
		t.Fatalf("source was changed through output hard link: %q, %v", data, err)
	}
}

func TestOutputDirectorySymlinkIntoRootRejected(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("covered by the Windows junction/reparse integration test")
	}
	root := buildTree(t, map[string]string{"a.txt": "x"})
	alias := filepath.Join(t.TempDir(), "alias")
	if err := os.Symlink(root, alias); err != nil {
		t.Skipf("symlinks unavailable: %v", err)
	}
	_, err := Run(context.Background(), Options{Root: root, Output: filepath.Join(alias, "manifest.csv"), Fresh: true}, nil)
	if err == nil {
		t.Fatal("resolved output inside root must be rejected")
	}
	if fileExists(filepath.Join(root, "manifest.csv")) {
		t.Fatal("output was created in source tree")
	}
}

func TestChangedResumeRowIsRehashed(t *testing.T) {
	root := buildTree(t, map[string]string{"a.txt": "old"})
	out := filepath.Join(t.TempDir(), "manifest.csv")
	runFresh(t, root, out)
	if err := os.WriteFile(filepath.Join(root, "a.txt"), []byte("new-and-different"), 0o644); err != nil {
		t.Fatal(err)
	}
	writeCheckpoint(t, out, root)
	res, err := Run(context.Background(), Options{Root: root, Output: out}, nil)
	if err != nil {
		t.Fatal(err)
	}
	if res.FilesResumed != 0 || res.FilesHashed != 1 {
		t.Fatalf("changed row was reused: %+v", res)
	}
	if got := readRows(t, out)[0][2]; got != sha256hex("new-and-different") {
		t.Fatalf("stale hash: %s", got)
	}
}

func TestDeletedResumeRowIsRemoved(t *testing.T) {
	root := buildTree(t, map[string]string{"keep.txt": "keep", "delete.txt": "delete"})
	out := filepath.Join(t.TempDir(), "manifest.csv")
	runFresh(t, root, out)
	if err := os.Remove(filepath.Join(root, "delete.txt")); err != nil {
		t.Fatal(err)
	}
	writeCheckpoint(t, out, root)
	res, err := Run(context.Background(), Options{Root: root, Output: out}, nil)
	if err != nil {
		t.Fatal(err)
	}
	if len(readRows(t, out)) != 1 || res.FilesResumed != 1 {
		t.Fatalf("deleted row retained: %+v", res)
	}
	if _, exists := rowMap(readRows(t, out))["delete.txt"]; exists {
		t.Fatal("deleted file remains in manifest")
	}
}

func TestRehashExistingDoesNotReuseRows(t *testing.T) {
	root := buildTree(t, map[string]string{"a.txt": "same"})
	out := filepath.Join(t.TempDir(), "manifest.csv")
	runFresh(t, root, out)
	writeCheckpoint(t, out, root)
	res, err := Run(context.Background(), Options{Root: root, Output: out, RehashExisting: true}, nil)
	if err != nil {
		t.Fatal(err)
	}
	if res.FilesResumed != 0 || res.FilesHashed != 1 {
		t.Fatalf("strict resume reused a row: %+v", res)
	}
}

func TestFileChangingDuringHashIsOmitted(t *testing.T) {
	root := buildTree(t, map[string]string{"moving.bin": strings.Repeat("x", 1<<20)})
	out := filepath.Join(t.TempDir(), "manifest.csv")
	var hookErr error
	res, err := Run(context.Background(), Options{
		Root: root, Output: out, Fresh: true, Workers: 1,
		afterHashRead: func(path string) {
			f, err := os.OpenFile(path, os.O_APPEND|os.O_WRONLY, 0)
			if err == nil {
				_, err = f.Write([]byte("changed"))
				_ = f.Close()
			}
			if err != nil {
				hookErr = err
			}
		},
	}, nil)
	if hookErr != nil {
		t.Skipf("filesystem did not permit concurrent mutation: %v", hookErr)
	}
	if err != nil {
		t.Fatal(err)
	}
	if res.FilesFailed != 1 || len(readRows(t, out)) != 0 {
		t.Fatalf("unstable file was accepted: %+v", res)
	}
	log, _ := os.ReadFile(ErrorLogPath(out))
	if !strings.Contains(string(log), "FILE_CHANGED") || !strings.Contains(string(log), "file changed while hashing") {
		t.Fatalf("unstable file not reported: %s", log)
	}
}

func TestPercentEncodingIsInjective(t *testing.T) {
	if got := encodeNameSpecials("%FF"); got != "%25FF" {
		t.Fatalf("literal percent: %q", got)
	}
	if got := encodeNameSpecials(string([]byte{0xff})); got != "%FF" {
		t.Fatalf("raw byte: %q", got)
	}
}

func TestCorruptMiddleRecordIsFatal(t *testing.T) {
	root := buildTree(t, map[string]string{"a.txt": "a", "b.txt": "b", "c.txt": "c"})
	out := filepath.Join(t.TempDir(), "manifest.csv")
	runFresh(t, root, out)
	data, err := os.ReadFile(out)
	if err != nil {
		t.Fatal(err)
	}
	lines := bytes.Split(data, []byte("\r\n"))
	if len(lines) < 4 {
		t.Fatalf("unexpected manifest")
	}
	lines[2] = []byte(`"broken`)
	if err := os.WriteFile(out, bytes.Join(lines, []byte("\r\n")), 0o644); err != nil {
		t.Fatal(err)
	}
	writeCheckpoint(t, out, root)
	if _, err := Run(context.Background(), Options{Root: root, Output: out}, nil); err == nil {
		t.Fatal("middle corruption must be fatal")
	}
}

func TestResumeRepairsSemanticallyTornFinalRow(t *testing.T) {
	root := buildTree(t, map[string]string{"a.txt": "a", "b.txt": "b"})
	out := filepath.Join(t.TempDir(), "manifest.csv")
	runFresh(t, root, out)
	rows := readRows(t, out)
	rows[len(rows)-1][3] = "2026-09-09T17:58:34."
	writeManifestRows(t, out, rows)
	writeCheckpoint(t, out, root)

	res, err := Run(context.Background(), Options{Root: root, Output: out}, nil)
	if err != nil {
		t.Fatal(err)
	}
	if res.FilesHashed != 1 || res.FilesResumed != 1 {
		t.Fatalf("damaged final row was not safely rehashed: %+v", res)
	}
}

func writeManifestRows(t *testing.T, output string, rows [][]string) {
	t.Helper()
	f, err := os.Create(output)
	if err != nil {
		t.Fatal(err)
	}
	if _, err = f.Write(utf8BOM); err != nil {
		f.Close()
		t.Fatal(err)
	}
	w := csv.NewWriter(f)
	w.UseCRLF = true
	_ = w.Write(csvHeader)
	for _, row := range rows {
		_ = w.Write(row)
	}
	w.Flush()
	if err = w.Error(); err == nil {
		err = f.Sync()
	}
	if closeErr := f.Close(); err == nil {
		err = closeErr
	}
	if err != nil {
		t.Fatal(err)
	}
}

func TestErrorLogCreationFailureIsFatal(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("creating a symlink warning requires privileges; covered on POSIX CI")
	}
	root := buildTree(t, map[string]string{"ok.txt": "ok"})
	if err := os.Symlink(filepath.Join(root, "ok.txt"), filepath.Join(root, "link.txt")); err != nil {
		t.Skipf("symlinks unavailable: %v", err)
	}
	out := filepath.Join(t.TempDir(), "manifest.csv")
	injected := errors.New("injected error-log failure")
	_, err := Run(context.Background(), Options{
		Root: root, Output: out, Fresh: true,
		openErrorLog: func(string) (*os.File, error) { return nil, injected },
	}, nil)
	if !errors.Is(err, injected) {
		t.Fatalf("logging failure was not fatal: %v", err)
	}
}

func TestForcedTerminationLeavesResumableManifest(t *testing.T) {
	if os.Getenv("GAMI_CRASH_HELPER") == "1" {
		_, _ = Run(context.Background(), Options{
			Root: os.Getenv("GAMI_CRASH_ROOT"), Output: os.Getenv("GAMI_CRASH_OUTPUT"), Fresh: true, Workers: 1,
			afterHashRead: func(string) { time.Sleep(20 * time.Millisecond) },
		}, nil)
		return
	}
	files := make(map[string]string)
	for i := 0; i < 40; i++ {
		files[fmt.Sprintf("f%02d.bin", i)] = strings.Repeat("x", 1<<20)
	}
	root := buildTree(t, files)
	out := filepath.Join(t.TempDir(), "manifest.csv")
	cmd := exec.Command(os.Args[0], "-test.run=^TestForcedTerminationLeavesResumableManifest$")
	cmd.Env = append(os.Environ(), "GAMI_CRASH_HELPER=1", "GAMI_CRASH_ROOT="+root, "GAMI_CRASH_OUTPUT="+out)
	if err := cmd.Start(); err != nil {
		t.Fatal(err)
	}
	killed := false
	deadline := time.Now().Add(10 * time.Second)
	for time.Now().Before(deadline) {
		data, err := os.ReadFile(CheckpointPath(out))
		if err == nil {
			var cp checkpoint
			if json.Unmarshal(data, &cp) == nil && cp.WorkPath != "" {
				if fi, err := os.Stat(cp.WorkPath); err == nil && fi.Size() > 200 {
					if err := cmd.Process.Kill(); err != nil {
						t.Fatal(err)
					}
					killed = true
					break
				}
			}
		}
		time.Sleep(10 * time.Millisecond)
	}
	_ = cmd.Wait()
	if !killed {
		t.Fatal("helper completed before forced termination could be tested")
	}
	if st := CheckResume(out); !st.Resumable {
		t.Fatal("forced termination did not leave resumable state")
	}
	res, err := Run(context.Background(), Options{Root: root, Output: out}, nil)
	if err != nil {
		t.Fatal(err)
	}
	if res.FilesHashed+res.FilesResumed != 40 || len(readRows(t, out)) != 40 {
		t.Fatalf("resume incomplete: %+v", res)
	}
}

type zeroReader struct{}

func (zeroReader) Read(p []byte) (int, error) {
	for i := range p {
		p[i] = 0
	}
	return len(p), nil
}

// --- helpers ---------------------------------------------------------------

// writePartialCopy writes BOM + header + the first n data rows of src to dst.
func writePartialCopy(t *testing.T, src, dst string, n int) {
	t.Helper()
	data, err := os.ReadFile(src)
	if err != nil {
		t.Fatal(err)
	}
	lines := strings.SplitAfter(string(data[3:]), "\r\n")
	keep := lines[0] // header
	for i := 1; i <= n && i < len(lines); i++ {
		keep += lines[i]
	}
	if err := os.WriteFile(dst, append(append([]byte{}, utf8BOM...), keep...), 0o644); err != nil {
		t.Fatal(err)
	}
}

func writeCheckpoint(t *testing.T, output, root string) {
	t.Helper()
	absRoot, err := filepath.Abs(root)
	if err != nil {
		t.Fatal(err)
	}
	// Match production checkpoint creation, which records the canonical source
	// path. On macOS, for example, /var is commonly an alias for /private/var.
	if resolvedRoot, resolveErr := resolveExisting(absRoot); resolveErr == nil {
		absRoot = resolvedRoot
	}
	absOutput, err := resolveOutput(output)
	if err != nil {
		t.Fatal(err)
	}
	cp := checkpoint{
		Format: manifestFormatVersion, Version: Version, Root: absRoot, Output: absOutput,
		Started: time.Now().UTC().Format(time.RFC3339), CSVHeader: strings.Join(csvHeader, ","),
	}
	data, _ := json.Marshal(cp)
	if err := os.WriteFile(CheckpointPath(output), data, 0o644); err != nil {
		t.Fatal(err)
	}
}

func assertSameRowSet(t *testing.T, want, got [][]string) {
	t.Helper()
	w, g := rowMap(want), rowMap(got)
	if len(w) != len(g) {
		t.Fatalf("row count differs: want %d, got %d", len(w), len(g))
	}
	for rel, wr := range w {
		gr, ok := g[rel]
		if !ok {
			t.Fatalf("missing row %q", rel)
		}
		// mtime may legitimately differ in representation; compare the rest.
		for i := 0; i < 4; i++ {
			if wr[i] != gr[i] {
				t.Fatalf("row %q differs at column %d: %q vs %q", rel, i, wr[i], gr[i])
			}
		}
	}
}
