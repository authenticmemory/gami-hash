package main

import (
	"bytes"
	"encoding/json"
	"strings"
	"testing"
)

func TestNativeUIWorkerHandshakeAndResumeInspection(t *testing.T) {
	input := strings.NewReader(
		`{"id":"1","method":"hello"}` + "\n" +
			`{"id":"2","method":"inspect_resume","payload":{"output":"Z:\\missing\\manifest.csv"}}` + "\n")
	var output bytes.Buffer
	handled, code := runNativeUIWorkerIfRequested([]string{"--native-ui-worker"}, input, &output)
	if !handled || code != 0 {
		t.Fatalf("handled=%t code=%d", handled, code)
	}
	decoder := json.NewDecoder(&output)
	var hello, inspection nativeUIResponse
	if err := decoder.Decode(&hello); err != nil || !hello.OK || hello.ID != "1" {
		t.Fatalf("bad hello response: %+v err=%v", hello, err)
	}
	if err := decoder.Decode(&inspection); err != nil || !inspection.OK || inspection.ID != "2" {
		t.Fatalf("bad inspection response: %+v err=%v", inspection, err)
	}
}

func TestNativeUIWorkerRejectsUnknownMethod(t *testing.T) {
	var output bytes.Buffer
	_, code := runNativeUIWorkerIfRequested([]string{"--native-ui-worker"}, strings.NewReader(`{"id":"1","method":"network"}`), &output)
	if code != 0 {
		t.Fatalf("worker returned %d", code)
	}
	var response nativeUIResponse
	if err := json.Unmarshal(output.Bytes(), &response); err != nil || response.OK || response.Error == "" {
		t.Fatalf("unexpected response: %+v err=%v", response, err)
	}
}

func TestNativeUIWorkerPreflightUsesAppServiceValidation(t *testing.T) {
	var output bytes.Buffer
	request := `{"id":"1","method":"preflight","payload":{"root":"C:\\source","output":"C:\\source\\manifest.csv","workers":2,"mode":"fresh"}}`
	_, code := runNativeUIWorkerIfRequested([]string{"--native-ui-worker"}, strings.NewReader(request), &output)
	if code != 0 {
		t.Fatalf("worker returned %d", code)
	}
	var response nativeUIResponse
	if err := json.Unmarshal(output.Bytes(), &response); err != nil || response.OK || response.Error == "" {
		t.Fatalf("unsafe preflight was accepted: %+v err=%v", response, err)
	}
}
