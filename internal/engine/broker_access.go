package engine

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"os"
	"path"
	"strings"
	"time"

	"github.com/authenticmemory/gami-hash/internal/storageprotocol"
)

// BrokeredOptions are logical references selected and validated by the native
// Windows broker. RootID is opaque to the Go worker. OutputName is a single
// filename within the separately selected destination folder.
type BrokeredOptions struct {
	RootID               string
	SourceIdentity       string
	OutputName           string
	Workers              int
	ContainmentValidated bool
	Resume               bool
}

// RunBrokeredFresh runs the production engine against picker-granted storage
// and explicitly ignores any checkpoint. Use RunBrokered with Resume set when
// the caller has selected the resume path.
func RunBrokeredFresh(ctx context.Context, opts BrokeredOptions, client *storageprotocol.Client, progressFn func(Progress)) (Result, error) {
	opts.Resume = false
	return RunBrokered(ctx, opts, client, progressFn)
}

func RunBrokered(ctx context.Context, opts BrokeredOptions, client *storageprotocol.Client, progressFn func(Progress)) (Result, error) {
	if client == nil {
		return Result{}, errors.New("storage broker is unavailable")
	}
	if !opts.ContainmentValidated {
		return Result{}, errors.New("storage broker did not validate source and destination containment")
	}
	if err := storageprotocol.ValidateOpaqueID(opts.RootID); err != nil {
		return Result{}, errors.New("invalid broker source reference")
	}
	if err := storageprotocol.ValidateOpaqueID(opts.SourceIdentity); err != nil {
		return Result{}, errors.New("invalid broker source identity")
	}
	if err := storageprotocol.ValidateRelativeName(opts.OutputName); err != nil || strings.Contains(opts.OutputName, "/") || !strings.EqualFold(path.Ext(opts.OutputName), ".csv") {
		return Result{}, errors.New("invalid broker output filename")
	}
	if opts.Workers == 0 {
		opts.Workers = DefaultWorkers
	}
	if opts.Workers < 1 || opts.Workers > MaxWorkers {
		return Result{}, fmt.Errorf("workers must be between 1 and %d", MaxWorkers)
	}
	source := &brokerSourceAccess{client: client}
	dest := &brokerDestinationAccess{client: client}
	engineOpts := Options{Root: opts.SourceIdentity, Output: opts.OutputName, Workers: opts.Workers, Fresh: !opts.Resume}
	var prepared *preparedResume
	if opts.Resume {
		var err error
		prepared, err = prepareBrokeredResume(dest, opts.SourceIdentity, opts.OutputName)
		if err != nil { return Result{}, err }
	}
	return runWithAccess(ctx, engineOpts, progressFn, source, dest, opts.RootID, true, prepared)
}

func prepareBrokeredResume(dest *brokerDestinationAccess, sourceIdentity, output string) (*preparedResume, error) {
	cpFile, err := dest.OpenExisting(CheckpointPath(output), false)
	if err != nil { return nil, fmt.Errorf("cannot open brokered checkpoint: %w", err) }
	data, readErr := io.ReadAll(io.LimitReader(cpFile, storageprotocol.MaxFrameSize+1))
	closeErr := cpFile.Close()
	if readErr != nil { return nil, fmt.Errorf("cannot read brokered checkpoint: %w", readErr) }
	if closeErr != nil { return nil, closeErr }
	if len(data) > storageprotocol.MaxFrameSize { return nil, errors.New("brokered checkpoint is too large") }
	var cp checkpoint
	if err := json.Unmarshal(data, &cp); err != nil || cp.Format != manifestFormatVersion || cp.Root != sourceIdentity || cp.Output != output || cp.CSVHeader != strings.Join(csvHeader, ",") {
		return nil, errors.New("brokered checkpoint is corrupt or belongs to another source")
	}
	manifest := output
	if cp.WorkPath != "" {
		if !validBrokerWorkName(cp.WorkPath) { return nil, errors.New("brokered checkpoint contains an unsafe work name") }
		manifest = cp.WorkPath
	}
	writable, err := dest.OpenExisting(manifest, true)
	if err != nil { return nil, fmt.Errorf("cannot open brokered resume manifest: %w", err) }
	if err = validateRepairableCSVFile(writable); err == nil { err = repairTruncatedTailFile(writable) }
	if close := writable.Close(); err == nil { err = close }
	if err != nil { return nil, fmt.Errorf("cannot repair brokered resume manifest: %w", err) }
	readable, err := dest.OpenExisting(manifest, false)
	if err != nil { return nil, err }
	rows, err := countValidRowsFile(readable)
	if err != nil { readable.Close(); return nil, err }
	cursor, err := openCompletedCursorFile(readable)
	if err != nil { return nil, err }
	return &preparedResume{state: ResumeState{Resumable:true, Root:cp.Root, RowCount:rows, manifestPath:manifest}, cursor:cursor}, nil
}

func validBrokerWorkName(name string) bool {
	return strings.HasPrefix(name, ".gami-work-") && storageprotocol.ValidateRelativeName(name) == nil && !strings.Contains(name, "/")
}

type brokerFileInfo struct {
	name, identity string
	size           int64
	modified       time.Time
	directory      bool
	attributes     uint32
	reparseTag     uint32
}

func (i brokerFileInfo) Name() string { return i.name }
func (i brokerFileInfo) Size() int64  { return i.size }
func (i brokerFileInfo) Mode() fs.FileMode {
	if i.directory {
		return fs.ModeDir | 0o555
	}
	return 0o444
}
func (i brokerFileInfo) ModTime() time.Time { return i.modified }
func (i brokerFileInfo) IsDir() bool        { return i.directory }
func (i brokerFileInfo) Sys() any           { return i.identity }

type brokerSourceEntry struct {
	item storageprotocol.Item
	info brokerFileInfo
}

func (e brokerSourceEntry) Name() string               { return e.item.Name }
func (e brokerSourceEntry) IsDir() bool                { return e.item.Kind == storageprotocol.ItemDirectory }
func (e brokerSourceEntry) Type() fs.FileMode          { return e.info.Mode().Type() }
func (e brokerSourceEntry) Info() (fs.FileInfo, error) { return e.info, nil }
func (e brokerSourceEntry) Ref() string                { return e.item.ID }
func (e brokerSourceEntry) LinkLike() (bool, error) {
	// The native broker supplies raw attributes/tags and fails closed when it
	// cannot establish them. The Go side independently refuses every reparse
	// item until provider-specific safe tags are explicitly supported.
	return e.item.Attributes&uint32(0x400) != 0 || e.item.ReparseTag != 0, nil
}

type brokerSourceDirectory struct {
	client   *storageprotocol.Client
	folderID string
	page     string
	pending  []sourceEntry
	done     bool
}

func (d *brokerSourceDirectory) ReadDir(n int) ([]sourceEntry, error) {
	if n <= 0 {
		n = storageprotocol.DefaultPageSize
	}
	for len(d.pending) < n && !d.done {
		limit := uint32(n - len(d.pending))
		if limit > storageprotocol.MaximumPageSize {
			limit = storageprotocol.MaximumPageSize
		}
		var response storageprotocol.ListResponse
		if err := d.client.Call(storageprotocol.OpList, storageprotocol.ListRequest{FolderID: d.folderID, Page: d.page, Limit: limit}, &response); err != nil {
			return nil, err
		}
		if len(response.Items) == 0 && response.NextPage != "" {
			return nil, errors.New("storage broker returned an empty non-final page")
		}
		for _, item := range response.Items {
			entry, err := makeBrokerEntry(item)
			if err != nil {
				return nil, err
			}
			d.pending = append(d.pending, entry)
		}
		if response.NextPage == "" {
			d.done = true
		} else if response.NextPage == d.page {
			return nil, errors.New("storage broker repeated a page token")
		} else {
			if err := storageprotocol.ValidateOpaqueID(response.NextPage); err != nil {
				return nil, errors.New("storage broker returned an invalid page token")
			}
			d.page = response.NextPage
		}
	}
	if len(d.pending) == 0 && d.done {
		return nil, io.EOF
	}
	count := min(n, len(d.pending))
	result := append([]sourceEntry(nil), d.pending[:count]...)
	d.pending = d.pending[count:]
	return result, nil
}

func (d *brokerSourceDirectory) Close() error { d.done = true; d.pending = nil; return nil }

type brokerSourceAccess struct{ client *storageprotocol.Client }

type brokerReadFile struct {
	file     *os.File
	identity string
	name     string
}

func (f *brokerReadFile) Read(p []byte) (int, error) { return f.file.Read(p) }
func (f *brokerReadFile) Close() error               { return f.file.Close() }
func (f *brokerReadFile) Stat() (fs.FileInfo, error) {
	info, err := f.file.Stat()
	if err != nil {
		return nil, err
	}
	return brokerFileInfo{
		name: f.name, identity: f.identity, size: info.Size(),
		modified: info.ModTime(), directory: info.IsDir(),
	}, nil
}

func (s *brokerSourceAccess) OpenDir(ref string) (sourceDirectory, error) {
	if err := storageprotocol.ValidateOpaqueID(ref); err != nil {
		return nil, err
	}
	return &brokerSourceDirectory{client: s.client, folderID: ref}, nil
}

func (s *brokerSourceAccess) OpenRead(ref string) (readFile, error) {
	if err := storageprotocol.ValidateOpaqueID(ref); err != nil {
		return nil, err
	}
	var response storageprotocol.HandleResponse
	if err := s.client.Call(storageprotocol.OpOpenRead, storageprotocol.ItemRequest{ItemID: ref}, &response); err != nil {
		return nil, err
	}
	if response.Handle == 0 {
		return nil, errors.New("storage broker returned an invalid read handle")
	}
	file := os.NewFile(uintptr(response.Handle), "broker-source")
	if file == nil {
		return nil, errors.New("cannot adopt broker read handle")
	}
	if response.Identity == "" {
		_ = file.Close()
		return nil, errors.New("storage broker returned a read handle without identity")
	}
	return &brokerReadFile{file: file, identity: response.Identity, name: "broker-source"}, nil
}

func (s *brokerSourceAccess) Lstat(ref string) (fs.FileInfo, error) {
	var response storageprotocol.StatResponse
	if err := s.client.Call(storageprotocol.OpStat, storageprotocol.ItemRequest{ItemID: ref}, &response); err != nil {
		return nil, err
	}
	entry, err := makeBrokerEntry(response.Item)
	if err != nil {
		return nil, err
	}
	return entry.Info()
}

func (s *brokerSourceAccess) SameFile(before, current fs.FileInfo) bool {
	a, aok := before.Sys().(string)
	b, bok := current.Sys().(string)
	return aok && bok && a != "" && a == b
}
func (*brokerSourceAccess) IsExcluded(string, string) bool { return false }

func makeBrokerEntry(item storageprotocol.Item) (brokerSourceEntry, error) {
	if err := storageprotocol.ValidateOpaqueID(item.ID); err != nil {
		return brokerSourceEntry{}, errors.New("storage broker returned an invalid item ID")
	}
	if err := storageprotocol.ValidateRelativeName(item.Name); err != nil || strings.Contains(item.Name, "/") {
		return brokerSourceEntry{}, errors.New("storage broker returned an invalid item name")
	}
	if item.Identity == "" {
		return brokerSourceEntry{}, errors.New("storage broker returned an item without stable identity")
	}
	if item.Attributes == 0 {
		return brokerSourceEntry{}, errors.New("storage broker returned an item without file attributes")
	}
	if item.Kind != storageprotocol.ItemFile && item.Kind != storageprotocol.ItemDirectory {
		return brokerSourceEntry{}, errors.New("storage broker returned an unsupported item kind")
	}
	modified, err := time.Parse(time.RFC3339Nano, item.ModifiedUTC)
	if err != nil {
		return brokerSourceEntry{}, errors.New("storage broker returned an invalid modification time")
	}
	return brokerSourceEntry{item: item, info: brokerFileInfo{name: item.Name, identity: item.Identity, size: item.Size, modified: modified, directory: item.Kind == storageprotocol.ItemDirectory, attributes: item.Attributes, reparseTag: item.ReparseTag}}, nil
}

type brokerDestinationAccess struct{ client *storageprotocol.Client }

func brokerSingleLink(response storageprotocol.WorkHandleResponse) bool {
	if response.LinkCount == 1 {
		return true
	}
	return response.LinkCount == 0 && response.VolumeCapabilitiesKnown && !response.HardLinksSupported
}

func (d *brokerDestinationAccess) CreateWork(string) (*os.File, error) { return d.create("manifest") }
func (d *brokerDestinationAccess) OpenExisting(name string, writable bool) (*os.File, error) {
	if err := validateDestinationName(name); err != nil {
		return nil, err
	}
	var response storageprotocol.WorkHandleResponse
	if err := d.client.Call(storageprotocol.OpOpenWork, storageprotocol.WorkRequest{Name: name, Writable: writable}, &response); err != nil {
		return nil, err
	}
	if response.Handle == 0 || response.Identity == "" || !brokerSingleLink(response) {
		if response.Handle != 0 {
			if file := os.NewFile(uintptr(response.Handle), name); file != nil {
				_ = file.Close()
			}
		}
		return nil, errors.New("storage broker returned an unsafe existing destination file")
	}
	file := os.NewFile(uintptr(response.Handle), name)
	if file == nil {
		return nil, errors.New("cannot adopt broker destination handle")
	}
	return file, nil
}
func (d *brokerDestinationAccess) OpenErrorLog(string) (*os.File, error) { return d.create("errors") }
func (d *brokerDestinationAccess) create(kind string) (*os.File, error) {
	var response storageprotocol.WorkHandleResponse
	if err := d.client.Call(storageprotocol.OpCreateWork, storageprotocol.CreateWorkRequest{Kind: kind}, &response); err != nil {
		return nil, err
	}
	if err := storageprotocol.ValidateRelativeName(response.Name); err != nil || strings.Contains(response.Name, "/") ||
		response.Handle == 0 || response.Identity == "" || !brokerSingleLink(response) {
		if response.Handle != 0 {
			if file := os.NewFile(uintptr(response.Handle), response.Name); file != nil {
				_ = file.Close()
			}
		}
		return nil, fmt.Errorf("storage broker returned invalid work file (name_valid=%t handle=%t identity=%t link_count=%d capabilities_known=%t hard_links_supported=%t)",
			storageprotocol.ValidateRelativeName(response.Name) == nil && !strings.Contains(response.Name, "/"),
			response.Handle != 0, response.Identity != "", response.LinkCount,
			response.VolumeCapabilitiesKnown, response.HardLinksSupported)
	}
	file := os.NewFile(uintptr(response.Handle), response.Name)
	if file == nil {
		return nil, errors.New("cannot adopt broker work handle")
	}
	return file, nil
}
func (d *brokerDestinationAccess) WriteSidecar(name string, data []byte) error {
	if err := validateDestinationName(name); err != nil {
		return err
	}
	file, err := d.create("sidecar")
	if err != nil {
		return err
	}
	work := file.Name()
	if _, err = file.Write(data); err == nil {
		err = file.Sync()
	}
	if closeErr := file.Close(); err == nil {
		err = closeErr
	}
	if err != nil {
		_ = d.Remove(work)
		return err
	}
	return d.Publish(work, name)
}
func (d *brokerDestinationAccess) Publish(work, final string) error {
	if err := validateDestinationName(work); err != nil {
		return err
	}
	if err := validateDestinationName(final); err != nil {
		return err
	}
	return d.client.Call(storageprotocol.OpPublishWork, storageprotocol.PublishWorkRequest{Name: work, DestinationName: final}, nil)
}
func (d *brokerDestinationAccess) Remove(name string) error {
	if err := validateDestinationName(name); err != nil {
		return err
	}
	return d.client.Call(storageprotocol.OpRemoveWork, storageprotocol.WorkRequest{Name: name}, nil)
}
func validateDestinationName(name string) error {
	if err := storageprotocol.ValidateRelativeName(name); err != nil || strings.Contains(name, "/") {
		return errors.New("invalid destination filename")
	}
	return nil
}
