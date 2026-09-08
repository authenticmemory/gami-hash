package wailsadapter

import (
	"reflect"
	"sort"
	"testing"
)

func TestBoundMethodAllowlist(t *testing.T) {
	typ := reflect.TypeOf(&Backend{})
	got := make([]string, 0, typ.NumMethod())
	for i := 0; i < typ.NumMethod(); i++ {
		got = append(got, typ.Method(i).Name)
	}
	sort.Strings(got)
	want := []string{
		"Cancel", "InspectResume", "OpenOutputFolder", "Preflight",
		"SelectFolder", "SelectOutput", "Start",
	}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("Wails-bound method set changed\n got: %v\nwant: %v", got, want)
	}
}

func TestRuntimeMethodsFailClosedBeforeStartup(t *testing.T) {
	b := New()
	if _, err := b.SelectFolder(); err == nil {
		t.Fatal("folder dialog accepted without Wails runtime context")
	}
	if _, err := b.SelectOutput("manifest.csv"); err == nil {
		t.Fatal("output dialog accepted without Wails runtime context")
	}
	if err := b.OpenOutputFolder(); err == nil {
		t.Fatal("output opener accepted without Wails runtime context")
	}
}
