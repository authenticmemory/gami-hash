// Package containedworker runs the Go hashing engine against the native
// Windows storage broker. It contains no folder paths, picker APIs, or network
// code. The broker supplies only opaque item IDs and duplicated handles.
package containedworker

import (
	"context"
	"errors"
	"io"
	"sync"

	"github.com/authenticmemory/gami-hash/internal/engine"
	"github.com/authenticmemory/gami-hash/internal/storageprotocol"
)

// Run serves one hashing run over a pair of inherited anonymous pipes.
func Run(parent context.Context, reader io.Reader, writer io.Writer) (engine.Result, error) {
	if reader == nil || writer == nil {
		return engine.Result{}, errors.New("contained worker pipes are unavailable")
	}
	client := storageprotocol.NewClient(storageprotocol.NewCodec(reader, writer))
	var begin storageprotocol.BeginResponse
	if err := client.Call(storageprotocol.OpBegin, storageprotocol.BeginRequest{WorkerVersion: engine.Version}, &begin); err != nil {
		return engine.Result{}, err
	}
	if begin.SourceIdentity == "" || begin.DestinationIdentity == "" {
		return engine.Result{}, errors.New("storage broker did not provide stable selected-folder identities")
	}
	ctx, cancel := context.WithCancel(parent)
	defer cancel()

	var progressErr error
	var progressMu sync.Mutex
	result, err := engine.RunBrokered(ctx, engine.BrokeredOptions{
		RootID: begin.RootID, SourceIdentity: begin.SourceIdentity, OutputName: begin.OutputName, Workers: begin.Workers,
		ContainmentValidated: begin.ContainmentValidated, Resume: begin.Resume,
	}, client, func(progress engine.Progress) {
		progressMu.Lock()
		defer progressMu.Unlock()
		if progressErr != nil {
			return
		}
		var response storageprotocol.ProgressResponse
		progressErr = client.Call(storageprotocol.OpProgress, storageprotocol.ProgressRequest{
			Phase: int(progress.Phase), FilesDone: progress.FilesDone, FilesTotal: progress.FilesTotal,
			BytesDone: progress.BytesDone, BytesTotal: progress.BytesTotal,
		}, &response)
		if response.CancelRequested || progressErr != nil {
			cancel()
		}
	})
	progressMu.Lock()
	defer progressMu.Unlock()
	if progressErr != nil && err == nil {
		return engine.Result{}, progressErr
	}
	if err != nil {
		return engine.Result{}, err
	}
	complete := storageprotocol.CompleteRequest{
		FilesHashed: result.FilesHashed, FilesResumed: result.FilesResumed,
		FilesFailed: result.FilesFailed, Skipped: result.Skipped, Warnings: result.Warnings,
		BytesHashed: result.BytesHashed, FilesTotal: result.FilesTotal, BytesTotal: result.BytesTotal,
		Output: result.Output, ErrorLog: result.ErrorLog, Canceled: result.Canceled,
		ElapsedNanos: result.Elapsed.Nanoseconds(),
	}
	if err := client.Call(storageprotocol.OpComplete, complete, nil); err != nil {
		return engine.Result{}, err
	}
	return result, nil
}
