//go:build !windows_appcontainer || !appcontainer_network_probe

package main

func runAppContainerNetworkProbeIfRequested([]string) (bool, int) { return false, 0 }
