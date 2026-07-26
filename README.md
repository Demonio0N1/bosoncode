# iVsCode — VS Code completo en el iPad Pro, cómputo en la RTX 4090

El iPad ejecuta una app nativa SwiftUI que envuelve un `WKWebView` apuntando a
`code-server` en tu PC. Todo el cómputo (Python, Julia, PyTorch, kernels de
Jupyter, SSH) corre en el PC dentro de un contenedor con passthrough de GPU.
La conexión va por Tailscale (WireGuard, sin puertos abiertos, HTTPS con
certificado válido).

```
iVsCode/
├── backend/            # Docker: code-server + Python/PyTorch + Julia + GPU
│   ├── Dockerfile
│   ├── docker-compose.yml
│   └── .env.example
└── ipad/               # App iPadOS (SwiftUI + WKWebView)
    ├── project.yml     # manifiesto XcodeGen → genera el .xcodeproj
    └── iVsCode/        # código fuente Swift + Info.plist
```

---

## Fase 0 — Red (una sola vez)

1. Instala Tailscale en el PC: `curl -fsSL https://tailscale.com/install.sh | sh && sudo tailscale up`
2. Instala la app de Tailscale en el iPad (App Store) e inicia sesión en la misma tailnet.
3. Verifica: desde el iPad, la web de admin de Tailscale debe mostrar ambos dispositivos online.

## Fase 1 — Backend (PC con la RTX 4090)

Prerequisitos: driver NVIDIA reciente + Docker + NVIDIA Container Toolkit:

```bash
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
  sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
  sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
sudo apt-get update && sudo apt-get install -y nvidia-container-toolkit
sudo nvidia-ctk runtime configure --runtime=docker && sudo systemctl restart docker

# Verificación del passthrough
docker run --rm --gpus all nvidia/cuda:12.4.1-base-ubuntu22.04 nvidia-smi
```

Levanta el backend:

```bash
cd backend
cp .env.example .env        # y edita la contraseña
docker compose up -d --build   # primera build: ~10-15 min (PyTorch cu124 pesa ~3 GB)
```

Publícalo con HTTPS válido, solo dentro de tu tailnet:

```bash
sudo tailscale serve --bg https / http://127.0.0.1:8443
tailscale serve status      # → https://tu-pc.tu-tailnet.ts.net
```

Verifica la GPU desde dentro (o luego desde la terminal en el iPad):

```bash
docker exec ivscode-backend /home/coder/.venvs/ml/bin/python \
  -c "import torch; print(torch.cuda.get_device_name(0), torch.cuda.is_available())"
# → NVIDIA GeForce RTX 4090 True
```

## Fase 2 — Validación sin app

Abre `https://tu-pc.tu-tailnet.ts.net` en Safari del iPad. Debes poder editar,
abrir la terminal (⌃`) y ejecutar un notebook con el kernel "Python (ML)".
Si algo falla aquí, es problema del backend — arréglalo antes de tocar Swift.

## Fase 3 — App iPadOS

En tu Mac:

```bash
brew install xcodegen
cd ipad
xcodegen                    # genera iVsCode.xcodeproj desde project.yml
open iVsCode.xcodeproj
```

En Xcode: selecciona tu equipo de firma (Signing & Capabilities → Team),
conecta el iPad y ejecuta. Al primer arranque la app pide la URL del backend
(la de `tailscale serve`).

> Alternativa sin XcodeGen: crea en Xcode un proyecto "App" (SwiftUI, iOS 17,
> solo iPad), borra los archivos generados y arrastra los de `ipad/iVsCode/`,
> incluyendo el `Info.plist`.

### Qué hace la app

| Archivo | Responsabilidad |
|---|---|
| `iVsCodeApp.swift` | Pantalla completa real: sin barra de estado, indicador de Home oculto, gestos de borde diferidos |
| `ContentView.swift` | Estado de conexión, overlay de reintento, hoja de ajustes |
| `SettingsView.swift` | URL del backend (persistida en `AppStorage`) |
| `CodeWebView.swift` | `WKWebView` configurado para VS Code + `KeyboardWebView` que arrebata ⌘W/⌘T/⌘N al sistema y los reinyecta en el DOM |
| `ClipboardBridge.swift` | `navigator.clipboard` ⇄ `UIPasteboard` sin prompts ni fallos silenciosos |

Gestos: **doble toque con tres dedos** abre los ajustes nativos.

## Fase 4 — SSH y Jupyter

- **Terminal**: es un shell real en el contenedor con tu `~/.ssh` montado (solo
  lectura). `ssh`, `scp`, `rsync` y `~/.ssh/config` funcionan 1:1 como en
  escritorio. Para llaves con passphrase, descomenta las líneas de
  `SSH_AUTH_SOCK` en el compose.
- **Editar carpetas remotas**: la extensión `jeanp413.open-remote-ssh`
  (preinstalada) replica el flujo de Remote-SSH de Microsoft.
- **Jupyter**: la extensión `ms-toolsai.jupyter` (preinstalada) detecta los
  kernels "Python (ML)" y "Julia" del contenedor. Los notebooks entrenan
  directamente sobre la 4090.
- **IntelliSense de Python**: `basedpyright` (preinstalado) — equivalente libre
  de Pylance, que no está licenciado para code-server/Open VSX.

## serve.sh — backend sin Docker (recomendado)

`serve.sh` (raíz del proyecto) convierte cualquier computador Linux/macOS en
backend sin Docker y sin root: descarga code-server standalone en `~/.ivscode`,
instala las extensiones (Jupyter, Python, basedpyright) en un directorio
aislado, publica HTTPS vía Tailscale (los notebooks lo exigen) y se anuncia por
mDNS para que la app lo detecte sola.

```bash
./serve.sh                        # arrancar en primer plano
./serve.sh --name "Mi PC"         # nombre que verá la app
./serve.sh --install-service      # dejarlo permanente: arranca al encender el
                                  # equipo (systemd + linger en Linux,
                                  # LaunchAgent en macOS) y se reinicia si cae
```

Gestión del servicio en Linux: `systemctl --user status|restart ivscode`,
logs con `journalctl --user -u ivscode -f`.

## Mantenimiento

- Actualizar el backend: `docker compose up -d --build` (las extensiones y
  settings viven en el volumen `code-local` y sobreviven).
- Resetear extensiones/settings a los del Dockerfile: `docker compose down -v`
  (⚠️ borra también los kernels registrados y el depot de Julia; `./workspace`
  nunca se toca).
- Paridad 100% con el Marketplace de Microsoft (Pylance incluido): corre en el
  PC `code tunnel` (CLI oficial de VS Code) y apunta la app a la URL de
  vscode.dev que te da — a costa de más latencia (relay de Microsoft).
