#!/usr/bin/env bash
# setup — deja este equipo listo para BosonCode, de una sola pasada.
#
#   ./setup.sh              instala lo que falte y arranca el servidor
#   ./setup.sh --service    además, que arranque solo al encender
#   ./setup.sh --check      solo diagnostica, no toca nada
#   ./setup.sh --password   enseña la contraseña de este equipo
#
# Instala Tailscale si falta, comprueba que la sesión esté iniciada, deja
# code-server en marcha y anuncia el equipo para que la app lo encuentre sin
# escribir ninguna dirección.
#
# Es deliberadamente conversador: cada paso dice qué va a hacer ANTES de
# hacerlo, y lo que necesita permisos de administrador lo avisa. Un instalador
# que se limita a callar y fallar al final es peor que no tenerlo.

set -euo pipefail
cd "$(dirname "$0")"

SOLO_COMPROBAR=0
COMO_SERVICIO=0
VER_PASSWORD=0
for arg in "$@"; do
  case "$arg" in
    --check) SOLO_COMPROBAR=1 ;;
    --password|--contrasena|--contraseña) VER_PASSWORD=1 ;;
    --service|--install-service) COMO_SERVICIO=1 ;;
    -h|--help) sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "opción desconocida: $arg (usa --help)"; exit 1 ;;
  esac
done

# ---------- presentación ----------
verde()  { printf '\033[32m%s\033[0m\n' "$*"; }
rojo()   { printf '\033[31m%s\033[0m\n' "$*"; }
gris()   { printf '\033[90m%s\033[0m\n' "$*"; }
titulo() { printf '\n\033[1m%s\033[0m\n' "$*"; }
ok()     { verde "  ✓ $*"; }
falta()  { rojo  "  ✗ $*"; }
nota()   { gris  "    $*"; }

# ---------- --password: enseñarla y salir ----------
# La primera vez la imprime el arranque, pero eso fue hace semanas. Cuando
# reinstalas la app o añades un iPad, la pregunta es siempre la misma —¿cuál
# era?— y la respuesta estaba enterrada en un README.
if [ "${VER_PASSWORD:-0}" = 1 ]; then
  ARCHIVO="$HOME/.ivscode/password"
  if [ ! -f "$ARCHIVO" ]; then
    echo "Todavía no hay contraseña: este equipo no se ha preparado."
    echo "Ejecuta ./setup.sh y se generará una."
    exit 1
  fi
  # El nombre importa tanto como la contraseña: es lo que se escribe en la app.
  # Darle solo la contraseña obliga a buscar el nombre en otro sitio.
  # El nombre y la DIRECCIÓN completa, no solo la contraseña: son las tres
  # cosas que hay que teclear, y tenerlas repartidas obliga a buscar.
  TS_BIN="$(command -v tailscale 2>/dev/null || echo /Applications/Tailscale.app/Contents/MacOS/Tailscale)"
  TS_DNS="$("$TS_BIN" status --json 2>/dev/null | sed -n 's/.*"DNSName"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
  TS_DNS="${TS_DNS%.}"
  TS_NOMBRE="${TS_DNS%%.*}"
  TS_PUERTO="$("$TS_BIN" serve status 2>/dev/null | sed -n "s#^https://[^:]*:\([0-9]*\).*#\1#p" | head -1)"
  case "$TS_PUERTO" in ''|*[!0-9]*) TS_PUERTO=9443 ;; esac
  printf '\n  \033[1mPara añadir este equipo en BosonCode\033[0m\n\n'
  [ -n "$TS_DNS" ] && printf '      Dirección:   \033[1;36mhttps://%s:%s\033[0m\n' "$TS_DNS" "$TS_PUERTO"
  [ -n "$TS_NOMBRE" ] && printf '      Nombre:      \033[1;36m%s\033[0m\n' "$TS_NOMBRE"
  printf '      Contraseña:  \033[1;36m%s\033[0m\n\n' "$(cat "$ARCHIVO")"
  printf '  \033[90mEn la app: Añadir → pega la dirección (o solo el nombre) → la contraseña.\n'
  printf '  Se guarda en el Llavero del iPad y no vuelve a pedirse.\033[0m\n\n'
  exit 0
fi

case "$(uname -s)" in
  Darwin) PLATAFORMA=macos ;;
  Linux)  PLATAFORMA=linux ;;
  *) rojo "Este script es para macOS y Linux. Detectado: $(uname -s)"; exit 1 ;;
esac

titulo "BosonCode · preparando $(hostname)"
gris "Sistema: $PLATAFORMA"

# ---------- 1. Tailscale ----------
# Va primero porque todo lo demás depende de él: sin red privada no hay HTTPS,
# y sin HTTPS el editor pierde los notebooks y las vistas web.
buscar_tailscale() {
  command -v tailscale 2>/dev/null && return
  for c in /Applications/Tailscale.app/Contents/MacOS/Tailscale \
           /opt/homebrew/bin/tailscale /usr/local/bin/tailscale \
           "$HOME/Applications/Tailscale.app/Contents/MacOS/Tailscale"; do
    [ -x "$c" ] && { echo "$c"; return; }
  done
  return 1
}

titulo "1 · Tailscale"
TS="$(buscar_tailscale || true)"

if [ -z "$TS" ]; then
  falta "no está instalado"
  if [ "$SOLO_COMPROBAR" = 1 ]; then
    nota "instálalo y vuelve a ejecutar este script"
  elif [ "$PLATAFORMA" = macos ]; then
    if command -v brew >/dev/null 2>&1; then
      nota "instalando con Homebrew…"
      brew install --cask tailscale-app 2>/dev/null || brew install --cask tailscale
      TS="$(buscar_tailscale || true)"
    else
      nota "necesitas Homebrew (https://brew.sh) o la app desde https://tailscale.com/download"
      exit 1
    fi
  else
    # El instalador oficial de Tailscale. Se enseña el comando antes de
    # ejecutarlo: descargar un script y correrlo con sudo no es algo que deba
    # pasar sin que lo veas.
    nota "voy a ejecutar el instalador oficial de Tailscale:"
    nota "  curl -fsSL https://tailscale.com/install.sh | sh"
    printf '    ¿Seguir? [S/n] '
    read -r respuesta </dev/tty || respuesta=s
    case "${respuesta:-s}" in
      [nN]*) nota "de acuerdo; instálalo a mano y vuelve a ejecutar esto"; exit 1 ;;
    esac
    curl -fsSL https://tailscale.com/install.sh | sh
    TS="$(buscar_tailscale || true)"
  fi
fi

[ -n "$TS" ] || { falta "sigo sin encontrar tailscale"; exit 1; }
ok "instalado ($TS)"

# ---------- 2. sesión de Tailscale ----------
titulo "2 · Sesión de Tailscale"
if "$TS" status >/dev/null 2>&1; then
  DNS="$("$TS" status --json 2>/dev/null | sed -n 's/.*"DNSName"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
  ok "sesión iniciada${DNS:+ · $DNS}"
else
  falta "sin sesión iniciada"
  if [ "$SOLO_COMPROBAR" = 1 ]; then
    nota "ejecuta: $TS up"
  else
    nota "abriendo el inicio de sesión; termínalo en el navegador y vuelve aquí"
    if [ "$PLATAFORMA" = linux ]; then sudo "$TS" up; else "$TS" up; fi
    ok "sesión iniciada"
  fi
fi

nota "Instala Tailscale también en el iPad y entra con la MISMA cuenta:"
nota "  https://apps.apple.com/app/tailscale/id1470499037"
nota "Sin eso, el iPad y este equipo no se ven: es lo que sustituye a abrir puertos."

# ---------- 3. lo que aporta el propio proyecto ----------
titulo "3 · Servidor"
if [ ! -x ./serve.sh ]; then
  falta "no encuentro serve.sh junto a este script"
  nota "ejecútalo desde la carpeta del repositorio"
  exit 1
fi
ok "serve.sh presente"
nota "instala code-server si falta, publica HTTPS por Tailscale y anuncia el equipo"

# ---------- 4. extras según la plataforma ----------
titulo "4 · Simulador"
if [ "$PLATAFORMA" = macos ]; then
  if [ -x /Applications/Xcode.app/Contents/Developer/usr/bin/simctl ]; then
    ok "Xcode: los simuladores de iOS se verán en la app"
    if command -v idb >/dev/null 2>&1; then
      ok "idb: además podrás tocarlos"
    else
      falta "idb: podrás ver el simulador, pero no tocarlo"
      nota "para activarlo:  ./serve.sh --install-idb"
    fi
  else
    gris "  · sin Xcode: no habrá simuladores de iOS (es normal si no desarrollas para iPhone)"
  fi
else
  gris "  · el simulador de iOS es de Apple y no existe en Linux"
fi
# adb rara vez está en el PATH: se instala con el SDK, que vive en el home. Se
# busca donde de verdad queda, igual que hace el gestor — decir "no está" cuando
# sí está manda a reinstalar algo que ya tienes.
buscar_adb() {
  command -v adb 2>/dev/null && return
  for c in "$HOME/Android/Sdk/platform-tools/adb" \
           "$HOME/Library/Android/sdk/platform-tools/adb" \
           /opt/homebrew/bin/adb /usr/local/bin/adb; do
    [ -x "$c" ] && { echo "$c"; return; }
  done
  return 1
}
ADB="$(buscar_adb || true)"
if [ -n "$ADB" ]; then
  ok "adb: los dispositivos y emuladores Android se verán en la app"
  BIN_ADB="$(dirname "$ADB")"
  case ":$PATH:" in
    *":$BIN_ADB:"*) ;;
    *)
      # Avisar no basta. El servicio arranca al encender el equipo y NO hereda
      # el PATH de tu shell, así que aunque `adb` te funcione al escribirlo, el
      # gestor no lo ve y la ventana del simulador sale vacía. Lo comprobamos:
      # tras una instalación limpia, Android desaparecía.
      if [ "$PLATAFORMA" = linux ] && [ "$SOLO_COMPROBAR" = 0 ]; then
        SDK="$(cd "$BIN_ADB/.." && pwd)"
        mkdir -p "$HOME/.config/systemd/user/ivscode.service.d"
        cat > "$HOME/.config/systemd/user/ivscode.service.d/android.conf" <<CONF
[Service]
Environment=ANDROID_HOME=$SDK
Environment=ANDROID_SDK_ROOT=$SDK
Environment=PATH=$BIN_ADB:$SDK/emulator:$HOME/.jdk/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
CONF
        systemctl --user daemon-reload 2>/dev/null || true
        nota "estaba fuera del PATH; añadido al entorno del servicio"
      else
        nota "está fuera del PATH ($ADB); si la app no ve Android, añádelo a ~/.profile"
      fi
      # y para tu propia shell, que es donde lo escribirás a mano
      if ! grep -q "$BIN_ADB" "$HOME/.profile" 2>/dev/null && [ "$SOLO_COMPROBAR" = 0 ]; then
        echo "export PATH=\"$BIN_ADB:\$PATH\"" >> "$HOME/.profile"
      fi
      ;;
  esac
else
  gris "  · sin adb: no habrá Android (ver README si lo quieres)"
fi

if [ "$SOLO_COMPROBAR" = 1 ]; then
  titulo "Comprobación terminada"
  gris "No he tocado nada. Ejecuta ./setup.sh sin --check para instalar."
  exit 0
fi

# ---------- 5. arrancar ----------
titulo "5 · Arrancando"
if [ "$COMO_SERVICIO" = 1 ]; then
  nota "se instalará como servicio: arrancará solo al encender el equipo"
  exec ./serve.sh --install-service
else
  nota "para que arranque solo al encender:  ./setup.sh --service"
  echo ""
  exec ./serve.sh
fi
