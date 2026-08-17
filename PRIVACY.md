# Privacy Policy — BosonCode and ZeroSpin

*Last updated: 13 August 2026 · [Versión en español](#política-de-privacidad--bosoncode-y-zerospin)*

**Neither app collects, transmits or stores any personal data.**

There is no account to create, no sign-up, no analytics, no advertising, no
crash reporting and no third-party SDK of any kind. Nothing is sent to the
developer, because there is no server belonging to the developer for it to be
sent to.

## What the apps connect to

**Only the machines you enter yourself.** BosonCode connects to computers you
add by address — your own, on your own Tailscale network. ZeroSpin reads that
same list so it can send a file to one of them when you ask it to.

There is no other network destination. No telemetry endpoint, no update check,
no content delivery network.

## What is stored on your device, and where

| What | Where | Why |
|---|---|---|
| Machine addresses and names | On the device, in the app group | So the list survives a restart |
| Machine passwords | iPad Keychain | So you type them once |
| Your preferences | On the device | Appearance, column widths, view mode |
| Permissions for folders you granted | On the device, as security-scoped bookmarks | So a mounted cloud stays mounted |

All of it stays on the device. None of it is transmitted anywhere. Deleting the
app removes all of it, including the Keychain entries.

## Your files

ZeroSpin can read and write files. It only touches:

- its own documents folder, and
- folders you explicitly granted through the system picker.

iPadOS enforces this; the app cannot reach anything else even if it tried. Files
are never copied, indexed or uploaded anywhere except when you ask for it —
sending a notebook to one of your own machines, for example.

## Photos

ZeroSpin can receive images dragged in from Photos. That is a system drag and
drop: iPadOS hands over the image you dragged, and nothing else. The app does
not read your photo library.

## Children

Neither app is directed at children and neither collects data from anyone.

## Changes

If this ever changes, this document changes with it, and the date at the top
tells you when.

## Contact

Questions about this policy: open an issue at
<https://github.com/Demonio0N1/bosoncode>.

---

# Política de privacidad — BosonCode y ZeroSpin

*Última actualización: 13 de agosto de 2026 · [English version](#privacy-policy--bosoncode-and-zerospin)*

**Ninguna de las dos apps recoge, transmite ni almacena datos personales.**

No hay cuenta que crear, ni registro, ni analítica, ni publicidad, ni informes
de fallos, ni SDK de terceros de ningún tipo. No se envía nada al desarrollador,
porque no existe ningún servidor del desarrollador al que enviarlo.

## Con qué se conectan las apps

**Solo con los equipos que tú escribes.** BosonCode se conecta a ordenadores que
añades por su dirección — los tuyos, en tu propia red de Tailscale. ZeroSpin lee
esa misma lista para poder mandarles un archivo cuando se lo pides.

No hay ningún otro destino de red. Ni servidor de telemetría, ni comprobación de
actualizaciones, ni red de distribución de contenidos.

## Qué se guarda en tu dispositivo, y dónde

| Qué | Dónde | Para qué |
|---|---|---|
| Direcciones y nombres de equipos | En el dispositivo, en el grupo de apps | Para que la lista sobreviva a un reinicio |
| Contraseñas de los equipos | Llavero del iPad | Para escribirlas una sola vez |
| Tus preferencias | En el dispositivo | Aspecto, ancho de columnas, modo de vista |
| Permisos de las carpetas que concediste | En el dispositivo, como marcadores con ámbito de seguridad | Para que una nube montada siga montada |

Todo se queda en el dispositivo. Nada se transmite a ningún sitio. Borrar la app
lo elimina todo, incluidas las entradas del Llavero.

## Tus archivos

ZeroSpin puede leer y escribir archivos. Solo toca:

- su propia carpeta de documentos, y
- las carpetas que hayas concedido explícitamente con el selector del sistema.

iPadOS lo impone; la app no podría alcanzar nada más aunque lo intentara. Los
archivos no se copian, ni se indexan, ni se suben a ninguna parte salvo cuando
tú lo pides — mandar un notebook a una de tus propias máquinas, por ejemplo.

## Fotos

ZeroSpin puede recibir imágenes arrastradas desde Fotos. Eso es un arrastre del
sistema: iPadOS entrega la imagen que arrastraste y nada más. La app no lee tu
fototeca.

## Menores

Ninguna de las dos apps está dirigida a menores y ninguna recoge datos de nadie.

## Cambios

Si esto cambiara alguna vez, este documento cambia con ello, y la fecha de
arriba dice cuándo.

## Contacto

Dudas sobre esta política: abre una incidencia en
<https://github.com/Demonio0N1/bosoncode>.
