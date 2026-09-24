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
#   Claude Sessions Monitor (opcional; se ofrece después de arrancar el editor):
#   ./setup.sh --csm          lo instala sin preguntar
#   ./setup.sh --no-csm       se salta ese paso
#   ./setup.sh -y             dice que sí a todo, CSM incluido
#   ./setup.sh --uninstall --csm   al desinstalar, quita también CSM
#
#   Asistente de IA en el editor (opcional; se ofrece al final):
#   ./setup.sh --ai continue  Continue: asistente abierto, con tu propio modelo
#   ./setup.sh --ai copilot   GitHub Copilot (necesita una cuenta con Copilot)
#   ./setup.sh --no-ai        se salta ese paso      (con -y se elige Continue)
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
# preguntar | si | no. «si» con --uninstall significa «quítalo también».
CSM_MODO=preguntar
# preguntar | continue | copilot | no
IA_MODO=preguntar
# `--ai` lleva el valor en el argumento siguiente (o pegado con «=»). El bucle
# va de uno en uno, así que se recuerda que el próximo es ese valor.
ESPERA_IA=0
elegir_ia() {
  case "$1" in
    continue|Continue) IA_MODO=continue ;;
    copilot|Copilot|github-copilot) IA_MODO=copilot ;;
    no|ninguno|none) IA_MODO=no ;;
    *) echo "--ai: «$1» no es una opción (continue, copilot o ninguno)"; exit 1 ;;
  esac
}
for arg in "$@"; do
  if [ "$ESPERA_IA" = 1 ]; then
    ESPERA_IA=0; elegir_ia "$arg"; continue
  fi
  case "$arg" in
    --check) SOLO_COMPROBAR=1 ;;
    --password|--contrasena|--contraseña) VER_PASSWORD=1 ;;
    --foreground|--fg|--primer-plano) EN_PRIMER_PLANO=1 ;;
    --uninstall|--desinstalar) DESINSTALAR=1 ;;
    --purge|--purgar) PURGAR=1 ;;
    -y|--yes|--si|--sí) SIN_PREGUNTAR=1 ;;
    --csm) CSM_MODO=si ;;
    --no-csm) CSM_MODO=no ;;
    --ai) ESPERA_IA=1 ;;
    --ai=*) elegir_ia "${arg#--ai=}" ;;
    --no-ai) IA_MODO=no ;;
    # Ya no hace falta: es lo que hace ./setup.sh a secas. Se acepta en
    # silencio para no romper a quien lo tenga escrito en una nota o un alias.
    --service|--install-service) ;;
    # Hasta el párrafo de filosofía, no hasta una línea fija: con un número
    # fijo, cada opción nueva que se documentaba dejaba la ayuda cortada.
    -h|--help) awk 'NR > 1 && /^# Es deliberadamente/ { exit }
                    NR > 1 { sub(/^# ?/, ""); print }' "$0"; exit 0 ;;
    *) echo "opción desconocida: $arg (usa --help)"; exit 1 ;;
  esac
done
[ "$ESPERA_IA" = 1 ] && { echo "--ai necesita un valor: continue, copilot o ninguno"; exit 1; }

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
  # Sin puerto publicado no hay dirección que dar. Poner 9443 «por si acaso»
  # era peor que no poner nada: la app intentaba conectarse a algo que no
  # existe y el fallo aparecía lejos de su causa.
  PUBLICADO=1
  case "$TS_PUERTO" in ''|*[!0-9]*) TS_PUERTO=""; PUBLICADO=0 ;; esac
  printf '\n  \033[1mPara añadir este equipo en BosonCode\033[0m\n\n'
  # Los tres campos SEGUIDOS, y la explicación después.
  #
  # La nota de «todavía no hay» se colaba entre la dirección y el nombre, y
  # partía en dos la única tabla que se viene a leer.
  if [ "$PUBLICADO" = 1 ] && [ -n "$TS_DNS" ]; then
    printf '      Dirección:   \033[1;36mhttps://%s:%s\033[0m\n' "$TS_DNS" "$TS_PUERTO"
  else
    printf '      Dirección:   \033[1;33mtodavía no hay\033[0m\n'
  fi
  [ -n "$TS_NOMBRE" ] && printf '      Nombre:      \033[1;36m%s\033[0m\n' "$TS_NOMBRE"
  printf '      Contraseña:  \033[1;36m%s\033[0m\n\n' "$(cat "$ARCHIVO")"

  if [ "$PUBLICADO" = 0 ]; then
    printf '  \033[90mLa contraseña ya vale; lo que falta es el HTTPS de Tailscale.\n'
    printf '  Para ver por qué:  ./setup.sh --check\033[0m\n\n'
  else
    printf '  \033[90mEn la app: Añadir → pega la dirección (o solo el nombre) → la contraseña.\n'
    printf '  Se guarda en el Llavero del iPad y no vuelve a pedirse.\033[0m\n\n'
  fi
  exit 0
fi

# Ejecuta algo con límite de tiempo, sin depender de `timeout`, que es de
# coreutils y en macOS no viene. Hace falta porque `tailscale serve` se cuelga
# esperando un certificado cuando la tailnet no lo va a emitir.
con_limite() {
  local segundos="$1"; shift
  "$@" &
  local hijo=$!
  ( sleep "$segundos"; kill -TERM "$hijo" 2>/dev/null ) &
  local vigia=$!
  wait "$hijo" 2>/dev/null
  local rc=$?
  kill "$vigia" 2>/dev/null
  wait "$vigia" 2>/dev/null || true
  return "$rc"
}

# Deja el HTTPS de Tailscale publicando, guiando lo que no se puede automatizar.
#
# Habilitar Serve es un permiso de la CUENTA y se concede desde el navegador:
# ningún script puede pulsar ese botón. Lo que sí puede es reconocer el caso,
# dar el enlace exacto —que tailscale genera para este equipo— y esperar a que
# se haga para reintentar solo, en vez de rendirse y dejar el servidor a medias.
#
# Se descubrió instalando en una tailnet recién creada: Serve viene apagado de
# fábrica, así que le pasa a TODO el que empieza.
asegurar_serve() {
  local intentos=0 salida enlace
  while [ "$intentos" -lt 4 ]; do
    if salida="$(con_limite 25 "$TS" serve --bg --https=9443 \
                             "http://127.0.0.1:${PUERTO_EDITOR:-8443}" 2>&1)"; then
      ok "publicando por HTTPS"
      return 0
    fi

    if printf '%s' "$salida" | grep -qi "serve is not enabled"; then
      enlace="$(printf '%s' "$salida" \
        | sed -n 's#.*\(https://login\.tailscale\.com/f/serve[^ ]*\).*#\1#p' | head -1)"
      falta "Serve no está habilitado en esta cuenta de Tailscale"
      nota "es un ajuste de la CUENTA, no de este equipo, y es un clic:"
      [ -n "$enlace" ] && printf '\n      %s\n\n' "$enlace"
      if [ -t 0 ] && [ -e /dev/tty ]; then
        printf '    Ábrelo, habilítalo y pulsa Intro para reintentar (Ctrl-C para dejarlo): '
        read -r _ </dev/tty || return 1
      else
        nota "vuelve a ejecutar ./setup.sh cuando lo hayas habilitado"
        return 1
      fi

    elif printf '%s' "$salida" | grep -qiE "access denied|operator"; then
      falta "tailscale no deja configurar serve a este usuario"
      nota "se arregla una sola vez:  sudo tailscale set --operator=$(id -un)"
      sudo "$TS" set --operator="$(id -un)" || return 1
      ok "operador configurado"

    else
      falta "tailscale serve no pudo publicar"
      printf '%s\n' "$salida" | head -4 | sed 's/^/      /'
      nota "si insiste, revisa MagicDNS y HTTPS Certificates:"
      nota "  https://login.tailscale.com/admin/dns"
      return 1
    fi
    intentos=$((intentos + 1))
  done
  return 1
}

# Lo que hay publicado en Tailscale, separado en lo que puso BosonCode y lo
# demás. Lee `tailscale serve status --json` por la entrada y escribe una línea
# por publicación, separada por tabuladores:
#
#   quitar <TAB> argumentos para `tailscale serve … off` <TAB> descripción
#   dejar  <TAB>                                         <TAB> descripción
#
# Existe porque `--uninstall` hacía `tailscale serve reset`, que borra TODA la
# publicación del equipo: también lo que otras herramientas hubieran puesto
# —un Funnel de otro proyecto, por ejemplo—, que no es nuestro y que el usuario
# no esperaba perder al desinstalar un editor.
#
# Qué se reconoce como nuestro, y por qué (son las reglas de serve.sh):
#   · TCP 39600 → 127.0.0.1:39600        el canal PTY del terminal
#   · lo que apunta a 127.0.0.1:39500    el gestor de máquinas
#   · rutas /m-<n> → 127.0.0.1:101xx     las máquinas Docker
#   · https P → 127.0.0.1:(P-1000), con code-server en 8443–8999: el editor.
#     serve.sh publica siempre el HTTPS mil puertos por encima de code-server.
#     El rango evita confundir cualquier otro par que por casualidad se lleve
#     1000.
#   · https → un puerto donde escucha un proceso de ~/.ivscode: también el
#     editor, aunque el HTTPS se hubiera movido por estar ocupado.
# Lo que no encaja en ninguna, se deja. Ante la duda, no se borra.
publicaciones_ts() {
  python3 -c "$(cat <<'PY'
import json, re, subprocess, sys

try:
    cfg = json.load(sys.stdin)
except Exception:
    cfg = {}

def comando_que_escucha(puerto):
    """Comando del proceso que escucha en ese puerto, o '' si no se sabe."""
    pid = ""
    try:
        pid = subprocess.run(["lsof", "-nP", "-t", f"-iTCP:{puerto}", "-sTCP:LISTEN"],
                             capture_output=True, text=True, timeout=5).stdout.split()[0]
    except Exception:
        try:  # Linux sin lsof: ss dice el pid
            out = subprocess.run(["ss", "-ltnpH", f"sport = :{puerto}"],
                                 capture_output=True, text=True, timeout=5).stdout
            m = re.search(r"pid=(\d+)", out)
            pid = m.group(1) if m else ""
        except Exception:
            pass
    if not pid:
        return ""
    try:
        return subprocess.run(["ps", "-o", "command=", "-p", pid],
                              capture_output=True, text=True, timeout=5).stdout
    except Exception:
        return ""

def linea(accion, args, texto):
    print(f"{accion}\t{args}\t{texto}")

for puerto, tcp in (cfg.get("TCP") or {}).items():
    destino = (tcp or {}).get("TCPForward")
    if not destino:
        continue  # los puertos HTTPS también salen aquí; se tratan abajo
    if puerto == "39600" and destino.endswith(":39600"):
        linea("quitar", f"--tcp={puerto}", f"tcp :{puerto} → {destino} · terminal de BosonCode")
    else:
        linea("dejar", "", f"tcp :{puerto} → {destino}")

embudo = cfg.get("AllowFunnel") or {}
for anfitrion, web in (cfg.get("Web") or {}).items():
    puerto = anfitrion.rsplit(":", 1)[1] if ":" in anfitrion else "443"
    publico = " (Funnel: abierto a internet)" if embudo.get(anfitrion) else ""
    for ruta, h in ((web or {}).get("Handlers") or {}).items():
        destino = h.get("Proxy") or h.get("Path") or ("texto" if "Text" in h else "?")
        m = re.match(r"https?://(?:127\.0\.0\.1|localhost):(\d+)", destino)
        p = int(m.group(1)) if m else None
        motivo = None
        if p == 39500:
            motivo = "gestor de máquinas de BosonCode"
        elif ruta.startswith("/m-") and p and 10100 <= p < 10200:
            motivo = f"máquina Docker «{ruta[3:]}» de BosonCode"
        elif ruta == "/" and p and 8443 <= p < 9000 and puerto.isdigit() and int(puerto) == p + 1000:
            motivo = f"editor de BosonCode (code-server :{p})"
        elif ruta == "/" and p and "/.ivscode/" in comando_que_escucha(p):
            motivo = f"editor de BosonCode (code-server :{p})"
        texto = f"https :{puerto}{ruta} → {destino}"
        if motivo:
            linea("quitar", f"--https={puerto} --set-path={ruta}", f"{texto} · {motivo}")
        else:
            linea("dejar", "", texto + publico)
PY
)"
}

# ---------- Claude Sessions Monitor ----------
# CSM es un proyecto hermano: un panel web con las sesiones de Claude Code de
# todas tus máquinas en una sola página, que también deja contestarles desde el
# móvil. BosonCode no lo necesita. Se ofrece aquí porque quien prepara un
# equipo para programar desde el iPad suele quererlo también, y este es el
# momento más barato: la terminal está abierta y Tailscale recién configurado.
#
# El código se descarga en ~/.ivscode/csm, junto a lo demás que trae este
# script. Lo que CSM instala —el hub en ~/.local/share/csm-hub, el agente en
# ~/.local/bin— lo pone su PROPIO setup.sh: aquí no se duplica nada de eso. Se
# le llama y se le deja hacer su pregunta (¿panel propio o sumarse al de otra
# máquina?), que solo él sabe responder bien porque busca los paneles que ya
# hay en la tailnet.
#
# CSM_REPO se puede cambiar para probar un fork; CSM_PORT es el mismo que usa
# el propio CSM.
CSM_REPO="${CSM_REPO:-https://github.com/Demonio0N1/claude-sessions-monitor.git}"
CSM_DIR="$HOME/.ivscode/csm"
CSM_PUERTO="${CSM_PORT:-4000}"
CSM_RESULTADO=""   # instalado | ya-estaba | fallo | saltado

# Puerto del agente: el que dejó escrito en su configuración, 8787 si no dice.
csm_puerto_agente() {
  local p
  p="$(sed -n 's/.*"hookPort"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/p' \
         "$HOME/.config/csm/agent.json" 2>/dev/null | head -1 || true)"
  echo "${p:-8787}"
}

# ¿Hay algo de CSM en este equipo, corra o no?
csm_instalado() {
  [ -d "$HOME/.local/share/csm-hub" ] || [ -f "$HOME/.config/csm/agent.json" ] \
    || [ -x "$HOME/.local/bin/csm-agent" ]
}

# Qué hay corriendo: «hub» (panel propio, que ya trae su agente), «agente»
# (esta máquina reporta al panel de otra) o nada.
#
# Se exigen las dos cosas —estar instalado Y responder— porque cada una sola
# engaña: el 4000 es un puerto popular y puede ser cualquier otro servidor de
# desarrollo, y los archivos pueden quedar de una instalación cuyo servicio ya
# no arranca. Decir «ya está» en cualquiera de esos casos dejaría al usuario
# sin CSM y convencido de tenerlo.
csm_estado() {
  if [ -d "$HOME/.local/share/csm-hub" ] &&
     curl -fsS -m 2 "http://127.0.0.1:$CSM_PUERTO/api/ping" 2>/dev/null | grep -q '"csm":true'; then
    echo hub
  elif [ -f "$HOME/.config/csm/agent.json" ] &&
       curl -fsS -m 2 "http://127.0.0.1:$(csm_puerto_agente)/ping" >/dev/null 2>&1; then
    echo agente
  fi
}

# Dirección del panel CON su token, la misma que imprime el setup de CSM: es la
# que hay que abrir una vez en cada dispositivo, porque el enlace empareja. Con
# hub propio es la de este equipo; si esta máquina solo reporta a otra, la del
# hub de aquella, que está en la configuración del agente.
#
# `con_token=0` la da sin él, para diagnósticos que no deben sacar secretos por
# pantalla sin que se pidan.
csm_url_panel() {
  local con_token="${1:-1}" ts ip token url
  if [ -f "$HOME/.local/share/csm-hub/data/token.txt" ]; then
    ts="$(command -v tailscale 2>/dev/null || echo /Applications/Tailscale.app/Contents/MacOS/Tailscale)"
    ip="$("$ts" ip -4 2>/dev/null | head -1 || true)"
    token="$(cat "$HOME/.local/share/csm-hub/data/token.txt" 2>/dev/null || true)"
    url="http://${ip:-<ip-de-este-equipo>}:$CSM_PUERTO"
  else
    # agent.json va con un campo por línea: {"hubs":[{"url": …, "token": …}]}
    url="$(sed -n 's/.*"url"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
             "$HOME/.config/csm/agent.json" 2>/dev/null | head -1 || true)"
    token="$(sed -n 's/.*"token"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
               "$HOME/.config/csm/agent.json" 2>/dev/null | head -1 || true)"
    url="${url%/}"
  fi
  [ -n "$url" ] || return 0
  if [ "$con_token" = 1 ] && [ -n "$token" ]; then
    echo "$url/#t=$token"
  else
    echo "$url"
  fi
}

# El paso de instalación. Devuelve 0 PASE LO QUE PASE: un panel de sesiones que
# no se instala no es motivo para dejar el equipo sin editor, que es a lo que se
# vino. El fallo se dice claro, se deja escrito cómo reintentarlo y el resumen
# final lo recuerda.
paso_csm() {
  local numero="$1" estado respuesta
  titulo "$numero · Claude Sessions Monitor"
  nota "un panel web con tus sesiones de Claude Code de todas tus máquinas,"
  nota "que además deja contestarles desde el móvil. Es opcional: BosonCode"
  nota "funciona igual sin él."

  estado="$(csm_estado)"
  if [ -n "$estado" ]; then
    if [ "$estado" = hub ]; then
      ok "ya está instalado y corriendo, con panel propio en :$CSM_PUERTO"
    else
      ok "ya está instalado y corriendo; esta máquina reporta a $(csm_url_panel 0)"
    fi
    if [ -d "$CSM_DIR/.git" ]; then
      nota "no lo reinstalo. Para actualizarlo:  cd ~/.ivscode/csm && git pull && ./setup.sh"
    else
      nota "no lo reinstalo. Para actualizarlo: git pull y ./setup.sh en la carpeta de CSM"
    fi
    CSM_RESULTADO=ya-estaba
    return 0
  fi

  case "$CSM_MODO" in
    no)
      gris "  · saltado (--no-csm)"
      CSM_RESULTADO=saltado; return 0 ;;
    preguntar)
      if [ "$SIN_PREGUNTAR" = 1 ]; then
        :
      elif [ -t 0 ]; then
        nota "si dices que sí: lo descargo en ~/.ivscode/csm y ejecuto su"
        nota "instalador, que te preguntará si este equipo tendrá su propio panel"
        nota "o si se suma al de otra máquina (te enseña los que encuentre)."
        nota "Necesita Node, Go y tmux; si faltan, los instala él y puede pedir sudo."
        printf '\n    ¿Instalar también Claude Sessions Monitor? [S/n] '
        read -r respuesta || respuesta=n
        case "${respuesta:-s}" in
          [nN]*)
            nota "de acuerdo. Cuando quieras:  ./setup.sh --csm"
            CSM_RESULTADO=saltado; return 0 ;;
        esac
      else
        # Sin nadie delante, instalar algo que no se pidió —y que puede
        # necesitar sudo— sería abusar del silencio.
        nota "no hay terminal donde preguntar: lo salto (para instalarlo: --csm)"
        CSM_RESULTADO=saltado; return 0
      fi ;;
  esac

  if ! command -v git >/dev/null 2>&1; then
    falta "hace falta git para descargarlo"
    nota "instálalo y ejecuta:  ./setup.sh --csm"
    CSM_RESULTADO=fallo; return 0
  fi

  if [ -d "$CSM_DIR/.git" ]; then
    nota "actualizando la copia que ya había en ~/.ivscode/csm…"
    git -C "$CSM_DIR" pull --ff-only -q 2>/dev/null \
      || nota "no pude actualizarla (¿sin internet o con cambios locales?); sigo con la que hay"
  else
    nota "descargando en ~/.ivscode/csm…"
    mkdir -p "$(dirname "$CSM_DIR")"
    if ! git clone -q --depth 1 "$CSM_REPO" "$CSM_DIR" 2>/dev/null; then
      falta "no pude descargar $CSM_REPO"
      nota "¿hay internet? Reinténtalo con:  ./setup.sh --csm"
      CSM_RESULTADO=fallo; return 0
    fi
  fi
  ok "código en ~/.ivscode/csm"

  if [ ! -f "$CSM_DIR/setup.sh" ]; then
    falta "la copia descargada no trae setup.sh"
    CSM_RESULTADO=fallo; return 0
  fi

  nota "a partir de aquí habla el instalador de CSM:"
  echo ""
  # En un subshell: su `cd` y su `set -e` se quedan dentro, y si aborta a
  # mitad solo muere él. Con `sh` explícito porque es un script POSIX y así no
  # depende de que el clon conserve el bit de ejecución.
  if (cd "$CSM_DIR" && sh ./setup.sh); then
    echo ""
    ok "Claude Sessions Monitor instalado"
    CSM_RESULTADO=instalado
  else
    echo ""
    falta "el instalador de Claude Sessions Monitor no terminó"
    nota "el editor NO se ve afectado: sigue funcionando igual."
    nota "el motivo está justo arriba. Para reintentar:"
    nota "  cd ~/.ivscode/csm && ./setup.sh"
    CSM_RESULTADO=fallo
  fi
  return 0
}

# Quita CSM con sus propias herramientas: `csm-agent service uninstall` para el
# agente y `scripts/hub-service.sh uninstall` para el hub. Son ellas las que
# saben qué servicios y archivos pusieron; repetir aquí esa lista a mano se
# quedaría vieja en cuanto CSM cambiara algo.
csm_desinstalar() {
  local agente="$HOME/.local/bin/csm-agent" servicio="$CSM_DIR/scripts/hub-service.sh"

  if [ -x "$agente" ]; then
    if "$agente" service uninstall >/dev/null 2>&1; then
      ok "agente de CSM quitado"
    else
      nota "el agente de CSM no tenía servicio que quitar"
    fi
    rm -f "$agente" "$HOME/.local/bin/csm"
  fi

  if [ -d "$HOME/.local/share/csm-hub/app" ]; then
    # hub-service.sh viene con el repositorio, no con lo instalado. Si la copia
    # de ~/.ivscode/csm no está (se instaló CSM desde otra carpeta), se trae
    # una solo para esto.
    if [ ! -x "$servicio" ] && command -v git >/dev/null 2>&1; then
      git clone -q --depth 1 "$CSM_REPO" "$CSM_DIR" 2>/dev/null || true
    fi
    if [ -x "$servicio" ] && "$servicio" uninstall >/dev/null 2>&1; then
      ok "hub de CSM quitado"
    else
      falta "no pude quitar el hub de CSM"
      nota "sin su script no sé qué servicio dejó. Descárgalo y ejecuta:"
      nota "  ./scripts/hub-service.sh uninstall"
    fi
  fi

  rm -rf "$CSM_DIR"
  # Los datos y el token del hub los conserva su desinstalador a propósito
  # (re-instalar no obliga a re-emparejar los dispositivos). Solo se van con
  # --purge, igual que los ajustes del editor.
  if [ "$PURGAR" = 1 ]; then
    rm -rf "$HOME/.local/share/csm-hub" "$HOME/.config/csm"
    ok "datos y token de CSM borrados"
  elif [ -d "$HOME/.local/share/csm-hub/data" ]; then
    nota "se conservan su token y sus datos (con --purge se borran también)"
  fi
}

# ---------- Asistente de IA en el editor ----------
# Opcional, como CSM: el editor funciona igual sin él. Se ofrecen dos, porque
# resuelven cosas distintas:
#
#   · Continue — extensión abierta (Open VSX) que habla con el modelo que tú
#     le des: Claude con una clave de API de Anthropic (se paga por uso; no es
#     la suscripción de Claude), u Ollama en local. No depende de ninguna
#     cuenta de Microsoft ni de GitHub.
#   · GitHub Copilot — el de siempre, con tu cuenta de GitHub. Desde que VS Code
#     abrió Copilot Chat (finales de 2025), code-server lo trae INTEGRADO: en
#     4.133/4.134 ya viene dentro (Copilot Chat 0.61/0.63), con sus APIs
#     propuestas permitidas y con inicio de sesión por código de dispositivo,
#     que es el flujo que funciona en un editor web. Instalarle encima el .vsix
#     del Marketplace era peor: bajaba una versión más vieja que la integrada.
#     Ese camino queda solo para un code-server antiguo que no lo traiga.
IA_EXT_DIR="$HOME/.ivscode/extensions"
IA_RESULTADO=""   # instalado | ya-estaba | fallo | saltado
IA_DETALLE=""

ia_code_server() { echo "$HOME/.ivscode/current/bin/code-server"; }

# El campo «version» de un package.json. Como JSON, no con sed: los de las
# extensiones integradas vienen minificados en una sola línea, y un sed por
# líneas no encontraba nada (así se escapó el Copilot integrado en la prueba).
version_de_paquete() {
  [ -f "$1" ] || return 0
  if command -v python3 >/dev/null 2>&1; then
    python3 -c 'import json, sys; print(json.load(open(sys.argv[1])).get("version", ""))' "$1" 2>/dev/null || true
  else
    grep -o '"version"[[:space:]]*:[[:space:]]*"[^"]*"' "$1" 2>/dev/null | head -1 | sed 's/.*"\([^"]*\)"$/\1/' || true
  fi
}

# Versión de VS Code que lleva dentro el code-server instalado.
ia_version_vscode() { version_de_paquete "$HOME/.ivscode/current/lib/vscode/package.json"; }

# Extensiones instaladas, como «id@versión» en minúsculas.
ia_extensiones() {
  local cs; cs="$(ia_code_server)"
  [ -x "$cs" ] || return 0
  "$cs" --extensions-dir "$IA_EXT_DIR" --list-extensions --show-versions 2>/dev/null \
    | tr '[:upper:]' '[:lower:]' || true
}

# Versión del Copilot Chat integrado en code-server, o nada si no lo trae.
ia_copilot_integrado() {
  version_de_paquete "$HOME/.ivscode/current/lib/vscode/extensions/copilot/package.json"
}

# Qué asistente hay ya, en una línea para leer. Vacío si ninguno elegido.
ia_estado() {
  local lista v sep=""
  lista="$(ia_extensiones)"
  v="$(printf '%s\n' "$lista" | sed -n 's/^continue\.continue@//p' | head -1)"
  [ -n "$v" ] && { printf 'Continue v%s' "$v"; sep=" · "; }
  v="$(printf '%s\n' "$lista" | sed -n 's/^github\.copilot-chat@//p' | head -1)"
  [ -n "$v" ] && { printf '%sCopilot Chat v%s (instalado a mano)' "$sep" "$v"; sep=" · "; }
  v="$(printf '%s\n' "$lista" | sed -n 's/^github\.copilot@//p' | head -1)"
  [ -n "$v" ] && printf '%sCopilot v%s (instalado a mano)' "$sep" "$v"
  return 0
}

# En una instalación nueva, `serve.sh --install-service` vuelve ANTES de que el
# servicio descargue code-server: lo baja él después, en segundo plano. Aquí se
# espera a que el editor RESPONDA, y no solo a que exista el binario, porque
# serve.sh lo arranca después de instalar sus extensiones de fábrica: esperar a
# eso evita dos instalaciones de extensiones escribiendo a la vez en la misma
# carpeta.
ia_esperar_editor() {
  local limite="${1:-900}" pasado=0 puerto="${PUERTO_EDITOR:-8443}"
  curl -fsS -m 3 "http://127.0.0.1:$puerto/healthz" >/dev/null 2>&1 && return 0
  nota "espero a que el servicio termine de preparar el editor"
  nota "(la primera vez descarga code-server y sus extensiones: unos minutos)…"
  while [ "$pasado" -lt "$limite" ]; do
    sleep 10; pasado=$((pasado + 10))
    if curl -fsS -m 3 "http://127.0.0.1:$puerto/healthz" >/dev/null 2>&1; then
      ok "editor listo"
      return 0
    fi
    [ $((pasado % 60)) = 0 ] && nota "  sigue preparándose… ($((pasado / 60)) min)"
  done
  return 1
}

# Configuración base de Continue, solo si no hay ninguna: la de alguien que ya
# lo usa es suya y no se toca. La clave NO va aquí: Continue resuelve
# `${{ secrets.X }}` leyendo ~/.continue/.env, que queda con permisos 600 y una
# plantilla comentada.
#
# Modelos (identificadores comprobados en la documentación de Anthropic,
# platform.claude.com/docs/en/about-claude/models/overview, sept. 2026):
#   · chat, edición y aplicar: Claude Opus 5.5 — claude-opus-5-5
#   · autocompletar: tiene que ser rápido. Si en este equipo corre Ollama, un
#     modelo LOCAL: sin clave, sin coste por pulsación y sin que el código salga
#     de la máquina; se prefiere uno «coder», que son los entrenados para
#     rellenar código. Si no hay Ollama, Claude Haiku 4.5 —
#     claude-haiku-4-5-20251001—, con dos advertencias que se dejan escritas en
#     el propio archivo (ver abajo).
ia_config_continue() {
  local dir="$HOME/.continue" ollama="" local_autocompletar=0
  if [ -f "$dir/config.yaml" ]; then
    nota "ya tienes ~/.continue/config.yaml: lo dejo como está"
    return 0
  fi
  mkdir -p "$dir"
  if command -v python3 >/dev/null 2>&1; then
    # Hasta tres modelos de Ollama para chat; el primero «coder» (o, si no hay
    # ninguno, el primero de la lista) también para autocompletar. La primera
    # línea de la salida dice si hubo modelo local para autocompletar.
    ollama="$(curl -fsS -m 2 http://127.0.0.1:11434/api/tags 2>/dev/null | python3 -c '
import json, sys
try:
    nombres = [m["name"] for m in json.load(sys.stdin).get("models", [])]
except Exception:
    nombres = []
coder = next((n for n in nombres if "coder" in n.lower()), nombres[0] if nombres else None)
print("autocompletar-local" if coder else "sin-ollama")
for n in nombres[:3]:
    roles = "[chat, edit, apply, autocomplete]" if n == coder else "[chat, edit, apply]"
    print(f"  - name: {n} (Ollama, local)\n    provider: ollama\n    model: {n}\n    roles: {roles}")
' 2>/dev/null || true)"
    [ "$(printf '%s\n' "$ollama" | head -1)" = autocompletar-local ] && local_autocompletar=1
    ollama="$(printf '%s\n' "$ollama" | tail -n +2)"
  fi
  {
    echo "# Configuración base que dejó setup.sh de BosonCode. Es tuya: cámbiala"
    echo "# a tu gusto; setup.sh no vuelve a tocarla mientras exista."
    echo "#"
    echo "# Los modelos de Claude usan una CLAVE DE API de Anthropic, que se paga"
    echo "# por uso con créditos prepago. NO es tu suscripción de Claude (Pro, Max,"
    echo "# Team): esa no incluye la API. La clave se crea en"
    echo "#   https://platform.claude.com/settings/keys"
    echo "# y va en ~/.continue/.env (ANTHROPIC_API_KEY=sk-ant-…), nunca aquí: este"
    echo "# archivo se copia y se comparte, ese no."
    echo "name: BosonCode"
    echo "version: 1.0.0"
    echo "schema: v1"
    echo "models:"
    echo "  - name: Claude Opus 5.5"
    echo "    provider: anthropic"
    echo "    model: claude-opus-5-5"
    echo "    apiKey: \${{ secrets.ANTHROPIC_API_KEY }}"
    echo "    roles: [chat, edit, apply]"
    if [ "$local_autocompletar" = 0 ]; then
      echo "  # Autocompletar con Claude Haiku 4.5, el más rápido. Dos avisos:"
      echo "  #  · la documentación de Continue advierte que los modelos de chat como"
      echo "  #    Claude no se entrenan con el formato de relleno (FIM) que usa el"
      echo "  #    autocompletado, y recomienda QwenCoder (local, con Ollama) o Codestral."
      echo "  #  · Anthropic anuncia su retirada «no antes del 15 de octubre de 2026»:"
      echo "  #    cuando llegue, cambia este modelo por su sucesor."
      echo "  - name: Claude Haiku 4.5 (autocompletar)"
      echo "    provider: anthropic"
      echo "    model: claude-haiku-4-5-20251001"
      echo "    apiKey: \${{ secrets.ANTHROPIC_API_KEY }}"
      echo "    roles: [autocomplete]"
    fi
    [ -n "$ollama" ] && printf '%s\n' "$ollama"
  } > "$dir/config.yaml"
  if [ ! -f "$dir/.env" ]; then
    {
      echo "# Claves para Continue. Este archivo no sale de este equipo."
      echo "# Clave de API de Anthropic (se paga por uso; no es la suscripción de"
      echo "# Claude). Se crea en https://platform.claude.com/settings/keys"
      echo "# ANTHROPIC_API_KEY=sk-ant-..."
    } > "$dir/.env"
    chmod 600 "$dir/.env"
  fi
  ok "configuración base en ~/.continue/config.yaml"
  nota "  chat y edición: Claude Opus 5.5"
  if [ "$local_autocompletar" = 1 ]; then
    nota "  autocompletar: un modelo local de Ollama (sin clave ni coste)"
  else
    nota "  autocompletar: Claude Haiku 4.5 (Continue avisa de que Claude no está"
    nota "  hecho para autocompletar; con Ollama y un modelo «coder» va mejor)"
  fi
  nota "Claude necesita una CLAVE DE API de Anthropic: se paga por uso, aparte de"
  nota "cualquier suscripción de Claude (Pro/Max no la incluye). Créala en"
  nota "  https://platform.claude.com/settings/keys"
  nota "y ponla en ~/.continue/.env:  ANTHROPIC_API_KEY=sk-ant-…"
}

ia_instalar_continue() {
  local cs v
  cs="$(ia_code_server)"
  v="$(ia_extensiones | sed -n 's/^continue\.continue@//p' | head -1)"
  if [ -n "$v" ]; then
    ok "Continue ya estaba instalado (v$v): no lo reinstalo"
  else
    nota "instalando Continue desde Open VSX…"
    if ! "$cs" --extensions-dir "$IA_EXT_DIR" --install-extension Continue.continue >/dev/null 2>&1; then
      falta "no pude instalar Continue (¿sin internet?)"
      return 1
    fi
    v="$(ia_extensiones | sed -n 's/^continue\.continue@//p' | head -1)"
    ok "Continue instalado (v${v:-?})"
  fi
  ia_config_continue
  nota "en el editor: el icono de Continue en la barra lateral"
  IA_DETALLE="Continue v${v:-?}"
}

# Descarga del Marketplace la versión estable más nueva de una extensión ($1,
# p. ej. GitHub.copilot-chat) cuyo motor admita el VS Code de este
# code-server, en $2. Imprime la versión. Solo para code-server viejos.
ia_descargar_vsix() {
  python3 - "$(ia_version_vscode)" "$1" "$2" <<'PY'
import gzip, json, re, sys, urllib.request
vscode, extension, destino = sys.argv[1], sys.argv[2], sys.argv[3]
tiene = tuple(int(x) for x in (vscode or "0.0.0").split(".")[:3])
peticion = urllib.request.Request(
    "https://marketplace.visualstudio.com/_apis/public/gallery/extensionquery",
    data=json.dumps({"filters": [{"criteria": [{"filterType": 7, "value": extension}],
                                  "pageSize": 1}], "flags": 147}).encode(),
    headers={"Content-Type": "application/json",
             "Accept": "application/json;api-version=7.2-preview.1"})
ext = json.load(urllib.request.urlopen(peticion, timeout=30))["results"][0]["extensions"][0]
for v in ext["versions"]:
    p = {x["key"]: x["value"] for x in v.get("properties", [])}
    if p.get("Microsoft.VisualStudio.Code.PreRelease") == "true":
        continue
    m = re.match(r"\^?(\d+)\.(\d+)\.(\d+)", p.get("Microsoft.VisualStudio.Code.Engine", ""))
    if not m or tuple(map(int, m.groups())) > tiene:
        continue
    url = next(f["source"] for f in v["files"]
               if f["assetType"] == "Microsoft.VisualStudio.Services.VSIXPackage")
    datos = urllib.request.urlopen(url, timeout=180).read()
    if datos[:2] == b"\x1f\x8b":
        datos = gzip.decompress(datos)
    open(destino, "wb").write(datos)
    print(v["version"])
    break
else:
    sys.exit("ninguna versión estable es compatible con VS Code " + vscode)
PY
}

ia_instalar_copilot() {
  local integrado cs tmp vsix version salida ext instaladas
  integrado="$(ia_copilot_integrado)"
  if [ -n "$integrado" ]; then
    ok "GitHub Copilot ya viene dentro de este code-server (Copilot Chat v$integrado)"
    nota "no hay nada que instalar. Para entrar: abre el chat del editor, escribe"
    nota "algo y elige «Continue with GitHub». Te da un código de un solo uso que"
    nota "se pega en https://github.com/login/device"
    nota "hace falta una cuenta de GitHub con Copilot (hay un plan gratuito)."
    IA_DETALLE="Copilot Chat v$integrado (integrado)"
    return 0
  fi

  # code-server antiguo, sin Copilot integrado.
  falta "este code-server no trae Copilot integrado (VS Code $(ia_version_vscode))"
  nota "lo bajo del Marketplace de Microsoft. Aviso, antes de hacerlo:"
  nota "  · es una ZONA GRIS de licencia: las condiciones del Marketplace reservan"
  nota "    sus extensiones a los productos de Microsoft, y code-server no lo es."
  nota "  · Copilot Chat depende de APIs internas de VS Code: según la versión de"
  nota "    code-server puede instalarse y aun así no funcionar el chat."
  nota "  · lo más limpio es actualizar code-server, que ya lo trae dentro."
  if ! command -v python3 >/dev/null 2>&1; then
    falta "hace falta python3 para buscar la versión compatible"
    return 1
  fi
  # Las dos: antes de la fusión de diciembre de 2025, el chat iba en
  # GitHub.copilot-chat y las sugerencias en línea en GitHub.copilot. Solo con
  # la primera, el chat arranca y se queja de «Copilot extension not found»
  # (visto en code-server 4.107.1 con Copilot Chat 0.35.3).
  cs="$(ia_code_server)"
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/copilot.XXXXXX")"
  instaladas=""
  for ext in GitHub.copilot-chat GitHub.copilot; do
    # En una carpeta temporal y con nombre acabado en .vsix: code-server toma
    # cualquier otra cosa por el identificador de una extensión del catálogo,
    # y la instalación fallaba buscándola en Open VSX.
    vsix="$tmp/$ext.vsix"
    if ! version="$(ia_descargar_vsix "$ext" "$vsix" 2>&1)"; then
      falta "no pude descargar $ext: $(printf '%s' "$version" | tail -1)"
      continue
    fi
    if salida="$("$cs" --extensions-dir "$IA_EXT_DIR" --install-extension "$vsix" 2>&1)"; then
      ok "$ext v$version instalado"
      instaladas="$instaladas${instaladas:+ + }$ext v$version"
    else
      falta "no pude instalar $ext v$version"
      printf '%s\n' "$salida" | tail -3 | sed 's/^/      /'
    fi
  done
  rm -rf "$tmp"
  [ -n "$instaladas" ] || return 1
  nota "para entrar: abre el chat, escribe algo y elige iniciar sesión con GitHub."
  IA_DETALLE="$instaladas (instalado a mano)"
}

# El paso. $1 número, $2 «servicio» o «primer-plano», $3 código de salida del
# servidor. Como el de CSM, devuelve 0 pase lo que pase: sin asistente el
# editor sigue sirviendo, que es lo importante.
paso_ia() {
  local numero="$1" modo_arranque="$2" rc_servidor="${3:-0}" eleccion="$IA_MODO" hay respuesta
  titulo "$numero · Asistente de IA en el editor"
  nota "opcional. Continue: abierto, con tu propio modelo — Claude, con una clave"
  nota "de API de Anthropic que se paga por uso (no es la suscripción de Claude),"
  nota "u Ollama en local, gratis. GitHub Copilot: con tu cuenta de GitHub."

  hay="$(ia_estado)"
  if [ "$eleccion" = preguntar ] && [ -n "$hay" ]; then
    ok "ya hay asistente: $hay — no reinstalo nada"
    nota "para añadir otro:  ./setup.sh --ai continue   o   --ai copilot"
    IA_RESULTADO=ya-estaba; IA_DETALLE="$hay"; return 0
  fi

  if [ "$eleccion" = preguntar ]; then
    if [ "$SIN_PREGUNTAR" = 1 ]; then
      eleccion=continue
    elif [ -t 0 ]; then
      printf '\n      [1] Continue        (por defecto)\n'
      printf '      [2] GitHub Copilot\n'
      printf '      [3] ninguno\n\n    ¿Cuál instalo? [1] '
      read -r respuesta || respuesta=3
      case "${respuesta:-1}" in
        1|c|C|continue) eleccion=continue ;;
        2|copilot|Copilot) eleccion=copilot ;;
        *) eleccion=no ;;
      esac
    else
      nota "no hay terminal donde preguntar: lo salto (para instalarlo: --ai continue)"
      IA_RESULTADO=saltado; return 0
    fi
  fi
  if [ "$eleccion" = no ]; then
    gris "  · sin asistente de IA. Cuando quieras:  ./setup.sh --ai continue"
    IA_RESULTADO=saltado; return 0
  fi

  # Hace falta code-server instalado. Con el servicio se espera a que termine
  # de prepararse; en primer plano todavía no ha arrancado —arranca después de
  # este paso—, así que solo sirve si ya estaba de una vez anterior.
  if [ "$modo_arranque" = servicio ]; then
    if [ "$rc_servidor" != 0 ]; then
      falta "el editor no arrancó, así que no puedo instalar el asistente"
      nota "cuando funcione:  ./setup.sh --ai $eleccion"
      IA_RESULTADO=fallo; return 0
    fi
    if ! ia_esperar_editor 900; then
      falta "el editor tardó demasiado en estar listo"
      nota "sigue preparándose en segundo plano; luego:  ./setup.sh --ai $eleccion"
      IA_RESULTADO=fallo; return 0
    fi
  elif [ ! -x "$(ia_code_server)" ]; then
    falta "code-server todavía no está descargado (se descarga al arrancar)"
    nota "cuando haya arrancado una vez:  ./setup.sh --ai $eleccion"
    IA_RESULTADO=fallo; return 0
  fi

  if { [ "$eleccion" = continue ] && ia_instalar_continue; } ||
     { [ "$eleccion" = copilot ] && ia_instalar_copilot; }; then
    IA_RESULTADO=instalado
  else
    nota "el editor NO se ve afectado. Para reintentar:  ./setup.sh --ai $eleccion"
    IA_RESULTADO=fallo
  fi
  return 0
}

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
  # Qué hay publicado en Tailscale, clasificado AHORA, con el servicio todavía
  # corriendo: una de las reglas mira qué proceso escucha detrás de cada
  # puerto, y después de parar el servicio ya no escucharía nadie.
  TS_BIN="$(command -v tailscale 2>/dev/null || echo /Applications/Tailscale.app/Contents/MacOS/Tailscale)"
  PUBLICACIONES=""
  SIN_PYTHON=0
  if [ -x "$TS_BIN" ]; then
    if command -v python3 >/dev/null 2>&1; then
      PUBLICACIONES="$("$TS_BIN" serve status --json 2>/dev/null | publicaciones_ts || true)"
    else
      SIN_PYTHON=1
    fi
  fi

  nota "se va a borrar:"
  nota "  · el servicio, para que deje de arrancar solo"
  nota "  · ~/.ivscode — code-server, extensiones y la contraseña de este equipo"
  if printf '%s\n' "$PUBLICACIONES" | grep -q '^quitar'; then
    nota "  · de Tailscale, SOLO lo que publicó BosonCode:"
    printf '%s\n' "$PUBLICACIONES" | awk -F'\t' '$1 == "quitar" { print "        " $3 }' | while IFS= read -r l; do gris "$l"; done
  fi
  if [ "$PURGAR" = 1 ]; then
    nota "  · ~/.local/share/code-server y ~/.config/code-server — TUS ajustes"
  fi
  if [ "$CSM_MODO" = si ]; then
    nota "  · Claude Sessions Monitor: su agente, su hub y ~/.ivscode/csm"
  fi
  nota "NO se toca: tu código, tu sesión de Tailscale, ni Tailscale."
  # Continue se va con ~/.ivscode/extensions, pero su configuración está en
  # ~/.continue y puede tener tus claves y tus modelos: es tuya.
  [ -d "$HOME/.continue" ] && nota "Tampoco ~/.continue (la configuración de Continue)."
  if printf '%s\n' "$PUBLICACIONES" | grep -q '^dejar'; then
    nota "Tampoco lo que otros publicaron en Tailscale:"
    printf '%s\n' "$PUBLICACIONES" | awk -F'\t' '$1 == "dejar" { print "        " $3 }' | while IFS= read -r l; do gris "$l"; done
  fi
  if [ "$SIN_PYTHON" = 1 ]; then
    nota "Tailscale no se toca: sin python3 no sé distinguir lo nuestro de lo ajeno."
  fi
  # CSM es una instalación aparte con vida propia —puede estar sirviendo el
  # panel de otras máquinas—, así que solo se quita si se pide por nombre.
  if [ "$CSM_MODO" != si ] && csm_instalado; then
    nota "Tampoco Claude Sessions Monitor; para quitarlo también:  --uninstall --csm"
  fi
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

  # Una a una, y solo las nuestras — nunca `serve reset`, que se lleva también
  # lo que publicaron otros (ver publicaciones_ts). `off` necesita el mismo
  # permiso que `serve`: si falta, se dice qué quedó sin quitar y cómo hacerlo.
  QUITADAS=0; FALLIDAS=""
  while IFS="$(printf '\t')" read -r accion args texto; do
    [ "$accion" = quitar ] || continue
    # shellcheck disable=SC2086 — args son varias opciones a propósito
    if "$TS_BIN" serve $args off >/dev/null 2>&1; then
      QUITADAS=$((QUITADAS + 1))
    else
      FALLIDAS="$FALLIDAS$args
"
    fi
  done <<EOF
$PUBLICACIONES
EOF
  if [ "$QUITADAS" -gt 0 ]; then
    ok "quitado de Tailscale lo que publicó BosonCode ($QUITADAS)"
  elif [ -z "$FALLIDAS" ]; then
    nota "BosonCode no tenía nada publicado en Tailscale"
  fi
  if [ -n "$FALLIDAS" ]; then
    falta "no pude quitar de Tailscale:"
    printf '%s' "$FALLIDAS" | while IFS= read -r a; do
      [ -n "$a" ] && nota "  $TS_BIN serve $a off"
    done
    # Casi siempre es permiso: `off` pide lo mismo que `serve`.
    [ "$PLATAFORMA" = linux ] && nota "si dice «access denied»:  sudo $TS_BIN set --operator=$(id -un)"
  fi

  if [ "$CSM_MODO" = si ]; then
    csm_desinstalar
    rm -rf "$HOME/.ivscode"
    ok "~/.ivscode borrado"
  else
    # Todo ~/.ivscode MENOS la copia de CSM que vive ahí dentro. Borrarla entera
    # sería tocar CSM sin que se pidiera: su hub seguiría corriendo, pero sin el
    # repositorio con el que se actualiza y se desinstala.
    if [ -d "$HOME/.ivscode" ]; then
      find "$HOME/.ivscode" -mindepth 1 -maxdepth 1 ! -name csm -exec rm -rf {} + 2>/dev/null || true
      rmdir "$HOME/.ivscode" 2>/dev/null || true
    fi
    if [ -d "$CSM_DIR" ]; then
      ok "~/.ivscode borrado, salvo ~/.ivscode/csm (Claude Sessions Monitor)"
    else
      ok "~/.ivscode borrado"
    fi
  fi

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
    # `|| true` no es descuido: este script corre con `set -e`, y sin eso el
    # fallo del instalador lo mataba AQUÍ MISMO, sin imprimir nada. Quien lo
    # ejecutaba volvía al prompt sin un solo mensaje y sin saber qué pasó.
    curl -fsSL https://tailscale.com/install.sh | sh || RC_TS=$?
    TS="$(buscar_tailscale || true)"

    if [ -z "$TS" ] && command -v apt-get >/dev/null 2>&1; then
      # El instalador de Tailscale hace `apt-get update` y aborta si falla.
      # Y falla por cualquier repositorio ajeno que esté roto —un PPA viejo,
      # uno que ya no publica Release—, aunque no tenga nada que ver con
      # Tailscale. Es la causa más común de que esto no funcione, y el mensaje
      # del instalador no lo dice.
      roto="$(sudo apt-get update 2>&1 | sed -n "s/^E: The repository '\([^ ]*\).*/\1/p" | head -3)"
      if [ -n "$roto" ]; then
        falta "el instalador se detuvo porque apt no puede actualizar"
        nota "hay repositorios rotos en este equipo, ajenos a BosonCode:"
        printf '%s\n' "$roto" | sed 's/^/      /'
        nota "quítalos y vuelve a intentarlo:"
        nota "  sudo add-apt-repository --remove <el-de-arriba>"
        nota "o instala Tailscale sin pasar por su script:"
        nota "  sudo apt install tailscale"
      else
        falta "el instalador de Tailscale terminó sin dejarlo instalado"
        nota "prueba directamente:  sudo apt install tailscale"
      fi
      exit 1
    fi
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

titulo "5 · Publicación HTTPS"
if [ "$SOLO_COMPROBAR" != 1 ]; then
  URL_TS="$("$TS" serve status 2>/dev/null | sed -n 's#^\(https://[^ ]*\).*#\1#p' | head -1)"
  if [ -n "$URL_TS" ]; then
    ok "ya publicaba · $URL_TS"
  else
    asegurar_serve || nota "seguiré sin HTTPS: el editor funcionará, lo demás no"
  fi
fi

if [ "$SOLO_COMPROBAR" = 1 ]; then
  # La pregunta que trae a cualquiera a `--check` es «¿puedo ya añadir este
  # equipo, y con qué dirección?». Diagnosticar y callar justo esa respuesta
  # deja al usuario buscando en otro sitio lo único que quería.
  URL_TS="$("$TS" serve status 2>/dev/null | sed -n 's#^\(https://[^ ]*\).*#\1#p' | head -1)"
  if [ -n "$URL_TS" ]; then
    ok "sí · $URL_TS"
    nota "el nombre y la contraseña:  ./setup.sh --password"
  else
    falta "todavía no: falta el HTTPS de Tailscale"
    nota "sin él la app no tiene notebooks, ni máquinas, ni terminal"
    nota "prueba:  sudo tailscale set --operator=$(id -un)"
    if [ "$PLATAFORMA" = linux ] && \
       systemctl --user is-enabled ivscode.service >/dev/null 2>&1; then
      nota "y luego:  systemctl --user restart ivscode"
    else
      nota "y luego:  ./setup.sh"
    fi
    nota "si insiste, activa MagicDNS y HTTPS Certificates en tu cuenta:"
    nota "  https://login.tailscale.com/admin/dns"
  fi

  titulo "Claude Sessions Monitor"
  # Sin el token en la dirección: un diagnóstico se copia y se pega en
  # cualquier sitio, y el token es lo que da acceso al panel.
  case "$(csm_estado)" in
    hub)
      ok "instalado y corriendo, con panel propio · $(csm_url_panel 0)"
      # Solo se señala la copia de ~/.ivscode/csm si existe: CSM puede haberse
      # instalado desde otra carpeta, y mandar a un script que no está es peor
      # que no decir nada.
      if [ -x "$CSM_DIR/scripts/hub-service.sh" ]; then
        nota "el enlace con el token:  ~/.ivscode/csm/scripts/hub-service.sh status"
      else
        nota "el enlace con el token:  scripts/hub-service.sh status, en la carpeta de CSM"
      fi ;;
    agente)
      ok "instalado y corriendo; esta máquina reporta a $(csm_url_panel 0)" ;;
    *)
      if csm_instalado; then
        falta "instalado, pero no responde (ni hub en :$CSM_PUERTO ni agente en :$(csm_puerto_agente))"
        if [ -x "$CSM_DIR/scripts/hub-service.sh" ]; then
          nota "para arrancarlo:  ~/.ivscode/csm/scripts/hub-service.sh start"
        else
          nota "para repararlo:  ./setup.sh --csm"
        fi
      else
        gris "  · no instalado (es opcional; para añadirlo:  ./setup.sh --csm)"
      fi ;;
  esac

  titulo "Asistente de IA en el editor"
  if [ ! -x "$(ia_code_server)" ]; then
    gris "  · code-server aún no está instalado"
  else
    IA_HAY="$(ia_estado)"
    if [ -n "$IA_HAY" ]; then ok "$IA_HAY"; else gris "  · ni Continue ni Copilot instalado a mano"; fi
    IA_INTEGRADO="$(ia_copilot_integrado)"
    # El integrado está siempre que la versión de code-server lo trae; se dice
    # aparte porque no es algo que se haya elegido, sino que viene de serie.
    if [ -n "$IA_INTEGRADO" ]; then
      ok "Copilot Chat v$IA_INTEGRADO viene integrado en code-server $(ia_version_vscode | sed 's/^/(VS Code /;s/$/)/')"
    fi
    if printf '%s' "$IA_HAY" | grep -q Continue; then
      if [ -f "$HOME/.continue/config.yaml" ]; then
        nota "configuración de Continue: ~/.continue/config.yaml"
      else
        nota "Continue aún sin configuración: se crea al abrirlo por primera vez"
      fi
    fi
    [ -z "$IA_HAY" ] && nota "para añadir uno:  ./setup.sh --ai continue   o   --ai copilot"
  fi

  titulo "Comprobación terminada"
  gris "No he tocado nada. Ejecuta ./setup.sh sin --check para instalar."
  exit 0
fi

# ---------- 6. arrancar ----------

# systemd de usuario no está en todas partes: WSL sin systemd es el caso
# habitual. Si no lo hay, no se puede instalar el servicio, así que se avisa y
# se sigue en primer plano en lugar de fallar.
SIRVE_SERVICIO=1
if [ "$PLATAFORMA" = linux ] && ! systemctl --user show-environment >/dev/null 2>&1; then
  SIRVE_SERVICIO=0
fi

# La línea del panel de CSM, si quedó instalado. Va en el resumen, que es lo
# último que se lee y lo que se copia.
resumen_csm() {
  local url
  case "$CSM_RESULTADO" in
    instalado|ya-estaba)
      url="$(csm_url_panel)"
      ok "Claude Sessions Monitor"
      [ -n "$url" ] && printf '      Panel:  \033[1;36m%s\033[0m\n' "$url"
      nota "ábrelo una vez en cada dispositivo (por Tailscale): el enlace lleva"
      nota "el token y la app lo recuerda."
      nota "sesiones nuevas:  cd <proyecto> && csm" ;;
    fallo)
      falta "Claude Sessions Monitor no se instaló (el motivo está más arriba)"
      nota "reintentar:  ./setup.sh --csm" ;;
  esac
}

# La línea del asistente de IA en el resumen.
resumen_ia() {
  case "$IA_RESULTADO" in
    instalado|ya-estaba) ok "Asistente de IA: $IA_DETALLE" ;;
    fallo)
      falta "el asistente de IA no quedó instalado (el motivo está más arriba)" ;;
  esac
}

# En primer plano el servidor se queda con esta terminal hasta que se cierre:
# lo que venga después no llegaría a ejecutarse nunca. Por eso, en ese modo, CSM
# se ofrece ANTES de arrancar, y se deja dicho por qué el orden es otro.
if [ "$EN_PRIMER_PLANO" = 1 ] || [ "$SIRVE_SERVICIO" = 0 ]; then
  nota "el servidor va a quedarse con esta terminal, así que los pasos opcionales"
  nota "(Claude Sessions Monitor y el asistente de IA) van primero"
  paso_csm 6
  paso_ia 7 primer-plano
  resumen_csm
  resumen_ia
  titulo "8 · Arrancando"
  if [ "$EN_PRIMER_PLANO" = 1 ]; then
    nota "en primer plano: se para al cerrar esta terminal"
    nota "para dejarlo permanente:  ./setup.sh"
  else
    falta "aquí no hay systemd de usuario, no puedo dejarlo permanente"
    nota "en WSL: pon systemd=true en /etc/wsl.conf, y luego  wsl --shutdown"
    nota "mientras tanto arranca en primer plano: NO cierres esta terminal"
  fi
  echo ""
  # Ya avisado: que serve.sh no repita el recuadro ni se niegue a arrancar si
  # hay servicio (con --foreground se quiere ver los registros igualmente), ni
  # aconseje ./setup.sh cuando ./setup.sh no puede dejarlo permanente.
  IVSCODE_FOREGROUND=1 exec ./serve.sh
fi

titulo "6 · Arrancando"
# Como servicio por defecto, y en primer plano solo si se pide.
#
# Antes era al revés y era la elección equivocada. Dejarlo en primer plano ata
# el servidor a la terminal que lo lanzó: cierras esa ventana y el iPad pierde
# el editor, el terminal y los notebooks de golpe, sin ninguna pista de por qué.
# Y un equipo que sirve a otro dispositivo se espera que siga sirviendo cuando
# nadie lo mira — que es justo lo que hace un servicio.
#
# Ya no con `exec`: eso reemplazaba este script por serve.sh y nada de lo que
# viniera detrás —el paso de CSM, el resumen— llegaba a ejecutarse.
# `--install-service` deja el servicio corriendo y vuelve.
nota "se instala como servicio: sigue vivo al cerrar la terminal y arranca al encender"
RC_SERVIDOR=0
./serve.sh --install-service || RC_SERVIDOR=$?

paso_csm 7
paso_ia 8 servicio "$RC_SERVIDOR"

titulo "Resumen"
if [ "$RC_SERVIDOR" = 0 ]; then
  ok "editor en marcha como servicio"
  nota "para añadir este equipo en la app:  ./setup.sh --password"
else
  falta "el servidor no quedó en marcha (el motivo está más arriba)"
  nota "para ver qué falta:  ./setup.sh --check"
fi
resumen_csm
resumen_ia
echo ""
# El código de salida es el del servidor: CSM es opcional y su fallo ya se ha
# dicho; que el editor no arranque, en cambio, sí es un fallo de este script.
exit "$RC_SERVIDOR"
