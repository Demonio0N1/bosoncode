# Link_space

Comparte carpetas y archivos de tu computadora con **un enlace único**, sin
subir nada a la nube y sin abrir puertos en tu router. Todo sale directo de tu
máquina a través de [Tailscale](https://tailscale.com).

Link_space vive dentro del repositorio de BosonCode, en `linkspace/`, y lo
instala el mismo `./setup.sh` que deja el servidor de ZeroSpin. Aporta dos
comandos:

* **`linkspace`** — el atajo de una palabra: entras a una carpeta, lo escribes
  y sales con un enlace en el portapapeles.
* **`carpeta-share`** — el CLI completo: invitados, permisos, panel en vivo,
  revocación.

Y es lo que usa la app ZeroSpin para «Share with Link_space…»: un enlace de un
solo uso para descargar cualquier archivo o carpeta del equipo, creado desde el
iPad, el iPhone o el Mac.

Funciona en **macOS y Linux**.

## Tres formas de compartir

| | Enlace **web** | Enlace **VS Code escritorio** | Enlace de **solo descarga** |
|---|---|---|---|
| Qué recibe el invitado | VS Code en el navegador, con terminal y notebooks | Su VS Code nativo conectado por SSH | El archivo, o la carpeta en un `.zip` |
| El invitado instala | Nada | VS Code + Remote-SSH + Tailscale (una vez) | Nada |
| Protección | Contraseña opcional | Llave SSH | Token único; caducidad, límite de descargas y contraseña opcionales |
| Exposición | URL pública (Tailscale Funnel) | Solo tu red privada Tailscale | URL pública (el mismo Funnel) |
| Acceso a tu equipo | Editor + terminal, confinado a esa carpeta | Editor + terminal, confinado a esa carpeta | Ninguno: solo bajar eso |

## Instalación

```bash
git clone https://github.com/Demonio0N1/bosoncode.git
cd bosoncode
./setup.sh          # instala Tailscale si falta, el servidor de ZeroSpin y Link_space
```

`./setup.sh` instala los comandos en `/usr/local/bin` (pide administrador para
eso), el clic derecho del gestor de archivos y la extensión de VS Code si hay
`npm`. Con `./setup.sh --no-linkspace` se salta esta parte. Para instalar o
actualizar solo Link_space: `linkspace/instalar.sh` (o `linkspace actualizar`).

Requisitos: `python3` y Tailscale. Opcionales: `code-server` (para el modo
web; el servidor de ZeroSpin ya trae uno en `~/.ivscode`) y VS Code + `npm`
(para la extensión con el clic derecho "Compartir carpeta…").

## Uso en 30 segundos

```bash
# VS Code en el navegador para quien tenga el enlace (te pregunta la contraseña)
cd ~/Proyectos/tesis
linkspace

# Solo entregar algo: un enlace que únicamente permite descargarlo
linkspace descarga                          # la carpeta actual, como .zip
linkspace descarga ~/Documentos/informe.pdf # un archivo suelto
linkspace descarga contrato.pdf --una-vez --expira 24h --con-contrasena

# Ver quién está conectado ahora mismo y cortar accesos
linkspace panel
```

Lo mismo con el CLI completo:

| Quiero… | Comando |
|---|---|
| VS Code web con contraseña generada | `carpeta-share compartir <carpeta> --web --con-contrasena` |
| VS Code web con mi contraseña | `carpeta-share compartir <carpeta> --web --contrasena "MiClave123"` |
| Un enlace de solo descarga | `carpeta-share compartir <archivo-o-carpeta> --descarga` |
| …que caduque, de un solo uso y con contraseña | añade `--expira 24h`, `--una-vez` (o `--max-descargas 3`), `--con-contrasena` |
| VS Code de escritorio (el invitado me dio su llave) | `carpeta-share invitado agregar ana "ssh-ed25519 AAAA…"` y `carpeta-share compartir <carpeta> --con ana` |
| …o con las llaves de su cuenta de GitHub | `carpeta-share invitado agregar ana --github <usuario>` |
| VS Code de escritorio sin que el invitado genere llaves | `carpeta-share compartir <carpeta> --sin-clave` |
| Ver todo lo compartido | `carpeta-share estado` |
| Panel interactivo (uso en vivo, revocar) | `carpeta-share panel` |
| Dejar de compartir una carpeta | `carpeta-share dejar-de-compartir <carpeta>` |
| Revocar solo un enlace de descarga | `carpeta-share dejar-de-compartir <ruta> --descarga` |
| Cortar a un invitado | `carpeta-share invitado suspender\|reactivar\|eliminar <nombre>` |
| Actualizar a la última versión | `carpeta-share actualizar` |

También hay clic derecho en **Finder** (Acciones rápidas), **Nautilus/Dolphin**
y en el explorador de **VS Code**.

## Cómo funciona

```
 invitado ──https──▶ Tailscale Funnel ──▶ 127.0.0.1 en tu equipo
                                            ├─ /     code-server (modo web), como usuario invitado confinado
                                            └─ /dl   servidor de solo descarga (un token por archivo o carpeta)

 invitado ──ssh (red privada Tailscale)──▶ usuario invitado confinado (modo VS Code escritorio)
```

* **Modos web y escritorio:** cada invitado es un usuario real del sistema, sin
  contraseña utilizable y sin `sudo`. Solo recibe permisos (ACLs) sobre la
  carpeta compartida; el resto de tu disco no lo ve. Puede usar tus entornos
  de conda en solo lectura y crear los suyos.
* **Modo solo descarga:** no hay usuario, editor ni terminal. Un servidor
  mínimo de solo lectura, que escucha únicamente en `127.0.0.1`, entrega lo
  registrado para cada token (192 bits aleatorios); la carpeta se comprime al
  vuelo, sin los archivos ocultos (`.git`, `.env`…). Se publica en la ruta
  `/dl` del mismo Funnel que usa el modo web, así que no gasta puertos extra.
  El enlace abre una página con el nombre, el tamaño y un botón; puede
  caducar, limitarse a N descargas y pedir contraseña, y los archivos grandes
  se pueden reanudar si la descarga se corta.
* **Nada sale de tu equipo hasta que alguien abre el enlace**, y revocar es un
  comando: el acceso se corta al instante.

## Seguridad, en corto

* Los enlaces **web** y de **descarga** son URLs públicas: quien tenga el
  enlace (y la contraseña, si la pusiste) entra. Envía la contraseña por un
  canal distinto y trata los enlaces de descarga como contraseñas.
* En los modos web y escritorio el invitado **ejecuta código en tu máquina**
  como un usuario sin privilegios: comparte solo con gente de confianza.
* El modo solo descarga no permite subir, listar ni modificar nada, y la URL
  no lleva rutas: solo se puede bajar exactamente lo que compartiste. Para
  algo sensible, combínalo con `--una-vez`, `--expira` y `--con-contrasena`.

El detalle de qué puede y qué no puede hacer un invitado está en la
[documentación completa](GUIA.md#seguridad).

## Estructura

```
linkspace/
├── bin/
│   ├── carpeta-share             CLI principal (bash + python3)
│   ├── carpeta-share-descargas   servidor del modo solo descarga (python3, sin dependencias)
│   └── linkspace                 atajo interactivo
├── instalar.sh                   instalador / actualizador / desinstalador (lo llama ./setup.sh)
├── vscode-extension/             extensión: clic derecho → "Compartir carpeta…"
├── GUIA.md                       documentación completa
└── PRUEBAS.md                    checklist de verificación manual
```

## Documentación

* [Guía completa](GUIA.md): instalación paso a paso, cada modo
  en detalle, qué instala el invitado, notebooks y conda, administración y
  seguridad.
* [Checklist de pruebas](PRUEBAS.md).

## Ideas tomadas de otros proyectos

Varias funciones del modo solo descarga existen porque otras herramientas ya
habían demostrado que hacen falta. No se copió código; sí las ideas:

| Idea | Proyectos donde está |
|---|---|
| Caducidad y límite de descargas | [transfer.sh](https://github.com/dutchcoders/transfer.sh) (`Max-Days`, `Max-Downloads`), [PsiTransfer](https://github.com/psi-4ward/psitransfer), [Gokapi](https://github.com/Forceu/Gokapi) |
| Contraseña por enlace y página de descarga | [PsiTransfer](https://github.com/psi-4ward/psitransfer), [pingvin-share](https://github.com/stonith404/pingvin-share) |
| Descargas reanudables (HTTP Range) | [miniserve](https://github.com/svenstaro/miniserve), [dufs](https://github.com/sigoden/dufs), [HFS](https://github.com/rejetto/hfs) |
| Archivos ocultos (`.git`, `.env`…) fuera por defecto | [miniserve](https://github.com/svenstaro/miniserve), [copyparty](https://github.com/9001/copyparty) |
| Freno a la fuerza bruta de contraseñas | [HFS](https://github.com/rejetto/hfs) |
| Alta de invitados con las llaves de su cuenta de GitHub | [upterm](https://github.com/owenthereal/upterm) (`--authorized-user github:`) |

## Actualizar y desinstalar

```bash
carpeta-share actualizar        # git pull + reinstalar, sin tocar tu configuración

carpeta-share invitado eliminar <nombre>   # primero revoca accesos…
linkspace/instalar.sh --uninstall          # o ./setup.sh --uninstall de BosonCode, que lo incluye
```
