#!/usr/bin/env bash
# =============================================================================
# instalar.sh — instala Link_space (los comandos carpeta-share y linkspace, el
# clic derecho del gestor de archivos y la extensión de VS Code) en macOS y
# Linux. Lo llama el ./setup.sh de BosonCode, que es el instalador de todo; a
# mano solo hace falta para reinstalar o actualizar esta parte.
# Idempotente: correrlo dos veces no rompe nada.
#
# Uso:  ./instalar.sh               instala (pide administrador para /usr/local/bin)
#       ./instalar.sh --actualizar  git pull del repositorio y reinstalar, sin preguntas
#       ./instalar.sh --uninstall   revierte la instalación (los invitados se
#                                   eliminan antes con 'carpeta-share invitado eliminar')
#
# Tailscale lo instala y comprueba el setup.sh de BosonCode; aquí se da por
# hecho. code-server tampoco se instala aquí: el servidor de ZeroSpin trae el
# suyo en ~/.ivscode, y el modo web de Link_space usa el que encuentre.
# =============================================================================
set -euo pipefail

AQUI="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$AQUI/.." && pwd)"
SO="$(uname -s)"
es_macos() { [[ "$SO" == "Darwin" ]]; }

DESTINO_CLI="/usr/local/bin/carpeta-share"
DESTINO_LINKSPACE="/usr/local/bin/linkspace"
DESTINO_DESCARGAS="/usr/local/bin/carpeta-share-descargas"   # servidor del modo solo descarga
WF_DIR="$HOME/Library/Services/Compartir carpeta con VS Code.workflow"
NAUTILUS_SCRIPT="$HOME/.local/share/nautilus/scripts/Compartir carpeta con VS Code"
DOLPHIN_MENU="$HOME/.local/share/kio/servicemenus/carpeta-share.desktop"

info() { printf '• %s\n' "$*"; }
ok()   { printf '\033[32m✓ %s\033[0m\n' "$*"; }
aviso(){ printf '\033[33m! %s\033[0m\n' "$*"; }
err()  { printf '\033[31m✗ %s\033[0m\n' "$*" >&2; exit 1; }

[[ -f "$AQUI/bin/carpeta-share" ]] || err "No encuentro bin/carpeta-share junto a este script."
[[ $EUID -ne 0 ]] || err "No lo ejecutes como root: usaré sudo solo donde haga falta."

buscar_code() {
  if command -v code >/dev/null 2>&1; then command -v code; return 0; fi
  local c="/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code"
  if [[ -x "$c" ]]; then echo "$c"; return 0; fi
  return 1
}

# =============================================================================
# Desinstalación
# =============================================================================
if [[ "${1:-}" == "--uninstall" ]]; then
  info "Desinstalando Link_space…"
  if [[ -x "$DESTINO_CLI" ]]; then
    restantes="$("$DESTINO_CLI" listar-invitados 2>/dev/null || true)"
    if [[ -n "$restantes" ]]; then
      aviso "Aún hay invitados registrados: $(echo "$restantes" | tr '\n' ' ')"
      aviso "Elimínalos primero (revierte usuarios, ACLs y sshd_config):"
      echo "$restantes" | while read -r n; do [[ -n "$n" ]] && echo "    carpeta-share invitado eliminar $n"; done
      err "Desinstalación detenida para no dejar accesos huérfanos."
    fi
    descargas="$("$DESTINO_CLI" listar-descargas 2>/dev/null || true)"
    if [[ -n "$descargas" ]]; then
      aviso "Aún hay enlaces de descarga activos. Revócalos primero (apaga el servidor y despublica la URL):"
      echo "$descargas" | while read -r r; do [[ -n "$r" ]] && echo "    carpeta-share dejar-de-compartir \"$r\" --descarga"; done
      err "Desinstalación detenida para no dejar enlaces públicos huérfanos."
    fi
  fi
  sudo rm -f "$DESTINO_CLI" "$DESTINO_LINKSPACE" "$DESTINO_DESCARGAS" && ok "CLI y linkspace eliminados."
  rm -rf "$WF_DIR" && ok "Quick Action de Finder eliminada."
  rm -f "$NAUTILUS_SCRIPT" "$DOLPHIN_MENU" 2>/dev/null || true
  if CODE="$(buscar_code)"; then
    "$CODE" --uninstall-extension local.carpeta-share >/dev/null 2>&1 && ok "Extensión de VS Code eliminada." || true
  fi
  aviso "Se conserva ~/.config/carpeta-share (estado) y ~/CarpetaShare-Accesos (llaves generadas)."
  aviso "Bórralos a mano si ya no los quieres. Tailscale y SSH no se tocan."
  ok "Desinstalación completa."
  exit 0
fi

# =============================================================================
# Actualización rápida: git pull + reinstalar binarios/extensión, sin preguntas.
# También disponible desde cualquier carpeta como: carpeta-share actualizar
# =============================================================================
if [[ "${1:-}" == "--actualizar" ]]; then
  info "Actualizando Link_space…"
  if git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1; then
    git -C "$REPO" pull --ff-only || aviso "No pude hacer git pull; instalaré la versión local tal cual."
  else
    aviso "Esta copia no es un clon de git; instalo la versión local tal cual."
  fi
  sudo install -m 0755 "$AQUI/bin/carpeta-share" "$DESTINO_CLI"
  sudo install -m 0755 "$AQUI/bin/linkspace" "$DESTINO_LINKSPACE"
  sudo install -m 0755 "$AQUI/bin/carpeta-share-descargas" "$DESTINO_DESCARGAS"
  mkdir -p "$HOME/.config/carpeta-share"
  printf '%s\n' "$AQUI" > "$HOME/.config/carpeta-share/ruta_instalacion"
  # Extensión de VS Code: recompilar e instalar en silencio si se puede.
  if command -v npm >/dev/null 2>&1 && [[ -d "$AQUI/vscode-extension" ]]; then
    if (cd "$AQUI/vscode-extension" \
        && npm install --no-audit --no-fund >/dev/null 2>&1 \
        && npm run compile >/dev/null 2>&1 \
        && npx --yes @vscode/vsce package --allow-missing-repository -o carpeta-share.vsix >/dev/null 2>&1) \
       && CODE="$(buscar_code)"; then
      "$CODE" --install-extension "$AQUI/vscode-extension/carpeta-share.vsix" >/dev/null 2>&1 \
        && ok "Extensión de VS Code actualizada." || true
    fi
  fi
  ok "Actualizado a la versión $("$DESTINO_CLI" version)."
  exit 0
fi

# =============================================================================
# 1. Dependencias
# =============================================================================
info "Sistema detectado: $SO"

command -v python3 >/dev/null 2>&1 || {
  if es_macos; then err "Falta python3: ejecuta 'xcode-select --install' y vuelve a correr setup.sh"; fi
  err "Falta python3: instálalo con tu gestor de paquetes (apt install python3)."
}

# --- Paquetes de Linux (acl para setfacl, openssh-server, portapapeles) ------
if ! es_macos; then
  faltan=()
  command -v setfacl >/dev/null 2>&1 || faltan+=(acl)
  command -v sshd >/dev/null 2>&1 || [[ -x /usr/sbin/sshd ]] || faltan+=(openssh-server)
  command -v xclip >/dev/null 2>&1 || command -v wl-copy >/dev/null 2>&1 || faltan+=(xclip)
  if [[ ${#faltan[@]} -gt 0 ]]; then
    info "Instalando paquetes: ${faltan[*]}"
    if command -v apt-get >/dev/null 2>&1; then sudo apt-get install -y "${faltan[@]}"
    elif command -v dnf >/dev/null 2>&1; then sudo dnf install -y "${faltan[@]}"
    elif command -v pacman >/dev/null 2>&1; then sudo pacman -S --needed --noconfirm "${faltan[@]}"
    else aviso "Instala a mano: ${faltan[*]}"; fi
  fi
fi

# =============================================================================
# 2. SSH del sistema
# =============================================================================
if es_macos; then
  if sudo systemsetup -getremotelogin 2>/dev/null | grep -qi "on"; then
    ok "Remote Login (SSH) ya está activo."
  else
    info "Activando Remote Login (SSH)…"
    if sudo systemsetup -setremotelogin on 2>/dev/null; then
      ok "Remote Login activado."
    else
      aviso "macOS bloqueó el cambio por línea de comandos. Actívalo a mano:"
      aviso "  Ajustes del Sistema → General → Compartir → Sesión remota (ON)"
      aviso "  y marca 'Permitir acceso total al disco para los usuarios remotos'"
    fi
  fi
  aviso "IMPORTANTE (macOS): para compartir carpetas dentro de Escritorio/Documentos/Descargas,"
  aviso "activa 'Acceso total al disco' para los usuarios remotos en Compartir → Sesión remota (ⓘ)."
else
  info "Habilitando sshd…"
  sudo systemctl enable --now ssh 2>/dev/null || sudo systemctl enable --now sshd 2>/dev/null \
    || aviso "No pude habilitar sshd con systemctl; hazlo con tu init."
  ok "sshd habilitado."
fi

# =============================================================================
# 3. CLI
# =============================================================================
info "Instalando CLI en $DESTINO_CLI…"
sudo install -m 0755 "$AQUI/bin/carpeta-share" "$DESTINO_CLI"
sudo install -m 0755 "$AQUI/bin/linkspace" "$DESTINO_LINKSPACE"
sudo install -m 0755 "$AQUI/bin/carpeta-share-descargas" "$DESTINO_DESCARGAS"
mkdir -p "$HOME/.config/carpeta-share"
[[ -f "$HOME/.config/carpeta-share/estado.json" ]] || printf '{"invitados": {}, "carpetas": [], "config": {}}\n' > "$HOME/.config/carpeta-share/estado.json"
# Recordamos dónde vive el repo para que 'carpeta-share actualizar' funcione
# desde cualquier carpeta.
printf '%s\n' "$AQUI" > "$HOME/.config/carpeta-share/ruta_instalacion"
ok "CLI instalado. Prueba: carpeta-share estado  ·  o dentro de una carpeta: linkspace"

# =============================================================================
# 4. Clic derecho en el gestor de archivos
# =============================================================================
if es_macos; then
  # Quick Action de Automator generada por script: bundle .workflow con
  # Info.plist (declara el servicio de Finder para carpetas) y document.wflow
  # (un único "Run Shell Script" que recibe las rutas como argumentos).
  info "Creando Quick Action de Finder…"
  mkdir -p "$WF_DIR/Contents"

  cat > "$WF_DIR/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>NSServices</key>
	<array>
		<dict>
			<key>NSBackgroundColorName</key>
			<string>background</string>
			<key>NSIconName</key>
			<string>NSActionTemplate</string>
			<key>NSMenuItem</key>
			<dict>
				<key>default</key>
				<string>Compartir carpeta con VS Code</string>
			</dict>
			<key>NSMessage</key>
			<string>runWorkflowAsService</string>
			<key>NSRequiredContext</key>
			<dict>
				<key>NSApplicationIdentifier</key>
				<string>com.apple.finder</string>
			</dict>
			<key>NSSendFileTypes</key>
			<array>
				<string>public.folder</string>
			</array>
		</dict>
	</array>
</dict>
</plist>
PLIST

  cat > "$WF_DIR/Contents/document.wflow" <<'WFLOW'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>AMApplicationBuild</key>
	<string>528</string>
	<key>AMApplicationVersion</key>
	<string>2.10</string>
	<key>AMDocumentVersion</key>
	<string>2</string>
	<key>actions</key>
	<array>
		<dict>
			<key>action</key>
			<dict>
				<key>AMAccepts</key>
				<dict>
					<key>Container</key>
					<string>List</string>
					<key>Optional</key>
					<true/>
					<key>Types</key>
					<array>
						<string>com.apple.cocoa.string</string>
					</array>
				</dict>
				<key>AMActionVersion</key>
				<string>2.0.3</string>
				<key>AMApplication</key>
				<array>
					<string>Automator</string>
				</array>
				<key>AMParameterProperties</key>
				<dict>
					<key>COMMAND_STRING</key>
					<dict/>
					<key>CheckedForUserDefaultShell</key>
					<dict/>
					<key>inputMethod</key>
					<dict/>
					<key>shell</key>
					<dict/>
					<key>source</key>
					<dict/>
				</dict>
				<key>AMProvides</key>
				<dict>
					<key>Container</key>
					<string>List</string>
					<key>Types</key>
					<array>
						<string>com.apple.cocoa.string</string>
					</array>
				</dict>
				<key>ActionBundlePath</key>
				<string>/System/Library/Automator/Run Shell Script.action</string>
				<key>ActionName</key>
				<string>Run Shell Script</string>
				<key>ActionParameters</key>
				<dict>
					<key>COMMAND_STRING</key>
					<string>for f in "$@"; do
  if [ -d "$f" ]; then
    /usr/local/bin/carpeta-share compartir "$f" --gui || /usr/bin/osascript -e 'display notification "Error al compartir la carpeta" with title "carpeta-share"'
  fi
done</string>
					<key>CheckedForUserDefaultShell</key>
					<true/>
					<key>inputMethod</key>
					<integer>1</integer>
					<key>shell</key>
					<string>/bin/zsh</string>
					<key>source</key>
					<string></string>
				</dict>
				<key>BundleIdentifier</key>
				<string>com.apple.RunShellScript</string>
				<key>CFBundleVersion</key>
				<string>2.0.3</string>
				<key>CanShowSelectedItemsWhenRun</key>
				<false/>
				<key>CanShowWhenRun</key>
				<true/>
				<key>Category</key>
				<array>
					<string>AMCategoryUtilities</string>
				</array>
				<key>Class Name</key>
				<string>RunShellScriptAction</string>
				<key>InputUUID</key>
				<string>6ED0745D-92AA-4A63-A48C-01A3D001B2A1</string>
				<key>Keywords</key>
				<array/>
				<key>OutputUUID</key>
				<string>7C4B7C55-8B21-4A46-9C2B-02B3D001B2A2</string>
				<key>UUID</key>
				<string>8A1C7D66-3C42-4B57-8D3C-03C3D001B2A3</string>
				<key>UnlocalizedApplications</key>
				<array>
					<string>Automator</string>
				</array>
				<key>arguments</key>
				<dict/>
			</dict>
		</dict>
	</array>
	<key>connectors</key>
	<dict/>
	<key>workflowMetaData</key>
	<dict>
		<key>applicationBundleIDsByPath</key>
		<dict/>
		<key>applicationPaths</key>
		<array/>
		<key>inputTypeIdentifier</key>
		<string>com.apple.Automator.fileSystemObject.folder</string>
		<key>outputTypeIdentifier</key>
		<string>com.apple.Automator.nothing</string>
		<key>presentationMode</key>
		<integer>15</integer>
		<key>processesInput</key>
		<integer>0</integer>
		<key>serviceInputTypeIdentifier</key>
		<string>com.apple.Automator.fileSystemObject.folder</string>
		<key>serviceOutputTypeIdentifier</key>
		<string>com.apple.Automator.nothing</string>
		<key>serviceProcessesInput</key>
		<integer>0</integer>
		<key>systemImageName</key>
		<string>NSActionTemplate</string>
		<key>useAutomaticInputType</key>
		<integer>0</integer>
		<key>workflowTypeIdentifier</key>
		<string>com.apple.Automator.servicesMenu</string>
	</dict>
</dict>
</plist>
WFLOW

  # Pedimos a macOS que re-escanee los servicios; si el menú no aparece,
  # abrir el .workflow una vez con Automator lo registra seguro.
  /System/Library/CoreServices/pbs -update 2>/dev/null || /System/Library/CoreServices/pbs -flush 2>/dev/null || true
  ok "Quick Action creada: clic derecho sobre una carpeta → Acciones rápidas → 'Compartir carpeta con VS Code'."
  aviso "Si no aparece el menú, ábrela una vez con Automator para registrarla:"
  aviso "  open \"$WF_DIR\""
else
  # Nautilus (GNOME Files): script de usuario en el menú "Scripts".
  info "Instalando script de Nautilus…"
  mkdir -p "$(dirname "$NAUTILUS_SCRIPT")"
  cat > "$NAUTILUS_SCRIPT" <<'NSCRIPT'
#!/usr/bin/env bash
# Menú contextual de Nautilus: Scripts → Compartir carpeta con VS Code
IFS=$'\n'
for f in $NAUTILUS_SCRIPT_SELECTED_FILE_PATHS; do
  if [ -d "$f" ]; then
    /usr/local/bin/carpeta-share compartir "$f" --gui
  fi
done
NSCRIPT
  chmod +x "$NAUTILUS_SCRIPT"
  ok "Script de Nautilus instalado (clic derecho → Scripts)."

  # Dolphin (KDE): menú de servicio equivalente.
  mkdir -p "$(dirname "$DOLPHIN_MENU")"
  cat > "$DOLPHIN_MENU" <<'DESKTOP'
[Desktop Entry]
Type=Service
ServiceTypes=KonqPopupMenu/Plugin
MimeType=inode/directory;
Actions=compartirCarpeta;
X-KDE-Priority=TopLevel

[Desktop Action compartirCarpeta]
Name=Compartir carpeta con VS Code
Exec=/usr/local/bin/carpeta-share compartir %f --gui
Icon=folder-remote
DESKTOP
  ok "Menú de Dolphin instalado (si usas KDE)."
fi

# =============================================================================
# 5. Extensión de VS Code
# =============================================================================
EXT_DIR="$AQUI/vscode-extension"
if [[ -d "$EXT_DIR" ]]; then
  if command -v npm >/dev/null 2>&1; then
    info "Compilando la extensión de VS Code…"
    if (cd "$EXT_DIR" \
        && npm install --no-audit --no-fund >/dev/null 2>&1 \
        && npm run compile >/dev/null 2>&1 \
        && npx --yes @vscode/vsce package --allow-missing-repository -o carpeta-share.vsix >/dev/null 2>&1); then
      if CODE="$(buscar_code)"; then
        "$CODE" --install-extension "$EXT_DIR/carpeta-share.vsix" >/dev/null 2>&1 \
          && ok "Extensión instalada en VS Code (clic derecho en el explorador → 'Compartir carpeta…')." \
          || aviso "Extensión empaquetada pero no instalada. Instálala con: code --install-extension \"$EXT_DIR/carpeta-share.vsix\""
      else
        aviso "No encontré el CLI 'code'. Instala la extensión con:"
        aviso "  code --install-extension \"$EXT_DIR/carpeta-share.vsix\""
        aviso "  (En VS Code: Cmd+Shift+P → 'Shell Command: Install code command in PATH')"
      fi
    else
      aviso "No pude compilar/empaquetar la extensión automáticamente. A mano:"
      aviso "  cd \"$EXT_DIR\" && npm install && npm run compile && npx @vscode/vsce package --allow-missing-repository"
      aviso "  code --install-extension carpeta-share.vsix"
    fi
  else
    aviso "npm no está disponible: la extensión queda lista para compilar. Pasos:"
    aviso "  cd \"$EXT_DIR\" && npm install && npm run compile && npx @vscode/vsce package --allow-missing-repository"
    aviso "  code --install-extension carpeta-share.vsix"
  fi
fi

# =============================================================================
# 6. Resumen
# =============================================================================
cat <<RESUMEN

════════════════════════════════════════════════════════════════════
✓ Link_space instalado.

Próximos pasos:
 1. Tailscale encendido y con sesión (lo comprueba ./setup.sh de BosonCode).
 2. Comparte una carpeta (el flujo siempre ofrece las opciones):
      * ATAJO: entra a la carpeta y escribe:
          cd ~/Proyectos/algo && linkspace
        (pregunta si quieres contraseña generada, la tuya, o sin contraseña,
         y te deja el enlace en el portapapeles)
      * MODO WEB (el invitado NO instala nada; URL con o sin contraseña):
          carpeta-share compartir ~/Proyectos/algo --web --con-contrasena
        La primera vez, Tailscale te pedirá habilitar Funnel y HTTPS en tu
        tailnet (te muestra el enlace del panel; es un clic, una sola vez).
      * SOLO DESCARGA (enlace único para BAJAR un archivo, o una carpeta en
        .zip; quien lo abre no instala nada ni entra a tu equipo):
          carpeta-share compartir ~/Proyectos/algo --descarga
        o el atajo:  linkspace descarga ~/Documentos/informe.pdf
        Opcional: --expira 24h, --una-vez, --max-descargas 3, --con-contrasena
      * MODO VS CODE ESCRITORIO (más seguro; el invitado instala VS Code +
        Remote-SSH + Tailscale una vez):
          carpeta-share compartir ~/Proyectos/algo --sin-clave
        y comparte tu equipo con él en el panel de Tailscale:
          https://login.tailscale.com/admin/machines → ⋯ → "Share…"
      * o clic derecho en Finder/Nautilus/VS Code → "Compartir carpeta…"
 3. Estado general:  carpeta-share estado
════════════════════════════════════════════════════════════════════
RESUMEN
