//go:build !appcontainer_webview2_spike

package main

func runAppContainerNetworkProbeIfRequested([]string) (bool, int) { return false, 0 }
