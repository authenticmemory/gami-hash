//go:build !windows

package main

func runContainedWorkerIfRequested([]string) (bool, int) { return false, 0 }
