package storageprotocol

import (
	"bytes"
	"encoding/binary"
	"errors"
	"strings"
	"testing"
)

func TestValidateRelativeName(t *testing.T) {
	valid := []string{"a.txt", "folder/a.txt", "évidence/写真 01.tif"}
	for _, name := range valid {
		if err := ValidateRelativeName(name); err != nil {
			t.Errorf("ValidateRelativeName(%q) = %v", name, err)
		}
	}
	invalid := []string{"", "/absolute", `C:/absolute`, `folder\\file`, "a//b", "a/../b", "./a", "a/.", "a ", "a\x00b", "file:stream"}
	for _, name := range invalid {
		if err := ValidateRelativeName(name); !errors.Is(err, ErrUnsafeName) {
			t.Errorf("ValidateRelativeName(%q) = %v, want ErrUnsafeName", name, err)
		}
	}
}

func TestCodecRoundTrip(t *testing.T) {
	request, err := NewRequest(7, OpList, ListRequest{FolderID: "root", Limit: 10})
	if err != nil {
		t.Fatal(err)
	}
	var wire bytes.Buffer
	if err := NewCodec(nil, &wire).WriteRequest(request); err != nil {
		t.Fatal(err)
	}
	got, err := NewCodec(&wire, nil).ReadRequest()
	if err != nil {
		t.Fatal(err)
	}
	if got.RequestID != 7 || got.Operation != OpList {
		t.Fatalf("unexpected request: %#v", got)
	}
	payload, err := DecodePayload[ListRequest](got.Payload)
	if err != nil || payload.FolderID != "root" || payload.Limit != 10 {
		t.Fatalf("unexpected payload: %#v, %v", payload, err)
	}
}

func TestCodecRejectsOversizedFrameBeforeAllocation(t *testing.T) {
	var wire bytes.Buffer
	var header [4]byte
	binary.LittleEndian.PutUint32(header[:], MaxFrameSize+1)
	wire.Write(header[:])
	_, err := NewCodec(&wire, nil).ReadRequest()
	if !errors.Is(err, ErrFrameTooLarge) {
		t.Fatalf("got %v, want ErrFrameTooLarge", err)
	}
}

func TestCodecRejectsUnknownVersionAndOperation(t *testing.T) {
	for _, request := range []Request{
		{Version: Version + 1, RequestID: 1, Operation: OpList},
		{Version: Version, RequestID: 1, Operation: Operation("delete_source")},
	} {
		var wire bytes.Buffer
		if err := NewCodec(nil, &wire).writeJSON(request); err != nil {
			t.Fatal(err)
		}
		if _, err := NewCodec(&wire, nil).ReadRequest(); !errors.Is(err, ErrInvalidRequest) {
			t.Fatalf("request %#v: got %v", request, err)
		}
	}
}

func TestClientEnforcesResponseID(t *testing.T) {
	var requests bytes.Buffer
	response, err := Success(2, struct{}{})
	if err != nil {
		t.Fatal(err)
	}
	var responses bytes.Buffer
	if err := NewCodec(nil, &responses).WriteResponse(response); err != nil {
		t.Fatal(err)
	}
	client := NewClient(NewCodec(&responses, &requests))
	if err := client.Call(OpCancel, struct{}{}, nil); !errors.Is(err, ErrResponseMismatch) {
		t.Fatalf("got %v, want ErrResponseMismatch", err)
	}
}

func TestFrameWriterRejectsLargePayload(t *testing.T) {
	request, err := NewRequest(1, OpList, map[string]string{"value": strings.Repeat("x", MaxFrameSize)})
	if err != nil {
		t.Fatal(err)
	}
	if err := NewCodec(nil, &bytes.Buffer{}).WriteRequest(request); !errors.Is(err, ErrFrameTooLarge) {
		t.Fatalf("got %v, want ErrFrameTooLarge", err)
	}
}
