# carpeta-share

Comparte carpetas de tu computadora con otras personas mediante un enlace
único. El invitado abre el enlace y obtiene VS Code conectado a esa carpeta
**en tu máquina**: puede editar archivos, usar una terminal real, activar tus
entornos de conda y ejecutar notebooks — todo confinado a esa carpeta, sin
ver el resto de tu sistema.

Hay **tres tipos de enlace**, y el flujo de compartir siempre te deja elegir:

| | Enlace **web** | Enlace **VS Code escritorio** | Enlace de **solo descarga** |
|---|---|---|---|
| Qué recibe el invitado | VS Code en el navegador (code-server) | VS Code nativo de escritorio | El archivo, o la carpeta en un `.zip` |
| El invitado instala | **Nada** — abre la URL en su navegador | VS Code + Remote-SSH + Tailscale (una vez) | **Nada** — abre la URL y pulsa Descargar |
| Protección | Contraseña opcional (**con clave o no**) | Llave SSH (siempre) | Token único; caducidad, límite de descargas y contraseña opcionales |
| Exposición | URL pública en internet (Tailscale Funnel) | Solo tu red privada Tailscale | URL pública (el mismo Funnel) |
| Acceso a tu equipo | Editor + terminal, confinado a la carpeta | Editor + terminal, confinado a la carpeta | **Ninguno**: solo bajar eso |

**Cómo funciona por dentro:** usuarios invitados dedicados del sistema (sin
contraseña de login, sin sudo) + ACLs del sistema de archivos; el modo web usa
code-server publicado con Tailscale Funnel (sin abrir puertos en el router), y
el modo escritorio usa SSH por llave dentro de Tailscale con enlaces
`vscode://vscode-remote/ssh-remote+…`. El modo solo descarga no crea usuarios
ni da terminal: un servidor mínimo de solo lectura, en loopback, publicado en
la ruta `/dl` de ese mismo Funnel.

---

## Instalación (anfitrión) — 3 pasos

1. **Ejecuta el instalador** (macOS o Linux):

   ```bash
   git clone https://github.com/Demonio0N1/bosoncode.git
   cd bosoncode
   ./setup.sh
   ```

   Es el instalador de BosonCode: verifica/instala Tailscale, deja el servidor
   de ZeroSpin y, en su paso de Link_space, activa SSH, instala el CLI
   `carpeta-share`, el clic derecho de Finder/Nautilus y la extensión de VS
   Code. Solo esa parte, a mano: `linkspace/instalar.sh`.

2. **Enciende Tailscale** e inicia sesión: abre la app o corre `tailscale up`.

3. **Comparte tu equipo con cada invitado** desde el panel de Tailscale:
   <https://login.tailscale.com/admin/machines> → tu equipo → menú **⋯** →
   **Share…** → envíale el enlace de invitación. El invitado lo acepta con su
   propia cuenta de Tailscale y solo ve **este** equipo, no tu red.

> **macOS:** en Ajustes del Sistema → General → Compartir → **Sesión remota**,
> activa también "Permitir acceso total al disco para los usuarios remotos" si
> vas a compartir carpetas dentro de Escritorio/Documentos/Descargas (macOS
> las protege aparte).

---

## Compartir una carpeta

### El atajo: `linkspace`

Entra a la carpeta y escribe una sola palabra:

```
$ cd ~/Proyectos/tesis
$ linkspace
📁 Carpeta a compartir: /Users/tu/Proyectos/tesis

¿Proteger el enlace con contraseña?
  1) Sí, generar una segura (recomendado)
  2) Sí, escribir la mía
  3) No — cualquiera con el enlace podrá entrar

Opción [1]:
```

Y obtienes la URL (ya copiada al portapapeles) con la contraseña elegida.
También acepta una ruta: `linkspace ~/otra/carpeta`.

### Modo web — el invitado NO instala nada

```bash
carpeta-share compartir ~/Proyectos/tesis --web --con-contrasena   # contraseña generada
carpeta-share compartir ~/Proyectos/tesis --web --contrasena "MiClave123"  # la tuya
carpeta-share compartir ~/Proyectos/tesis --web --sin-contrasena   # URL abierta
```

Obtienes una URL `https://tu-equipo.xxxx.ts.net/` (queda en tu portapapeles)
y, si elegiste con contraseña, una contraseña generada. El invitado abre la
URL en **cualquier navegador** — computadora, tablet o celular — y ve VS Code
completo con editor, terminal, conda y notebooks. No instala absolutamente
nada.

La primera vez, Tailscale te pedirá habilitar **Funnel** y **HTTPS** en tu
tailnet: el propio comando te muestra el enlace del panel; es un clic, una
sola vez.

Cosas que debes saber del modo web:

* La URL es **pública en internet**: cualquiera que la tenga puede intentar
  entrar. Por eso el flujo te ofrece la opción **con contraseña** (envíala
  por un canal distinto al del enlace) o **sin contraseña** (solo para cosas
  no sensibles).
* Corre como un usuario invitado confinado igual que el modo escritorio
  (sin sudo, solo la carpeta, conda en solo lectura).
* Usa el marketplace Open VSX (la extensión de Jupyter está disponible; el
  invitado la instala dentro del propio VS Code web con dos clics).
* Si reinicias tu equipo, repite el mismo comando `compartir --web` para
  relanzar el servidor; los permisos y la contraseña se conservan.
* Hay un máximo de **3 enlaces web simultáneos** (límite de puertos de
  Funnel: 443, 8443 y 10000). Los enlaces de solo descarga no cuentan: van
  todos por la ruta `/dl` de uno de esos puertos.

### Modo solo descarga — un enlace para bajar y nada más

Para cuando solo quieres **entregar** algo: sin editor, sin terminal y sin
que nadie entre a tu equipo. Vale para una carpeta (se baja como `.zip`) o
para un archivo suelto:

```bash
carpeta-share compartir ~/Proyectos/tesis --descarga         # carpeta → tesis.zip
carpeta-share compartir ~/Documentos/informe.pdf --descarga  # archivo tal cual
linkspace descarga                                           # atajo: la carpeta actual
linkspace descarga ~/Documentos/informe.pdf --una-vez --expira 24h
```

Obtienes un enlace único (queda en tu portapapeles), del estilo
`https://tu-equipo.xxxx.ts.net/dl/Zk3…token…`. Quien lo abre ve una página
con el nombre, el tamaño y un botón **Descargar**. No instala nada y no
necesita Tailscale.

Condiciones opcionales (se pueden combinar):

| Opción | Efecto |
|---|---|
| `--expira 30m` / `24h` / `7d` | El enlace caduca pasado ese tiempo |
| `--max-descargas 3` | Deja de funcionar tras 3 descargas completas |
| `--una-vez` | Lo mismo que `--max-descargas 1` |
| `--con-contrasena` | Pide una contraseña generada (envíala por otro canal) |
| `--contrasena "MiClave123"` | Pide la contraseña que tú elijas (mínimo 8 caracteres) |
| `--con-ocultos` | Incluye en el `.zip` los archivos ocultos (ver abajo) |

Sin opciones, el enlace no caduca ni tiene límite: funciona hasta que lo
revoques.

Cosas que debes saber del modo solo descarga:

* **El token es la llave**: cualquiera que tenga el enlace puede descargar,
  salvo que le pongas contraseña. Trátalo como una contraseña. Cada archivo o
  carpeta tiene su propio token.
* **Repetir el comando no cambia el enlace**: sobre la misma ruta devuelve el
  mismo token y solo cambia lo que indiques (por ejemplo, `--expira 7d` para
  alargarlo o `--sin-contrasena` para quitarle la clave). Si el enlace ya
  caducó o se agotó, se crea uno nuevo.
* **Los archivos ocultos no viajan**: al comprimir una carpeta se dejan fuera
  los archivos y carpetas cuyo nombre empieza por punto (`.git`, `.env`,
  `.venv`, `.DS_Store`…), que es donde suelen vivir las credenciales. El
  comando te dice cuántos omitió; `--con-ocultos` los incluye. Tampoco se
  incluyen los enlaces simbólicos que apunten fuera de la carpeta.
* **La página protege el límite**: los chats (WhatsApp, Telegram, Slack…)
  abren cada enlace que ven para generar la vista previa. Como el enlace
  lleva a una página y no al archivo, esa visita no gasta una descarga.
* **Una descarga cuenta cuando termina entera.** Si se corta a mitad, un
  enlace de un solo uso sigue disponible; dos personas no pueden bajarlo a la
  vez.
* **Descargas reanudables**: si se corta la descarga de un archivo grande, el
  navegador (o `curl -C -`) continúa donde iba. Solo en enlaces sin límite de
  descargas ni contraseña, y no en carpetas (el `.zip` se genera al vuelo).
* **Desde la terminal**: el comando imprime también la URL directa
  (`…/dl/<token>/<nombre>`), que sirve para `curl -O` o `wget`. Con
  contraseña: `curl -OJ -d clave=TU_CLAVE <url-directa>`.
* **Reutiliza el Funnel del modo web**: se publica en la ruta `/dl` del puerto
  que ya use un enlace web tuyo (o, si no hay ninguno, en el primero de Funnel
  que esté libre: normalmente el 443), así que convive con ellos y no consume
  ninguno de los 3 puertos de Funnel. Nunca se monta sobre un
  `tailscale serve` tuyo que no sea de carpeta-share.
* **La carpeta se comprime al vuelo**, sin archivos temporales, con lo que
  haya en ese momento: si cambias algo, la próxima descarga ya lo trae.
* **No hace falta root** (en macOS): no se crean usuarios ni ACLs. El
  servidor corre como tú, solo en `127.0.0.1`, y únicamente sabe entregar lo
  que registraste. En Linux, Tailscale pide `sudo` para tocar Funnel salvo
  que seas su *operator* (`sudo tailscale set --operator=$USER`).
* **Revocar** es inmediato: `carpeta-share dejar-de-compartir <ruta>
  --descarga` (o desde el panel). Al revocar el último enlace se apaga el
  servidor y se despublica `/dl`.
* Si reinicias tu equipo, repite `compartir <ruta> --descarga` con cualquiera
  de tus rutas: relanza el servidor y **todos** los enlaces vuelven a
  funcionar, con sus mismos tokens y contadores.
* `carpeta-share estado` y el panel muestran, por enlace, cuántas descargas
  lleva, cuándo fue la última, cuánto le queda y si está **CADUCADO** o
  **AGOTADO** (registro de accesos en `~/.config/carpeta-share/descargas.log`).

### Modo VS Code escritorio

El invitado instala una sola vez VS Code + Remote-SSH + Tailscale (y acepta
tu invitación de nodo compartido). A cambio, el enlace nunca sale de tu red
privada y la autenticación es siempre por llave SSH. Dos variantes:

#### Modo A — con llave (recomendado)

El invitado genera su llave **una sola vez** y te manda la parte pública:

```bash
# (en la máquina del invitado)
ssh-keygen -t ed25519            # Enter a todo; crea ~/.ssh/id_ed25519
cat ~/.ssh/id_ed25519.pub        # ← te envía ESTA línea (empieza con ssh-ed25519)
```

Tú lo das de alta y compartes:

```bash
carpeta-share invitado agregar ana "ssh-ed25519 AAAA... ana@laptop"
carpeta-share compartir ~/Proyectos/tesis --con ana
```

Si el invitado tiene cuenta de **GitHub** con llaves SSH cargadas, no hace
falta que te mande nada: basta su nombre de usuario.

```bash
carpeta-share invitado agregar ana --github ana-dev   # usa https://github.com/ana-dev.keys
```

Comprueba bien el nombre: quien controle esa cuenta de GitHub es quien podrá
entrar.

#### Modo B — sin llave (el invitado no sabe/quiere generar llaves)

```bash
carpeta-share compartir ~/Proyectos/tesis --sin-clave
```

La herramienta genera el par de llaves por ti, crea el usuario invitado y
deja un **paquete** en `~/CarpetaShare-Accesos/<nombre>/` con la llave
privada + `LEEME.txt` (instrucciones paso a paso + el enlace). Envíale la
carpeta completa (zip) por un canal razonablemente privado. Es menos seguro
que el modo A porque la llave privada viaja por tu canal de envío.

### Desde la interfaz gráfica

* **Finder (macOS):** clic derecho sobre una carpeta → *Acciones rápidas* →
  **Compartir carpeta con VS Code**. Si el menú no aparece tras instalar,
  ábrela una vez con Automator:
  `open ~/Library/Services/"Compartir carpeta con VS Code.workflow"`
* **Nautilus (Linux):** clic derecho → *Scripts* → **Compartir carpeta con VS
  Code** (en KDE/Dolphin aparece directamente en el menú contextual).
* **VS Code:** clic derecho sobre una carpeta en el explorador →
  **Compartir carpeta…** → eliges enlace web (con o sin contraseña), solo
  descarga, invitado existente o "nuevo acceso sin llave" → el enlace queda
  copiado. Sobre un **archivo**: clic derecho → **Compartir enlace de
  descarga…** En ambos casos puedes marcar caducidad, un solo uso y
  contraseña.

En Finder y Nautilus el menú de opciones incluye también **Enlace de SOLO
DESCARGA (.zip)** y su variante **de un solo uso que caduca en 24 h**.

En todos los casos el enlace queda **copiado en tu portapapeles**, listo para
WhatsApp o correo.

---

## Qué necesita instalar el invitado

**Enlace web: nada.** Abre la URL en su navegador y escribe la contraseña si
el enlace la lleva. Eso es todo.

**Enlace de solo descarga: nada.** Abre la URL, escribe la contraseña si el
enlace la lleva y pulsa **Descargar**: baja el archivo (o el `.zip` de la
carpeta).

**Enlace VS Code escritorio** (una sola vez):

1. **VS Code de escritorio** + extensión **Remote - SSH** (y **Jupyter** si
   usará notebooks).
2. **Tailscale**, con sesión iniciada en su propia cuenta.
3. **Aceptar tu invitación** de nodo compartido de Tailscale.
4. Haberte dado su llave pública (modo A) **o** instalar el paquete de acceso
   que le enviaste (modo B; el `LEEME.txt` lo guía).

Después, solo abre el enlace `vscode://…` que le mandaste: su VS Code se
conecta y abre la carpeta. La primera conexión tarda un poco (VS Code instala
su componente remoto en tu máquina, dentro del home del invitado).

## Notebooks y conda (invitado)

* La terminal integrada ya trae `conda` configurado: `conda activate <env>`
  activa **tus** entornos (solo lectura — puede usarlos, no modificarlos).
* `conda create -n suyo python=3.12` funciona: sus entornos y paquetes se
  guardan en **su** home de invitado (`CONDA_ENVS_PATH`/`CONDA_PKGS_DIRS`),
  nunca en tu instalación.
* En un `.ipynb`, con la extensión Jupyter, el selector de kernel muestra los
  entornos de conda del anfitrión; el notebook se ejecuta en tu máquina.

---

## Administración diaria

### Panel de conexiones

```bash
carpeta-share panel     # o: linkspace panel
```

Un panel interactivo en la terminal que muestra cada carpeta compartida y su
estado **en vivo**:

```
════════════════ carpeta-share · panel ════════════════  18:42:10

  CARPETAS COMPARTIDAS
   1) [WEB] ~/Proyectos/tesis
        invitado web1       ● EN USO (2 conexión/es)
        https://mi-equipo.tailxxxx.ts.net/  (contraseña: f52pFbTSLyXR)
   2) [SSH] ~/Proyectos/datos
        invitado ana        ○ libre
   3) [DESCARGA] ~/Documentos/informe.pdf
        archivo · 1/3 descargas · caduca en 5 h · última: 2026-10-05 18:20
        https://mi-equipo.tailxxxx.ts.net/dl/Zk3vQ…

  INVITADOS
   4) ana          usuario cs-ana      modo clave    activo
   5) web1         usuario cs-web1     modo web      activo

  [número] gestionar · [Enter] refrescar · [q] salir
```

`● EN USO` significa que hay conexiones abiertas en este momento (pestañas
del navegador en modo web, sesiones SSH en modo escritorio). Eliges un número
y puedes **cerrar el enlace**, **suspender** (corta las sesiones al instante,
reversible), **eliminar al invitado por completo** o **revocar un enlace de
descarga** — sin recordar comandos.

### Comandos sueltos

```bash
carpeta-share estado                          # invitados, carpetas, Tailscale/SSH
carpeta-share dejar-de-compartir <carpeta>    # retira las ACLs (y su enlace de descarga)
carpeta-share dejar-de-compartir <ruta> --descarga   # revoca solo el enlace de descarga
carpeta-share invitado suspender ana          # corta el acceso (reversible)
carpeta-share invitado reactivar ana
carpeta-share invitado eliminar ana           # borra usuario, ACLs y bloque sshd
```

Las acciones destructivas piden confirmación; añade `--si` para saltarla.

## Seguridad

**Lo que el invitado SÍ puede hacer:**

* Leer/escribir la carpeta compartida (y solo esa).
* Usar una terminal como su usuario invitado, ejecutar scripts y notebooks.
* Usar tus entornos de conda en solo lectura y crear entornos propios.
* Redirigir puertos TCP (necesario para Remote-SSH/Jupyter).

**Seguridad específica del modo web:**

* La URL de Funnel es alcanzable desde todo internet; la contraseña del
  enlace es la única barrera. Prefiere siempre **con contraseña** y envíala
  por un canal distinto al del enlace.
* code-server corre solo en `127.0.0.1` (nadie de tu red local entra
  directo) y como el usuario invitado confinado, nunca como tú.
* `carpeta-share dejar-de-compartir <carpeta>` apaga el servidor **y**
  despublica la URL de Funnel al instante.

**Seguridad específica del modo solo descarga:**

* El enlace **solo permite descargar** lo que registraste para ese token: no
  hay editor, terminal, subida de archivos ni listado de carpetas. La URL no
  lleva rutas —solo el token y un nombre decorativo—, así que no existe forma
  de pedir otro archivo.
* El token (192 bits aleatorios) es la barrera principal, y la URL es
  alcanzable desde todo internet. Para algo sensible súmale **contraseña**
  (por un canal distinto), **caducidad** y **un solo uso**: si el enlace se
  filtra, el daño queda acotado.
* Con contraseña, la página no muestra ni el nombre ni el tamaño hasta que se
  acierta, y tras 8 fallos en 10 minutos el enlace se bloquea un rato (quien
  tenga el enlace puede provocar ese bloqueo; se levanta solo).
* El límite cuenta descargas **completas**: quien corte la descarga antes del
  final no la gasta, así que un enlace de un solo uso no garantiza que nadie
  más haya leído parte del archivo.
* Los archivos ocultos (`.git`, `.env`…) quedan fuera del `.zip` salvo que
  uses `--con-ocultos`. Aun así, revisa qué hay en la carpeta antes de
  compartirla.
* El servidor corre como **tu** usuario (nunca como root), escucha solo en
  `127.0.0.1` y relee el estado en cada petición: un enlace revocado deja de
  funcionar en el acto. Solo acepta GET/HEAD, más un POST que únicamente lee
  la contraseña del formulario.

**Lo que NO puede hacer (modos web y escritorio):**

* Entrar con contraseña de sistema (no existe: los usuarios invitados tienen
  el login bloqueado; en SSH además sshd la rechaza).
* Usar `sudo` (no es administrador) ni leer tu home u otras carpetas: los
  directorios padres solo tienen permiso de *tránsito* (atravesar sin listar).
* Modificar tu conda, usar tu agente SSH o tu pantalla (agent/X11 forwarding
  deshabilitados por bloque `Match User` en sshd).

**Revocar acceso en un comando:**

```bash
carpeta-share invitado suspender ana   # inmediato y reversible
# o, definitivo:
carpeta-share invitado eliminar ana --si
```

También puedes dejar de compartir tu equipo desde el panel de Tailscale
(corta la red por completo).

**Límites honestos:** el invitado ejecuta código real en tu máquina como un
usuario sin privilegios. Eso es lo que pediste (kernels, terminal), pero
significa que puede consumir CPU/RAM/disco y acceder a Internet desde tu IP.
Comparte solo con gente en la que confíes a ese nivel. Revisa además que tu
home no sea legible por otros (`chmod 750 ~` si hace falta; el CLI te avisa).

## Actualizar

```bash
carpeta-share actualizar     # o: linkspace actualizar
```

Hace `git pull` en el repositorio, reinstala los comandos y actualiza la
extensión de VS Code, sin preguntas. (Equivale a `linkspace/instalar.sh
--actualizar` dentro del repositorio de BosonCode.) Tu configuración, invitados y carpetas compartidas no se
tocan.

## Desinstalar

```bash
# primero elimina los invitados (revierte usuarios, ACLs y sshd_config):
carpeta-share invitado eliminar <nombre>
linkspace/instalar.sh --uninstall     # solo Link_space; ./setup.sh --uninstall de BosonCode lo incluye
```

## Pruebas

Checklist completo de verificación manual en [PRUEBAS.md](PRUEBAS.md).
