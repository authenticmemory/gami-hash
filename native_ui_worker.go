package main

import (
	"bufio"
	"encoding/json"
	"fmt"
	"io"
	"sync"

	appservice "github.com/authenticmemory/gami-hash/internal/app"
)

const nativeUIProtocolVersion = 1

type nativeUIRequest struct {
	ID      string          `json:"id"`
	Method  string          `json:"method"`
	Payload json.RawMessage `json:"payload,omitempty"`
}

type nativeUIResponse struct {
	ID     string `json:"id"`
	OK     bool   `json:"ok"`
	Result any    `json:"result,omitempty"`
	Error  string `json:"error,omitempty"`
}

type nativeUIEvent struct {
	Event appservice.Event `json:"event"`
}

// runNativeUIWorkerIfRequested exposes the existing app.Service over a local
// stdin/stdout protocol. It opens no listener and gives the WPF process no
// filesystem authority beyond the explicit paths supplied by the user.
func runNativeUIWorkerIfRequested(args []string, input io.Reader, output io.Writer) (bool, int) {
	if len(args) != 1 || args[0] != "--native-ui-worker" {
		return false, 0
	}

	service := appservice.NewService(nil, nil)
	decoder := json.NewDecoder(bufio.NewReader(input))
	encoder := json.NewEncoder(output)
	var writer sync.Mutex
	write := func(value any) error {
		writer.Lock()
		defer writer.Unlock()
		return encoder.Encode(value)
	}
	go func() {
		for event := range service.Events() {
			if err := write(nativeUIEvent{Event: event}); err != nil {
				return
			}
		}
	}()
	for {
		var request nativeUIRequest
		if err := decoder.Decode(&request); err != nil {
			if err == io.EOF {
				return true, 0
			}
			_ = write(nativeUIResponse{OK: false, Error: "invalid request: " + err.Error()})
			return true, 2
		}

		response := nativeUIResponse{ID: request.ID, OK: true}
		switch request.Method {
		case "hello":
			response.Result = map[string]any{"protocol": nativeUIProtocolVersion, "service": "gami-hash-engine"}
		case "inspect_resume":
			var payload struct {
				Output string `json:"output"`
			}
			if err := json.Unmarshal(request.Payload, &payload); err != nil || payload.Output == "" {
				response.OK = false
				response.Error = "inspect_resume requires a non-empty output path"
			} else {
				response.Result = service.InspectResume(payload.Output)
			}
		case "preflight":
			var payload appservice.RunRequest
			if err := json.Unmarshal(request.Payload, &payload); err != nil {
				response.OK = false
				response.Error = "preflight request is invalid"
			} else if result, err := service.Preflight(payload); err != nil {
				response.OK = false
				response.Error = err.Error()
			} else {
				response.Result = result
			}
		case "start":
			var payload appservice.RunRequest
			if err := json.Unmarshal(request.Payload, &payload); err != nil {
				response.OK = false
				response.Error = "start request is invalid"
			} else if err := service.Start(payload); err != nil {
				response.OK = false
				response.Error = err.Error()
			} else {
				response.Result = map[string]bool{"started": true}
			}
		case "cancel":
			if err := service.Cancel(); err != nil {
				response.OK = false
				response.Error = err.Error()
			} else {
				response.Result = map[string]bool{"canceling": true}
			}
		default:
			response.OK = false
			response.Error = fmt.Sprintf("unknown method %q", request.Method)
		}
		if err := write(response); err != nil {
			return true, 2
		}
	}
}
