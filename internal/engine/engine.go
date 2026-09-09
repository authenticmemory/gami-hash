// Package engine implements the core hashing run: it walks a folder tree,
// computes SHA-256 for every regular file and writes one CSV manifest.
//
// Guarantees:
//   - Strictly read-only towards the scanned tree (files are opened O_RDONLY,
//     nothing is ever created or modified under the root).
//   - Per-file errors (permissions, vanished files, I/O errors) never abort
//     the run; they are appended to an error log and the file is skipped.
//   - Runs are resumable: the CSV itself is the record of completed files, a
//     small sidecar checkpoint file marks an unfinished run and remembers the
//     root folder. On resume, files already present in the CSV are skipped.
//   - No network access anywhere (the whole program has no networking code).
package engine

import (
	"container/heap"
	"context"
	"crypto/sha256"
	"encoding/csv"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"os"
	"path/filepath"
	"runtime"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"time"
	"unicode/utf8"
)

type walkItem struct {
	abs, rel string
	entry    fs.DirEntry
}

type walkHeap []walkItem

func (h walkHeap) Len() int           { return len(h) }
func (h walkHeap) Less(i, j int) bool { return h[i].rel < h[j].rel }
func (h walkHeap) Swap(i, j int)      { h[i], h[j] = h[j], h[i] }
func (h *walkHeap) Push(x any)        { *h = append(*h, x.(walkItem)) }
func (h *walkHeap) Pop() any          { old := *h; n := len(old); x := old[n-1]; *h = old[:n-1]; return x }

// Version of the tool. Overridden at build time via
// -ldflags "-X .../internal/engine.Version=v1.0.0".
var Version = "dev"

// CSV layout. The header is fixed; a resume run refuses to append to a file
// with a different header.
var csvHeader = []string{"relative_path", "filename", "size_bytes", "sha256", "mtime_utc"}

const (
	checkpointSuffix = ".part.json"
	errorLogSuffix   = "_errors.log"
	readBufSize      = 1 << 20 // 1 MiB
	flushEveryRows   = 64
	flushEvery       = 2 * time.Second
)

// DefaultWorkers is the default number of parallel hashing workers. It is
// deliberately low: on spinning disks (the common case for archive drives)
// parallel reads cause seeking and are often slower than sequential reads.
const DefaultWorkers = 2

// MaxWorkers is enforced by the engine, not merely by its callers. Interfaces
// may offer a smaller range but cannot force unbounded concurrency.
const MaxWorkers = 64

// Options configures a run.
type Options struct {
	Root    string // folder to scan (must exist)
	Output  string // CSV file to write (must not be inside Root)
	Workers int    // parallel hashing workers; <1 means DefaultWorkers
	Fresh   bool   // true: ignore any resumable state and start over
	// RehashExisting verifies every current file instead of reusing compatible
	// rows from an interrupted manifest.
	RehashExisting bool

	// AllowRootMismatch resumes even when the checkpoint records a different
	// root path. Needed when the same external drive reappears under a new
	// drive letter or mount point: relative paths still match, so the resume
	// is correct. Only set when the user confirmed it is the same folder.
	AllowRootMismatch bool

	// afterHashRead is an internal fault-injection hook used by engine tests.
	afterHashRead func(string)
	openErrorLog  func(string) (*os.File, error)
}

// Phase of a run, reported through Progress.
type Phase int

const (
	PhaseScan Phase = iota // counting files (fast pre-pass)
	PhaseHash              // hashing
)

// Progress is a point-in-time snapshot passed to the progress callback.
type Progress struct {
	Phase      Phase
	FilesDone  int64 // hashed + resumed + failed
	FilesTotal int64
	BytesDone  int64
	BytesTotal int64
}

// Result summarises a finished (or cancelled) run.
type Result struct {
	FilesHashed  int64 // hashed during this run
	FilesResumed int64 // skipped because a previous run already hashed them
	FilesFailed  int64 // unreadable, vanished, ... (see error log)
	Skipped      int64 // non-regular entries (symlinks, sockets, ...)
	Warnings     int64 // intentionally omitted non-regular entries and name warnings
	BytesHashed  int64
	FilesTotal   int64
	BytesTotal   int64
	Output       string
	ErrorLog     string // "" if no error log was written
	Canceled     bool
	Elapsed      time.Duration
}

// ResumeState describes whether an interrupted run exists for an output file.
type ResumeState struct {
	Resumable    bool   // checkpoint + CSV exist and are consistent
	Root         string // root folder recorded in the checkpoint
	RowCount     int64  // completed rows in the existing CSV
	manifestPath string
}

type checkpoint struct {
	Format     int    `json:"format_version"`
	Version    string `json:"tool_version"`
	Root       string `json:"root"`
	Output     string `json:"output"`
	WorkPath   string `json:"work_path,omitempty"`
	Started    string `json:"started_utc"`
	CSVHeader  string `json:"csv_header"`
	FormatNote string `json:"note"`
}

const manifestFormatVersion = 1

type completedRow struct {
	fields []string
	size   int64
	mtime  time.Time
}

// Validate checks and canonicalizes a proposed run without modifying any
// filesystem content. Run performs these checks again and remains authoritative
// if filesystem state changes after validation.
func Validate(opts Options) (Options, error) {
	if opts.Root == "" || opts.Output == "" {
		return Options{}, fmt.Errorf("root folder and output file are required")
	}
	if opts.Workers < 1 {
		opts.Workers = DefaultWorkers
	}
	if opts.Workers > MaxWorkers {
		return Options{}, fmt.Errorf("workers must not exceed %d", MaxWorkers)
	}
	var err error
	opts.Root, err = resolveExisting(opts.Root)
	if err != nil {
		return Options{}, fmt.Errorf("invalid root folder: %w", err)
	}
	opts.Output, err = resolveOutput(opts.Output)
	if err != nil {
		return Options{}, fmt.Errorf("invalid output path: %w", err)
	}
	info, err := os.Stat(opts.Root)
	if err != nil {
		return Options{}, fmt.Errorf("cannot access root folder: %w", err)
	}
	if !info.IsDir() {
		return Options{}, fmt.Errorf("root is not a folder: %s", opts.Root)
	}
	if isWithin(opts.Output, opts.Root) {
		return Options{}, fmt.Errorf("output file must not be inside the scanned folder")
	}
	if di, derr := os.Stat(filepath.Dir(opts.Output)); derr != nil || !di.IsDir() {
		return Options{}, fmt.Errorf("output folder does not exist: %s", filepath.Dir(opts.Output))
	}
	if !opts.Fresh {
		st := CheckResume(opts.Output)
		switch {
		case fileExists(CheckpointPath(opts.Output)) && !st.Resumable:
			return Options{}, fmt.Errorf("checkpoint or partial manifest is corrupt or incompatible; use --fresh only if you intend to replace it")
		case st.Resumable && !(SameRoot(st.Root, opts.Root) || opts.AllowRootMismatch):
			return Options{}, fmt.Errorf("checkpoint belongs to a different source root; confirm the same moved drive or use --fresh")
		case !st.Resumable && fileExists(opts.Output):
			return Options{}, fmt.Errorf("output file already exists; use --fresh only if you intend to replace it")
		}
	}
	return opts, nil
}

// CheckpointPath returns the sidecar checkpoint path for an output CSV.
func CheckpointPath(output string) string { return output + checkpointSuffix }

// ErrorLogPath returns the error log path for an output CSV
// (foo.csv -> foo_errors.log).
func ErrorLogPath(output string) string {
	base := strings.TrimSuffix(output, filepath.Ext(output))
	return base + errorLogSuffix
}

// CheckResume inspects output and reports whether an interrupted run can be
// resumed. It never modifies anything.
func CheckResume(output string) ResumeState {
	var st ResumeState
	// Callers may supply a lexical alias for an existing directory. This is
	// common on macOS, where /var resolves to /private/var. Checkpoints record
	// canonical paths, so normalize the requested output before comparing it.
	resolvedOutput, err := resolveOutput(output)
	if err != nil {
		return st
	}
	output = resolvedOutput
	data, err := os.ReadFile(CheckpointPath(output))
	if err != nil {
		return st
	}
	var cp checkpoint
	if json.Unmarshal(data, &cp) != nil || cp.Root == "" || cp.Format != manifestFormatVersion || cp.CSVHeader != strings.Join(csvHeader, ",") {
		return st
	}
	if cp.Output != "" && !SameRoot(cp.Output, output) {
		return st
	}
	manifest := output
	if cp.WorkPath != "" {
		workAbs, err := filepath.Abs(cp.WorkPath)
		if err != nil || !SameRoot(filepath.Dir(workAbs), filepath.Dir(output)) || !strings.HasPrefix(filepath.Base(workAbs), ".gami-manifest-") {
			return st
		}
		if li, err := os.Lstat(workAbs); err == nil && li.Mode().IsRegular() {
			manifest = workAbs
		}
	}
	if _, err := os.Stat(manifest); err != nil {
		return st
	}
	if err := validateRepairableCSV(manifest); err != nil {
		return st
	}
	rows, err := countValidRows(manifest)
	if err != nil {
		return st
	}
	st.Resumable = true
	st.Root = cp.Root
	st.RowCount = rows
	st.manifestPath = manifest
	return st
}

// SameRoot reports whether two cleaned absolute paths refer to the same root,
// using case-insensitive comparison on Windows.
func SameRoot(a, b string) bool {
	a, b = filepath.Clean(a), filepath.Clean(b)
	if runtime.GOOS == "windows" {
		return strings.EqualFold(a, b)
	}
	return a == b
}

// isWithin reports whether path is inside (or equal to) dir. Both must be
// absolute; comparison is lexical, case-insensitive on Windows.
func isWithin(path, dir string) bool {
	path, dir = filepath.Clean(path), filepath.Clean(dir)
	if runtime.GOOS == "windows" {
		path, dir = strings.ToLower(path), strings.ToLower(dir)
	}
	if path == dir {
		return true
	}
	return strings.HasPrefix(path, dir+string(filepath.Separator))
}

// job is one file to hash, in deterministic walk order.
type job struct {
	index int64
	rel   string // slash-separated relative path
	abs   string
	size  int64
	mtime time.Time
}

// outcome is the result of hashing one file.
type outcome struct {
	index   int64
	rel     string
	name    string
	size    int64
	mtime   time.Time
	hash    string
	resumed bool
	err     error // non-nil: file failed, goes to the error log
}

type engineRun struct {
	opts     Options
	ctx      context.Context
	progress func(Progress)

	completed *completedCursor // streaming sorted rows available for resume

	filesTotal  atomic.Int64
	bytesTotal  atomic.Int64
	filesDone   atomic.Int64
	bytesDone   atomic.Int64
	filesFailed atomic.Int64 // written by producer and writer goroutines
	skipped     atomic.Int64
	warnings    atomic.Int64

	res Result

	errLogMu  sync.Mutex
	errLog    *os.File
	errLogErr error
}

// Run executes a hashing run. progressFn may be nil; it is called from a
// single goroutine, throttled to roughly one call per 100ms.
//
// Fatal setup problems (bad root, output inside root, unwritable output)
// return an error. Per-file problems never do.
func Run(ctx context.Context, opts Options, progressFn func(Progress)) (Result, error) {
	start := time.Now()
	var err error
	opts, err = Validate(opts)
	if err != nil {
		return Result{}, err
	}
	if progressFn == nil {
		progressFn = func(Progress) {}
	}

	r := &engineRun{opts: opts, ctx: ctx, progress: progressFn}
	r.res.Output = opts.Output

	// ---- Resume handling -------------------------------------------------
	resuming := false
	var resumeState ResumeState
	if !opts.Fresh {
		st := CheckResume(opts.Output)
		checkpointExists := fileExists(CheckpointPath(opts.Output))
		switch {
		case checkpointExists && !st.Resumable:
			return Result{}, fmt.Errorf("checkpoint or partial manifest is corrupt or incompatible; use --fresh only if you intend to replace it")
		case st.Resumable && (SameRoot(st.Root, opts.Root) || opts.AllowRootMismatch):
			resuming = true
			resumeState = st
		case st.Resumable:
			return Result{}, fmt.Errorf("checkpoint belongs to a different source root; confirm the same moved drive or use --fresh")
		case fileExists(opts.Output):
			return Result{}, fmt.Errorf("output file already exists; use --fresh only if you intend to replace it")
		}
	}

	var csvFile *os.File
	if resuming {
		// Validate before any mutation, then detach aliases/hard links before
		// repairing. The final output is reconstructed from the current tree.
		resumeSource := resumeState.manifestPath
		if err := validateRepairableCSV(resumeSource); err != nil {
			return Result{}, fmt.Errorf("cannot resume existing CSV: %w", err)
		}
		// Detach every resume source before any possible truncation. This also
		// protects against a tampered checkpoint whose work file is a hard link.
		if f, err := detachForAppend(resumeSource, 0o644); err != nil {
			return Result{}, fmt.Errorf("cannot make existing CSV safe: %w", err)
		} else if err := f.Close(); err != nil {
			return Result{}, fmt.Errorf("cannot close existing CSV: %w", err)
		}
		if err := repairTruncatedTail(resumeSource); err != nil {
			return Result{}, fmt.Errorf("cannot repair existing CSV: %w", err)
		}
		r.completed, err = openCompletedCursor(resumeSource)
		if err != nil {
			return Result{}, fmt.Errorf("cannot read existing CSV: %w", err)
		}
		if !SameRoot(resumeSource, opts.Output) {
			defer os.Remove(resumeSource)
		}
		defer func() {
			if r.completed != nil {
				_ = r.completed.Close()
			}
		}()
	}
	csvFile, err = os.CreateTemp(filepath.Dir(opts.Output), ".gami-manifest-*")
	if err != nil {
		return Result{}, fmt.Errorf("cannot create working manifest: %w", err)
	}
	workPath := csvFile.Name()
	defer os.Remove(workPath)
	defer csvFile.Close()
	// Every run reconstructs a complete current-tree manifest.
	if _, err := csvFile.Write(utf8BOM); err != nil {
		csvFile.Close()
		return Result{}, fmt.Errorf("cannot write output file: %w", err)
	}
	headerWriter := csv.NewWriter(csvFile)
	headerWriter.UseCRLF = true
	_ = headerWriter.Write(csvHeader)
	headerWriter.Flush()
	if err := headerWriter.Error(); err != nil {
		csvFile.Close()
		return Result{}, fmt.Errorf("cannot write output file: %w", err)
	}

	// Checkpoint marks "run in progress". Removed only on full success.
	cp := checkpoint{
		Format:     manifestFormatVersion,
		Version:    Version,
		Root:       opts.Root,
		Output:     opts.Output,
		WorkPath:   workPath,
		Started:    time.Now().UTC().Format(time.RFC3339),
		CSVHeader:  strings.Join(csvHeader, ","),
		FormatNote: "temporary file; marks an interrupted hashing run so it can be resumed. Safe to delete.",
	}
	// Always (re)written so the recorded root stays current — e.g. after an
	// external drive came back under a different drive letter.
	cpData, _ := json.MarshalIndent(cp, "", "  ")
	if err := atomicWriteFile(CheckpointPath(opts.Output), cpData, 0o644); err != nil {
		csvFile.Close()
		return Result{}, fmt.Errorf("cannot write checkpoint file: %w", err)
	}
	// The second traversal recreates the complete warning/error set, including
	// on resume. Remove only the external directory entry, never truncate it.
	if err := os.Remove(ErrorLogPath(opts.Output)); err != nil && !errors.Is(err, fs.ErrNotExist) {
		return Result{}, fmt.Errorf("cannot reset error log: %w", err)
	}

	defer func() {
		if r.errLog != nil {
			_ = r.errLog.Close()
		}
	}()

	// ---- Pass 1: count files and bytes (for the progress display) --------
	r.progress(Progress{Phase: PhaseScan})
	scanTick := time.Now()
	err = r.walk(func(rel, abs string, info fs.FileInfo) error {
		r.filesTotal.Add(1)
		r.bytesTotal.Add(info.Size())
		if time.Since(scanTick) > 100*time.Millisecond {
			scanTick = time.Now()
			r.progress(Progress{Phase: PhaseScan, FilesTotal: r.filesTotal.Load(), BytesTotal: r.bytesTotal.Load()})
		}
		return nil
	}, false)
	if err != nil {
		return Result{}, err
	}
	if r.ctx.Err() != nil {
		if r.completed != nil {
			if err := r.completed.Close(); err != nil {
				return Result{}, fmt.Errorf("cannot close resume manifest: %w", err)
			}
			r.completed = nil
		}
		if err := csvFile.Sync(); err != nil {
			return Result{}, fmt.Errorf("cannot flush canceled manifest: %w", err)
		}
		if err := csvFile.Close(); err != nil {
			return Result{}, fmt.Errorf("cannot close canceled manifest: %w", err)
		}
		if err := publishFile(workPath, opts.Output); err != nil {
			return Result{}, fmt.Errorf("cannot publish canceled manifest: %w", err)
		}
		cp.WorkPath = ""
		cpData, _ = json.MarshalIndent(cp, "", "  ")
		if err := atomicWriteFile(CheckpointPath(opts.Output), cpData, 0o644); err != nil {
			return Result{}, fmt.Errorf("cannot update canceled checkpoint: %w", err)
		}
		r.res.Canceled = true
		r.res.Elapsed = time.Since(start)
		return r.res, nil
	}
	r.res.FilesTotal = r.filesTotal.Load()
	r.res.BytesTotal = r.bytesTotal.Load()

	// ---- Pass 2: hash ------------------------------------------------------
	jobs := make(chan job, 4*opts.Workers)
	results := make(chan outcome, 4*opts.Workers)
	window := make(chan struct{}, max(8, 8*opts.Workers))

	var wg sync.WaitGroup
	for i := 0; i < opts.Workers; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			r.worker(jobs, results)
		}()
	}

	// Progress reporter.
	repCtx, repCancel := context.WithCancel(context.Background())
	var repWG sync.WaitGroup
	repWG.Add(1)
	go func() {
		defer repWG.Done()
		t := time.NewTicker(100 * time.Millisecond)
		defer t.Stop()
		for {
			select {
			case <-repCtx.Done():
				return
			case <-t.C:
				r.progress(r.snapshot())
			}
		}
	}()

	// Writer goroutine: emits rows in deterministic walk order.
	var writeErr error
	var writerWG sync.WaitGroup
	writerWG.Add(1)
	go func() {
		defer writerWG.Done()
		writeErr = r.writeLoop(csvFile, results, window)
	}()

	// Producer: walk again with identical order, enqueue jobs.
	var index int64
	prodErr := r.walk(func(rel, abs string, info fs.FileInfo) error {
		var old completedRow
		var done bool
		if r.completed != nil {
			var matchErr error
			old, done, matchErr = r.completed.match(rel)
			if matchErr != nil {
				return matchErr
			}
		}
		if done && !opts.RehashExisting && old.size == info.Size() && old.mtime.Equal(info.ModTime()) {
			select {
			case window <- struct{}{}:
			case <-r.ctx.Done():
				return nil
			}
			select {
			case results <- outcome{index: index, rel: rel, name: relBase(rel), size: old.size, mtime: old.mtime, hash: old.fields[3], resumed: true}:
				index++
				r.filesDone.Add(1)
				r.bytesDone.Add(info.Size())
			case <-r.ctx.Done():
				<-window
			}
			return nil
		}
		select {
		case window <- struct{}{}:
		case <-r.ctx.Done():
			return nil
		}
		select {
		case jobs <- job{index: index, rel: rel, abs: abs, size: info.Size(), mtime: info.ModTime()}:
			index++
		case <-r.ctx.Done():
			<-window
		}
		return nil
	}, true)
	close(jobs)
	wg.Wait()
	close(results)
	writerWG.Wait()
	repCancel()
	repWG.Wait()
	r.res.FilesFailed = r.filesFailed.Load()
	r.res.Skipped = r.skipped.Load()
	r.res.Warnings = r.warnings.Load()

	if prodErr != nil {
		return Result{}, prodErr
	}
	if writeErr != nil {
		return Result{}, fmt.Errorf("cannot write output file: %w", writeErr)
	}
	if r.errLogErr != nil {
		return Result{}, fmt.Errorf("cannot write error log: %w", r.errLogErr)
	}
	if r.completed != nil {
		if err := r.completed.Close(); err != nil {
			return Result{}, fmt.Errorf("cannot close resume manifest: %w", err)
		}
		r.completed = nil
	}

	if err := csvFile.Sync(); err != nil {
		return Result{}, fmt.Errorf("cannot flush output file: %w", err)
	}
	if err := csvFile.Close(); err != nil {
		return Result{}, fmt.Errorf("cannot close output file: %w", err)
	}
	if r.errLog != nil {
		if err := r.errLog.Sync(); err != nil {
			return Result{}, fmt.Errorf("cannot flush error log: %w", err)
		}
		if err := r.errLog.Close(); err != nil {
			return Result{}, fmt.Errorf("cannot close error log: %w", err)
		}
		r.errLog = nil
	} else if !resuming || opts.Fresh {
		_ = os.Remove(ErrorLogPath(opts.Output))
	}
	if err := publishFile(workPath, opts.Output); err != nil {
		return Result{}, fmt.Errorf("cannot publish output file: %w", err)
	}
	cp.WorkPath = ""
	cpData, _ = json.MarshalIndent(cp, "", "  ")
	if err := atomicWriteFile(CheckpointPath(opts.Output), cpData, 0o644); err != nil {
		return Result{}, fmt.Errorf("cannot finalize checkpoint: %w", err)
	}

	r.res.Elapsed = time.Since(start)
	if r.ctx.Err() != nil {
		r.res.Canceled = true
		r.progress(r.snapshot())
		return r.res, nil
	}

	// Success: remove the checkpoint marker.
	if err := os.Remove(CheckpointPath(opts.Output)); err != nil && !errors.Is(err, fs.ErrNotExist) {
		return Result{}, fmt.Errorf("cannot remove checkpoint file: %w", err)
	}
	r.progress(Progress{
		Phase: PhaseHash, FilesDone: r.res.FilesTotal, FilesTotal: r.res.FilesTotal,
		BytesDone: r.res.BytesTotal, BytesTotal: r.res.BytesTotal,
	})
	return r.res, nil
}

func (r *engineRun) snapshot() Progress {
	return Progress{
		Phase:      PhaseHash,
		FilesDone:  r.filesDone.Load(),
		FilesTotal: r.filesTotal.Load(),
		BytesDone:  r.bytesDone.Load(),
		BytesTotal: r.bytesTotal.Load(),
	}
}

// walk traverses the tree depth-first with entries sorted byte-wise, so both
// passes and any two runs see files in the same order. fn is called for
// regular files only. When logIssues is true, unreadable directories and
// skipped non-regular entries are recorded in the error log.
func (r *engineRun) walk(fn func(rel, abs string, info fs.FileInfo) error, logIssues bool) error {
	// Our own files must never end up in the manifest, even if the user put
	// the output right next to (or, blocked elsewhere, inside) the tree.
	excluded := []string{r.opts.Output, CheckpointPath(r.opts.Output), ErrorLogPath(r.opts.Output)}
	isExcluded := func(abs string) bool {
		for _, p := range excluded {
			if SameRoot(abs, p) {
				return true
			}
		}
		return false
	}

	q := &walkHeap{}
	heap.Init(q)
	addDir := func(abs, rel string) error {
		dir, err := os.Open(abs)
		if err != nil {
			if logIssues {
				r.filesFailed.Add(1)
				return r.logIssue("ERROR", "FOLDER_READ_FAILED", rel, fmt.Errorf("cannot read folder: %w", err))
			}
			return nil
		}
		defer dir.Close()
		encodedNames := make(map[string]string)
		for {
			if r.ctx.Err() != nil {
				return nil
			}
			entries, readErr := dir.ReadDir(1024)
			for _, e := range entries {
				if r.ctx.Err() != nil {
					return nil
				}
				name := encodeNameSpecials(e.Name())
				if prior, exists := encodedNames[name]; exists && prior != e.Name() {
					if logIssues {
						r.filesFailed.Add(1)
						collisionRel := name
						if rel != "" {
							collisionRel = rel + "/" + name
						}
						if err := r.logIssue("ERROR", "PATH_ENCODING_COLLISION", collisionRel,
							fmt.Errorf("two source names encode identically: %s and %s", strconv.Quote(prior), strconv.Quote(e.Name()))); err != nil {
							return err
						}
					}
					continue
				}
				encodedNames[name] = e.Name()
				childRel := name
				if rel != "" {
					childRel = rel + "/" + name
				}
				if containsUnsafeNameBytes(e.Name()) && logIssues {
					r.warnings.Add(1)
					if err := r.logIssue("WARNING", "FILENAME_ENCODED", childRel,
						fmt.Errorf("filename encoded; raw name: %s", strconv.Quote(e.Name()))); err != nil {
						return err
					}
				}
				heap.Push(q, walkItem{abs: filepath.Join(abs, e.Name()), rel: childRel, entry: e})
			}
			if errors.Is(readErr, io.EOF) {
				return nil
			}
			if readErr != nil {
				if logIssues {
					r.filesFailed.Add(1)
					return r.logIssue("ERROR", "FOLDER_READ_FAILED", rel, fmt.Errorf("cannot read folder: %w", readErr))
				}
				return nil
			}
		}
	}
	if err := addDir(r.opts.Root, ""); err != nil {
		return err
	}
	for q.Len() > 0 {
		if r.ctx.Err() != nil {
			return nil
		}
		item := heap.Pop(q).(walkItem)
		if isExcluded(item.abs) {
			continue
		}
		e := item.entry
		linkLike, linkErr := entryLinkLike(item.abs, e)
		if linkErr != nil {
			if logIssues {
				r.filesFailed.Add(1)
				if err := r.logIssue("ERROR", "FILE_METADATA_FAILED", item.rel,
					fmt.Errorf("cannot inspect entry attributes: %w", linkErr)); err != nil {
					return err
				}
			}
			continue
		}
		switch {
		case linkLike:
			if logIssues {
				r.skipped.Add(1)
				r.warnings.Add(1)
				if err := r.logIssue("WARNING", "LINK_ENTRY_SKIPPED", item.rel,
					fmt.Errorf("skipped: link, junction, or reparse point")); err != nil {
					return err
				}
			}
		case e.IsDir():
			if err := addDir(item.abs, item.rel); err != nil {
				return err
			}
		case !e.Type().IsRegular():
			if logIssues {
				r.skipped.Add(1)
				r.warnings.Add(1)
				if err := r.logIssue("WARNING", "SPECIAL_ENTRY_SKIPPED", item.rel,
					fmt.Errorf("skipped: not a regular file (%s)", entryTypeName(e.Type()))); err != nil {
					return err
				}
			}
		default:
			info, err := e.Info()
			if err != nil {
				if logIssues {
					r.filesFailed.Add(1)
					r.filesDone.Add(1)
					if err := r.logIssue("ERROR", "FILE_METADATA_FAILED", item.rel,
						fmt.Errorf("cannot read file attributes: %w", err)); err != nil {
						return err
					}
				}
				continue
			}
			if err := fn(item.rel, item.abs, info); err != nil {
				return err
			}
		}
	}
	return nil
}

func entryTypeName(m fs.FileMode) string {
	switch {
	case m&fs.ModeSymlink != 0:
		return "symlink"
	case m&fs.ModeDevice != 0:
		return "device"
	case m&fs.ModeNamedPipe != 0:
		return "named pipe"
	case m&fs.ModeSocket != 0:
		return "socket"
	default:
		return m.Type().String()
	}
}

// worker hashes files from jobs and sends outcomes to results.
func (r *engineRun) worker(jobs <-chan job, results chan<- outcome) {
	buf := make([]byte, readBufSize)
	for j := range jobs {
		if r.ctx.Err() != nil {
			// Drain quickly on cancel; unprocessed files stay unhashed and
			// will be picked up on resume.
			continue
		}
		out := outcome{index: j.index, rel: j.rel, name: relBase(j.rel), size: j.size, mtime: j.mtime}
		hashed, err := r.hashFile(j.abs, buf)
		if err != nil {
			out.err = err
			// Keep the progress bar honest: count the unread remainder.
			r.bytesDone.Add(j.size - hashed.bytes)
		} else {
			out.hash = hashed.sum
			out.size = hashed.bytes
			out.mtime = hashed.mtime
		}
		r.filesDone.Add(1)
		select {
		case results <- out:
		case <-r.ctx.Done():
			// Writer may already be gone; do not block.
			select {
			case results <- out:
			default:
			}
		}
	}
}

type hashed struct {
	sum   string
	bytes int64
	mtime time.Time
}

var errFileChanged = errors.New("file changed while hashing")

// hashFile opens a file strictly read-only, hashes it, and verifies metadata
// from the same open handle before and after the read. One unstable attempt is
// retried; a second is reported rather than accepted.
func (r *engineRun) hashFile(abs string, buf []byte) (hashed, error) {
	for attempt := 0; attempt < 2; attempt++ {
		got, err := r.hashFileOnce(abs, buf)
		if !errors.Is(err, errFileChanged) {
			return got, err
		}
		// The failed attempt does not count toward logical byte progress.
		r.bytesDone.Add(-got.bytes)
		if attempt == 1 {
			return got, err
		}
	}
	return hashed{}, errFileChanged
}

func (r *engineRun) hashFileOnce(abs string, buf []byte) (hashed, error) {
	f, err := os.Open(abs) // O_RDONLY
	if err != nil {
		return hashed{}, err
	}
	defer f.Close()
	before, err := f.Stat()
	if err != nil {
		return hashed{}, err
	}
	if !before.Mode().IsRegular() {
		return hashed{}, fmt.Errorf("not a regular file after open")
	}
	h := sha256.New()
	var n int64
	for {
		if r.ctx.Err() != nil {
			return hashed{bytes: n}, r.ctx.Err()
		}
		read, rerr := f.Read(buf)
		if read > 0 {
			h.Write(buf[:read])
			n += int64(read)
			r.bytesDone.Add(int64(read))
		}
		if rerr == io.EOF {
			break
		}
		if rerr != nil {
			return hashed{bytes: n}, rerr
		}
	}
	if r.opts.afterHashRead != nil {
		r.opts.afterHashRead(abs)
	}
	after, err := f.Stat()
	if err != nil {
		return hashed{bytes: n}, err
	}
	got := hashed{sum: hex.EncodeToString(h.Sum(nil)), bytes: n, mtime: after.ModTime()}
	if before.Size() != after.Size() || !before.ModTime().Equal(after.ModTime()) || n != after.Size() {
		return got, errFileChanged
	}
	// The open handle may remain readable after its directory entry is deleted
	// or replaced. Verify that the path still names this same file before
	// accepting the digest.
	current, err := os.Lstat(abs)
	if err != nil || !current.Mode().IsRegular() || !os.SameFile(before, current) {
		return got, errFileChanged
	}
	return got, nil
}

// writeLoop receives outcomes and writes CSV rows in walk order (buffering
// out-of-order results), flushing regularly so a crash loses little work.
func (r *engineRun) writeLoop(f *os.File, results <-chan outcome, window chan struct{}) error {
	w := csv.NewWriter(f)
	w.UseCRLF = true
	pending := map[int64]outcome{}
	var next int64
	rowsSinceFlush := 0
	lastFlush := time.Now()

	emit := func(o outcome) error {
		defer func() { <-window }()
		if o.err != nil {
			if errors.Is(o.err, context.Canceled) {
				return nil // not a real file error, just shutdown
			}
			r.filesFailed.Add(1)
			code := "FILE_READ_FAILED"
			if errors.Is(o.err, errFileChanged) {
				code = "FILE_CHANGED"
			}
			if err := r.logIssue("ERROR", code, o.rel, o.err); err != nil {
				return err
			}
			return nil
		}
		if o.resumed {
			r.res.FilesResumed++
		} else {
			r.res.FilesHashed++
			r.res.BytesHashed += o.size
		}
		err := w.Write([]string{
			o.rel,
			o.name,
			strconv.FormatInt(o.size, 10),
			o.hash,
			o.mtime.UTC().Format(time.RFC3339Nano),
		})
		if err != nil {
			return err
		}
		rowsSinceFlush++
		if rowsSinceFlush >= flushEveryRows || time.Since(lastFlush) > flushEvery {
			w.Flush()
			if err := w.Error(); err != nil {
				return err
			}
			if err := f.Sync(); err != nil {
				return err
			}
			rowsSinceFlush = 0
			lastFlush = time.Now()
		}
		return nil
	}

	for o := range results {
		pending[o.index] = o
		for {
			p, ok := pending[next]
			if !ok {
				break
			}
			delete(pending, next)
			next++
			if err := emit(p); err != nil {
				// Output disk failed: drain and report.
				for range pending {
					<-window
				}
				for range results {
					<-window
				}
				return err
			}
		}
	}
	// On cancel there may be a gap in indices; everything after the gap is
	// dropped and will be re-hashed on resume (correctness over speed).
	w.Flush()
	return w.Error()
}

// logIssue appends one structured line to the error log (created on first
// use). Logging is part of correctness: failures are returned, never ignored.
func (r *engineRun) logIssue(severity, code, rel string, issue error) error {
	r.errLogMu.Lock()
	defer r.errLogMu.Unlock()
	if r.errLogErr != nil {
		return r.errLogErr
	}
	if r.errLog == nil {
		openLog := r.opts.openErrorLog
		if openLog == nil {
			openLog = func(path string) (*os.File, error) {
				return os.OpenFile(path, os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0o644)
			}
		}
		f, ferr := openLog(ErrorLogPath(r.opts.Output))
		if ferr != nil {
			r.errLogErr = ferr
			return ferr
		}
		r.errLog = f
		r.res.ErrorLog = ErrorLogPath(r.opts.Output)
	}
	line := fmt.Sprintf("%s\t%s\t%s\t%s\t%s\n",
		time.Now().UTC().Format(time.RFC3339Nano), severity, code, strconv.Quote(rel), issue.Error())
	if _, err := r.errLog.WriteString(line); err != nil {
		r.errLogErr = err
		return err
	}
	if err := r.errLog.Sync(); err != nil {
		r.errLogErr = err
		return err
	}
	return nil
}

func fileExists(p string) bool {
	_, err := os.Stat(p)
	return err == nil
}

// relBase returns the last component of a slash-separated relative path
// (the sanitized filename, matching the relative_path column exactly).
func relBase(rel string) string {
	if i := strings.LastIndexByte(rel, '/'); i >= 0 {
		return rel[i+1:]
	}
	return rel
}

// encodeNameSpecials returns s with literal percent signs, every byte that is not part of a valid
// UTF-8 sequence, every control character (U+0000..U+001F) and DEL replaced
// by %XX. Ordinary names — including umlauts, spaces, commas, quotes and
// other Unicode — pass through unchanged.
func encodeNameSpecials(s string) string {
	isControl := func(r rune) bool { return r < 0x20 || r == 0x7F }
	if utf8.ValidString(s) && !strings.ContainsFunc(s, isControl) && !strings.Contains(s, "%") {
		return s
	}
	var b strings.Builder
	for i := 0; i < len(s); {
		r, size := utf8.DecodeRuneInString(s[i:])
		switch {
		case s[i] == '%':
			b.WriteString("%25")
		case (r == utf8.RuneError && size == 1) || isControl(r):
			fmt.Fprintf(&b, "%%%02X", s[i])
		default:
			b.WriteString(s[i : i+size])
		}
		i += size
	}
	return b.String()
}

func containsUnsafeNameBytes(s string) bool {
	isControl := func(r rune) bool { return r < 0x20 || r == 0x7F }
	return !utf8.ValidString(s) || strings.ContainsFunc(s, isControl)
}
