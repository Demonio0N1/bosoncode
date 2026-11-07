# Boson Server

La ventana del servidor de BosonCode, para Mac y Linux. Hace lo mismo que
`./setup.sh`, pero con pantalla: enseña si el equipo está sirviendo, la
dirección para ZeroSpin, el estado de Tailscale, las claves (la contraseña del
editor y el enlace del panel de sesiones de Claude), Claude Sessions Monitor y
el asistente de IA. Vive en la barra de menús del Mac o en la bandeja de Linux.

## Cómo funciona

La app no sabe nada por su cuenta. Todo lo que enseña sale de los scripts que
ya usa quien instala desde la terminal:

- `setup.sh --estado` devuelve el estado del equipo en JSON (sin secretos).
- `setup.sh --clave editor` y `--clave csm` dan la contraseña del editor y el
  enlace del panel con su token, solo cuando alguien pulsa «Mostrar» o «Copiar».

Así hay una sola verdad y la app es la cara, no otra copia de la lógica. Lo que
el script no sabe llega como `null` y la ventana lo dice como «desconocido».

Dónde busca los scripts, por orden: la variable `BOSON_REPO`, la raíz de este
repositorio cuando se ejecuta desde el código, y `Contents/Resources/scripts`
(o `/usr/lib/boson-server/scripts` en Linux) una vez instalada.

## Qué hace

- **Inicio**: si el equipo está sirviendo, la dirección para ZeroSpin (copiar,
  abrir, QR de emparejamiento con la contraseña dentro), lo que publica, y los
  botones de instalar, reparar, actualizar, reiniciar y detener el servidor.
- **Tailscale**: instalado, sesión, Serve, certificados, permiso de operador
  (Linux), lo publicado; iniciar sesión y volver a publicar.
- **Claves**: la contraseña del editor (mostrar, copiar, cambiar, generar otra)
  y el enlace del panel de sesiones con su token; en el Mac, el Acceso total al
  disco de la propia app, que es la que arranca el servidor.
- **Sesiones de Claude**: instalar el panel aquí, sumar este equipo al panel de
  otro (pegando su enlace), actualizar, abrir, copiar el enlace.
- **Asistente de IA**, **Simulador**, **Registro** y **Ajustes** (idioma,
  arrancar con la sesión, buscar actualizaciones).

Toda acción corre `setup.sh` con sus opciones y enseña la salida en vivo: los
pasos, los enlaces que hay que abrir (iniciar sesión en Tailscale, habilitar
Serve) y el registro completo. Cuando el script necesita que hagas algo tú,
termina con el código 10 y la app lo dice como «te toca», con el botón de volver
a intentar; no como un fallo.

### Administrador

Lo que necesita `sudo` (publicar en Linux, los comandos de Link_space, instalar
dependencias) lo pide con una ventana: la app deja `SUDO_ASKPASS` apuntando a
`askpass.sh` (copiado a `~/.ivscode/askpass.sh`), que en el Mac usa un diálogo
del sistema y en Linux `zenity`, `kdialog` o `ssh-askpass`. La contraseña no se
guarda en ningún sitio.

### El servidor lo lanza la app (Mac)

`boson-server --servir` ejecuta `~/.ivscode/serve.sh` y nada más. Al instalar
desde la app, el LaunchAgent apunta a ese binario, así que el permiso de Acceso
total al disco se concede a «Boson Server», una sola vez, desde Ajustes del
Sistema (la app tiene el botón). Sustituye a la envoltura «BosonCode Server.app»
que creaba `serve.sh --install-service` desde la terminal.

## Instaladores

`npm run tauri build` deja en `src-tauri/target/release/bundle/` el `.app` y el
`.dmg` en el Mac, y el `.deb` y el `.AppImage` en Linux. En GitHub,
`.github/workflows/boson-server.yml` los compila los tres al subir una etiqueta
`v1.2.3` y los adjunta a un borrador de versión.

El DMG solo abre sin avisos si va firmado con un certificado Developer ID y
notarizado: `./publicar-mac.sh` lo hace en este Mac con las variables
`APPLE_SIGNING_IDENTITY`, `APPLE_ID`, `APPLE_PASSWORD` y `APPLE_TEAM_ID` (en
GitHub, los mismos nombres como secretos). Sin firmar, macOS pide «abrir de
todos modos» la primera vez.

## Desarrollo

Hace falta Node 20+, Rust estable y, en Linux, `webkit2gtk-4.1`,
`libayatana-appindicator3` y `librsvg2` de desarrollo.

```bash
cd boson-server
npm install
npm run tauri dev            # la ventana con recarga en caliente
npm run tauri build --debug  # un .app (Mac) o binario (Linux) de prueba
npm run tauri build          # el .app y el .dmg; en Linux, .deb y .AppImage
```

El resultado queda en `src-tauri/target/<perfil>/bundle/`.

## Estructura

| Dónde | Qué |
|---|---|
| `src/` | La interfaz: React y TypeScript, sin más librerías. `textos.ts` lleva el español y el inglés. |
| `src/paginas/` | Una pantalla por archivo: Inicio, Tailscale, Claves, Sesiones, Asistente, Simulador, Registro, Ajustes. |
| `src/estado.ts` | El contrato con `setup.sh --estado`, tipado. |
| `src-tauri/src/lib.rs` | El lado nativo: ejecuta los scripts, el menú de la barra, abrir enlaces. |
| `src-tauri/iconos/` | El símbolo de Boson Code para la barra de menús (plantilla). |
| `src-tauri/icons/` | El icono de la app, generado del avatar de la marca con `npm run tauri icon`. |

La identidad visual es la de Boson Code (`branding/boson-code`): Manrope, Crema
y Carbón de día, Noche y Crema de noche, y el naranja solo para el punto y lo
que hay que pulsar. Sigue el modo claro u oscuro del sistema.
