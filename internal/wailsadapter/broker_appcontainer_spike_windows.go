//go:build windows && appcontainer_webview2_spike

package wailsadapter

import (
	"context"
	"errors"
	"path/filepath"
	"sync"
	"syscall"
	"time"
	"unsafe"

	"github.com/authenticmemory/gami-hash/internal/app"
	"github.com/authenticmemory/gami-hash/internal/engine"
)

const nativeTextCapacity = 32768

type appContainerBroker struct {
	dll         *syscall.LazyDLL
	selectDir   *syscall.LazyProc
	setName     *syscall.LazyProc
	run         *syscall.LazyProc
	getProgress *syscall.LazyProc
	getResult   *syscall.LazyProc
	cancel      *syscall.LazyProc
	openOutput  *syscall.LazyProc
	restore     *syscall.LazyProc
	events      chan app.Event

	mu          sync.Mutex
	restoreOnce sync.Once
	root        string
	destination string
	output      string
	active      bool
	resumable   bool
	resumeRows  int64
}

type nativeProgress struct {
	Phase                                        int32
	_                                            int32
	FilesDone, FilesTotal, BytesDone, BytesTotal int64
}

type nativeResult struct {
	FilesHashed, FilesResumed, FilesFailed, Skipped, Warnings int64
	BytesHashed, FilesTotal, BytesTotal, ElapsedNanos         int64
	Canceled                                                  int32
	_                                                         int32
}

func newBrokerBackend() brokerBackend {
	dll := syscall.NewLazyDLL("GamiHashStorageBridge.dll")
	b := &appContainerBroker{
		dll:         dll,
		selectDir:   dll.NewProc("GamiSelectFolder"),
		setName:     dll.NewProc("GamiSetOutputName"),
		run:         dll.NewProc("GamiRun"),
		getProgress: dll.NewProc("GamiGetProgress"),
		getResult:   dll.NewProc("GamiGetResult"),
		cancel:      dll.NewProc("GamiCancel"),
		openOutput:  dll.NewProc("GamiOpenOutputFolder"),
		restore:     dll.NewProc("GamiRestoreState"),
		events:      make(chan app.Event, 32),
	}
	return b
}

func (b *appContainerBroker) restoreSelection() {
	root := make([]uint16, nativeTextCapacity)
	output := make([]uint16, nativeTextCapacity)
	errText := make([]uint16, nativeTextCapacity)
	var resumable int32
	var rows int64
	ok, _, _ := b.restore.Call(
		uintptr(unsafe.Pointer(&root[0])), uintptr(len(root)),
		uintptr(unsafe.Pointer(&output[0])), uintptr(len(output)),
		uintptr(unsafe.Pointer(&resumable)),
		uintptr(unsafe.Pointer(&rows)),
		uintptr(unsafe.Pointer(&errText[0])), uintptr(len(errText)),
	)
	if ok != 1 {
		return
	}
	b.root = utf16Text(root)
	b.output = utf16Text(output)
	b.destination = filepath.Dir(b.output)
	b.resumable = resumable != 0
	b.resumeRows = rows
}

func (b *appContainerBroker) Events() <-chan app.Event { return b.events }

func utf16Text(buffer []uint16) string { return syscall.UTF16ToString(buffer) }

func (b *appContainerBroker) pick(source bool) (string, error) {
	path := make([]uint16, nativeTextCapacity)
	errText := make([]uint16, nativeTextCapacity)
	which := uintptr(0)
	if source {
		which = 1
	}
	ok, _, callErr := b.selectDir.Call(which, uintptr(unsafe.Pointer(&path[0])), uintptr(len(path)), uintptr(unsafe.Pointer(&errText[0])), uintptr(len(errText)))
	if ok == ^uintptr(0) {
		return "", nil
	}
	if ok == 0 {
		if message := utf16Text(errText); message != "" {
			return "", errors.New(message)
		}
		return "", callErr
	}
	return utf16Text(path), nil
}

func (b *appContainerBroker) SelectFolder(context.Context) (string, error) {
	path, err := b.pick(true)
	if err == nil && path != "" {
		b.mu.Lock()
		b.root = path
		b.mu.Unlock()
	}
	return path, err
}

func (b *appContainerBroker) SelectOutput(_ context.Context, suggested string) (string, error) {
	destination, err := b.pick(false)
	if err != nil || destination == "" {
		return "", err
	}
	name := filepath.Base(suggested)
	name16, _ := syscall.UTF16PtrFromString(name)
	errText := make([]uint16, nativeTextCapacity)
	ok, _, callErr := b.setName.Call(uintptr(unsafe.Pointer(name16)), uintptr(unsafe.Pointer(&errText[0])), uintptr(len(errText)))
	if ok == 0 {
		if message := utf16Text(errText); message != "" {
			return "", errors.New(message)
		}
		return "", callErr
	}
	output := filepath.Join(destination, name)
	b.mu.Lock()
	b.destination, b.output = destination, output
	b.mu.Unlock()
	return output, nil
}

func (b *appContainerBroker) InspectResume(output string) app.ResumeInspection {
	b.restoreOnce.Do(b.restoreSelection)
	b.mu.Lock()
	defer b.mu.Unlock()
	if !b.resumable || output != b.output {
		return app.ResumeInspection{}
	}
	return app.ResumeInspection{Resumable: true, Root: b.root, Rows: b.resumeRows}
}

func (b *appContainerBroker) Preflight(req app.RunRequest) (app.PreflightResult, error) {
	b.mu.Lock()
	root, output, resumable, rows := b.root, b.output, b.resumable, b.resumeRows
	b.mu.Unlock()
	if req.Mode != app.ModeFresh && req.Mode != app.ModeResume {
		return app.PreflightResult{}, errors.New("unsupported run mode")
	}
	if root == "" || output == "" || req.Root != root || req.Output != output {
		return app.PreflightResult{}, errors.New("select the source and result locations again")
	}
	if req.Mode == app.ModeResume && !resumable {
		return app.PreflightResult{}, errors.New("no valid resumable run exists for this output")
	}
	resume := app.ResumeInspection{Resumable: resumable, Root: root, Rows: rows}
	return app.PreflightResult{Root: root, Output: output, Resume: resume, WillResume: req.Mode == app.ModeResume}, nil
}

func (b *appContainerBroker) Start(req app.RunRequest) error {
	if _, err := b.Preflight(req); err != nil {
		return err
	}
	b.mu.Lock()
	if b.active {
		b.mu.Unlock()
		return app.ErrRunActive
	}
	b.active = true
	b.mu.Unlock()
	go b.runAndReport(req.Mode == app.ModeResume)
	return nil
}

func (b *appContainerBroker) runAndReport(resume bool) {
	done := make(chan struct{})
	go func() {
		ticker := time.NewTicker(100 * time.Millisecond)
		defer ticker.Stop()
		var prior nativeProgress
		for {
			select {
			case <-done:
				return
			case <-ticker.C:
				var raw nativeProgress
				b.getProgress.Call(uintptr(unsafe.Pointer(&raw)))
				if raw != prior {
					prior = raw
					p := engine.Progress{Phase: engine.Phase(raw.Phase), FilesDone: raw.FilesDone, FilesTotal: raw.FilesTotal, BytesDone: raw.BytesDone, BytesTotal: raw.BytesTotal}
					b.events <- app.Event{Kind: app.EventProgress, Progress: &p}
				}
			}
		}
	}()
	errText := make([]uint16, nativeTextCapacity)
	resumeArg := uintptr(0)
	if resume {
		resumeArg = 1
	}
	ok, _, callErr := b.run.Call(resumeArg, uintptr(unsafe.Pointer(&errText[0])), uintptr(len(errText)))
	close(done)
	b.mu.Lock()
	b.active = false
	b.mu.Unlock()
	if ok == 0 {
		message := utf16Text(errText)
		if message == "" {
			message = callErr.Error()
		}
		b.events <- app.Event{Kind: app.EventFatal, Error: message}
		return
	}
	var raw nativeResult
	output := make([]uint16, nativeTextCapacity)
	errorLog := make([]uint16, nativeTextCapacity)
	b.getResult.Call(uintptr(unsafe.Pointer(&raw)), uintptr(unsafe.Pointer(&output[0])), uintptr(len(output)), uintptr(unsafe.Pointer(&errorLog[0])), uintptr(len(errorLog)))
	result := engine.Result{FilesHashed: raw.FilesHashed, FilesResumed: raw.FilesResumed, FilesFailed: raw.FilesFailed, Skipped: raw.Skipped, Warnings: raw.Warnings, BytesHashed: raw.BytesHashed, FilesTotal: raw.FilesTotal, BytesTotal: raw.BytesTotal, Output: utf16Text(output), ErrorLog: utf16Text(errorLog), Canceled: raw.Canceled != 0, Elapsed: time.Duration(raw.ElapsedNanos)}
	b.mu.Lock()
	b.resumable = result.Canceled
	if result.Canceled {
		b.resumeRows = result.FilesHashed + result.FilesResumed
	} else {
		b.resumeRows = 0
	}
	b.mu.Unlock()
	b.events <- app.Event{Kind: app.EventResult, Result: &result}
}

func (b *appContainerBroker) Cancel() error {
	b.mu.Lock()
	active := b.active
	b.mu.Unlock()
	if !active {
		return app.ErrNoRunActive
	}
	b.cancel.Call()
	return nil
}

func (b *appContainerBroker) OpenOutputFolder(context.Context) error {
	errText := make([]uint16, nativeTextCapacity)
	ok, _, callErr := b.openOutput.Call(uintptr(unsafe.Pointer(&errText[0])), uintptr(len(errText)))
	if ok == 0 {
		if message := utf16Text(errText); message != "" {
			return errors.New(message)
		}
		return callErr
	}
	return nil
}
