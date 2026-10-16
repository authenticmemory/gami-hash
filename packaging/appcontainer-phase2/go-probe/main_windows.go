//go:build windows

// A disposable contained-process probe for Windows' *FromApp file APIs.
// It is not the GAMI Hash product or a replacement hashing engine.
package main

import (
	"bufio"
	"context"
	"crypto/sha256"
	"encoding/csv"
	"encoding/hex"
	"flag"
	"fmt"
	"io"
	"os"
	"path"
	"path/filepath"
	"strconv"
	"strings"
	"unicode/utf8"
	"unsafe"

	"github.com/authenticmemory/gami-hash/internal/engine"
	"golang.org/x/sys/windows"
)

var (
	fromApp                  = windows.NewLazySystemDLL("kernelbase.dll")
	createFileFromApp        = fromApp.NewProc("CreateFileFromAppW")
	getFileAttributesFromApp = fromApp.NewProc("GetFileAttributesExFromAppW")
	deleteFileFromApp        = fromApp.NewProc("DeleteFileFromAppW")
)

func openFromApp(path string, access, creation, flags uint32) (*os.File, error) {
	wide, err := windows.UTF16PtrFromString(path)
	if err != nil {
		return nil, err
	}
	handle, _, callErr := createFileFromApp.Call(
		uintptr(unsafe.Pointer(wide)), uintptr(access),
		uintptr(windows.FILE_SHARE_READ|windows.FILE_SHARE_WRITE|windows.FILE_SHARE_DELETE),
		0, uintptr(creation), uintptr(flags), 0,
	)
	if windows.Handle(handle) == windows.InvalidHandle {
		return nil, fmt.Errorf("CreateFileFromAppW(%q): %w", path, callErr)
	}
	return os.NewFile(handle, path), nil
}

func attributesFromApp(path string) error {
	wide, err := windows.UTF16PtrFromString(path)
	if err != nil {
		return err
	}
	var attributes [36]byte // WIN32_FILE_ATTRIBUTE_DATA on Windows x64.
	result, _, callErr := getFileAttributesFromApp.Call(
		uintptr(unsafe.Pointer(wide)), uintptr(0), uintptr(unsafe.Pointer(&attributes[0])))
	if result == 0 {
		return fmt.Errorf("GetFileAttributesExFromAppW(%q): %w", path, callErr)
	}
	return nil
}

func removeFromApp(path string) error {
	wide, err := windows.UTF16PtrFromString(path)
	if err != nil {
		return err
	}
	result, _, callErr := deleteFileFromApp.Call(uintptr(unsafe.Pointer(wide)))
	if result == 0 {
		return fmt.Errorf("DeleteFileFromAppW(%q): %w", path, callErr)
	}
	return nil
}

func run(root, output string) error {
	if err := attributesFromApp(root); err != nil {
		return err
	}
	folder, err := openFromApp(root, windows.GENERIC_READ, windows.OPEN_EXISTING, windows.FILE_FLAG_BACKUP_SEMANTICS)
	if err != nil {
		return err
	}
	defer folder.Close()
	entries, err := folder.ReadDir(-1)
	if err != nil {
		return fmt.Errorf("folder.ReadDir: %w", err)
	}
	fmt.Printf("FromApp Go root entries=%d\n", len(entries))
	for _, entry := range entries {
		if !entry.Type().IsRegular() {
			continue
		}
		path := filepath.Join(root, entry.Name())
		file, err := openFromApp(path, windows.GENERIC_READ, windows.OPEN_EXISTING, windows.FILE_ATTRIBUTE_NORMAL)
		if err != nil {
			return err
		}
		digest := sha256.New()
		count, copyErr := io.CopyBuffer(digest, file, make([]byte, 1<<20))
		stat, statErr := file.Stat()
		closeErr := file.Close()
		if copyErr != nil {
			return copyErr
		}
		if statErr != nil {
			return statErr
		}
		if closeErr != nil {
			return closeErr
		}
		fmt.Printf("FromApp Go file=%q bytes=%d statSize=%d sha256=%s\n", entry.Name(), count, stat.Size(), hex.EncodeToString(digest.Sum(nil)))
		break
	}
	if output == "" {
		return nil
	}
	path := filepath.Join(output, "phase2-go-fromapp-test.tmp")
	out, err := openFromApp(path, windows.GENERIC_WRITE, windows.CREATE_NEW, windows.FILE_ATTRIBUTE_NORMAL)
	if err != nil {
		return err
	}
	_, writeErr := out.Write([]byte{'x'})
	closeErr := out.Close()
	if writeErr != nil {
		return writeErr
	}
	if closeErr != nil {
		return closeErr
	}
	if err := removeFromApp(path); err != nil {
		return err
	}
	fmt.Println("FromApp Go output create/write/remove=ok")
	return nil
}

func inheritedHandleProbe(sourceText, outputText string) error {
	sourceValue, err := strconv.ParseUint(sourceText, 10, 64)
	if err != nil || sourceValue == 0 {
		return fmt.Errorf("invalid inherited source handle %q", sourceText)
	}
	outputValue, err := strconv.ParseUint(outputText, 10, 64)
	if err != nil || outputValue == 0 {
		return fmt.Errorf("invalid inherited output handle %q", outputText)
	}
	source := os.NewFile(uintptr(sourceValue), "brokered-source")
	if source == nil {
		return fmt.Errorf("source handle could not become an os.File")
	}
	defer source.Close()
	digest := sha256.New()
	n, err := io.CopyBuffer(digest, source, make([]byte, 1<<20))
	if err != nil {
		return fmt.Errorf("inherited source read: %w", err)
	}
	info, err := source.Stat()
	if err != nil {
		return fmt.Errorf("inherited source stat: %w", err)
	}
	fmt.Printf("Inherited source bytes=%d statSize=%d sha256=%s\n", n, info.Size(), hex.EncodeToString(digest.Sum(nil)))
	output := os.NewFile(uintptr(outputValue), "brokered-output")
	if output == nil {
		return fmt.Errorf("output handle could not become an os.File")
	}
	_, writeErr := output.Write([]byte{'x'})
	closeErr := output.Close()
	if writeErr != nil {
		return fmt.Errorf("inherited output write: %w", writeErr)
	}
	if closeErr != nil {
		return fmt.Errorf("inherited output close: %w", closeErr)
	}
	fmt.Println("Inherited output write=ok")
	return nil
}

// A manifest name is display data supplied by the storage broker, never an
// authority to open a path. Reject path syntax that could later be mistaken
// for an absolute path, traversal, or an NTFS alternate data stream.
func validateManifestRelativeName(rel string) error {
	if rel == "" || !utf8.ValidString(rel) || strings.HasPrefix(rel, "/") ||
		strings.ContainsAny(rel, "\\:\x00\r\n") || path.Clean(rel) != rel {
		return fmt.Errorf("unsafe relative name %q", rel)
	}
	for _, part := range strings.Split(rel, "/") {
		if part == "" || part == "." || part == ".." || strings.HasSuffix(part, ".") || strings.HasSuffix(part, " ") {
			return fmt.Errorf("unsafe relative name %q", rel)
		}
	}
	return nil
}

// manifestProbe is a disposable, sequential wire-protocol check. The native
// broker supplies handles and relative names; the Go child never opens picked
// paths. It deliberately has no resume or provider-identity logic yet.
func manifestProbe(input io.Reader) error {
	scanner := bufio.NewScanner(input)
	scanner.Buffer(make([]byte, 4096), 1<<20)
	if !scanner.Scan() {
		return fmt.Errorf("missing output-handle frame: %w", scanner.Err())
	}
	start := strings.Fields(scanner.Text())
	if len(start) != 3 || start[0] != "GAMI-MANIFEST-1" || start[1] != "OUT" {
		return fmt.Errorf("invalid manifest protocol header")
	}
	outputValue, err := strconv.ParseUint(start[2], 10, 64)
	if err != nil || outputValue == 0 {
		return fmt.Errorf("invalid output handle")
	}
	output := os.NewFile(uintptr(outputValue), "brokered-manifest-output")
	if output == nil {
		return fmt.Errorf("output handle could not become an os.File")
	}
	defer output.Close()
	if _, err := output.Write([]byte{0xef, 0xbb, 0xbf}); err != nil {
		return err
	}
	writer := csv.NewWriter(output)
	writer.UseCRLF = true
	if err := writer.Write(engine.ManifestHeader()); err != nil {
		return err
	}
	if _, err := fmt.Fprintln(os.Stdout, "READY"); err != nil {
		return err
	}
	files := 0
	var totalBytes int64
	for scanner.Scan() {
		fields := strings.Fields(scanner.Text())
		if len(fields) == 1 && fields[0] == "END" {
			writer.Flush()
			if err := writer.Error(); err != nil {
				return err
			}
			if err := output.Sync(); err != nil {
				return err
			}
			if _, err := fmt.Fprintf(os.Stdout, "DONE %d %d\n", files, totalBytes); err != nil {
				return err
			}
			return nil
		}
		if len(fields) != 3 || fields[0] != "FILE" {
			return fmt.Errorf("invalid file frame")
		}
		handleValue, err := strconv.ParseUint(fields[1], 10, 64)
		if err != nil || handleValue == 0 {
			return fmt.Errorf("invalid source handle")
		}
		pathBytes, err := hex.DecodeString(fields[2])
		if err != nil || len(pathBytes) == 0 || !utf8.Valid(pathBytes) {
			return fmt.Errorf("invalid relative name")
		}
		rel := string(pathBytes)
		if err := validateManifestRelativeName(rel); err != nil {
			return err
		}
		file := os.NewFile(uintptr(handleValue), "brokered-source")
		if file == nil {
			return fmt.Errorf("source handle could not become an os.File")
		}
		before, err := file.Stat()
		if err != nil {
			file.Close()
			return err
		}
		if !before.Mode().IsRegular() {
			file.Close()
			return fmt.Errorf("non-regular source %q", rel)
		}
		digest, n, readErr := engine.HashReader(context.Background(), file)
		after, statErr := file.Stat()
		closeErr := file.Close()
		if readErr != nil {
			return fmt.Errorf("read %q: %w", rel, readErr)
		}
		if statErr != nil {
			return statErr
		}
		if closeErr != nil {
			return closeErr
		}
		if before.Size() != after.Size() || n != after.Size() || !before.ModTime().Equal(after.ModTime()) {
			return fmt.Errorf("source changed while hashing: %q", rel)
		}
		if err := writer.Write(engine.ManifestFields(engine.EncodeManifestRelativePath(rel), n, digest, after.ModTime())); err != nil {
			return err
		}
		files++
		totalBytes += n
		if _, err := fmt.Fprintf(os.Stdout, "OK %d\n", files); err != nil {
			return err
		}
	}
	if err := scanner.Err(); err != nil {
		return err
	}
	return fmt.Errorf("manifest stream ended without END frame")
}

func main() {
	root := flag.String("root", "", "picked source folder")
	output := flag.String("output", "", "CSV path in picked output folder")
	sourceHandle := flag.String("source-handle", "", "inherited read-only source handle")
	outputHandle := flag.String("output-handle", "", "inherited output handle")
	dynamicHandles := flag.Bool("handles-stdin", false, "receive duplicated handle values over stdin")
	manifestStdin := flag.Bool("manifest-stdin", false, "receive a sequence of brokered source handles")
	flag.Parse()
	if *manifestStdin {
		if err := manifestProbe(os.Stdin); err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}
		return
	}
	if *dynamicHandles {
		line, err := bufio.NewReader(os.Stdin).ReadString('\n')
		if err != nil {
			fmt.Fprintln(os.Stderr, "handle control read:", err)
			os.Exit(1)
		}
		fields := strings.Fields(line)
		if len(fields) != 2 {
			fmt.Fprintln(os.Stderr, "invalid handle control message")
			os.Exit(1)
		}
		if err := inheritedHandleProbe(fields[0], fields[1]); err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}
		return
	}
	if *sourceHandle != "" || *outputHandle != "" {
		if err := inheritedHandleProbe(*sourceHandle, *outputHandle); err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}
		return
	}
	if *root == "" {
		fmt.Fprintln(os.Stderr, "--root is required")
		os.Exit(2)
	}
	if err := run(*root, *output); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}
