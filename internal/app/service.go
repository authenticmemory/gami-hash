// Package app defines the narrow, GUI-facing boundary around the hashing
// engine. It contains no Wails dependency and grants the frontend no direct
// filesystem or engine authority.
package app

import (
	"context"
	"errors"
	"fmt"
	"sync"

	"github.com/authenticmemory/gami-hash/internal/engine"
)

var (
	ErrRunActive   = errors.New("a hashing run is already active")
	ErrNoRunActive = errors.New("no hashing run is active")
)

// RunMode is a user intent. The engine still validates whether that intent is
// safe and compatible with the filesystem state at Start time.
type RunMode string

const (
	ModeResume         RunMode = "resume"
	ModeFresh          RunMode = "fresh"
	ModeRehashExisting RunMode = "rehash-existing"
	ModeResumeMoved    RunMode = "resume-moved-root"
)

type RunRequest struct {
	Root    string  `json:"root"`
	Output  string  `json:"output"`
	Workers int     `json:"workers"`
	Mode    RunMode `json:"mode"`
}

type ResumeInspection struct {
	Resumable bool   `json:"resumable"`
	Root      string `json:"root,omitempty"`
	Rows      int64  `json:"rows"`
}

type PreflightResult struct {
	Root       string           `json:"root"`
	Output     string           `json:"output"`
	Resume     ResumeInspection `json:"resume"`
	WillResume bool             `json:"willResume"`
}

type EventKind string

const (
	EventProgress EventKind = "progress"
	EventResult   EventKind = "result"
	EventFatal    EventKind = "fatal"
)

type Event struct {
	Kind     EventKind        `json:"kind"`
	Progress *engine.Progress `json:"progress,omitempty"`
	Result   *engine.Result   `json:"result,omitempty"`
	Error    string           `json:"error,omitempty"`
}

// Dialogs and OutputOpener are implemented by the Wails adapter. Keeping them
// here as narrow capabilities prevents frontend-supplied code from touching
// the source collection.
type Dialogs interface {
	SelectFolder(context.Context) (string, error)
	SelectOutput(context.Context, string) (string, error)
}

type OutputOpener interface {
	OpenFolder(context.Context, string) error
}

type Service struct {
	dialogs Dialogs
	opener  OutputOpener

	mu          sync.Mutex
	cancel      context.CancelFunc
	active      bool
	lastOutput  string
	events      chan Event
	runFinished chan struct{}
	eventMu     sync.Mutex
}

func NewService(dialogs Dialogs, opener OutputOpener) *Service {
	return &Service{dialogs: dialogs, opener: opener, events: make(chan Event, 32)}
}

func (s *Service) Events() <-chan Event { return s.events }

func (s *Service) SelectFolder(ctx context.Context) (string, error) {
	if s.dialogs == nil {
		return "", errors.New("folder dialog is unavailable")
	}
	return s.dialogs.SelectFolder(ctx)
}

func (s *Service) SelectOutput(ctx context.Context, suggested string) (string, error) {
	if s.dialogs == nil {
		return "", errors.New("output dialog is unavailable")
	}
	return s.dialogs.SelectOutput(ctx, suggested)
}

func (s *Service) InspectResume(output string) ResumeInspection {
	st := engine.CheckResume(output)
	return ResumeInspection{Resumable: st.Resumable, Root: st.Root, Rows: st.RowCount}
}

func optionsFor(req RunRequest) (engine.Options, error) {
	if req.Root == "" || req.Output == "" {
		return engine.Options{}, errors.New("source folder and output file are required")
	}
	if req.Workers == 0 {
		req.Workers = engine.DefaultWorkers
	}
	if req.Workers < 1 || req.Workers > engine.MaxWorkers {
		return engine.Options{}, fmt.Errorf("workers must be between 1 and %d", engine.MaxWorkers)
	}
	opts := engine.Options{Root: req.Root, Output: req.Output, Workers: req.Workers}
	switch req.Mode {
	case ModeResume:
	case ModeFresh:
		opts.Fresh = true
	case ModeRehashExisting:
		opts.RehashExisting = true
	case ModeResumeMoved:
		opts.AllowRootMismatch = true
	default:
		return engine.Options{}, fmt.Errorf("unsupported run mode %q", req.Mode)
	}
	return opts, nil
}

func (s *Service) validateRequest(req RunRequest) (engine.Options, ResumeInspection, error) {
	opts, err := optionsFor(req)
	if err != nil {
		return engine.Options{}, ResumeInspection{}, err
	}
	validated, err := engine.Validate(opts)
	if err != nil {
		return engine.Options{}, ResumeInspection{}, err
	}
	resume := s.InspectResume(validated.Output)
	if (req.Mode == ModeResume || req.Mode == ModeRehashExisting || req.Mode == ModeResumeMoved) && !resume.Resumable {
		return engine.Options{}, ResumeInspection{}, errors.New("no valid resumable run exists for this output")
	}
	return validated, resume, nil
}

// Preflight is deliberately read-only. It gives early feedback, but Start
// never trusts it: engine.Run repeats every safety and resume validation.
func (s *Service) Preflight(req RunRequest) (PreflightResult, error) {
	validated, resume, err := s.validateRequest(req)
	if err != nil {
		return PreflightResult{}, err
	}
	// A complete dry-run validation is intentionally performed by the engine
	// at Start. This inspection must not create, truncate, or repair artifacts.
	return PreflightResult{
		Root: validated.Root, Output: validated.Output, Resume: resume,
		WillResume: !validated.Fresh && resume.Resumable,
	}, nil
}

func (s *Service) Start(req RunRequest) error {
	opts, _, err := s.validateRequest(req)
	if err != nil {
		return err
	}
	s.mu.Lock()
	if s.active {
		s.mu.Unlock()
		return ErrRunActive
	}
	ctx, cancel := context.WithCancel(context.Background())
	s.active = true
	s.cancel = cancel
	s.runFinished = make(chan struct{})
	done := s.runFinished
	s.mu.Unlock()

	go func() {
		defer close(done)
		res, runErr := engine.Run(ctx, opts, func(p engine.Progress) {
			copy := p
			s.emit(Event{Kind: EventProgress, Progress: &copy})
		})
		if runErr != nil {
			s.emit(Event{Kind: EventFatal, Error: runErr.Error()})
		} else {
			copy := res
			s.emit(Event{Kind: EventResult, Result: &copy})
		}
		s.mu.Lock()
		s.active = false
		s.cancel = nil
		if runErr == nil {
			s.lastOutput = res.Output
		}
		s.mu.Unlock()
	}()
	return nil
}

func (s *Service) emit(event Event) {
	s.eventMu.Lock()
	defer s.eventMu.Unlock()
	if event.Kind == EventProgress {
		select {
		case s.events <- event:
		default: // A broken frontend cannot block the engine.
		}
		return
	}
	// A terminal event takes precedence over stale progress. Make room without
	// blocking if the frontend stopped consuming events.
	for {
		select {
		case s.events <- event:
			return
		default:
			<-s.events
		}
	}
}

func (s *Service) Cancel() error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if !s.active || s.cancel == nil {
		return ErrNoRunActive
	}
	s.cancel()
	return nil
}

func (s *Service) OpenOutputFolder(ctx context.Context) error {
	s.mu.Lock()
	output := s.lastOutput
	s.mu.Unlock()
	if output == "" {
		return errors.New("no completed output is available")
	}
	if s.opener == nil {
		return errors.New("output-folder opener is unavailable")
	}
	return s.opener.OpenFolder(ctx, output)
}
