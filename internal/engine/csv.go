package engine

import (
	"bytes"
	"encoding/csv"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"os"
	"strconv"
	"strings"
	"time"
)

const sha256ManifestPrefix = "sha256:"

type completedCursor struct {
	file     *os.File
	reader   *csv.Reader
	current  completedRow
	rel      string
	eof      bool
	previous string
}

func openCompletedCursor(path string) (*completedCursor, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	r := csv.NewReader(skipBOM(f))
	r.FieldsPerRecord = len(csvHeader)
	header, err := r.Read()
	if err != nil || !sliceEqual(header, csvHeader) {
		f.Close()
		return nil, errors.New("unexpected CSV header")
	}
	c := &completedCursor{file: f, reader: r}
	if err := c.advance(); err != nil {
		f.Close()
		return nil, err
	}
	return c, nil
}

func (c *completedCursor) Close() error { return c.file.Close() }

func (c *completedCursor) advance() error {
	rec, err := c.reader.Read()
	if err == io.EOF {
		c.eof = true
		c.rel = ""
		return nil
	}
	if err != nil {
		return err
	}
	row, err := parseCompletedRow(rec, c.previous)
	if err != nil {
		return err
	}
	c.previous = rec[0]
	c.rel = rec[0]
	c.current = row
	return nil
}

func parseCompletedRow(rec []string, previous string) (completedRow, error) {
	if len(rec) != len(csvHeader) {
		return completedRow{}, fmt.Errorf("invalid field count")
	}
	if previous != "" && rec[0] <= previous {
		return completedRow{}, fmt.Errorf("existing manifest is not strictly sorted or contains duplicate path %q", rec[0])
	}
	size, err := strconv.ParseInt(rec[1], 10, 64)
	if err != nil || size < 0 {
		return completedRow{}, fmt.Errorf("invalid size for %q", rec[0])
	}
	mtime, err := time.Parse(time.RFC3339Nano, rec[3])
	if err != nil {
		return completedRow{}, fmt.Errorf("invalid modification time for %q", rec[0])
	}
	hash, ok := normalizeManifestHash(rec[2])
	if !ok {
		return completedRow{}, fmt.Errorf("invalid SHA-256 for %q", rec[0])
	}
	fields := append([]string(nil), rec...)
	fields[2] = hash
	return completedRow{fields: fields, size: size, mtime: mtime}, nil
}

func formatManifestHash(hash string) string {
	if strings.HasPrefix(hash, sha256ManifestPrefix) {
		return hash
	}
	return sha256ManifestPrefix + hash
}

func normalizeManifestHash(hash string) (string, bool) {
	if strings.HasPrefix(hash, sha256ManifestPrefix) {
		bare := strings.TrimPrefix(hash, sha256ManifestPrefix)
		return hash, isLowerHexSHA256(bare)
	}
	return formatManifestHash(hash), isLowerHexSHA256(hash)
}

func isLowerHexSHA256(hash string) bool {
	if len(hash) != 64 || strings.ToLower(hash) != hash {
		return false
	}
	_, err := hex.DecodeString(hash)
	return err == nil
}

// match advances past deleted old rows and returns the row matching rel.
func (c *completedCursor) match(rel string) (completedRow, bool, error) {
	for !c.eof && c.rel < rel {
		if err := c.advance(); err != nil {
			return completedRow{}, false, err
		}
	}
	if c.eof || c.rel != rel {
		return completedRow{}, false, nil
	}
	row := c.current
	if err := c.advance(); err != nil {
		return completedRow{}, false, err
	}
	return row, true, nil
}

// validateRepairableCSV accepts a valid manifest or one whose only damage is
// in its final record. A terminated record can still be torn at the semantic
// level after sudden power loss. Corruption before the final record is fatal.
func validateRepairableCSV(path string) error {
	data, err := os.ReadFile(path)
	if err != nil {
		return err
	}
	if len(data) < len(utf8BOM) || !bytes.Equal(data[:3], utf8BOM) {
		return errors.New("existing file has no UTF-8 BOM")
	}
	body := data[3:]
	terminated := bytes.HasSuffix(body, []byte("\r\n"))
	lines := bytes.Split(body, []byte("\r\n"))
	if terminated {
		lines = lines[:len(lines)-1]
	}
	if len(lines) == 0 {
		return errors.New("existing file has no valid header")
	}
	previous := ""
	for i, line := range lines {
		r := csv.NewReader(bytes.NewReader(line))
		r.FieldsPerRecord = len(csvHeader)
		rec, parseErr := r.Read()
		if parseErr == nil {
			if _, extra := r.Read(); extra != io.EOF {
				parseErr = errors.New("multiple records on one physical line")
			}
		}
		if parseErr != nil {
			if i == len(lines)-1 && !terminated {
				return nil
			}
			return fmt.Errorf("manifest is corrupt at record %d: %w", i+1, parseErr)
		}
		if i == 0 {
			if !sliceEqual(rec, csvHeader) {
				return errors.New("unexpected CSV header")
			}
			continue
		}
		if _, semanticErr := parseCompletedRow(rec, previous); semanticErr != nil {
			if i == len(lines)-1 {
				return nil
			}
			return fmt.Errorf("manifest is corrupt at record %d: %w", i+1, semanticErr)
		}
		previous = rec[0]
	}
	return nil
}

var utf8BOM = []byte{0xEF, 0xBB, 0xBF}

// repairTruncatedTail truncates an existing manifest CSV to the end of its
// last complete, valid record. A crash or power loss can leave a partially
// written final line; cutting it is safe because the affected file is simply
// re-hashed on resume.
func repairTruncatedTail(path string) error {
	f, err := os.OpenFile(path, os.O_RDWR, 0)
	if err != nil {
		return err
	}
	defer f.Close()

	// Skip the BOM if present.
	var start int64
	head := make([]byte, 3)
	if n, _ := io.ReadFull(f, head); n == 3 && bytes.Equal(head, utf8BOM) {
		start = 3
	}
	if _, err := f.Seek(start, io.SeekStart); err != nil {
		return err
	}

	r := csv.NewReader(f)
	r.FieldsPerRecord = len(csvHeader)
	lastGood := start
	first := true
	previous := ""
	for {
		rec, err := r.Read()
		if err == io.EOF {
			break
		}
		if err != nil {
			// Anything from here on is a damaged tail: cut it off.
			break
		}
		if first {
			first = false
			if !sliceEqual(rec, csvHeader) {
				return fmt.Errorf("existing file has an unexpected format (not a manifest written by this tool)")
			}
		} else {
			if _, semanticErr := parseCompletedRow(rec, previous); semanticErr != nil {
				break
			}
			previous = rec[0]
		}
		lastGood = start + r.InputOffset()
	}
	if first {
		return fmt.Errorf("existing file has no valid header")
	}
	return f.Truncate(lastGood)
}

// countValidRows counts complete data rows in a manifest CSV, tolerating a
// damaged tail (used only for the resume prompt, read-only).
func countValidRows(path string) (int64, error) {
	f, err := os.Open(path)
	if err != nil {
		return 0, err
	}
	defer f.Close()
	r := csv.NewReader(skipBOM(f))
	r.FieldsPerRecord = len(csvHeader)
	r.ReuseRecord = true

	var n int64
	first := true
	previous := ""
	for {
		rec, err := r.Read()
		if err == io.EOF {
			break
		}
		if err != nil {
			break // damaged tail: count what is valid
		}
		if first {
			first = false
			if !sliceEqual(rec, csvHeader) {
				return 0, errors.New("unexpected CSV header")
			}
			continue
		}
		if _, semanticErr := parseCompletedRow(rec, previous); semanticErr != nil {
			break
		}
		previous = rec[0]
		n++
	}
	if first {
		return 0, errors.New("no valid header")
	}
	return n, nil
}

func skipBOM(f *os.File) io.Reader {
	head := make([]byte, 3)
	n, _ := io.ReadFull(f, head)
	if n == 3 && bytes.Equal(head, utf8BOM) {
		return f
	}
	f.Seek(0, io.SeekStart)
	return f
}

func sliceEqual(a, b []string) bool {
	if len(a) != len(b) {
		return false
	}
	for i := range a {
		if a[i] != b[i] {
			return false
		}
	}
	return true
}
