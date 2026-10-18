//go:build !windows || !appcontainer_webview2_spike

package wailsadapter

func newBrokerBackend() brokerBackend { return nil }
