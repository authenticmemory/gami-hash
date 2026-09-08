package app

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"testing"
	"time"
)

func TestPreflightRejectsOutputInsideSource(t *testing.T) {
	root := t.TempDir()
	s := NewService(nil, nil)
	_, err := s.Preflight(RunRequest{
		Root: root, Output: filepath.Join(root, "manifest.csv"),
		Workers: 2, Mode: ModeFresh,
	})
	if err == nil {
		t.Fatal("unsafe output passed preflight")
	}
}

func TestStartDoesNotTrustFrontendPreflight(t *testing.T) {
	root := t.TempDir()
	source := filepath.Join(root, "source.txt")
	if err := os.WriteFile(source, []byte("must survive"), 0o644); err != nil {
		t.Fatal(err)
	}
	s := NewService(nil, nil)
	err := s.Start(RunRequest{
		Root: root, Output: filepath.Join(root, "manifest.csv"),
		Workers: 2, Mode: ModeFresh,
	})
	if err == nil {
		t.Fatal("unsafe run did not fail synchronously")
	}
	data, err := os.ReadFile(source)
	if err != nil || string(data) != "must survive" {
		t.Fatalf("source changed: data=%q err=%v", data, err)
	}
}

func TestResumeModeRequiresEngineValidatedResume(t *testing.T) {
	root := t.TempDir()
	s := NewService(nil, nil)
	err := s.Start(RunRequest{
		Root: root, Output: filepath.Join(t.TempDir(), "manifest.csv"),
		Workers: 2, Mode: ModeResume,
	})
	if err == nil {
		t.Fatal("resume request without valid resume data was accepted")
	}
}

func TestBoundaryRejectsMalformedFrontendRequests(t *testing.T) {
	s := NewService(nil, nil)
	requests := []RunRequest{
		{},
		{Root: "x", Output: "y", Workers: 65, Mode: ModeFresh},
		{Root: "x", Output: "y", Workers: 1, Mode: "invented"},
	}
	for _, req := range requests {
		if err := s.Start(req); err == nil {
			t.Fatalf("malformed request accepted: %+v", req)
		}
	}
}

func TestCancelWithoutRunAndOpenWithoutResultAreRejected(t *testing.T) {
	s := NewService(nil, nil)
	if !errors.Is(s.Cancel(), ErrNoRunActive) {
		t.Fatal("cancel without an active run was accepted")
	}
	if err := s.OpenOutputFolder(context.Background()); err == nil {
		t.Fatal("open output without a completed result was accepted")
	}
}

func TestBrokenFrontendDoesNotBlockCompletion(t *testing.T) {
	root := t.TempDir()
	for i := 0; i < 100; i++ {
		if err := os.WriteFile(filepath.Join(root, time.Now().Add(time.Duration(i)).Format("150405.000000000")), []byte("x"), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	s := NewService(nil, nil)
	out := filepath.Join(t.TempDir(), "manifest.csv")
	if err := s.Start(RunRequest{Root: root, Output: out, Workers: 2, Mode: ModeFresh}); err != nil {
		t.Fatal(err)
	}
	// Deliberately do not consume progress for a moment. A full event buffer
	// must not apply backpressure to the hashing engine.
	time.Sleep(500 * time.Millisecond)
	event := waitTerminal(t, s.Events())
	if event.Kind != EventResult || event.Result == nil || event.Result.FilesHashed != 100 {
		t.Fatalf("run did not complete behind a broken frontend: %+v", event)
	}
}

func waitTerminal(t *testing.T, events <-chan Event) Event {
	t.Helper()
	timer := time.NewTimer(10 * time.Second)
	defer timer.Stop()
	for {
		select {
		case event := <-events:
			if event.Kind == EventResult || event.Kind == EventFatal {
				return event
			}
		case <-timer.C:
			t.Fatal("timed out waiting for terminal event")
		}
	}
}
