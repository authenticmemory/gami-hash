// Package storageprotocol defines the bounded request/response contract between
// the contained Go hashing worker and the native Windows storage broker.
//
// The protocol carries metadata and duplicated handle values. File contents
// never travel through it. Source operations accept opaque broker-issued IDs;
// destination operations accept only broker-issued work names.
package storageprotocol

import (
	"encoding/json"
	"errors"
	"fmt"
	"path"
	"strings"
	"unicode/utf8"
)

const (
	Version          = 1
	MaxFrameSize     = 1 << 20
	DefaultPageSize  = 256
	MaximumPageSize  = 4096
	MaximumNameBytes = 32 << 10
)

type Operation string

const (
	OpBegin       Operation = "begin"
	OpList        Operation = "list"
	OpStat        Operation = "stat"
	OpOpenRead    Operation = "open_read"
	OpCreateWork  Operation = "create_work"
	OpOpenWork    Operation = "open_work"
	OpPublishWork Operation = "publish_work"
	OpRemoveWork  Operation = "remove_work"
	OpCancel      Operation = "cancel"
	OpProgress    Operation = "progress"
	OpComplete    Operation = "complete"
)

func (o Operation) Valid() bool {
	switch o {
	case OpBegin, OpList, OpStat, OpOpenRead, OpCreateWork, OpOpenWork, OpPublishWork, OpRemoveWork, OpCancel, OpProgress, OpComplete:
		return true
	default:
		return false
	}
}

type Request struct {
	Version   uint32          `json:"version"`
	RequestID uint64          `json:"request_id"`
	Operation Operation       `json:"operation"`
	Payload   json.RawMessage `json:"payload,omitempty"`
}

type Response struct {
	Version   uint32          `json:"version"`
	RequestID uint64          `json:"request_id"`
	OK        bool            `json:"ok"`
	Error     *ProtocolError  `json:"error,omitempty"`
	Payload   json.RawMessage `json:"payload,omitempty"`
}

type ProtocolError struct {
	Code      string `json:"code"`
	Message   string `json:"message"`
	Retryable bool   `json:"retryable,omitempty"`
}

type BeginRequest struct {
	WorkerVersion string `json:"worker_version"`
}

type BeginResponse struct {
	RootID               string `json:"root_id"`
	OutputName           string `json:"output_name"`
	Workers              int    `json:"workers"`
	SourceIdentity       string `json:"source_identity"`
	DestinationIdentity  string `json:"destination_identity"`
	ContainmentValidated bool   `json:"containment_validated"`
	Resume               bool   `json:"resume"`
}

type ProgressRequest struct {
	Phase      int   `json:"phase"`
	FilesDone  int64 `json:"files_done"`
	FilesTotal int64 `json:"files_total"`
	BytesDone  int64 `json:"bytes_done"`
	BytesTotal int64 `json:"bytes_total"`
}

type ProgressResponse struct {
	CancelRequested bool `json:"cancel_requested"`
}

type CompleteRequest struct {
	FilesHashed  int64  `json:"files_hashed"`
	FilesResumed int64  `json:"files_resumed"`
	FilesFailed  int64  `json:"files_failed"`
	Skipped      int64  `json:"skipped"`
	Warnings     int64  `json:"warnings"`
	BytesHashed  int64  `json:"bytes_hashed"`
	FilesTotal   int64  `json:"files_total"`
	BytesTotal   int64  `json:"bytes_total"`
	Output       string `json:"output"`
	ErrorLog     string `json:"error_log,omitempty"`
	Canceled     bool   `json:"canceled"`
	ElapsedNanos int64  `json:"elapsed_nanos"`
}

type ListRequest struct {
	FolderID string `json:"folder_id"`
	Page     string `json:"page,omitempty"`
	Limit    uint32 `json:"limit,omitempty"`
}

type ListResponse struct {
	Items    []Item `json:"items"`
	NextPage string `json:"next_page,omitempty"`
}

type ItemKind string

const (
	ItemFile      ItemKind = "file"
	ItemDirectory ItemKind = "directory"
)

type Item struct {
	ID           string   `json:"id"`
	Name         string   `json:"name"`
	Kind         ItemKind `json:"kind"`
	Size         int64    `json:"size,omitempty"`
	ModifiedUTC  string   `json:"modified_utc,omitempty"`
	Identity     string   `json:"identity"`
	Attributes   uint32   `json:"attributes"`
	ReparseTag   uint32   `json:"reparse_tag,omitempty"`
	ProviderKind string   `json:"provider_kind,omitempty"`
}

type ItemRequest struct {
	ItemID string `json:"item_id"`
}

type StatResponse struct {
	Item Item `json:"item"`
}

type HandleResponse struct {
	Handle      uint64 `json:"handle,string"`
	Identity    string `json:"identity"`
	Size        int64  `json:"size,omitempty"`
	ModifiedUTC string `json:"modified_utc,omitempty"`
}

type CreateWorkRequest struct {
	Kind string `json:"kind"`
}

type WorkRequest struct {
	Name     string `json:"name"`
	Writable bool   `json:"writable,omitempty"`
}

type WorkHandleResponse struct {
	Name                    string `json:"name"`
	Handle                  uint64 `json:"handle,string"`
	Identity                string `json:"identity"`
	LinkCount               uint32 `json:"link_count"`
	VolumeCapabilitiesKnown bool   `json:"volume_capabilities_known,omitempty"`
	HardLinksSupported      bool   `json:"hard_links_supported,omitempty"`
}

type PublishWorkRequest struct {
	Name            string `json:"name"`
	DestinationName string `json:"destination_name"`
}

var (
	ErrUnsafeName     = errors.New("unsafe relative name")
	ErrInvalidRequest = errors.New("invalid protocol request")
)

func NewRequest(id uint64, operation Operation, payload any) (Request, error) {
	if id == 0 || !operation.Valid() {
		return Request{}, ErrInvalidRequest
	}
	raw, err := json.Marshal(payload)
	if err != nil {
		return Request{}, err
	}
	return Request{Version: Version, RequestID: id, Operation: operation, Payload: raw}, nil
}

func Success(id uint64, payload any) (Response, error) {
	raw, err := json.Marshal(payload)
	if err != nil {
		return Response{}, err
	}
	return Response{Version: Version, RequestID: id, OK: true, Payload: raw}, nil
}

func Failure(id uint64, code, message string, retryable bool) Response {
	return Response{Version: Version, RequestID: id, Error: &ProtocolError{Code: code, Message: message, Retryable: retryable}}
}

func DecodePayload[T any](raw json.RawMessage) (T, error) {
	var result T
	if len(raw) == 0 {
		return result, nil
	}
	if err := json.Unmarshal(raw, &result); err != nil {
		return result, fmt.Errorf("decode payload: %w", err)
	}
	return result, nil
}

// ValidateRelativeName accepts the slash-separated manifest namespace. It
// rejects Windows absolute paths, traversal, alternate-data-stream syntax,
// empty components, control characters, and ambiguous dot segments.
func ValidateRelativeName(name string) error {
	if name == "" || len(name) > MaximumNameBytes || !utf8.ValidString(name) {
		return ErrUnsafeName
	}
	if strings.Contains(name, "\\") || strings.HasPrefix(name, "/") || strings.Contains(name, ":") {
		return ErrUnsafeName
	}
	if path.Clean(name) != name {
		return ErrUnsafeName
	}
	for _, part := range strings.Split(name, "/") {
		if part == "" || part == "." || part == ".." || strings.HasSuffix(part, ".") || strings.HasSuffix(part, " ") || strings.ContainsFunc(part, func(r rune) bool { return r < 0x20 || r == 0x7f }) {
			return ErrUnsafeName
		}
	}
	return nil
}

func ValidateOpaqueID(id string) error {
	if id == "" || len(id) > MaximumNameBytes || !utf8.ValidString(id) || strings.ContainsFunc(id, func(r rune) bool { return r < 0x20 || r == 0x7f }) {
		return ErrInvalidRequest
	}
	return nil
}

func NormalizePageSize(size uint32) (uint32, error) {
	if size == 0 {
		return DefaultPageSize, nil
	}
	if size > MaximumPageSize {
		return 0, fmt.Errorf("page size %d exceeds maximum %d", size, MaximumPageSize)
	}
	return size, nil
}
