#!/usr/bin/env bash
# iVsCode serve.sh — convierte este computador en backend de la app iVsCode.
# Sin Docker, sin root: descarga code-server standalone en ~/.ivscode, lo
# levanta en la red y se anuncia por mDNS para que la app lo detecte sola.
#
# Uso:  ./serve.sh [--port N] [--name "Mi PC"] [--password PASS]
#       ./serve.sh --install-service   # deja el backend arrancando solo al encender
#                                      # (systemd de usuario en Linux, LaunchAgent en macOS)

set -euo pipefail

PORT="${PORT:-8443}"
NAME="${NAME:-$(hostname -s 2>/dev/null || hostname)}"
PASSWORD="${PASSWORD:-}"
IVSCODE_DIR="$HOME/.ivscode"
INSTALL_SERVICE=0

while [ $# -gt 0 ]; do
  case "$1" in
    --port) PORT="$2"; shift 2 ;;
    --name) NAME="$2"; shift 2 ;;
    --password) PASSWORD="$2"; shift 2 ;;
    --install-service) INSTALL_SERVICE=1; shift ;;
    -h|--help)
      grep '^# ' "$0" | sed 's/^# //'
      exit 0 ;;
    *) echo "opción desconocida: $1 (usa --help)"; exit 1 ;;
  esac
done

# ---------- detectar plataforma ----------
case "$(uname -s)" in
  Linux)  PLATFORM=linux ;;
  Darwin) PLATFORM=macos ;;
  *) echo "SO no soportado: $(uname -s)"; exit 1 ;;
esac
case "$(uname -m)" in
  x86_64|amd64)  ARCH=amd64 ;;
  aarch64|arm64) ARCH=arm64 ;;
  *) echo "arquitectura no soportada: $(uname -m)"; exit 1 ;;
esac

# ---------- --install-service: dejarlo permanente y salir ----------
if [ "$INSTALL_SERVICE" = 1 ]; then
  SCRIPT_PATH="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
  mkdir -p "$IVSCODE_DIR"
  if [ -n "$PASSWORD" ]; then
    printf '%s' "$PASSWORD" > "$IVSCODE_DIR/password"
    chmod 600 "$IVSCODE_DIR/password"
  fi
  if [ "$PLATFORM" = linux ]; then
    mkdir -p "$HOME/.config/systemd/user"
    cat > "$HOME/.config/systemd/user/ivscode.service" <<EOF
[Unit]
Description=iVsCode backend (code-server nativo + anuncio mDNS)
After=network-online.target

[Service]
Type=simple
Environment=NAME=$NAME
Environment=PORT=$PORT
ExecStart=$SCRIPT_PATH
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
EOF
    systemctl --user daemon-reload
    systemctl --user enable ivscode.service >/dev/null 2>&1
    loginctl enable-linger "$USER" 2>/dev/null \
      && echo "→ Linger activado: arranca aunque nadie inicie sesión." \
      || echo "⚠ No pude activar linger; ejecútalo tú: sudo loginctl enable-linger $USER"
    systemctl --user restart ivscode.service
    echo "✔ Servicio instalado y corriendo."
    echo "  Estado:    systemctl --user status ivscode"
    echo "  Logs:      journalctl --user -u ivscode -f"
    echo "  Reiniciar: systemctl --user restart ivscode"
  else
    PLIST="$HOME/Library/LaunchAgents/com.ivscode.serve.plist"
    mkdir -p "$HOME/Library/LaunchAgents"
    cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>com.ivscode.serve</string>
  <key>ProgramArguments</key>
  <array><string>$SCRIPT_PATH</string></array>
  <key>EnvironmentVariables</key>
  <dict>
    <key>NAME</key><string>$NAME</string>
    <key>PORT</key><string>$PORT</string>
  </dict>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><dict><key>SuccessfulExit</key><false/></dict>
  <key>StandardOutPath</key><string>$HOME/.ivscode/serve.log</string>
  <key>StandardErrorPath</key><string>$HOME/.ivscode/serve.log</string>
</dict>
</plist>
EOF
    launchctl unload "$PLIST" 2>/dev/null || true
    launchctl load -w "$PLIST"
    echo "✔ LaunchAgent instalado y corriendo (logs: ~/.ivscode/serve.log)"
  fi
  exit 0
fi

# ---------- instalar code-server standalone si falta ----------
mkdir -p "$IVSCODE_DIR"
if [ ! -x "$IVSCODE_DIR/current/bin/code-server" ]; then
  echo "→ Descargando code-server standalone ($PLATFORM-$ARCH)…"
  VERSION=$(curl -fsSL https://api.github.com/repos/coder/code-server/releases/latest 2>/dev/null \
    | sed -n 's/.*"tag_name": *"v\([0-9][0-9.]*\)".*/\1/p' | sed -n 1p || true)
  if [ -z "$VERSION" ]; then
    echo "⚠ No pude consultar la última versión (rate limit de GitHub?); uso 4.130.0"
    VERSION=4.130.0
  fi
  TAR="code-server-${VERSION}-${PLATFORM}-${ARCH}.tar.gz"
  curl -fL --progress-bar \
    "https://github.com/coder/code-server/releases/download/v${VERSION}/${TAR}" \
    -o "$IVSCODE_DIR/$TAR"
  tar -xzf "$IVSCODE_DIR/$TAR" -C "$IVSCODE_DIR"
  rm -f "$IVSCODE_DIR/$TAR"
  ln -sfn "$IVSCODE_DIR/code-server-${VERSION}-${PLATFORM}-${ARCH}" "$IVSCODE_DIR/current"
  echo "→ Instalado code-server v${VERSION} en $IVSCODE_DIR"
fi

# ---------- extensiones por defecto (Jupyter, Python) ----------
# Directorio AISLADO: si se usa el default, code-server mezcla las extensiones
# del VS Code de escritorio (~/.vscode/extensions), builds para un motor más
# nuevo que quedan desactivadas — y sin Jupyter no abren los notebooks.
EXT_DIR="$IVSCODE_DIR/extensions"
mkdir -p "$EXT_DIR"
INSTALLED=$("$IVSCODE_DIR/current/bin/code-server" --extensions-dir "$EXT_DIR" --list-extensions 2>/dev/null || true)
for ext in ms-toolsai.jupyter ms-python.python detachhead.basedpyright; do
  echo "$INSTALLED" | grep -qi "^$ext$" && continue
  echo "→ Instalando extensión $ext…"
  "$IVSCODE_DIR/current/bin/code-server" --extensions-dir "$EXT_DIR" --install-extension "$ext" >/dev/null 2>&1 \
    || echo "⚠ No pude instalar $ext (sin internet?); instálala luego desde la UI."
done

# ---------- ajustes por defecto (sin Restricted Mode) ----------
# En modo restringido code-server desactiva Jupyter y los notebooks no abren.
# Es tu propia máquina: se desactiva el workspace trust.
if command -v python3 >/dev/null 2>&1; then
  python3 - <<'PYEOF'
import json, pathlib
p = pathlib.Path.home() / ".local/share/code-server/User/settings.json"
p.parent.mkdir(parents=True, exist_ok=True)
raw = p.read_text() if p.exists() else "{}"
try:
    cfg = json.loads(raw)
except Exception:
    # settings.json con comentarios (JSONC) o corrupto: se respalda antes de
    # tocarlo para no perder la configuración del usuario
    p.with_suffix(".json.bak").write_text(raw)
    print("⚠ settings.json no era JSON válido; copia en settings.json.bak")
    cfg = {}
cfg.setdefault("security.workspace.trust.enabled", False)
cfg.setdefault("security.workspace.trust.startupPrompt", "never")
cfg.setdefault("security.workspace.trust.untrustedFiles", "open")
cfg.setdefault("extensions.ignoreRecommendations", True)
cfg.setdefault("window.autoDetectColorScheme", True)
p.write_text(json.dumps(cfg, indent=2))
PYEOF
fi

# ---------- contraseña persistente por equipo ----------
if [ -z "$PASSWORD" ]; then
  if [ -f "$IVSCODE_DIR/password" ]; then
    PASSWORD=$(cat "$IVSCODE_DIR/password")
  else
    PASSWORD=$(openssl rand -hex 8 2>/dev/null \
      || head -c 8 /dev/urandom | od -An -tx1 | tr -d ' \n')
    printf '%s' "$PASSWORD" > "$IVSCODE_DIR/password"
    chmod 600 "$IVSCODE_DIR/password"
  fi
else
  printf '%s' "$PASSWORD" > "$IVSCODE_DIR/password"
  chmod 600 "$IVSCODE_DIR/password"
fi

# ---------- buscar puerto libre ----------
port_busy() {
  if command -v ss >/dev/null 2>&1; then
    ss -ltn 2>/dev/null | grep -q ":$1 "
  elif command -v lsof >/dev/null 2>&1; then
    lsof -iTCP:"$1" -sTCP:LISTEN >/dev/null 2>&1
  else
    return 1
  fi
}
while port_busy "$PORT"; do
  echo "→ Puerto $PORT ocupado, pruebo $((PORT + 1))"
  PORT=$((PORT + 1))
done

# ---------- HTTPS vía Tailscale (contexto seguro: notebooks/webviews) ----------
# Los webviews de VS Code (editor de notebooks incluido) exigen HTTPS. Si hay
# tailscale, publicamos este puerto con cert válido y anunciamos ESA URL.
CANON_URL=""
if command -v tailscale >/dev/null 2>&1; then
  TS_DNS=$(tailscale status --json 2>/dev/null \
    | python3 -c 'import json,sys; print(json.load(sys.stdin)["Self"]["DNSName"].rstrip("."))' \
    2>/dev/null || true)
  # el listener HTTPS lo abre tailscaled: debe ir en un puerto DISTINTO al de
  # code-server o chocan (EADDRINUSE). Si ya existe un mapeo hacia nuestro
  # puerto, se reutiliza (la URL no cambia entre reinicios).
  HTTPS_PORT=$(tailscale serve status 2>/dev/null | awk -v tgt="http://127.0.0.1:$PORT" '
    /^https:\/\// { port = (match($1, /:[0-9]+$/) ? substr($1, RSTART+1, RLENGTH-1) : 443) }
    index($0, tgt) && port { print port; exit }' || true)
  case "$HTTPS_PORT" in ''|*[!0-9]*) HTTPS_PORT="" ;; esac
  if [ -z "$HTTPS_PORT" ]; then
    HTTPS_PORT=$((PORT + 1000))
    while port_busy "$HTTPS_PORT"; do HTTPS_PORT=$((HTTPS_PORT + 1)); done
  fi
  if [ -n "$TS_DNS" ] && tailscale serve --bg --https="$HTTPS_PORT" "http://127.0.0.1:$PORT" >/dev/null 2>&1; then
    CANON_URL="https://${TS_DNS}:${HTTPS_PORT}"
  else
    echo "⚠ No pude configurar tailscale serve (¿falta 'tailscale set --operator=$USER'?)."
    echo "  Los notebooks necesitan HTTPS; por http funcionará el resto del editor."
  fi
fi

# ---------- anunciar por mDNS (_ivscode._tcp) ----------
MDNS_PID=""
TXT_ARG=()
[ -n "$CANON_URL" ] && TXT_ARG=("url=$CANON_URL")
if command -v avahi-publish >/dev/null 2>&1; then
  avahi-publish -s "$NAME" _ivscode._tcp "$PORT" ${TXT_ARG[@]+"${TXT_ARG[@]}"} >/dev/null 2>&1 &
  MDNS_PID=$!
elif command -v dns-sd >/dev/null 2>&1; then
  dns-sd -R "$NAME" _ivscode._tcp . "$PORT" ${TXT_ARG[@]+"${TXT_ARG[@]}"} >/dev/null 2>&1 &
  MDNS_PID=$!
elif command -v python3 >/dev/null 2>&1 && python3 -c "import dbus" 2>/dev/null \
     && systemctl is-active -q avahi-daemon 2>/dev/null; then
  # fallback sin root ni instalaciones: publicar vía D-Bus de Avahi
  cat > "$IVSCODE_DIR/announce_dbus.py" <<'PYEOF'
import sys, time
import dbus

name, port = sys.argv[1], int(sys.argv[2])
txt_entries = [t.encode() for t in sys.argv[3:]]
bus = dbus.SystemBus()
server = dbus.Interface(
    bus.get_object("org.freedesktop.Avahi", "/"),
    "org.freedesktop.Avahi.Server",
)
group = dbus.Interface(
    bus.get_object("org.freedesktop.Avahi", server.EntryGroupNew()),
    "org.freedesktop.Avahi.EntryGroup",
)
group.AddService(
    dbus.Int32(-1), dbus.Int32(-1), dbus.UInt32(0),
    name, "_ivscode._tcp", "", "",
    dbus.UInt16(port),
    dbus.Array([dbus.ByteArray(t) for t in txt_entries], signature="ay"),
)
group.Commit()
while True:
    time.sleep(60)
PYEOF
  python3 "$IVSCODE_DIR/announce_dbus.py" "$NAME" "$PORT" ${TXT_ARG[@]+"${TXT_ARG[@]}"} >/dev/null 2>&1 &
  MDNS_PID=$!
elif command -v python3 >/dev/null 2>&1; then
  # fallback sin root: zeroconf instalado a nivel usuario
  if ! python3 -c "import zeroconf" 2>/dev/null; then
    echo "→ Preparando anunciador mDNS (python zeroconf)…"
    python3 -m pip install --user -q zeroconf 2>/dev/null \
      || python3 -m pip install --user --break-system-packages -q zeroconf \
      || echo "⚠ No pude instalar zeroconf; sin auto-detección (conéctate por IP)."
  fi
  cat > "$IVSCODE_DIR/announce.py" <<'PYEOF'
import socket, sys, time
from zeroconf import Zeroconf, ServiceInfo

name, port = sys.argv[1], int(sys.argv[2])
props = dict(t.split("=", 1) for t in sys.argv[3:] if "=" in t)
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
s.connect(("8.8.8.8", 80))
ip = s.getsockname()[0]
s.close()
info = ServiceInfo(
    "_ivscode._tcp.local.",
    f"{name}._ivscode._tcp.local.",
    addresses=[socket.inet_aton(ip)],
    port=port,
    properties=props,
    server=f"{name.lower().replace(' ', '-')}.local.",
)
zc = Zeroconf()
zc.register_service(info)
while True:
    time.sleep(60)
PYEOF
  if python3 -c "import zeroconf" 2>/dev/null; then
    python3 "$IVSCODE_DIR/announce.py" "$NAME" "$PORT" ${TXT_ARG[@]+"${TXT_ARG[@]}"} >/dev/null 2>&1 &
    MDNS_PID=$!
  fi
else
  echo "⚠ Sin avahi-publish, dns-sd ni python3: la app no detectará este equipo sola."
  echo "  Puedes conectarte por IP igualmente (URLs abajo)."
fi
MGR_PID=""
cleanup() {
  [ -n "$MDNS_PID" ] && kill "$MDNS_PID" 2>/dev/null || true
  if [ -n "$MGR_PID" ]; then
    kill "$MGR_PID" 2>/dev/null || true          # supervisor
    pkill -f "[m]anager\.py" 2>/dev/null || true # y el python que supervisa
  fi
}
trap cleanup EXIT INT TERM

# ---------- gestor de máquinas Docker (API para la app) ----------
# Crea/inicia/detiene contenedores con el OS elegido; cada uno corre el
# code-server del host montado read-only (crear una máquina no descarga nada).
if [ -n "$CANON_URL" ] && command -v docker >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1; then
  MGR_LOCAL=39500
  # setup-machine: disponible como comando dentro de cada máquina
  cat > "$IVSCODE_DIR/setup-machine.sh" <<'SETUPEOF'
#!/usr/bin/env bash
# setup-machine — configura esta máquina iVsCode como un entorno de desarrollo
# completo. Uso: setup-machine [--ml]  (--ml añade PyTorch con CUDA, ~3 GB)
set -euo pipefail
ML=0
[ "${1:-}" = "--ml" ] && ML=1
echo "══ setup-machine: configurando $(hostname) ══"
if command -v apt-get >/dev/null 2>&1; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y --no-install-recommends \
    git curl wget nano htop unzip zip ca-certificates openssh-client \
    build-essential python3 python3-pip python3-venv
elif command -v dnf >/dev/null 2>&1; then
  dnf install -y git curl wget nano htop unzip zip openssh-clients \
    gcc gcc-c++ make python3 python3-pip
elif command -v pacman >/dev/null 2>&1; then
  pacman -Sy --noconfirm git curl wget nano htop unzip zip openssh \
    base-devel python python-pip
else
  echo "✗ Gestor de paquetes no soportado"; exit 1
fi
echo "── Python: kernel de Jupyter + libs científicas ──"
python3 -m pip install --break-system-packages --upgrade \
  ipykernel ipywidgets numpy pandas matplotlib 2>/dev/null \
  || python3 -m pip install --upgrade ipykernel ipywidgets numpy pandas matplotlib
python3 -m ipykernel install --name python3 --display-name "Python 3 ($(hostname))"
if [ "$ML" = 1 ]; then
  echo "── PyTorch (CUDA) ──"
  python3 -m pip install --break-system-packages torch torchvision 2>/dev/null \
    || python3 -m pip install torch torchvision
  python3 -c "import torch; print('PyTorch:', torch.__version__, '| CUDA disponible:', torch.cuda.is_available())"
fi
echo ""
echo "✔ Máquina configurada. Recarga la ventana de VS Code y elige el kernel."
SETUPEOF
  chmod +x "$IVSCODE_DIR/setup-machine.sh"
  cat > "$IVSCODE_DIR/manager.py" <<'PYEOF'
import fcntl, hmac, json, os, pty, re, select, shlex, shutil, signal, socket
import struct, subprocess, sys, termios, threading, time, urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

# los hijos del pty se reapean solos: sin esto quedaba un zombie por sesion
try:
    signal.signal(signal.SIGCHLD, signal.SIG_IGN)
except Exception:
    pass

HOST_DNS = sys.argv[1]
PORT = int(sys.argv[2])
HTTPS_PORT = int(sys.argv[3])   # puerto HTTPS canonico del host (app-bound)
PASSWORD = open(os.path.expanduser("~/.ivscode/password")).read().strip()
CS_DIR = os.path.expanduser("~/.ivscode/current")
# carpeta compartida host<->maquinas: ~/ivscode-shared en el PC == /shared dentro
SHARED_DIR = os.path.expanduser("~/ivscode-shared")
os.makedirs(SHARED_DIR, exist_ok=True)

# extensiones del host (se copian a cada maquina nueva: nada que descargar)
EXT_DIR = os.path.expanduser("~/.ivscode/extensions")
# comando setup-machine montado dentro de cada maquina
MACHINE_SETUP = os.path.expanduser("~/.ivscode/setup-machine.sh")
# settings por defecto de cada maquina: sin Restricted Mode (mata Jupyter)
SETTINGS_FILE = os.path.expanduser("~/.ivscode/machine-settings.json")
with open(SETTINGS_FILE, "w") as _f:
    json.dump({
        "security.workspace.trust.enabled": False,
        "security.workspace.trust.startupPrompt": "never",
        "security.workspace.trust.untrustedFiles": "open",
        "extensions.ignoreRecommendations": True,
        "window.autoDetectColorScheme": True,
    }, _f)

def _docker_direct_ok():
    # OJO: `docker version --format ok` imprime ok y sale 0 aunque el daemon
    # sea inalcanzable. Hay que tocar el daemon de verdad.
    try:
        return subprocess.run(["docker", "ps", "-q"],
                              capture_output=True, timeout=10).returncode == 0
    except Exception:
        return False

# Si el proceso aun no tiene el grupo docker (usermod posterior al arranque de
# systemd --user), se enruta docker a traves de `sg docker`.
DOCKER_VIA_SG = (sys.platform.startswith("linux")
                 and shutil.which("sg") is not None
                 and not _docker_direct_ok())
IMAGES = {
    "ubuntu": "ubuntu:24.04",
    "debian": "debian:12",
    "fedora": "fedora:41",
    "arch": "archlinux:latest",
}
LABEL = "ivscode.machine"

def _run(args, timeout):
    try:
        r = subprocess.run(args, capture_output=True, text=True, timeout=timeout)
    except FileNotFoundError as e:
        return 127, "", str(e)
    except subprocess.TimeoutExpired:
        return 124, "", "timeout tras %ss" % timeout
    return r.returncode, r.stdout.strip(), r.stderr.strip()

def sh(*args, timeout=600):
    global DOCKER_VIA_SG
    is_docker = args[0] == "docker"
    def via_sg(a):
        return ("sg", "docker", "-c", " ".join(shlex.quote(x) for x in a))
    rc, out, err = _run(via_sg(args) if (is_docker and DOCKER_VIA_SG) else args, timeout)
    # OJO: docker 29 devuelve rc=0 y escribe "permission denied" en stderr, así
    # que el reintento NO puede depender del código de salida.
    if is_docker and not DOCKER_VIA_SG and "permission denied" in err.lower() \
            and shutil.which("sg"):
        DOCKER_VIA_SG = True
        rc, out, err = _run(via_sg(args), timeout)
    return rc, out, err

def machines():
    rc, out, err = sh("docker", "ps", "-a", "--filter", "label=" + LABEL, "--format",
                      '{{.Names}}\t{{.Status}}\t{{.Label "ivscode.port"}}\t{{.Label "ivscode.os"}}')
    if rc != 0 or "permission denied" in err.lower():
        raise RuntimeError((err or "docker no disponible")[-200:])
    result = []
    for line in out.splitlines():
        parts = line.split("\t")
        if len(parts) < 4 or not parts[2].isdigit():
            continue
        name, status, port, osname = parts[:4]
        short = name[5:] if name.startswith("ivsc_") else name
        result.append({
            "name": short,
            "os": osname,
            "status": "running" if status.startswith("Up") else "stopped",
            # misma origin (host:puerto) que el VS Code principal: WebKit solo
            # permite service workers en el dominio/puerto app-bound, asi que
            # cada maquina se monta como RUTA, nunca como puerto propio
            "url": "https://%s:%d/m-%s/" % (HOST_DNS, HTTPS_PORT, short),
            "port": int(port),
        })
    return result

# tmux propio de iVsCode: raton activo (scroll del historial y seleccion),
# historial largo y sin retardo de escape. No toca el ~/.tmux.conf del usuario.
TMUX_CONF = os.path.expanduser("~/.ivscode/tmux.conf")

def _tmux_conf():
    try:
        with open(TMUX_CONF, "w") as f:
            f.write(
                "source-file -q ~/.tmux.conf\n"
                "set -g mouse on\n"
                "set -g history-limit 50000\n"
                "set -sg escape-time 10\n"
                "set -g default-terminal 'xterm-256color'\n"
                "set -ga terminal-overrides ',*256col*:Tc'\n"
            )
    except Exception:
        pass

# portapapeles de archivos entre sesiones (host y maquinas del mismo PC)
STAGE = os.path.expanduser("~/.ivscode/clipboard")

def clip_copy(path, machine):
    machine = valid_machine(machine)
    if not path.startswith("/"):
        raise ValueError("selecciona un archivo en el explorador antes de copiar")
    os.makedirs(STAGE, exist_ok=True)
    for f in os.listdir(STAGE):
        p = os.path.join(STAGE, f)
        shutil.rmtree(p) if os.path.isdir(p) else os.remove(p)
    if machine:
        rc, out, err = sh("docker", "cp", "ivsc_%s:%s" % (machine, path), STAGE + "/")
    else:
        rc, out, err = sh("cp", "-r", path, STAGE + "/")
    if rc != 0:
        raise RuntimeError((err or out)[-200:])
    return os.listdir(STAGE)

def resolve_dest(machine, dest):
    home = "/root" if machine else os.path.expanduser("~")
    d = (dest or "").strip()
    if not d.startswith("/"):
        return home
    if machine:
        rc, out, err = sh("docker", "exec", "ivsc_" + machine, "sh", "-c",
                          '[ -d "$0" ] && echo dir || { [ -e "$0" ] && echo file || echo none; }', d)
        kind = out.strip()
    else:
        kind = "dir" if os.path.isdir(d) else ("file" if os.path.exists(d) else "none")
    if kind == "dir":
        return d
    if kind == "file":
        return os.path.dirname(d) or home
    return home

def clip_paste(machine, dest=""):
    machine = valid_machine(machine)
    items = os.listdir(STAGE) if os.path.isdir(STAGE) else []
    if not items:
        raise RuntimeError("portapapeles de archivos vacio: usa ctrl+opt+C primero")
    target = resolve_dest(machine, dest)
    for f in items:
        src = os.path.join(STAGE, f)
        if machine:
            rc, out, err = sh("docker", "cp", src, "ivsc_%s:%s/" % (machine, target))
        else:
            rc, out, err = sh("cp", "-r", src, target + "/")
        if rc != 0:
            raise RuntimeError((err or out)[-200:])
    return items, target

def valid_machine(m):
    m = (m or "").strip()
    if m and not re.fullmatch(r"[a-zA-Z0-9_-]{1,30}", m):
        raise ValueError("nombre de maquina invalido")
    return m

def fs_list(machine, path):
    machine = valid_machine(machine)
    if path in ("", "~"):
        path = "/root" if machine else os.path.expanduser("~")
    if not path.startswith("/"):
        raise ValueError("ruta invalida")
    entries = []
    if machine:
        rc, out, err = sh("docker", "exec", "ivsc_" + machine, "ls", "-1Ap", "--", path)
        if rc != 0:
            raise RuntimeError((err or out)[-200:] or "no pude listar (maquina apagada?)")
        for line in out.splitlines():
            if line:
                entries.append({"name": line.rstrip("/"), "dir": line.endswith("/")})
    else:
        for name in sorted(os.listdir(path), key=str.lower):
            full = os.path.join(path, name)
            entries.append({"name": name, "dir": os.path.isdir(full)})
    entries.sort(key=lambda e: (not e["dir"], e["name"].lower()))
    return path, entries

def mount(name, port):
    sh("tailscale", "serve", "--bg", "--https=%d" % HTTPS_PORT,
       "--set-path=/m-" + name, "http://127.0.0.1:%d" % port)

def unmount(name):
    sh("tailscale", "serve", "--https=%d" % HTTPS_PORT, "--set-path=/m-" + name, "off")

def free_port():
    used = {m["port"] for m in machines()}
    for p in range(10100, 10200):
        if p not in used:
            return p
    raise RuntimeError("sin puertos libres")

_create_lock = threading.Lock()

def create(name, osname):
    if not re.fullmatch(r"[a-zA-Z0-9_-]{1,30}", name):
        raise ValueError("nombre invalido: usa letras, numeros, - o _")
    if osname not in IMAGES:
        raise ValueError("os invalido; opciones: " + ", ".join(IMAGES))
    # el lock evita que dos creaciones simultaneas elijan el mismo puerto
    with _create_lock:
        _create_locked(name, osname)

def _create_locked(name, osname):
    port = free_port()
    opts = [
        "--name", "ivsc_" + name,
        "--label", LABEL + "=1",
        "--label", "ivscode.port=%d" % port,
        "--label", "ivscode.os=" + osname,
        "-p", "127.0.0.1:%d:8080" % port,
        "-e", "PASSWORD=" + PASSWORD,
        "-v", CS_DIR + ":/opt/code-server:ro",
        "-v", "ivsc_%s_home:/root" % name,
        "-v", SHARED_DIR + ":/shared",
        "-v", MACHINE_SETUP + ":/usr/local/bin/setup-machine:ro",
    ]
    cmd = [IMAGES[osname], "/opt/code-server/bin/code-server",
           "--bind-addr", "0.0.0.0:8080", "--auth", "password", "--disable-telemetry"]
    try:
        # primero con GPU (RTX del host); si el runtime no lo soporta, sin GPU
        rc, out, err = sh("docker", "run", "-d", "--gpus", "all", *opts, *cmd)
        if rc != 0:
            sh("docker", "rm", "-f", "ivsc_" + name)   # limpia el intento fallido
            rc, out, err = sh("docker", "run", "-d", *opts, *cmd)
        if rc != 0:
            raise RuntimeError((err or out)[-400:])
        # verificar que sigue viva: un contenedor que muere al instante (imagen
        # incompatible) devolvia "ok" y aparecia como maquina rota
        rc2, state, _ = sh("docker", "inspect", "-f", "{{.State.Running}}", "ivsc_" + name)
        if rc2 == 0 and state.strip() != "true":
            _, logs, _ = sh("docker", "logs", "--tail", "15", "ivsc_" + name)
            raise RuntimeError("la maquina arranco y murio: " + logs[-300:])
        provision(name)
        mount(name, port)
    except BaseException:
        sh("docker", "rm", "-f", "ivsc_" + name)   # nunca dejar restos a medias
        raise

def provision(name):
    """Deja la maquina lista: extensiones del host + settings sin Restricted Mode."""
    c = "ivsc_" + name
    sh("docker", "exec", c, "mkdir", "-p",
       "/root/.local/share/code-server/extensions",
       "/root/.local/share/code-server/User")
    if os.path.isdir(EXT_DIR):
        sh("docker", "cp", EXT_DIR + "/.", c + ":/root/.local/share/code-server/extensions")
    sh("docker", "cp", SETTINGS_FILE, c + ":/root/.local/share/code-server/User/settings.json")
    # reinicia el code-server interno para que cargue extensiones y settings
    sh("docker", "restart", c)

class Handler(BaseHTTPRequestHandler):
    timeout = 30

    def log_message(self, *a):
        pass

    def _body(self):
        n = min(int(self.headers.get("Content-Length", 0) or 0), 1 << 20)
        return self.rfile.read(n) if n else b"{}"

    def _send(self, code, obj):
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _authed(self):
        if not hmac.compare_digest(self.headers.get("X-Password", ""), PASSWORD):
            self._send(401, {"error": "no autorizado"})
            return False
        return True

    def do_GET(self):
        if not self._authed():
            return
        parsed = urllib.parse.urlparse(self.path)
        try:
            if parsed.path == "/machines":
                self._send(200, {"machines": machines()})
            elif parsed.path == "/fs/list":
                q = urllib.parse.parse_qs(parsed.query)
                machine = (q.get("machine") or [""])[0]
                path = (q.get("path") or ["~"])[0]
                resolved, entries = fs_list(machine, path)
                self._send(200, {"path": resolved, "entries": entries})
            else:
                self._send(404, {"error": "no existe"})
        except Exception as e:
            self._send(500, {"error": str(e)})

    def do_POST(self):
        if not self._authed():
            return
        try:
            if self.path == "/clipboard":
                data = json.loads(self._body() or b"{}")
                op = data.get("op", "")
                machine = data.get("machine", "")
                if op == "copy":
                    files = clip_copy(data.get("path", "").strip(), machine)
                    dest = ""
                elif op == "paste":
                    files, dest = clip_paste(machine, data.get("dest", ""))
                else:
                    raise ValueError("op debe ser copy o paste")
                self._send(200, {"files": files, "dest": dest})
                return
            if self.path == "/machines":
                data = json.loads(self._body() or b"{}")
                create(data.get("name", ""), data.get("os", ""))
                self._send(200, {"ok": True})
                return
            m = re.fullmatch(r"/machines/([a-zA-Z0-9_-]+)/(start|stop)", self.path)
            if not m:
                self._send(404, {"error": "no existe"})
                return
            name, action = m.groups()
            rc, out, err = sh("docker", action, "ivsc_" + name)
            if rc != 0:
                raise RuntimeError((err or out)[-200:])
            if action == "start":
                for mach in machines():
                    if mach["name"] == name:
                        mount(name, mach["port"])
            else:
                unmount(name)
            self._send(200, {"ok": True})
        except Exception as e:
            self._send(500, {"error": str(e)})

    def do_DELETE(self):
        if not self._authed():
            return
        parsed = urllib.parse.urlparse(self.path)
        m = re.fullmatch(r"/machines/([a-zA-Z0-9_-]+)", parsed.path)
        if not m:
            self._send(404, {"error": "no existe"})
            return
        name = m.group(1)
        q = urllib.parse.parse_qs(parsed.query)
        with_volume = (q.get("volume") or ["0"])[0] == "1"
        rc, out, err = sh("docker", "rm", "-f", "ivsc_" + name)
        if rc != 0:
            self._send(500, {"error": (err or out)[-200:]})
            return
        if with_volume:
            sh("docker", "volume", "rm", "ivsc_%s_home" % name)
        unmount(name)
        self._send(200, {"ok": True})

# ---------- servidor PTY para la terminal flotante de la app ----------
# TCP en 127.0.0.1:39600 (expuesto solo en la tailnet via tailscale serve --tcp).
# Protocolo: 1a linea JSON {password, machine, cols, rows}\n; luego bytes pty
# crudos en ambos sentidos. Resize: frame de 10 bytes 0x00 'R' cccc rrrr.
TERM_PORT = 39600

def _term_client(client):
    pid = None
    master = None
    try:
        client.settimeout(15)
        buf = b""
        while b"\n" not in buf:
            d = client.recv(1024)
            if not d:
                return
            buf += d
        line, rest = buf.split(b"\n", 1)
        req = json.loads(line.decode())
        if not hmac.compare_digest(str(req.get("password", "")), PASSWORD):
            time.sleep(1.0)
            client.sendall(b"auth incorrecta\r\n")
            return
        machine = req.get("machine", "")
        cols, rows = int(req.get("cols", 80)), int(req.get("rows", 24))
        if machine:
            if not re.fullmatch(r"[a-zA-Z0-9_-]+", machine):
                return
            argv = ["docker", "exec", "-it", "ivsc_" + machine, "sh", "-lc",
                    "if command -v tmux >/dev/null; then "
                    "printf '%s\\n' 'set -g mouse on' 'set -g history-limit 50000' "
                    "> /tmp/ivscode.tmux.conf; "
                    "exec tmux -f /tmp/ivscode.tmux.conf new-session -A -s ivscode; "
                    "else exec bash -l; fi"]
            if DOCKER_VIA_SG:
                argv = ["sg", "docker", "-c", " ".join(shlex.quote(a) for a in argv)]
        else:
            # con tmux, la sesion sobrevive a desconexiones (reattach automatico)
            if shutil.which("tmux"):
                _tmux_conf()
                argv = ["tmux", "-f", TMUX_CONF, "new-session", "-A", "-s", "ivscode"]
            else:
                argv = [os.environ.get("SHELL", "/bin/bash"), "-l"]
        pid, master = pty.fork()
        if pid == 0:
            os.environ["TERM"] = "xterm-256color"
            os.environ["LANG"] = os.environ.get("LANG", "C.UTF-8")
            os.execvp(argv[0], argv)
            os._exit(1)
        fcntl.ioctl(master, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0))
        client.settimeout(None)
        pend = rest
        if pend and 0 not in pend:
            os.write(master, pend)
            pend = b""
        while True:
            r, _, _ = select.select([client, master], [], [], 120)
            if client in r:
                d = client.recv(4096)
                if not d:
                    break
                data = pend + d
                pend = b""
                out = b""
                i = 0
                while i < len(data):
                    if data[i] == 0:
                        # 0x00 0x00 = un NUL literal del usuario (Ctrl+Espacio)
                        if i + 2 <= len(data) and data[i + 1] == 0:
                            out += b"\x00"
                            i += 2
                            continue
                        if i + 10 <= len(data) and data[i + 1:i + 2] == b"R":
                            try:
                                c2 = int(data[i + 2:i + 6])
                                r2 = int(data[i + 6:i + 10])
                                fcntl.ioctl(master, termios.TIOCSWINSZ,
                                            struct.pack("HHHH", r2, c2, 0, 0))
                                os.kill(pid, signal.SIGWINCH)
                                i += 10
                                continue
                            except Exception:
                                pass
                        elif i + 10 > len(data):
                            pend = data[i:]
                            break
                    out += data[i:i + 1]
                    i += 1
                if out:
                    os.write(master, out)
            if master in r:
                try:
                    d = os.read(master, 8192)
                except OSError:
                    break
                if not d:
                    break
                client.sendall(d)
    except Exception:
        pass
    finally:
        try:
            client.close()
        except Exception:
            pass
        if master is not None:
            try:
                os.close(master)   # sin esto se filtraba un fd por conexion
            except Exception:
                pass
        if pid:
            try:
                os.kill(pid, signal.SIGKILL)
            except Exception:
                pass

def term_server():
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.bind(("127.0.0.1", TERM_PORT))
    s.listen(8)
    while True:
        try:
            c, _ = s.accept()
        except OSError:
            time.sleep(0.5)
            continue
        threading.Thread(target=_term_client, args=(c,), daemon=True).start()

threading.Thread(target=term_server, daemon=True).start()

ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
PYEOF
  if tailscale serve --bg --https=9500 "http://127.0.0.1:$MGR_LOCAL" >/dev/null 2>&1; then
    pkill -f "[m]anager\.py $TS_DNS" 2>/dev/null || true
    sleep 0.3
    ( while true; do
        python3 "$IVSCODE_DIR/manager.py" "$TS_DNS" "$MGR_LOCAL" "$HTTPS_PORT" \
          >>"$IVSCODE_DIR/manager.log" 2>&1
        echo "[$(date '+%F %T')] gestor caído, reiniciando…" >>"$IVSCODE_DIR/manager.log"
        sleep 3
      done ) &
    MGR_PID=$!
    echo "→ Gestor de máquinas Docker: https://${TS_DNS}:9500"
    # canal PTY de la terminal flotante (TCP crudo dentro de la tailnet)
    tailscale serve --bg --tcp=39600 "tcp://127.0.0.1:39600" >/dev/null 2>&1 \
      && echo "→ Terminal PTY: puerto 39600 (tailnet)" \
      || echo "⚠ No pude exponer el puerto 39600 (terminal flotante no disponible)"
  fi
fi

# ---------- resumen de conexión ----------
echo ""
echo "═══════════════════════════════════════════════════"
echo "  iVsCode backend: $NAME"
if [ -t 1 ]; then echo "  Contraseña: $PASSWORD"; else echo "  Contraseña: (en $IVSCODE_DIR/password)"; fi
if [ -n "$CANON_URL" ]; then
  echo "  URL principal (HTTPS, notebooks OK):"
  echo "    $CANON_URL"
fi
echo "  URLs alternativas (http, sin webviews/notebooks):"
if [ "$PLATFORM" = linux ]; then
  for ip in $(hostname -I 2>/dev/null); do echo "    http://$ip:$PORT"; done
else
  for ip in $(ifconfig 2>/dev/null | awk '/inet / && $2 != "127.0.0.1" {print $2}'); do
    echo "    http://$ip:$PORT"
  done
fi
if command -v tailscale >/dev/null 2>&1; then
  TS_IP=$(tailscale ip -4 2>/dev/null | head -1 || true)
  [ -n "$TS_IP" ] && echo "    http://$TS_IP:$PORT  (tailscale, desde fuera de casa)"
fi
echo "  La app iVsCode lo detectará sola en esta red."
echo "═══════════════════════════════════════════════════"
echo ""

PASSWORD="$PASSWORD" "$IVSCODE_DIR/current/bin/code-server" \
  --bind-addr "0.0.0.0:$PORT" \
  --auth password \
  --extensions-dir "$EXT_DIR" \
  --disable-telemetry
