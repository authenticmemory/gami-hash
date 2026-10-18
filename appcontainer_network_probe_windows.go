//go:build windows && appcontainer_webview2_spike

package main

import (
	"context"
	"encoding/json"
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"
)

const appContainerNetworkProbeArgument = "--appcontainer-network-probe"

type networkAttempt struct {
	Name      string `json:"name"`
	Operation string `json:"operation"`
	Target    string `json:"target"`
	Result    string `json:"result"`
}

func spikeDataDirectory() (string, error) {
	root := os.Getenv("LOCALAPPDATA")
	if root == "" {
		var err error
		root, err = os.UserCacheDir()
		if err != nil {
			return "", err
		}
	}
	dir := filepath.Join(root, "AuthenticMemory", "GAMIHashWebView2Spike")
	return dir, os.MkdirAll(dir, 0o700)
}

func launchAppContainerNetworkProbe() {
	executable, err := os.Executable()
	if err != nil {
		return
	}
	_ = exec.Command(executable, appContainerNetworkProbeArgument).Start()
}

func runAppContainerNetworkProbeIfRequested(args []string) (bool, int) {
	if len(args) != 1 || args[0] != appContainerNetworkProbeArgument {
		return false, 0
	}
	dir, err := spikeDataDirectory()
	if err != nil {
		return true, 2
	}
	marker := filepath.Join(dir, "network-probe-started.txt")
	_ = os.WriteFile(marker, []byte(time.Now().UTC().Format(time.RFC3339Nano)), 0o600)
	attempts := []networkAttempt{}
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	addresses, dnsErr := net.DefaultResolver.LookupHost(ctx, "example.com")
	cancel()
	dnsResult := "resolved"
	if dnsErr != nil {
		dnsResult = dnsErr.Error()
	} else if len(addresses) == 0 {
		dnsResult = "no addresses"
	}
	attempts = append(attempts, networkAttempt{Name: "DNS-public", Operation: "lookup", Target: "example.com", Result: dnsResult})

	targets := []struct{ name, network, address string }{
		{"TCP-loopback", "tcp4", "127.0.0.1:48521"},
		{"TCP-private", "tcp4", "192.168.247.1:9"},
		{"TCP-public", "tcp4", "1.1.1.1:443"},
		{"UDP-loopback", "udp4", "127.0.0.1:48521"},
		{"UDP-private", "udp4", "192.168.247.1:9"},
		{"UDP-public", "udp4", "1.1.1.1:53"},
		{"TCP6-loopback", "tcp6", "[::1]:48521"},
		{"TCP6-private", "tcp6", "[fd00::1]:9"},
		{"TCP6-public", "tcp6", "[2606:4700:4700::1111]:443"},
		{"UDP6-loopback", "udp6", "[::1]:48521"},
		{"UDP6-private", "udp6", "[fd00::1]:9"},
		{"UDP6-public", "udp6", "[2606:4700:4700::1111]:53"},
	}
	for _, target := range targets {
		operation := "dial"
		connection, dialErr := net.DialTimeout(target.network, target.address, 800*time.Millisecond)
		result := "connected"
		if dialErr != nil {
			result = dialErr.Error()
		} else {
			if strings.HasPrefix(target.network, "udp") {
				operation = "dial+write"
				_ = connection.SetWriteDeadline(time.Now().Add(800 * time.Millisecond))
				if _, writeErr := connection.Write([]byte("GAMI-SPIKE")); writeErr != nil {
					result = writeErr.Error()
				} else {
					result = "write returned success"
				}
			}
			_ = connection.Close()
		}
		attempts = append(attempts, networkAttempt{Name: target.name, Operation: operation, Target: target.address, Result: result})
	}
	payload := struct {
		UTC      string           `json:"utc"`
		PID      int              `json:"pid"`
		Attempts []networkAttempt `json:"attempts"`
	}{time.Now().UTC().Format(time.RFC3339Nano), os.Getpid(), attempts}
	data, err := json.MarshalIndent(payload, "", "  ")
	if err != nil {
		return true, 3
	}
	if err := os.WriteFile(filepath.Join(dir, "network-probe.json"), data, 0o600); err != nil {
		_ = os.WriteFile(filepath.Join(dir, "network-probe-error.txt"), []byte(err.Error()), 0o600)
		return true, 4
	}
	time.Sleep(30 * time.Second)
	return true, 0
}
