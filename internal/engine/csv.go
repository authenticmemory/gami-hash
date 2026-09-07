package engine

import (
	"bytes"
	"encoding/csv"
	"errors"
	"fmt"
	"io"
	"os"
	"strconv"
	"time"
)

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
	if c.previous != "" && rec[0] <= c.previous {
		return fmt.Errorf("existing manifest is not strictly sorted or contains duplicate path %q", rec[0])
	}
	size, err := strconv.ParseInt(rec[2], 10, 64)
	if err != nil || size < 0 {
		return fmt.Errorf("invalid size for %q", rec[0])
	}
	mtime, err := time.Parse(time.RFC3339Nano, rec[4])
	if err != nil {
		return fmt.Errorf("invalid modification time for %q", rec[0])
	}
	if len(rec[3]) != 64 {
		return fmt.Errorf("invalid SHA-256 for %q", rec[0])
	}
	c.previous = rec[0]
	c.rel = rec[0]
	c.current = completedRow{fields: append([]string(nil), rec...), size: size, mtime: mtime}
	return nil
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
// an incomplete final physical record. Corruption before the final record is
// fatal and is never silently truncated.
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
		if i == 0 && !sliceEqual(rec, csvHeader) {
			return errors.New("unexpected CSV header")
		}
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
