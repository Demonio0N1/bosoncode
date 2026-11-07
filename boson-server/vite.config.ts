import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

// Puerto fijo: tauri.conf.json lo tiene apuntado en devUrl.
export default defineConfig({
  plugins: [react()],
  clearScreen: false,
  server: { port: 1420, strictPort: true },
  envPrefix: ["VITE_", "TAURI_ENV_"],
  build: { target: "es2022", minify: true, sourcemap: false },
});
