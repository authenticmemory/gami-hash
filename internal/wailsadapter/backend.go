// Package wailsadapter is the only bridge exposed to the TypeScript frontend.
package wailsadapter

import (
	"context"
	"errors"
	"path/filepath"
	"sync"

	"github.com/wailsapp/wails/v2/pkg/runtime"

	"github.com/authenticmemory/gami-hash/internal/app"
)

const EventName = "gami:engine"

// Backend is the sole value placed in Wails' Bind list. Keep its exported
// method set intentionally small: every exported method becomes callable by
// frontend JavaScript.
type Backend struct {
	service *app.Service

	mu     sync.RWMutex
	ctx    context.Context
	cancel context.CancelFunc
}

func New() *Backend {
	return &Backend{service: app.NewService(wailsDialogs{}, systemOutputOpener{})}
}

// OnStartup returns the lifecycle hook without adding a bindable method to
// Backend's exported method set.
func OnStartup(b *Backend) func(context.Context) {
	return func(ctx context.Context) {
		bridgeCtx, cancel := context.WithCancel(ctx)
		b.mu.Lock()
		b.ctx = ctx
		b.cancel = cancel
		b.mu.Unlock()
		go b.forwardEvents(bridgeCtx)
	}
}

// OnShutdown returns the lifecycle hook without exposing shutdown authority
// to frontend JavaScript.
func OnShutdown(b *Backend) func(context.Context) {
	return func(context.Context) {
		_ = b.service.Cancel()
		b.mu.Lock()
		if b.cancel != nil {
			b.cancel()
		}
		b.ctx = nil
		b.cancel = nil
		b.mu.Unlock()
	}
}

func (b *Backend) context() (context.Context, error) {
	b.mu.RLock()
	defer b.mu.RUnlock()
	if b.ctx == nil {
		return nil, errors.New("application runtime is not ready")
	}
	return b.ctx, nil
}

func (b *Backend) forwardEvents(ctx context.Context) {
	for {
		select {
		case <-ctx.Done():
			return
		case event := <-b.service.Events():
			runtime.EventsEmit(ctx, EventName, event)
		}
	}
}

func (b *Backend) SelectFolder() (string, error) {
	ctx, err := b.context()
	if err != nil {
		return "", err
	}
	return b.service.SelectFolder(ctx)
}

func (b *Backend) SelectOutput(suggested string) (string, error) {
	ctx, err := b.context()
	if err != nil {
		return "", err
	}
	return b.service.SelectOutput(ctx, suggested)
}

func (b *Backend) InspectResume(output string) app.ResumeInspection {
	return b.service.InspectResume(output)
}

func (b *Backend) Preflight(req app.RunRequest) (app.PreflightResult, error) {
	return b.service.Preflight(req)
}

func (b *Backend) Start(req app.RunRequest) error { return b.service.Start(req) }

func (b *Backend) Cancel() error { return b.service.Cancel() }

func (b *Backend) OpenOutputFolder() error {
	ctx, err := b.context()
	if err != nil {
		return err
	}
	return b.service.OpenOutputFolder(ctx)
}

type wailsDialogs struct{}

func (wailsDialogs) SelectFolder(ctx context.Context) (string, error) {
	return runtime.OpenDirectoryDialog(ctx, runtime.OpenDialogOptions{
		Title: "Select the folder to hash",
	})
}

func (wailsDialogs) SelectOutput(ctx context.Context, suggested string) (string, error) {
	return runtime.SaveFileDialog(ctx, runtime.SaveDialogOptions{
		Title:            "Save the GAMI hash manifest",
		DefaultDirectory: filepath.Dir(suggested),
		DefaultFilename:  filepath.Base(suggested),
		Filters: []runtime.FileFilter{{
			DisplayName: "CSV manifest (*.csv)",
			Pattern:     "*.csv",
		}},
	})
}
