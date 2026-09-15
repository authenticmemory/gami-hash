import { defineConfig } from "vite";

// Relative asset paths: identical behaviour inside the Wails window (the
// page sits at the asset-server root) and required for static previews.
export default defineConfig({ base: "./" });
