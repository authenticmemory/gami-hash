//go:build windows

package engine

import (
	"context"
	"encoding/csv"
	"encoding/json"
	"errors"
	"io"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/authenticmemory/gami-hash/internal/storageprotocol"
	"golang.org/x/sys/windows"
)

func TestRunBrokeredFreshUsesOpaqueIDsAndPublishesManifest(t *testing.T) {
	sourceDir := t.TempDir()
	destinationDir := t.TempDir()
	files := map[string]string{"id-a": "alpha", "id-b": "nested content"}
	paths := map[string]string{}
	items := make([]storageprotocol.Item, 0, len(files))
	for id, content := range files {
		name := map[string]string{"id-a": "a.txt", "id-b": "b.txt"}[id]
		filePath := filepath.Join(sourceDir, name)
		if err := os.WriteFile(filePath, []byte(content), 0o644); err != nil {
			t.Fatal(err)
		}
		info, err := os.Stat(filePath)
		if err != nil {
			t.Fatal(err)
		}
		paths[id] = filePath
		items = append(items, storageprotocol.Item{ID: id, Name: name, Kind: storageprotocol.ItemFile, Size: info.Size(), ModifiedUTC: info.ModTime().UTC().Format(time.RFC3339Nano), Identity: id, Attributes: 32})
	}
	// The broker, not the worker, owns deterministic enumeration order.
	if items[0].Name > items[1].Name {
		items[0], items[1] = items[1], items[0]
	}

	workerReads, brokerWrites := io.Pipe()
	brokerReads, workerWrites := io.Pipe()
	client := storageprotocol.NewClient(storageprotocol.NewCodec(workerReads, workerWrites))
	server := storageprotocol.NewCodec(brokerReads, brokerWrites)
	done := make(chan error, 1)
	go func() { done <- serveTestBroker(server, items, paths, destinationDir) }()

	result, err := RunBrokeredFresh(context.Background(), BrokeredOptions{RootID: "root", SourceIdentity: "source-identity", OutputName: "checksums.csv", Workers: 1, ContainmentValidated: true}, client, nil)
	_ = workerWrites.Close()
	_ = workerReads.Close()
	if err != nil {
		t.Fatal(err)
	}
	if err := <-done; err != nil {
		t.Fatal(err)
	}
	if result.FilesHashed != 2 || result.FilesFailed != 0 {
		t.Fatalf("unexpected result: %+v", result)
	}

	f, err := os.Open(filepath.Join(destinationDir, "checksums.csv"))
	if err != nil {
		t.Fatal(err)
	}
	defer f.Close()
	reader := csv.NewReader(f)
	rows, err := reader.ReadAll()
	if err != nil {
		t.Fatal(err)
	}
	if len(rows) != 3 || rows[1][0] != "a.txt" || rows[2][0] != "b.txt" {
		t.Fatalf("unexpected manifest rows: %#v", rows)
	}
	if _, err := os.Stat(filepath.Join(destinationDir, "checksums.csv.part.json")); !errors.Is(err, os.ErrNotExist) {
		t.Fatalf("checkpoint remained: %v", err)
	}
}

func serveTestBroker(codec *storageprotocol.Codec, items []storageprotocol.Item, paths map[string]string, destination string) error {
	work := map[string]string{}
	serial := 0
	for {
		request, err := codec.ReadRequest()
		if errors.Is(err, io.EOF) || errors.Is(err, io.ErrClosedPipe) {
			return nil
		}
		if err != nil {
			return err
		}
		var payload any = struct{}{}
		switch request.Operation {
		case storageprotocol.OpList:
			query, err := storageprotocol.DecodePayload[storageprotocol.ListRequest](request.Payload)
			if err != nil {
				return err
			}
			if query.FolderID != "root" {
				return errors.New("unexpected folder ID")
			}
			payload = storageprotocol.ListResponse{Items: items}
		case storageprotocol.OpStat:
			query, err := storageprotocol.DecodePayload[storageprotocol.ItemRequest](request.Payload)
			if err != nil {
				return err
			}
			item, ok := findTestItem(items, query.ItemID)
			if !ok {
				return errors.New("unknown item")
			}
			info, err := os.Stat(paths[query.ItemID])
			if err != nil {
				return err
			}
			item.Size, item.ModifiedUTC = info.Size(), info.ModTime().UTC().Format(time.RFC3339Nano)
			payload = storageprotocol.StatResponse{Item: item}
		case storageprotocol.OpOpenRead:
			query, err := storageprotocol.DecodePayload[storageprotocol.ItemRequest](request.Payload)
			if err != nil {
				return err
			}
			item, ok := findTestItem(items, query.ItemID)
			if !ok {
				return errors.New("unknown item")
			}
			file, err := os.Open(paths[query.ItemID])
			if err != nil {
				return err
			}
			handle, err := duplicateTestHandle(file)
			_ = file.Close()
			if err != nil {
				return err
			}
			payload = storageprotocol.HandleResponse{Handle: uint64(handle), Identity: item.Identity, Size: item.Size, ModifiedUTC: item.ModifiedUTC}
		case storageprotocol.OpCreateWork:
			query, err := storageprotocol.DecodePayload[storageprotocol.CreateWorkRequest](request.Payload)
			if err != nil { return err }
			serial++
			name := ".gami-work-" + strconv.Itoa(serial)
			if query.Kind == "errors" { name = "checksums_errors.log" }
			filePath := filepath.Join(destination, name)
			file, err := os.OpenFile(filePath, os.O_CREATE|os.O_EXCL|os.O_RDWR, 0o644)
			if err != nil {
				return err
			}
			handle, err := duplicateTestHandle(file)
			_ = file.Close()
			if err != nil {
				return err
			}
			if query.Kind != "errors" { work[name] = filePath }
			payload = storageprotocol.WorkHandleResponse{Name: name, Handle: uint64(handle), Identity: "work-" + strconv.Itoa(serial), LinkCount: 1}
		case storageprotocol.OpOpenWork:
			query, err := storageprotocol.DecodePayload[storageprotocol.WorkRequest](request.Payload)
			if err != nil { return err }
			flags := os.O_RDONLY
			if query.Writable { flags = os.O_RDWR }
			file, err := os.OpenFile(filepath.Join(destination, query.Name), flags, 0)
			if err != nil { return err }
			handle, err := duplicateTestHandle(file)
			_ = file.Close()
			if err != nil { return err }
			payload = storageprotocol.WorkHandleResponse{Name: query.Name, Handle: uint64(handle), Identity: "existing-" + query.Name, LinkCount: 1}
		case storageprotocol.OpPublishWork:
			query, err := storageprotocol.DecodePayload[storageprotocol.PublishWorkRequest](request.Payload)
			if err != nil {
				return err
			}
			from, ok := work[query.Name]
			if !ok {
				return errors.New("unknown work file")
			}
			to := filepath.Join(destination, query.DestinationName)
			_ = os.Remove(to)
			if err := os.Rename(from, to); err != nil {
				return err
			}
			delete(work, query.Name)
		case storageprotocol.OpRemoveWork:
			query, err := storageprotocol.DecodePayload[storageprotocol.WorkRequest](request.Payload)
			if err != nil {
				return err
			}
			if filePath, ok := work[query.Name]; ok {
				_ = os.Remove(filePath)
				delete(work, query.Name)
			} else {
				_ = os.Remove(filepath.Join(destination, query.Name))
			}
		default:
			return errors.New("unexpected operation " + string(request.Operation))
		}
		response, err := storageprotocol.Success(request.RequestID, payload)
		if err != nil {
			return err
		}
		if err := codec.WriteResponse(response); err != nil {
			return err
		}
	}
}

func TestRunBrokeredResumeUsesCheckpointAndExistingManifestHandles(t *testing.T) {
	sourceDir, destinationDir := t.TempDir(), t.TempDir()
	paths := map[string]string{}
	items := []storageprotocol.Item{}
	for i, content := range []string{"alpha", "beta"} {
		id, name := "id-"+strconv.Itoa(i), string(rune('a'+i))+".txt"
		p := filepath.Join(sourceDir, name)
		if err := os.WriteFile(p, []byte(content), 0o644); err != nil { t.Fatal(err) }
		info, _ := os.Stat(p)
		paths[id] = p
		items = append(items, storageprotocol.Item{ID:id, Name:name, Kind:storageprotocol.ItemFile, Size:info.Size(), ModifiedUTC:info.ModTime().UTC().Format(time.RFC3339Nano), Identity:id, Attributes:32})
	}
	manifest := filepath.Join(destinationDir, "checksums.csv")
	f, err := os.Create(manifest)
	if err != nil { t.Fatal(err) }
	_, _ = f.Write(utf8BOM)
	w := csv.NewWriter(f); w.UseCRLF = true
	_ = w.Write(csvHeader)
	info, _ := os.Stat(paths["id-0"])
	_ = w.Write(ManifestFields("a.txt", info.Size(), "8ed3f6ad685b959ead7022518e1af76cd816f8e8ec7ccdda1ed4018e8f2223f8", info.ModTime()))
	w.Flush(); _ = f.Close()
	cp := checkpoint{Format:manifestFormatVersion, Version:Version, Root:"source-identity", Output:"checksums.csv", CSVHeader:strings.Join(csvHeader, ",")}
	data, _ := json.Marshal(cp)
	if err := os.WriteFile(filepath.Join(destinationDir, "checksums.csv.part.json"), data, 0o644); err != nil { t.Fatal(err) }

	workerReads, brokerWrites := io.Pipe(); brokerReads, workerWrites := io.Pipe()
	client := storageprotocol.NewClient(storageprotocol.NewCodec(workerReads, workerWrites))
	done := make(chan error, 1)
	go func(){ done <- serveTestBroker(storageprotocol.NewCodec(brokerReads, brokerWrites), items, paths, destinationDir) }()
	result, err := RunBrokered(context.Background(), BrokeredOptions{RootID:"root", SourceIdentity:"source-identity", OutputName:"checksums.csv", Workers:1, ContainmentValidated:true, Resume:true}, client, nil)
	_ = workerWrites.Close(); _ = workerReads.Close()
	if err != nil { t.Fatal(err) }
	if err := <-done; err != nil { t.Fatal(err) }
	if result.FilesResumed != 1 || result.FilesHashed != 1 { t.Fatalf("unexpected resume result: %+v", result) }
	if _, err := os.Stat(filepath.Join(destinationDir, "checksums.csv.part.json")); !errors.Is(err, os.ErrNotExist) { t.Fatalf("checkpoint remained: %v", err) }
}

func TestRunBrokeredResumeRehashesChangedFile(t *testing.T) {
	sourceDir, destinationDir := t.TempDir(), t.TempDir()
	filePath := filepath.Join(sourceDir, "a.txt")
	if err := os.WriteFile(filePath, []byte("alpha"), 0o644); err != nil { t.Fatal(err) }
	oldInfo, err := os.Stat(filePath); if err != nil { t.Fatal(err) }
	writeBrokeredResumeFixture(t, destinationDir, [][]string{ManifestFields("a.txt", oldInfo.Size(), "8ed3f6ad685b959ead7022518e1af76cd816f8e8ec7ccdda1ed4018e8f2223f8", oldInfo.ModTime())})
	changedTime := oldInfo.ModTime().Add(2 * time.Second)
	if err := os.WriteFile(filePath, []byte("changed"), 0o644); err != nil { t.Fatal(err) }
	if err := os.Chtimes(filePath, changedTime, changedTime); err != nil { t.Fatal(err) }
	info, err := os.Stat(filePath); if err != nil { t.Fatal(err) }
	items := []storageprotocol.Item{{ID:"id-a", Name:"a.txt", Kind:storageprotocol.ItemFile, Size:info.Size(), ModifiedUTC:info.ModTime().UTC().Format(time.RFC3339Nano), Identity:"id-a", Attributes:32}}
	result := runBrokeredResumeFixture(t, items, map[string]string{"id-a":filePath}, destinationDir)
	if result.FilesResumed != 0 || result.FilesHashed != 1 { t.Fatalf("unexpected changed-file result: %+v", result) }
	rows := readRows(t, filepath.Join(destinationDir, "checksums.csv"))
	if len(rows) != 1 || rows[0][2] != "sha256:d67e2e944994496c8d8ec76eed0cf9f09679448d584b532bebf941852a37f5ed" {
		t.Fatalf("changed file was not rehashed: %#v", rows)
	}
}

func TestRunBrokeredResumeDropsMissingFile(t *testing.T) {
	sourceDir, destinationDir := t.TempDir(), t.TempDir()
	filePath := filepath.Join(sourceDir, "a.txt")
	if err := os.WriteFile(filePath, []byte("alpha"), 0o644); err != nil { t.Fatal(err) }
	info, err := os.Stat(filePath); if err != nil { t.Fatal(err) }
	writeBrokeredResumeFixture(t, destinationDir, [][]string{
		ManifestFields("a.txt", info.Size(), "8ed3f6ad685b959ead7022518e1af76cd816f8e8ec7ccdda1ed4018e8f2223f8", info.ModTime()),
		ManifestFields("missing.txt", 7, strings.Repeat("0", 64), info.ModTime()),
	})
	items := []storageprotocol.Item{{ID:"id-a", Name:"a.txt", Kind:storageprotocol.ItemFile, Size:info.Size(), ModifiedUTC:info.ModTime().UTC().Format(time.RFC3339Nano), Identity:"id-a", Attributes:32}}
	result := runBrokeredResumeFixture(t, items, map[string]string{"id-a":filePath}, destinationDir)
	if result.FilesResumed != 1 || result.FilesHashed != 0 { t.Fatalf("unexpected missing-file result: %+v", result) }
	rows := readRows(t, filepath.Join(destinationDir, "checksums.csv"))
	if len(rows) != 1 || rows[0][0] != "a.txt" { t.Fatalf("missing row was retained: %#v", rows) }
}

func writeBrokeredResumeFixture(t *testing.T, destination string, rows [][]string) {
	t.Helper()
	file, err := os.Create(filepath.Join(destination, "checksums.csv")); if err != nil { t.Fatal(err) }
	if _, err = file.Write(utf8BOM); err != nil { t.Fatal(err) }
	writer := csv.NewWriter(file); writer.UseCRLF = true
	if err = writer.Write(csvHeader); err != nil { t.Fatal(err) }
	if err = writer.WriteAll(rows); err != nil { t.Fatal(err) }
	writer.Flush(); if err = writer.Error(); err != nil { t.Fatal(err) }
	if err = file.Close(); err != nil { t.Fatal(err) }
	cp := checkpoint{Format:manifestFormatVersion, Version:Version, Root:"source-identity", Output:"checksums.csv", CSVHeader:strings.Join(csvHeader, ",")}
	data, err := json.Marshal(cp); if err != nil { t.Fatal(err) }
	if err = os.WriteFile(filepath.Join(destination, "checksums.csv.part.json"), data, 0o644); err != nil { t.Fatal(err) }
}

func runBrokeredResumeFixture(t *testing.T, items []storageprotocol.Item, paths map[string]string, destination string) Result {
	t.Helper()
	workerReads, brokerWrites := io.Pipe(); brokerReads, workerWrites := io.Pipe()
	client := storageprotocol.NewClient(storageprotocol.NewCodec(workerReads, workerWrites))
	done := make(chan error, 1)
	go func(){ done <- serveTestBroker(storageprotocol.NewCodec(brokerReads, brokerWrites), items, paths, destination) }()
	result, err := RunBrokered(context.Background(), BrokeredOptions{RootID:"root", SourceIdentity:"source-identity", OutputName:"checksums.csv", Workers:1, ContainmentValidated:true, Resume:true}, client, nil)
	_ = workerWrites.Close(); _ = workerReads.Close()
	if err != nil { t.Fatal(err) }
	if err = <-done; err != nil { t.Fatal(err) }
	return result
}

func findTestItem(items []storageprotocol.Item, id string) (storageprotocol.Item, bool) {
	for _, item := range items {
		if item.ID == id {
			return item, true
		}
	}
	return storageprotocol.Item{}, false
}

func duplicateTestHandle(file *os.File) (windows.Handle, error) {
	var duplicate windows.Handle
	process := windows.CurrentProcess()
	err := windows.DuplicateHandle(process, windows.Handle(file.Fd()), process, &duplicate, 0, false, windows.DUPLICATE_SAME_ACCESS)
	return duplicate, err
}

func TestRunBrokeredFreshRequiresContainmentValidation(t *testing.T) {
	_, err := RunBrokeredFresh(context.Background(), BrokeredOptions{RootID: "root", OutputName: "checksums.csv"}, &storageprotocol.Client{}, nil)
	if err == nil || !strings.Contains(err.Error(), "containment") {
		t.Fatalf("got %v", err)
	}
}

func TestBrokerDestinationRejectsHardLinkedWorkHandle(t *testing.T) {
	temp, err := os.CreateTemp(t.TempDir(), "unsafe-work")
	if err != nil { t.Fatal(err) }
	handle, err := duplicateTestHandle(temp); _ = temp.Close()
	if err != nil { t.Fatal(err) }
	workerReads, brokerWrites := io.Pipe()
	brokerReads, workerWrites := io.Pipe()
	client := storageprotocol.NewClient(storageprotocol.NewCodec(workerReads, workerWrites))
	server := storageprotocol.NewCodec(brokerReads, brokerWrites)
	done := make(chan error, 1)
	go func() {
		req, err := server.ReadRequest(); if err != nil { done <- err; return }
		response, _ := storageprotocol.Success(req.RequestID, storageprotocol.WorkHandleResponse{Name:".gami-work-unsafe", Handle:uint64(handle), Identity:"aliased", LinkCount:2})
		done <- server.WriteResponse(response)
	}()
	_, err = (&brokerDestinationAccess{client:client}).CreateWork("checksums.csv")
	_ = workerWrites.Close(); _ = workerReads.Close()
	if err == nil || !strings.Contains(err.Error(), "invalid work file") { t.Fatalf("got %v", err) }
	if serverErr := <-done; serverErr != nil { t.Fatal(serverErr) }
}

func TestBrokerSingleLinkAcceptsUnknownCountOnlyWhenVolumeCannotHardLink(t *testing.T) {
	tests := []struct{
		name string
		response storageprotocol.WorkHandleResponse
		want bool
	}{
		{"ordinary single link", storageprotocol.WorkHandleResponse{LinkCount:1}, true},
		{"provider without hard links", storageprotocol.WorkHandleResponse{LinkCount:0, VolumeCapabilitiesKnown:true}, true},
		{"unknown volume capabilities", storageprotocol.WorkHandleResponse{LinkCount:0}, false},
		{"hard-link capable volume", storageprotocol.WorkHandleResponse{LinkCount:0, VolumeCapabilitiesKnown:true, HardLinksSupported:true}, false},
		{"multiple links", storageprotocol.WorkHandleResponse{LinkCount:2, VolumeCapabilitiesKnown:true, HardLinksSupported:true}, false},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			if got := brokerSingleLink(test.response); got != test.want { t.Fatalf("got %v want %v", got, test.want) }
		})
	}
}

func TestPrepareBrokeredResumeRejectsDifferentSourceIdentity(t *testing.T) {
	destination := t.TempDir()
	cp := checkpoint{Format:manifestFormatVersion, Root:"other-source", Output:"checksums.csv", CSVHeader:strings.Join(csvHeader, ",")}
	data, _ := json.Marshal(cp)
	if err := os.WriteFile(filepath.Join(destination,"checksums.csv.part.json"), data, 0o644); err != nil { t.Fatal(err) }
	if err := os.WriteFile(filepath.Join(destination,"checksums.csv"), append(append([]byte{},utf8BOM...), []byte(strings.Join(csvHeader,",")+"\r\n")...), 0o644); err != nil { t.Fatal(err) }
	workerReads, brokerWrites := io.Pipe(); brokerReads, workerWrites := io.Pipe()
	client := storageprotocol.NewClient(storageprotocol.NewCodec(workerReads, workerWrites)); server := storageprotocol.NewCodec(brokerReads, brokerWrites)
	done := make(chan error,1)
	go func(){ done <- serveTestBroker(server,nil,map[string]string{},destination) }()
	_, err := prepareBrokeredResume(&brokerDestinationAccess{client:client}, "expected-source", "checksums.csv")
	_ = workerWrites.Close(); _ = workerReads.Close()
	if err == nil || !strings.Contains(err.Error(), "another source") { t.Fatalf("got %v",err) }
	if serverErr:=<-done; serverErr!=nil { t.Fatal(serverErr) }
}
