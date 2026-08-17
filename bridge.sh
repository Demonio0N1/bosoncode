#!/usr/bin/env bash
# bridge.sh — puente SSH de iVsCode. Corre EN tu PC con Tailscale y expone el
# VS Code de un host remoto (supercomputador, servidor sin root/tailscale) a
# través de este PC, como ruta HTTPS del origen ya autorizado por la app.
#
# Uso:
#   ./bridge.sh usuario@host --scan            # diagnóstico: docker, GPU, python
#   ./bridge.sh usuario@host --name hpc        # instala, arranca, tunela y publica
#   ./bridge.sh usuario@host --name hpc --stop # apaga túnel y code-server remoto
#
# Requisitos: acceso SSH al remoto (idealmente con llave), y que el remoto
# tenga salida a internet para descargar code-server (~110 MB, solo 1ª vez).

set -euo pipefail

TARGET="${1:?uso: ./bridge.sh usuario@host [--name N] [--scan] [--stop]}"
shift
NAME=""; SCAN=0; STOP=0; RPORT=18443
while [ $# -gt 0 ]; do
  case "$1" in
    --name) NAME="$2"; shift 2 ;;
    --scan) SCAN=1; shift ;;
    --stop) STOP=1; shift ;;
    --remote-port) RPORT="$2"; shift 2 ;;
    -h|--help) grep '^# ' "$0" | sed 's/^# //'; exit 0 ;;
    *) echo "opción desconocida: $1 (usa --help)"; exit 1 ;;
  esac
done
[ -z "$NAME" ] && NAME=$(echo "$TARGET" | sed 's/.*@//' | cut -d. -f1 | tr -c 'a-zA-Z0-9-\n' '-')

IVSCODE_DIR="$HOME/.ivscode"
BRIDGES="$IVSCODE_DIR/bridges"
mkdir -p "$BRIDGES"
# una sola contraseña SSH para todos los pasos (multiplexación)
CTL="$BRIDGES/.ctl-$NAME"
SSHOPTS=(-o ConnectTimeout=15 -o StrictHostKeyChecking=accept-new \
         -o ControlMaster=auto -o "ControlPath=$CTL" -o ControlPersist=10m)

# puerto HTTPS canónico de este PC (el de serve.sh); 9444 como fallback
HTTPS_PORT=$(tailscale serve status 2>/dev/null | awk '
  /^https:\/\// { n = split($1, a, ":"); port = a[n] }
  index($0, "http://127.0.0.1:8444") && port { print port; exit }')
HTTPS_PORT="${HTTPS_PORT:-9444}"
TS_DNS=$(tailscale status --json 2>/dev/null \
  | grep -o '"DNSName": *"[^"]*"' | head -1 | sed 's/.*"\([^"]*\)"$/\1/')
TS_DNS=${TS_DNS%.}

# ---------- --scan: diagnóstico del remoto ----------
if [ "$SCAN" = 1 ]; then
  ssh "${SSHOPTS[@]}" "$TARGET" '
    echo "══ $(hostname) — $(uname -sm) ══"
    if command -v docker >/dev/null 2>&1; then
      if docker ps >/dev/null 2>&1; then
        echo "docker: SÍ, con acceso. Contenedores:"
        docker ps -a --format "   {{.Names}}  ({{.Image}}, {{.Status}})" | head -10
      else
        echo "docker: instalado pero SIN acceso al daemon (pide al admin unirte al grupo docker)"
      fi
    else
      echo "docker: NO instalado"
    fi
    command -v apptainer >/dev/null 2>&1 && echo "apptainer: $(apptainer --version 2>/dev/null)" \
      || { command -v singularity >/dev/null 2>&1 && echo "singularity: sí" || echo "apptainer/singularity: NO"; }
    command -v nvidia-smi >/dev/null 2>&1 \
      && nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | sed "s/^/GPU: /" \
      || echo "GPU: no visible desde este nodo"
    command -v python3 >/dev/null 2>&1 && echo "python3: $(python3 -V 2>&1)" || echo "python3: NO"
    command -v curl >/dev/null 2>&1 && echo "curl: sí" || echo "curl: NO (necesario para instalar code-server)"
    echo "home: $HOME ($(df -h "$HOME" 2>/dev/null | tail -1 | awk "{print \$4}") libres)"
  '
  exit 0
fi

# ---------- --stop: apagar puente ----------
if [ "$STOP" = 1 ]; then
  if [ -f "$BRIDGES/$NAME.env" ]; then
    . "$BRIDGES/$NAME.env"
    pkill -f "[s]sh.*-L 127.0.0.1:$LPORT" 2>/dev/null || true
  fi
  tailscale serve --https="$HTTPS_PORT" --set-path="/r-$NAME" off 2>/dev/null || true
  ssh "${SSHOPTS[@]}" "$TARGET" "pkill -f '[c]ode-server.*127.0.0.1:$RPORT' 2>/dev/null" || true
  rm -f "$BRIDGES/$NAME.env"
  echo "✔ Puente '$NAME' detenido."
  exit 0
fi

# ---------- instalar code-server en el remoto (sin root) ----------
echo "→ [1/4] Instalando/verificando code-server en el remoto…"
ssh "${SSHOPTS[@]}" "$TARGET" 'bash -s' <<'REMOTE'
set -e
IV="$HOME/.ivscode"
mkdir -p "$IV"
if [ ! -x "$IV/current/bin/code-server" ]; then
  case "$(uname -s)" in Linux) P=linux ;; Darwin) P=macos ;; *) echo "SO no soportado"; exit 1 ;; esac
  case "$(uname -m)" in x86_64|amd64) A=amd64 ;; aarch64|arm64) A=arm64 ;; *) echo "arch no soportada"; exit 1 ;; esac
  V=$(curl -fsSL https://api.github.com/repos/coder/code-server/releases/latest \
    | grep -o '"tag_name": *"v[^"]*"' | head -1 | grep -o '[0-9][0-9.]*')
  T="code-server-$V-$P-$A.tar.gz"
  echo "  descargando code-server v$V ($P-$A)…"
  curl -fL --progress-bar "https://github.com/coder/code-server/releases/download/v$V/$T" -o "$IV/$T"
  tar -xzf "$IV/$T" -C "$IV" && rm -f "$IV/$T"
  ln -sfn "$IV/code-server-$V-$P-$A" "$IV/current"
fi
# extensiones (Jupyter/Python) + settings sin Restricted Mode
mkdir -p "$IV/extensions" "$HOME/.local/share/code-server/User"
for ext in ms-toolsai.jupyter ms-python.python detachhead.basedpyright; do
  "$IV/current/bin/code-server" --extensions-dir "$IV/extensions" --list-extensions 2>/dev/null \
    | grep -qi "^$ext$" || "$IV/current/bin/code-server" --extensions-dir "$IV/extensions" \
        --install-extension "$ext" >/dev/null 2>&1 || echo "  ⚠ no pude instalar $ext"
done
cat > "$HOME/.local/share/code-server/User/settings.json" <<'EOF'
{
  "security.workspace.trust.enabled": false,
  "security.workspace.trust.startupPrompt": "never",
  "security.workspace.trust.untrustedFiles": "open",
  "extensions.ignoreRecommendations": true,
  "window.autoDetectColorScheme": true
}
EOF
echo "  code-server listo en el remoto."
REMOTE

# ---------- arrancar code-server remoto (solo localhost del remoto) ----------
echo "→ [2/4] Arrancando code-server remoto en 127.0.0.1:${RPORT}…"
PASSWORD=$(cat "$IVSCODE_DIR/password")
# matar y arrancar van en SSH SEPARADOS: si la misma shell contiene el pkill y
# el texto real del comando, el patrón coincide con su propia línea y se mata
ssh "${SSHOPTS[@]}" "$TARGET" "pkill -f '[c]ode-server.*127.0.0.1:$RPORT' 2>/dev/null; true"
ssh "${SSHOPTS[@]}" "$TARGET" "
  printf '%s' '$PASSWORD' > ~/.ivscode/password && chmod 600 ~/.ivscode/password
  rm -f ~/.ivscode/bridge.log
  nohup env PASSWORD='$PASSWORD' ~/.ivscode/current/bin/code-server \
    --bind-addr 127.0.0.1:$RPORT --auth password \
    --extensions-dir ~/.ivscode/extensions --disable-telemetry \
    > ~/.ivscode/bridge.log 2>&1 &
  sleep 3
  grep -m1 'listening' ~/.ivscode/bridge.log || { tail -5 ~/.ivscode/bridge.log; exit 1; }
"

# ---------- túnel SSH persistente PC → remoto ----------
echo "→ [3/4] Levantando túnel persistente…"
LPORT=20100
while ss -ltn 2>/dev/null | grep -q ":$LPORT "; do LPORT=$((LPORT + 1)); done
pkill -f "[s]sh.*-L 127.0.0.1:$LPORT" 2>/dev/null || true
(nohup bash -c "while true; do
    ssh -N -o ServerAliveInterval=30 -o ServerAliveCountMax=3 \
        -o ExitOnForwardFailure=yes -o ControlPath='$CTL' \
        -L 127.0.0.1:$LPORT:127.0.0.1:$RPORT '$TARGET'
    sleep 5
  done" > "$BRIDGES/$NAME.log" 2>&1 &)
echo "LPORT=$LPORT" > "$BRIDGES/$NAME.env"
sleep 2

# ---------- publicar como ruta del origen autorizado ----------
echo "→ [4/4] Publicando en HTTPS…"
tailscale serve --bg --https="$HTTPS_PORT" --set-path="/r-$NAME" "http://127.0.0.1:$LPORT" >/dev/null

echo ""
echo "═══════════════════════════════════════════════════"
echo "  Puente '$NAME' activo → $TARGET"
echo "  URL para la app iVsCode (Añadir manualmente):"
echo "    https://${TS_DNS}:${HTTPS_PORT}/r-${NAME}/"
echo "  Contraseña: la misma de siempre (auto-login funcionará)"
echo "  Detener:  ./bridge.sh $TARGET --name $NAME --stop"
echo "  Nota: este PC debe seguir encendido (es el puente)."
echo "═══════════════════════════════════════════════════"
