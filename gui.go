//go:build !cli

package main

import (
	"embed"

	"github.com/wailsapp/wails/v2"
	"github.com/wailsapp/wails/v2/pkg/options"
	"github.com/wailsapp/wails/v2/pkg/options/assetserver"
	"github.com/wailsapp/wails/v2/pkg/options/windows"

	"github.com/authenticmemory/gami-hash/internal/wailsadapter"
)

//go:embed all:frontend/dist
var frontendAssets embed.FS

func runGUI() error {
	backend := wailsadapter.New()
	return wails.Run(&options.App{
		Title: "Authentic Memory Hashing Tool",
		// The window is frameless: the frontend draws its own title bar in
		// the corporate design (drag region plus window controls), so the
		// look does not depend on OS titlebar themes or accent colors.
		Frameless: true,
		Width:     980,
		Height:    720,
		MinWidth:  760,
		MinHeight: 620,
		AssetServer: &assetserver.Options{
			Assets: frontendAssets,
		},
		OnStartup:  wailsadapter.OnStartup(backend),
		OnShutdown: wailsadapter.OnShutdown(backend),
		Bind:       []interface{}{backend},
		SingleInstanceLock: &options.SingleInstanceLock{
			UniqueId: "a61fc80f-8125-4ca8-b873-c9dde1f503e1",
		},
		Windows: &windows.Options{
			WebviewIsTransparent:              false,
			WindowIsTranslucent:               false,
			DisableFramelessWindowDecorations: false,
			WebviewUserDataPath:               "",
			ZoomFactor:                        1,
		},
	})
}
