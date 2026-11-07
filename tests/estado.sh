#!/usr/bin/env bash
# Prueba del contrato de estado de setup.sh: lo que lee Boson Server.
#
#   tests/estado.sh          en este equipo, tal cual está
#
# Comprueba tres cosas que, si fallan, la app falla con ellas:
#   1. `--estado` devuelve JSON válido con todos los bloques y tipos esperados,
#      aquí y en un equipo vacío (HOME sin nada, PATH sin herramientas).
#   2. `--estado` NUNCA contiene la contraseña ni el token, aunque existan.
#   3. `--clave` da la contraseña a secas, y se niega con un valor que no existe.
# No instala ni cambia nada; no imprime secretos (los compara, no los enseña).
set -euo pipefail
cd "$(dirname "$0")/.."

fallos=0
ok()    { printf '  \033[32m✓\033[0m %s\n' "$*"; }
falla() { printf '  \033[31m✗\033[0m %s\n' "$*"; fallos=$((fallos + 1)); }

valida() {
  # $1 = archivo JSON, $2 = etiqueta. Valida forma y tipos con python3.
  python3 - "$1" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
def espera(cond, msg):
    if not cond:
        raise SystemExit("  forma inesperada: " + msg)
espera(d.get("version") == 1, "version != 1")
for bloque in ("equipo", "boson", "servidor", "tailscale", "csm", "ia", "linkspace", "simulador"):
    espera(isinstance(d.get(bloque), dict), f"falta el bloque {bloque}")
espera(d["equipo"]["so"] in ("macos", "linux"), "equipo.so")
espera(d["servidor"]["estado"] in ("sirviendo", "arrancando", "parado", "sin_instalar"), "servidor.estado")
espera(d["servidor"]["servicio"] in ("launchd", "systemd", "ninguno"), "servidor.servicio")
espera(isinstance(d["servidor"]["puerto"], int), "servidor.puerto")
espera(isinstance(d["tailscale"]["instalado"], bool), "tailscale.instalado")
espera(isinstance(d["tailscale"]["publicaciones"], list), "tailscale.publicaciones")
for p in d["tailscale"]["publicaciones"]:
    espera(p["tipo"] in ("editor", "gestor", "terminal", "maquina", "otro"), "publicacion.tipo")
    espera(isinstance(p["puerto"], int) and isinstance(p["nuestro"], bool), "publicacion.puerto/nuestro")
espera(d["csm"]["estado"] in ("hub", "agente", "parado", "ninguno"), "csm.estado")
espera(isinstance(d["csm"]["equipos"], list), "csm.equipos")
espera(isinstance(d["ia"]["extensiones"], list), "ia.extensiones")
for k in ("comandos", "al_dia", "en_ivscode"):
    espera(isinstance(d["linkspace"][k], bool), "linkspace." + k)
PY
}

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

echo "1 · --estado en este equipo"
if ./setup.sh --estado > "$tmp/estado.json" 2> "$tmp/err"; then
  ok "termina con 0"
else
  falla "termina con error:"; sed 's/^/      /' "$tmp/err"
fi
if valida "$tmp/estado.json"; then ok "JSON válido y con la forma esperada"; else falla "JSON inválido o con otra forma"; fi

echo "2 · --estado en un equipo vacío"
mkdir -p "$tmp/home"
if HOME="$tmp/home" PATH=/usr/bin:/bin ./setup.sh --estado > "$tmp/vacio.json" 2> "$tmp/err"; then
  ok "termina con 0 sin nada instalado"
else
  falla "falla sin nada instalado:"; sed 's/^/      /' "$tmp/err"
fi
if valida "$tmp/vacio.json"; then ok "JSON válido también vacío"; else falla "JSON inválido en vacío"; fi
if python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
assert d["csm"]["estado"] == "ninguno", d["csm"]["estado"]
assert d["boson"]["code_server_instalado"] is False
assert d["servidor"]["servicio"] == "ninguno"
assert d["servidor"]["password_existe"] is False
' "$tmp/vacio.json"; then ok "dice «ninguno» donde no hay nada"; else falla "inventa cosas en un equipo vacío"; fi

echo "3 · las claves no se cuelan en el estado"
if [ -f "$HOME/.ivscode/password" ]; then
  clave="$(./setup.sh --clave editor)"
  if [ "$clave" = "$(cat "$HOME/.ivscode/password")" ]; then ok "--clave editor da la contraseña"; else falla "--clave editor no coincide con el archivo"; fi
  if grep -qF -- "$clave" "$tmp/estado.json"; then falla "LA CONTRASEÑA APARECE EN --estado"; else ok "la contraseña no está en --estado"; fi
else
  ok "sin contraseña en este equipo: nada que comparar"
fi
if [ -f "$HOME/.local/share/csm-hub/data/token.txt" ]; then
  token="$(cat "$HOME/.local/share/csm-hub/data/token.txt")"
  if grep -qF -- "$token" "$tmp/estado.json"; then falla "EL TOKEN DE CSM APARECE EN --estado"; else ok "el token de CSM no está en --estado"; fi
  if ./setup.sh --clave csm | grep -qF -- "#t=$token"; then ok "--clave csm da el enlace con el token"; else falla "--clave csm no lleva el token"; fi
else
  ok "sin hub de CSM en este equipo: nada que comparar"
fi
if ./setup.sh --clave nada >/dev/null 2>&1; then falla "--clave acepta un valor que no existe"; else ok "--clave rechaza un valor que no existe"; fi
if ./setup.sh --clave >/dev/null 2>&1; then falla "--clave sin valor no avisa"; else ok "--clave sin valor avisa"; fi

echo "4 · las acciones que usa Boson Server"
if ./setup.sh --servidor nada >/dev/null 2>&1; then falla "--servidor acepta un valor que no existe"; else ok "--servidor rechaza un valor que no existe"; fi
mkdir -p "$tmp/home2"
if printf 'corta' | HOME="$tmp/home2" ./setup.sh --nueva-clave >/dev/null 2>&1; then falla "--nueva-clave acepta una contraseña de 5 caracteres"; else ok "--nueva-clave rechaza una contraseña corta"; fi
if printf 'clave-de-prueba' | HOME="$tmp/home2" ./setup.sh --nueva-clave >/dev/null 2>&1 \
   && [ "$(cat "$tmp/home2/.ivscode/password")" = "clave-de-prueba" ] \
   && [ "$(stat -f %Lp "$tmp/home2/.ivscode/password" 2>/dev/null || stat -c %a "$tmp/home2/.ivscode/password")" = 600 ]; then
  ok "--nueva-clave guarda la contraseña con permisos 600 (en un HOME de prueba)"
else
  falla "--nueva-clave no guardó bien la contraseña de prueba"
fi
if printf '' | HOME="$tmp/home2" ./setup.sh --nueva-clave >/dev/null 2>&1 && [ "$(wc -c < "$tmp/home2/.ivscode/password" | tr -d ' ')" = 16 ]; then
  ok "--nueva-clave vacía genera una de 16 caracteres"
else
  falla "--nueva-clave vacía no generó una contraseña"
fi
# En una variable y no en una tubería: con pipefail, `grep -q` corta la tubería
# al primer acierto y el script muere con SIGPIPE, que contaría como fallo.
salida_app="$(BOSON_APP=1 ./setup.sh --check 2>/dev/null || true)"
if printf '%s\n' "$salida_app" | grep -q '^@@titulo '; then ok "con BOSON_APP=1 la salida lleva las marcas de la app"; else falla "sin marcas @@ en modo app"; fi
if printf '%s\n' "$salida_app" | grep -q $'\033'; then falla "en modo app salen colores ANSI"; else ok "en modo app no hay colores ANSI"; fi

echo ""
if [ "$fallos" = 0 ]; then echo "Todo bien."; else echo "$fallos fallo(s)."; exit 1; fi
