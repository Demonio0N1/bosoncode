#!/usr/bin/env bash
# setup — deja este equipo listo para BosonCode, de una sola pasada.
#
#   ./setup.sh                instala lo que falte y deja el servidor puesto
#                             para siempre: sobrevive a cerrar la terminal y
#                             arranca solo al encender el equipo
#   ./setup.sh --foreground   lo arranca aquí y ahora, atado a esta terminal
#   ./setup.sh --check        solo diagnostica, no toca nada
#   ./setup.sh --password     enseña la contraseña de este equipo
#   ./setup.sh --uninstall    quita el servicio y lo descargado (no tu código)
#                             añade --purge para llevarse también tus ajustes
#                             del editor, y -y para no preguntar
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
EN_PRIMER_PLANO=0
VER_PASSWORD=0
DESINSTALAR=0
PURGAR=0
SIN_PREGUNTAR=0
for arg in "$@"; do
  case "$arg" in
    --check) SOLO_COMPROBAR=1 ;;
    --password|--contrasena|--contraseña) VER_PASSWORD=1 ;;
    --foreground|--fg|--primer-plano) EN_PRIMER_PLANO=1 ;;
    --uninstall|--desinstalar) DESINSTALAR=1 ;;
    --purge|--purgar) PURGAR=1 ;;
    -y|--yes|--si|--sí) SIN_PREGUNTAR=1 ;;
    # Ya no hace falta: es lo que hace ./setup.sh a secas. Se acepta en
    # silencio para no romper a quien lo tenga escrito en una nota o un alias.
    --service|--install-service) ;;
    -h|--help) sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
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

# ---------- --uninstall: quitar lo que puso este script y salir ----------
# Todo lo que instala vive en sitios propios, así que se puede deshacer entero.
# Lo que NO se toca importa tanto como lo que sí: el código del usuario está en
# su carpeta personal y no pasa por aquí, y la sesión de Tailscale es suya y le
# sirve para otras cosas.
if [ "$DESINSTALAR" = 1 ]; then
  titulo "BosonCode · desinstalando de $(hostname)"

  # La lista antes de tocar nada: borrar cosas de la carpeta personal de alguien
  # sin enseñarle qué se va es la clase de favor que nadie agradece.
  nota "se va a borrar:"
  nota "  · el servicio, para que deje de arrancar solo"
  nota "  · ~/.ivscode — code-server, extensiones y la contraseña de este equipo"
  nota "  · la publicación HTTPS de Tailscale"
  if [ "$PURGAR" = 1 ]; then
    nota "  · ~/.local/share/code-server y ~/.config/code-server — TUS ajustes"
  fi
  nota "NO se toca: tu código, tu sesión de Tailscale, ni Tailscale."
  [ "$PURGAR" = 1 ] || \
    nota "para llevarse también los ajustes del editor:  --uninstall --purge"

  if [ "$SIN_PREGUNTAR" != 1 ]; then
    printf '\n  ¿Sigo? [s/N] '
    read -r RESPUESTA || RESPUESTA=""
    case "$RESPUESTA" in
      s|S|si|Si|SI|sí|Sí|SÍ|y|Y|yes) ;;
      *) echo "  No he tocado nada."; exit 0 ;;
    esac
  fi
  echo ""

  if [ "$PLATAFORMA" = linux ]; then
    if systemctl --user show-environment >/dev/null 2>&1; then
      systemctl --user stop ivscode 2>/dev/null || true
      systemctl --user disable ivscode 2>/dev/null || true
      rm -rf "$HOME/.config/systemd/user/ivscode.service" \
             "$HOME/.config/systemd/user/ivscode.service.d"
      systemctl --user daemon-reload 2>/dev/null || true
      ok "servicio quitado"
    else
      nota "sin systemd de usuario: no había servicio que quitar"
    fi
  else
    PLIST="$HOME/Library/LaunchAgents/com.ivscode.serve.plist"
    if [ -f "$PLIST" ]; then
      launchctl bootout "gui/$(id -u)/com.ivscode.serve" 2>/dev/null \
        || launchctl unload "$PLIST" 2>/dev/null || true
      rm -f "$PLIST"
      ok "LaunchAgent quitado"
    else
      nota "no había LaunchAgent"
    fi

    APP="$HOME/Applications/BosonCode Server.app"
    if [ -d "$APP" ]; then
      rm -rf "$APP"
      ok "aplicación quitada"
      # El permiso de disco no se puede retirar desde aquí: la lista de Ajustes
      # es del sistema y solo la toca su dueño. Se avisa en vez de dejar una
      # entrada muerta ahí para siempre.
      nota "queda su entrada en Ajustes → Privacidad → Acceso total al disco;"
      nota "puedes borrarla tú con el botón −"
    fi
  fi

  # `serve reset` necesita el mismo permiso que `serve`: si no lo hay, no es un
  # problema — significa que tampoco llegó a publicarse nada.
  TS_BIN="$(command -v tailscale 2>/dev/null || echo /Applications/Tailscale.app/Contents/MacOS/Tailscale)"
  if [ -x "$TS_BIN" ] && "$TS_BIN" serve reset >/dev/null 2>&1; then
    ok "publicación HTTPS de Tailscale borrada"
  else
    nota "no había publicación de Tailscale que borrar"
  fi

  rm -rf "$HOME/.ivscode"
  ok "~/.ivscode borrado"

  if [ "$PURGAR" = 1 ]; then
    rm -rf "$HOME/.local/share/code-server" "$HOME/.config/code-server"
    ok "ajustes del editor borrados"
  fi

  titulo "Desinstalado"
  nota "para volver a instalarlo:  ./setup.sh"
  nota "en el iPad, borra la tarjeta de este equipo antes de añadirla otra vez:"
  nota "la contraseña se genera de cero y la vieja ya no vale."
  echo ""
  exit 0
fi

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

# `tailscale serve` —lo que publica el HTTPS— exige ser root o el usuario
# marcado como operador. Sin ese permiso serve.sh falla más adelante y el equipo
# queda sin notebooks, sin gestor de máquinas y sin terminal: se veía el aviso al
# final de una instalación por lo demás correcta, y había que arreglarlo a mano.
#
# Se comprueba y se concede AQUÍ, mientras la terminal es interactiva y pedir la
# contraseña de sudo tiene sentido. Dentro de serve.sh sería pedirla en mitad del
# arranque, o peor, en un servicio donde no hay nadie para contestarla.
#
# La comprobación es el propio `serve status`: si responde, ya hay permiso y no
# se molesta a nadie; si no, es justo lo que va a fallar luego.
if [ "$PLATAFORMA" = linux ] && ! "$TS" serve status >/dev/null 2>&1; then
  USUARIO="$(id -un)"
  if [ "$SOLO_COMPROBAR" = 1 ]; then
    falta "sin permiso para publicar HTTPS"
    nota "ejecuta:  sudo $TS set --operator=$USUARIO"
  elif sudo -n true 2>/dev/null || [ -t 0 ]; then
    nota "falta el permiso para publicar HTTPS; te pido sudo una vez"
    if sudo "$TS" set --operator="$USUARIO" >/dev/null 2>&1; then
      ok "permiso concedido a $USUARIO"
    else
      falta "no pude conceder el permiso"
      nota "hazlo a mano:  sudo $TS set --operator=$USUARIO"
    fi
  else
    falta "sin permiso para publicar HTTPS y sin terminal donde pedir sudo"
    nota "ejecuta:  sudo $TS set --operator=$USUARIO"
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

# Como servicio por defecto, y en primer plano solo si se pide.
#
# Antes era al revés y era la elección equivocada. Dejarlo en primer plano ata
# el servidor a la terminal que lo lanzó: cierras esa ventana y el iPad pierde
# el editor, el terminal y los notebooks de golpe, sin ninguna pista de por qué.
# Y un equipo que sirve a otro dispositivo se espera que siga sirviendo cuando
# nadie lo mira — que es justo lo que hace un servicio.
#
# `--foreground` conserva el comportamiento de antes, que sigue siendo el bueno
# para depurar: se ven los registros según salen.
if [ "$EN_PRIMER_PLANO" = 1 ]; then
  nota "en primer plano: se para al cerrar esta terminal"
  nota "para dejarlo permanente:  ./setup.sh"
  echo ""
  exec ./serve.sh
fi

# systemd de usuario no está en todas partes: WSL sin systemd es el caso
# habitual. Si no lo hay, no se puede instalar el servicio, así que se avisa y
# se sigue en primer plano en lugar de fallar.
SIRVE_SERVICIO=1
if [ "$PLATAFORMA" = linux ] && ! systemctl --user show-environment >/dev/null 2>&1; then
  SIRVE_SERVICIO=0
fi

if [ "$SIRVE_SERVICIO" = 1 ]; then
  nota "se instala como servicio: sigue vivo al cerrar la terminal y arranca al encender"
  exec ./serve.sh --install-service
else
  falta "aquí no hay systemd de usuario, no puedo dejarlo permanente"
  nota "en WSL: pon systemd=true en /etc/wsl.conf, y luego  wsl --shutdown"
  nota "mientras tanto arranca en primer plano: NO cierres esta terminal"
  echo ""
  exec ./serve.sh
fi
