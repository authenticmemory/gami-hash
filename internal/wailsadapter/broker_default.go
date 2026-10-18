//go:build !windows || !windows_appcontainer

package wailsadapter

func newBrokerBackend() brokerBackend { return nil }
