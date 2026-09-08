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
		Title:     "GAMI Hash",
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
		Windows: &windows.Options{
			WebviewIsTransparent:              false,
			WindowIsTranslucent:               false,
			DisableFramelessWindowDecorations: false,
			WebviewUserDataPath:               "",
			ZoomFactor:                        1,
		},
	})
}
