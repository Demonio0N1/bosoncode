#!/usr/bin/env bash
# Pide la contraseña de administrador con una ventana.
#
# sudo lo ejecuta cuando no tiene terminal donde preguntar (Boson Server lo
# deja en SUDO_ASKPASS), le pasa su aviso como argumento y lee la contraseña
# de la salida. Es lo que permite que la instalación desde la app pida sudo
# igual que desde la terminal, sin guardar la contraseña en ningún sitio.
case "$(uname -s)" in
  Darwin)
    osascript \
      -e 'on run argv' \
      -e '  set r to display dialog (item 1 of argv) default answer "" with hidden answer with title "Boson Server" buttons {"Cancelar", "Aceptar"} default button "Aceptar" with icon caution' \
      -e '  return text returned of r' \
      -e 'end run' \
      "Boson Server necesita tu contraseña de administrador para seguir con la instalación." 2>/dev/null || exit 1
    ;;
  *)
    if command -v zenity >/dev/null 2>&1; then
      zenity --password --title="Boson Server" 2>/dev/null || exit 1
    elif command -v kdialog >/dev/null 2>&1; then
      kdialog --title "Boson Server" --password "Boson Server necesita tu contraseña de administrador para seguir con la instalación." 2>/dev/null || exit 1
    elif command -v ssh-askpass >/dev/null 2>&1; then
      ssh-askpass "Boson Server: contraseña de administrador" || exit 1
    else
      echo "no hay con qué pedir la contraseña: instala zenity (GNOME) o kdialog (KDE)" >&2
      exit 1
    fi
    ;;
esac
