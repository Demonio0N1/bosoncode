# Checklist de pruebas manuales

Marca cada casilla en orden. Necesitas: tu máquina (anfitrión) y una segunda
máquina (invitado) con su propia cuenta de Tailscale.

## En el anfitrión

### Instalación
- [ ] `./instalar.sh` (o el `./setup.sh` de BosonCode) termina sin errores y es re-ejecutable (correrlo 2 veces no rompe nada).
- [ ] `carpeta-share estado` muestra Tailscale activo (con nombre `*.ts.net`) y SSH activo en el puerto 22.
- [ ] macOS: clic derecho sobre una carpeta en Finder → Acciones rápidas → aparece "Compartir carpeta con VS Code". (Si no: `open ~/Library/Services/"Compartir carpeta con VS Code.workflow"` una vez con Automator.)
- [ ] VS Code: clic derecho sobre una carpeta del explorador → aparece "Compartir carpeta…".

### Alta de invitado (modo con llave)
- [ ] `carpeta-share invitado agregar prueba "<llave pública del invitado>"` crea el usuario `cs-prueba`.
- [ ] macOS: `cs-prueba` NO aparece en la pantalla de login. Linux: `passwd -S cs-prueba` muestra `L` (bloqueada).
- [ ] `/etc/ssh/sshd_config` contiene el bloque `# >>> carpeta-share: cs-prueba >>>` y `sshd -t` no da errores.

### Compartir
- [ ] `carpeta-share compartir ~/alguna/carpeta --con prueba` imprime el enlace `vscode://vscode-remote/ssh-remote+cs-prueba@...` y queda en el portapapeles (pégalo para verificar).
- [ ] `carpeta-share compartir <otra carpeta> --sin-clave` crea `~/CarpetaShare-Accesos/acceso1/` con `clave_carpeta_share`, `.pub` y `LEEME.txt` con el enlace.
- [ ] El flujo gráfico (Finder o VS Code) ofrece las dos opciones: invitado con llave y "nuevo acceso sin llave".
- [ ] `carpeta-share estado` lista la carpeta compartida con su invitado.
- [ ] Repetir el mismo `compartir` no duplica ACLs ni entradas en el estado (idempotencia).

### Modo web (enlace en el navegador)
- [ ] `carpeta-share compartir <carpeta> --web --con-contrasena` arranca code-server, activa Funnel e imprime URL `https://…ts.net/` + contraseña (URL en el portapapeles).
- [ ] La primera vez, si Funnel no está habilitado en el tailnet, el error muestra el enlace del panel para activarlo; tras activarlo, el mismo comando funciona.
- [ ] `carpeta-share estado` lista el enlace web con su URL, invitado (`webN`) y contraseña.
- [ ] Repetir el mismo comando es idempotente: conserva URL, puerto y contraseña.
- [ ] El proceso `code-server` corre como el usuario invitado `cs-webN` (verifica con `ps aux | grep code-server`), NO como tu usuario.
- [ ] `curl http://127.0.0.1:<puerto_local>` responde solo en localhost; desde otra máquina de tu LAN el puerto no es accesible.
- [ ] `carpeta-share compartir <otra> --web --sin-contrasena` avisa que cualquiera con la URL puede entrar.
- [ ] `carpeta-share dejar-de-compartir <carpeta>` mata el proceso code-server y la URL pública deja de responder.

### Modo solo descarga (enlace único con token)
- [ ] `carpeta-share compartir <carpeta> --descarga` imprime una URL `https://…ts.net/dl/<token>` (queda en el portapapeles) sin pedir contraseña de administrador en macOS.
- [ ] `carpeta-share compartir <archivo> --descarga` funciona también con un archivo suelto; sin `--descarga`, un archivo se rechaza con el aviso de usar `--descarga`.
- [ ] `linkspace descarga` (dentro de una carpeta) y `linkspace descarga <ruta>` dan el mismo resultado.
- [ ] Repetir el comando sobre la misma ruta devuelve el MISMO enlace (idempotencia); dos rutas distintas tienen tokens distintos.
- [ ] `tailscale funnel status` muestra `/dl` como ruta del puerto; si ya había un enlace web en ese puerto, su `/` sigue ahí y ambos funcionan.
- [ ] El servidor corre como TU usuario y solo en loopback: `ps aux | grep carpeta-share-descargas` y, desde otra máquina de tu LAN, el puerto local (13480) no responde.
- [ ] `carpeta-share estado` lista el enlace con su tipo (archivo/carpeta) y el número de descargas; tras descargar una vez, el contador sube.
- [ ] `carpeta-share dejar-de-compartir <ruta> --descarga` revoca el enlace: la URL responde 404 al instante. Si era el último, `ps` ya no muestra el servidor y `tailscale funnel status` ya no muestra `/dl`.
- [ ] Con un enlace web y uno de descarga en el mismo puerto, cerrar el enlace web NO rompe el de descarga (y viceversa).
- [ ] Tras matar el servidor (o reiniciar), `carpeta-share estado` avisa de que está apagado y repetir `compartir <ruta> --descarga` lo relanza con los mismos enlaces.
- [ ] `./instalar.sh --uninstall` se detiene si quedan enlaces de descarga activos y lista cómo revocarlos.

### Solo descarga: caducidad, límite, contraseña y ocultos
- [ ] `compartir <ruta> --descarga --expira 30m` muestra "Caduca en 30 min"; `estado` lo refleja y, pasado el tiempo, lo marca **CADUCADO** y la URL responde "Este enlace caducó".
- [ ] `--expira 5x` o `--max-descargas 0` se rechazan; `--expira` sin `--descarga` también.
- [ ] `--una-vez`: tras UNA descarga completa, la URL responde "ya alcanzó su número máximo de descargas" y `estado` muestra `1/1 descargas · AGOTADO`.
- [ ] Repetir el comando sobre un enlace vivo conserva el token y cambia solo lo pedido; sobre uno caducado o agotado genera un enlace NUEVO.
- [ ] `--con-contrasena` imprime una contraseña generada; repetirlo la conserva; `--contrasena "<8+ caracteres>"` pone la tuya; `--sin-contrasena` la quita.
- [ ] En una carpeta con `.git`/`.env`, el comando avisa de cuántos ocultos deja fuera y el `.zip` no los trae; con `--con-ocultos` sí.
- [ ] `carpeta-share invitado agregar <nombre> --github <usuario>` da de alta al invitado con las llaves de `https://github.com/<usuario>.keys`; con un usuario inexistente o sin llaves, falla sin crear nada.

### Panel de conexiones
- [ ] `carpeta-share panel` (o `linkspace panel`) lista las carpetas web y SSH con su invitado, URL y contraseña.
- [ ] Con el invitado conectado (navegador abierto o sesión SSH activa), el panel muestra `● EN USO` con el número de conexiones; al cerrar el navegador/sesión y refrescar (Enter), pasa a `○ libre`.
- [ ] Desde el panel, la acción [c] cierra un enlace web (la URL deja de responder al instante).
- [ ] Desde el panel, [s] suspende a un invitado con sesión abierta y su sesión se corta al momento.
- [ ] Desde el panel, [e] elimina un invitado por completo (igual que `invitado eliminar --si`).
- [ ] Los enlaces de solo descarga aparecen como `[DESCARGA]` con su URL y contador, y [c] los revoca al instante.

### Revocación
- [ ] `carpeta-share dejar-de-compartir <carpeta>` pide confirmación (y `--si` la salta); tras esto el invitado pierde acceso a la carpeta (verifícalo desde el invitado).
- [ ] `carpeta-share invitado suspender prueba` cierra la sesión abierta del invitado y bloquea nuevas conexiones.
- [ ] `carpeta-share invitado reactivar prueba` restaura el acceso.
- [ ] `carpeta-share invitado eliminar prueba` borra el usuario, su home, su bloque en sshd_config y sus ACLs (en la carpeta: `ls -led <carpeta>` en macOS / `getfacl <carpeta>` en Linux ya no muestran `cs-prueba`).

## En la máquina del invitado

### Modo web (no requiere instalar nada)
- [ ] Abrir la URL en un navegador cualquiera muestra la pantalla de contraseña (si el enlace la lleva) y, tras escribirla, VS Code con la carpeta compartida.
- [ ] Con enlace SIN contraseña, la URL abre VS Code directamente.
- [ ] La terminal integrada funciona (`whoami` → `cs-webN`) y `conda activate <env>` funciona.
- [ ] Puede instalar la extensión Jupyter (Open VSX) dentro del VS Code web y ejecutar un notebook con un kernel de conda del anfitrión.
- [ ] El confinamiento aplica igual: `ls /Users/<tu-usuario>` → *Permission denied*; `sudo` no disponible.
- [ ] Funciona también desde un celular o tablet (mismo enlace).

### Modo solo descarga (no requiere instalar nada)
- [ ] Abrir el enlace muestra una página con el nombre, el tamaño y el botón **Descargar** (legible en modo claro y oscuro, y en el celular).
- [ ] El botón descarga el archivo con su nombre original (acentos y espacios incluidos) y el contenido es idéntico al original.
- [ ] En una carpeta descarga `<carpeta>.zip`; al descomprimirlo están los archivos y subcarpetas (también las vacías), sin los ocultos.
- [ ] Funciona sin Tailscale en el invitado, desde un celular y con `curl -O <url-directa>`.
- [ ] Pegar el enlace de un solo uso en WhatsApp/Telegram (que generan vista previa) NO lo gasta: después sigue pudiéndose descargar una vez.
- [ ] Con contraseña: la página no muestra el nombre del archivo; una clave incorrecta dice "Contraseña incorrecta" y la correcta inicia la descarga. Tras 8 fallos seguidos, bloquea unos minutos.
- [ ] Cortar la descarga de un archivo grande y reanudarla (botón del navegador o `curl -C - -O <url-directa>`) termina con un archivo idéntico.
- [ ] Dos personas a la vez sobre un enlace de un solo uso: la segunda recibe "Alguien está descargando este enlace ahora mismo".
- [ ] Cambiar un carácter del token, o pedir `/dl/` a secas → *404 Enlace no válido o revocado*.
- [ ] Añadir rutas al enlace (`…/dl/<token>/../../etc/passwd`) NO da acceso a nada distinto de lo compartido.
- [ ] Un enlace simbólico dentro de la carpeta que apunte FUERA de ella no aparece en el `.zip`.
- [ ] No hay forma de subir ni modificar: `curl -X POST`/`PUT` contra el enlace es rechazado.

### Conexión (modo VS Code escritorio)
- [ ] Aceptó la invitación del nodo compartido; `tailscale status` muestra tu equipo.
- [ ] Con VS Code + Remote-SSH instalados, **abrir el enlace** abre VS Code conectado con la carpeta compartida como raíz del explorador.
- [ ] Puede crear, editar y borrar archivos dentro de la carpeta y tú ves los cambios al instante.

### Terminal y conda
- [ ] La terminal integrada abre una shell real del anfitrión como `cs-...` (`whoami` lo confirma).
- [ ] `conda env list` muestra los entornos del anfitrión y `conda activate <env>` funciona; `python -c "import sys; print(sys.executable)"` apunta al conda del anfitrión.
- [ ] `pip install` DENTRO de un entorno del anfitrión FALLA (solo lectura).
- [ ] `conda create -n mio python -y` funciona y el entorno queda en el home del invitado (`~/.conda/envs/mio`).
- [ ] Ejecutar un script: `python archivo.py` dentro de la carpeta funciona.

### Notebooks
- [ ] Con la extensión Jupyter, al abrir un `.ipynb` el selector de kernel ofrece los entornos de conda del anfitrión.
- [ ] Una celda con `import sys; sys.executable` ejecuta y muestra el python del entorno elegido (del anfitrión).

### Confinamiento (todo esto debe FALLAR)
- [ ] `ls /Users/<tu-usuario>` (o `/home/<tu-usuario>`) → *Permission denied* (puede atravesar, no listar).
- [ ] `cat` de un archivo tuyo fuera de la carpeta compartida → *Permission denied*.
- [ ] `sudo -l` / `sudo id` → no tiene sudo (pide contraseña que no existe / "not in the sudoers file").
- [ ] `ssh` con contraseña: `ssh -o PubkeyAuthentication=no cs-...@<host>` → rechazado sin siquiera pedir contraseña.
- [ ] Escribir en la instalación de conda del anfitrión (`touch <conda>/test`) → *Permission denied*.
- [ ] `ssh -A` (agent forwarding): `ssh-add -l` dentro de la sesión no ve tu agente.
