//go:build windows

package main

import (
	"crypto/sha256"
	"encoding/csv"
	"encoding/hex"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"golang.org/x/sys/windows"
)

func duplicateForProbe(t *testing.T, file *os.File) windows.Handle {
	t.Helper()
	var target windows.Handle
	if err := windows.DuplicateHandle(windows.CurrentProcess(), windows.Handle(file.Fd()),
		windows.CurrentProcess(), &target, 0, false, windows.DUPLICATE_SAME_ACCESS); err != nil {
		t.Fatal(err)
	}
	return target
}

func TestManifestProbeWritesFiveColumnUnicodeRow(t *testing.T) {
	dir := t.TempDir()
	payload := []byte("hello from a brokered source\n")
	sourcePath := filepath.Join(dir, "source.txt")
	if err := os.WriteFile(sourcePath, payload, 0o600); err != nil {
		t.Fatal(err)
	}
	source, err := os.Open(sourcePath)
	if err != nil {
		t.Fatal(err)
	}
	defer source.Close()
	outputPath := filepath.Join(dir, "output.csv")
	output, err := os.Create(outputPath)
	if err != nil {
		t.Fatal(err)
	}
	defer output.Close()
	sourceHandle := duplicateForProbe(t, source)
	outputHandle := duplicateForProbe(t, output)
	rel := "nested folder/Grüße%raw.txt"
	protocol := fmt.Sprintf("GAMI-MANIFEST-1 OUT %d\nFILE %d %s\nEND\n",
		outputHandle, sourceHandle, hex.EncodeToString([]byte(rel)))
	if err := manifestProbe(strings.NewReader(protocol)); err != nil {
		t.Fatal(err)
	}
	if err := output.Close(); err != nil {
		t.Fatal(err)
	}
	data, err := os.ReadFile(outputPath)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.HasPrefix(string(data), "\xef\xbb\xbf") {
		t.Fatal("manifest is missing UTF-8 BOM")
	}
	rows, err := csv.NewReader(strings.NewReader(strings.TrimPrefix(string(data), "\xef\xbb\xbf"))).ReadAll()
	if err != nil {
		t.Fatal(err)
	}
	if len(rows) != 2 || len(rows[0]) != 5 || len(rows[1]) != 5 {
		t.Fatalf("unexpected CSV dimensions: %#v", rows)
	}
	if got := strings.Join(rows[0], ","); got != "relative_path,size_bytes,file_hash,mtime_utc,source_record_id" {
		t.Fatalf("unexpected header: %q", got)
	}
	sum := sha256.Sum256(payload)
	wantRel := "nested folder/Grüße%25raw.txt"
	if rows[1][0] != wantRel || rows[1][1] != fmt.Sprint(len(payload)) ||
		rows[1][2] != "sha256:"+hex.EncodeToString(sum[:]) || rows[1][4] != wantRel {
		t.Fatalf("unexpected row: %#v", rows[1])
	}
	if _, err := time.Parse(time.RFC3339Nano, rows[1][3]); err != nil {
		t.Fatalf("invalid mtime: %v", err)
	}
}

func TestValidateManifestRelativeName(t *testing.T) {
	accepted := []string{"file.txt", "nested/Grüße.txt", "a folder/record 001.bin"}
	for _, name := range accepted {
		if err := validateManifestRelativeName(name); err != nil {
			t.Errorf("rejected %q: %v", name, err)
		}
	}
	rejected := []string{"", "/absolute", "C:/absolute", "a\\b", "a:stream", "a//b", "a/./b", "a/../b", "a/", "a.", "a /b", "a\x00b", "a\nb"}
	for _, name := range rejected {
		if err := validateManifestRelativeName(name); err == nil {
			t.Errorf("accepted unsafe name %q", name)
		}
	}
}
