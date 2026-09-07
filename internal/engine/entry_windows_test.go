//go:build windows

package engine

import (
	"context"
	"os"
	"os/exec"
	"path/filepath"
	"testing"
)

func makeJunction(t *testing.T, target, junction string) {
	t.Helper()
	cmd := exec.Command("cmd.exe", "/c", "mklink", "/J", junction, target)
	if output, err := cmd.CombinedOutput(); err != nil {
		t.Skipf("junction unavailable: %v (%s)", err, output)
	}
	t.Cleanup(func() { _ = os.Remove(junction) })
}

func TestOutputJunctionIntoRootRejected(t *testing.T) {
	root := buildTree(t, map[string]string{"source.txt": "safe"})
	alias := filepath.Join(t.TempDir(), "source-alias")
	makeJunction(t, root, alias)
	_, err := Run(context.Background(), Options{Root: root, Output: filepath.Join(alias, "manifest.csv"), Fresh: true}, nil)
	if err == nil {
		resolvedRoot, _ := resolveExisting(root)
		resolvedAlias, resolveErr := resolveExisting(alias)
		t.Fatalf("output junction into source root must be rejected (root=%q alias=%q resolveErr=%v)", resolvedRoot, resolvedAlias, resolveErr)
	}
	if fileExists(filepath.Join(root, "manifest.csv")) {
		t.Fatal("manifest was written through junction into source")
	}
}

func TestSourceJunctionIsSkipped(t *testing.T) {
	outside := buildTree(t, map[string]string{"outside.txt": "must not hash"})
	root := buildTree(t, map[string]string{"inside.txt": "hash me"})
	makeJunction(t, outside, filepath.Join(root, "junction"))
	out := filepath.Join(t.TempDir(), "manifest.csv")
	res := runFresh(t, root, out)
	if res.FilesHashed != 1 || res.Skipped != 1 {
		t.Fatalf("junction was not safely skipped: %+v", res)
	}
	if _, found := rowMap(readRows(t, out))["junction/outside.txt"]; found {
		t.Fatal("junction target was traversed")
	}
}
