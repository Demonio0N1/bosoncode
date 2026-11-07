#!/usr/bin/env bash
# Compila el DMG de Boson Server firmado y notarizado, en este Mac.
#
# Hace falta un certificado «Developer ID Application» en el Llavero y una
# contraseña específica de app de tu Apple ID (appleid.apple.com → Iniciar
# sesión y seguridad → Contraseñas específicas de app). Nada de eso se
# escribe aquí: se pasa por variables de entorno al ejecutar, por ejemplo
#
#   APPLE_SIGNING_IDENTITY="Developer ID Application: Tu Nombre (EQUIPO)" \
#   APPLE_ID="tu@correo" APPLE_PASSWORD="xxxx-xxxx-xxxx-xxxx" APPLE_TEAM_ID="EQUIPO" \
#   ./publicar-mac.sh
#
# Tauri firma la app, construye el DMG, lo manda a notarizar y lo grapa. Sin
# las variables compila igual, pero sin firmar: macOS pedirá «abrir de todos
# modos» la primera vez.
set -euo pipefail
cd "$(dirname "$0")"

if [ -z "${APPLE_SIGNING_IDENTITY:-}" ]; then
  echo "Sin APPLE_SIGNING_IDENTITY: el DMG saldrá SIN firmar (vale para probar, no para repartir)."
  echo "Identidades disponibles en este Mac:"
  security find-identity -v -p codesigning | sed 's/^/  /' || true
  echo ""
elif [ -z "${APPLE_ID:-}" ] || [ -z "${APPLE_PASSWORD:-}" ] || [ -z "${APPLE_TEAM_ID:-}" ]; then
  echo "Para notarizar hacen falta también APPLE_ID, APPLE_PASSWORD (específica de app) y APPLE_TEAM_ID." >&2
  exit 1
fi

[ -d node_modules ] || npm ci
npx tauri build --bundles app,dmg --target universal-apple-darwin 2>/dev/null \
  || npx tauri build --bundles app,dmg

echo ""
echo "Listo. El DMG:"
ls -1 src-tauri/target/*/release/bundle/dmg/*.dmg src-tauri/target/release/bundle/dmg/*.dmg 2>/dev/null | sed 's/^/  /'
