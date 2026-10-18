// Package wailsadapter is the only bridge exposed to the TypeScript frontend.
package wailsadapter

import (
	"context"
	"errors"
	"log"
	"path/filepath"
	"sync"
	"time"

	"github.com/wailsapp/wails/v2/pkg/runtime"

	"github.com/authenticmemory/gami-hash/internal/app"
)

const EventName = "gami:engine"

// Backend is the sole value placed in Wails' Bind list. Keep its exported
// method set intentionally small: every exported method becomes callable by
// frontend JavaScript.
type Backend struct {
	service *app.Service
	broker  brokerBackend

	mu     sync.RWMutex
	ctx    context.Context
	cancel context.CancelFunc
}

func New() *Backend {
	if broker := newBrokerBackend(); broker != nil {
		return &Backend{broker: broker}
	}
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
		log.Printf("[Wails adapter] shutdown begin")
		if b.broker != nil {
			if err := b.broker.Shutdown(15 * time.Second); err != nil {
				log.Printf("[Wails adapter] broker shutdown: %v", err)
			}
		} else {
			_ = b.service.Cancel()
		}
		b.mu.Lock()
		if b.cancel != nil {
			b.cancel()
		}
		b.ctx = nil
		b.cancel = nil
		b.mu.Unlock()
		log.Printf("[Wails adapter] shutdown complete")
		terminateAfterShutdown()
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
	var events <-chan app.Event
	if b.broker != nil {
		events = b.broker.Events()
	} else {
		events = b.service.Events()
	}
	for {
		select {
		case <-ctx.Done():
			return
		case event := <-events:
			runtime.EventsEmit(ctx, EventName, event)
		}
	}
}

func (b *Backend) SelectFolder() (string, error) {
	ctx, err := b.context()
	if err != nil {
		return "", err
	}
	if b.broker != nil {
		return b.broker.SelectFolder(ctx)
	}
	return b.service.SelectFolder(ctx)
}

func (b *Backend) SelectOutput(suggested string) (string, error) {
	ctx, err := b.context()
	if err != nil {
		return "", err
	}
	if b.broker != nil {
		return b.broker.SelectOutput(ctx, suggested)
	}
	return b.service.SelectOutput(ctx, suggested)
}

func (b *Backend) InspectResume(output string) app.ResumeInspection {
	if b.broker != nil {
		return b.broker.InspectResume(output)
	}
	return b.service.InspectResume(output)
}

func (b *Backend) Preflight(req app.RunRequest) (app.PreflightResult, error) {
	if b.broker != nil {
		return b.broker.Preflight(req)
	}
	return b.service.Preflight(req)
}

func (b *Backend) Start(req app.RunRequest) error {
	if b.broker != nil {
		return b.broker.Start(req)
	}
	return b.service.Start(req)
}

func (b *Backend) Cancel() error {
	if b.broker != nil {
		return b.broker.Cancel()
	}
	return b.service.Cancel()
}

func (b *Backend) OpenOutputFolder() error {
	ctx, err := b.context()
	if err != nil {
		return err
	}
	if b.broker != nil {
		return b.broker.OpenOutputFolder(ctx)
	}
	return b.service.OpenOutputFolder(ctx)
}

type brokerBackend interface {
	Events() <-chan app.Event
	SelectFolder(context.Context) (string, error)
	SelectOutput(context.Context, string) (string, error)
	InspectResume(string) app.ResumeInspection
	Preflight(app.RunRequest) (app.PreflightResult, error)
	Start(app.RunRequest) error
	Cancel() error
	OpenOutputFolder(context.Context) error
	Shutdown(time.Duration) error
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
