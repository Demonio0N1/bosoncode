# BosonCode

*[Read this in English](README.md)*

**Un cliente nativo de iPadOS para [code-server](https://github.com/coder/code-server).**
Editas en el iPad, calcula tu ordenador — por Tailscale y sin abrir un solo puerto.

El repositorio contiene además **ZeroSpin**, un gestor de archivos al estilo del
Finder de macOS para iPadOS, que comparte el mismo cliente de servidor.

> BosonCode es un cliente independiente de code-server. Visual Studio Code es
> una marca registrada de Microsoft Corporation. Sin afiliación ni respaldo de
> Microsoft.

---

## Qué obtienes

| | |
|---|---|
| **VS Code completo** | Extensiones, notebooks de Jupyter, terminal integrada |
| **Tu hardware** | Python, Julia, PyTorch y CUDA corren en el equipo, no en la tableta |
| **Terminal nativa** | SwiftTerm sobre un canal PTY, en su propia ventana de iPadOS |
| **Ventanas independientes** | Cada ventana mira una máquina distinta; la lista se comparte, la selección no |
| **Descubrimiento sin configurar** | Los equipos se anuncian por mDNS y la app los encuentra |
| **Máquinas Docker** | Crea, arranca, detén y elimina contenedores desde la app |
| **SSH** | Salta de un equipo a cualquier otro que él alcance |
| **Ventana de simulador** | El simulador de iOS o el emulador de Android de tu equipo, en el iPad, con toques |
| **Sin puertos abiertos** | Solo Tailscale — el equipo nunca queda expuesto a internet |

### En la terminal

- `⌃⌥T` abre una terminal en su propia ventana, desde el momento en que entras
  en una máquina.
- Cada ventana tiene su sesión de tmux, así que los shells son independientes en
  vez de estar duplicados.
- El desplazamiento con dos dedos recorre el historial de tmux, con inercia. Con
  un dedo se selecciona.
- **Suelta un archivo encima** —desde Archivos, Fotos, donde sea— y se sube a la
  máquina, con su ruta remota ya escrita en el prompt, lista para un comando.
- El modo claro y oscuro sigue al iPad, y la paleta y la tipografía se pueden
  cambiar.

---

## ZeroSpin

Un gestor de archivos al estilo Finder para iPadOS, en este mismo repositorio y
compartiendo el cliente de servidor. Lee la lista de equipos de BosonCode, así
que las máquinas que ya añadiste están disponibles también aquí.

| | |
|---|---|
| **Disposición de Finder** | Columnas, lista e iconos; barra lateral flotante con selección en burbuja |
| **Ventanas, no hojas** | Las vistas previas, el editor de texto y los notebooks abren cada uno su ventana de iPadOS |
| **Editor de texto y scripts** | Monoespaciado, con resaltado, `⌘S`, guarda en el propio archivo |
| **Visor de notebooks** | `.ipynb` con sus celdas, su Markdown y sus resultados |
| **Editor de imágenes** | Dibuja sobre una imagen con PencilKit y guarda el resultado |
| **Nubes montadas** | OneDrive, Drive, Dropbox… se conceden una vez y se conservan |
| **Arrastrar y soltar** | En los dos sentidos, incluidas fotos, que llegan como datos de imagen y no como archivos |
| **Ejecutar en BosonCode** | Manda un notebook o un script a una máquina y ábrelo allí |

### Lo que iPadOS no permite

Dos límites que conviene decir, porque se preguntan a menudo y no hay código que
los sortee:

- **Una app no puede poner el fondo de pantalla del sistema.** El «usar como
  fondo» de ZeroSpin cambia el fondo de su propia ventana. El del dispositivo
  solo lo cambian Ajustes y Fotos.
- **Una app no puede abrir un archivo en otra app en silencio.** No hay
  asociación tipo → app que consultar, y `UIApplication.open` rechaza las URL
  `file://`. La app Archivos lo consigue con privilegios del sistema que las
  apps de terceros no reciben — `UIDocumentBrowserViewController` tampoco los
  concede: su propia documentación dice que abre documentos *en tu* aplicación.
  «Abrir con…» muestra la lista del sistema de apps capaces, que es lo más
  cerca que llega una app de terceros.

---

## Preparar el equipo

### Un solo comando

```bash
git clone https://github.com/Demonio0N1/bosoncode.git
cd bosoncode
./setup.sh
```

Eso instala Tailscale si falta, comprueba que la sesión esté iniciada, instala
code-server, deja el servidor instalado como servicio y anuncia el equipo. Al
terminar imprime la dirección y la contraseña, y tu equipo aparece solo en la
app.

Queda puesto para siempre: sobrevive a cerrar la terminal y vuelve solo al
encender el equipo. Es lo que hace falta para que el iPad no se quede sin
servidor por haber cerrado una ventana.

```bash
./setup.sh --check        # solo diagnostica, no toca nada
./setup.sh --foreground   # lo arranca atado a esta terminal (para depurar)
./setup.sh --password     # vuelve a enseñar la contraseña de este equipo
```

La contraseña se genera una vez y se enseña al arrancar el servidor. Ese momento
suele quedar semanas antes de que vuelva a hacer falta —añadir otro iPad,
reinstalar la app—, así que `--password` la imprime cuando quieras. También está
en `~/.ivscode/password`.

**Instala Tailscale también en el iPad**, con la misma cuenta —
[App Store](https://apps.apple.com/app/tailscale/id1470499037). Es el paso que
más gente se salta, y su ausencia se manifiesta como *«mi equipo no aparece»*,
que manda a buscar el problema donde no está. Las dos puntas o nada: es lo que
sustituye a abrir un puerto.

El resto de esta sección es lo que hace `setup.sh`, por si prefieres hacerlo a
mano o algo falla.

### Requisitos

- Linux o macOS. Sin root y sin Docker para lo básico.
- [Tailscale](https://tailscale.com/download) instalado y con sesión iniciada en
  el equipo **y** en el iPad.

### 1. Tailscale

Instálalo e inicia sesión con la misma cuenta en los dos dispositivos:

```bash
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up
```

Y deja que tu usuario gestione `tailscale serve`, que es lo que publica el HTTPS:

```bash
sudo tailscale set --operator=$USER
```

**Aquí el HTTPS no es opcional.** Los notebooks de Jupyter dentro de code-server
dependen de Service Workers, y los navegadores se niegan a registrarlos sobre
HTTP a secas. `serve.sh` usa `tailscale serve` para obtener un certificado real
para tu nombre `*.ts.net`.

### 2. Arrancar el servidor

```bash
git clone https://github.com/Demonio0N1/bosoncode.git
cd bosoncode
./serve.sh
```

Eso es todo. El script descarga un `code-server` independiente en `~/.ivscode`,
lo arranca, lo publica por HTTPS a través de Tailscale y anuncia el equipo por
mDNS para que la app lo liste sola.

Opciones:

```bash
./serve.sh --name "Equipo del laboratorio"   # nombre que se ve en la tarjeta
./serve.sh --port 8443                       # puerto local (por defecto 8443)
./serve.sh --password "…"                    # por defecto: generada una vez y guardada
./serve.sh --install-service                 # arranca solo al encender
./serve.sh --install-idb                     # (macOS) toques en el simulador de iOS
./serve.sh --help
```

`--install-service` instala un servicio de systemd **de usuario** en Linux (con
*linger* activado, para que sobreviva al cierre de sesión) o un LaunchAgent en
macOS.

### 3. Tu contraseña

`serve.sh` genera una contraseña aleatoria la primera vez y la guarda en
`~/.ivscode/password` con permisos `600`. Nunca se escribe en los registros, así
que léela del equipo cuando la necesites:

```bash
./setup.sh --password        # la enseña junto con el nombre y la dirección
cat ~/.ivscode/password      # o directamente el archivo
```

Dos cosas que conviene saber antes de que te sorprendan:

- **La contraseña va atada a `~/.ivscode`.** Si borras esa carpeta, el siguiente
  arranque genera otra *nueva* y la anterior deja de valer. Es la causa más
  frecuente de que el acceso falle de golpe tras reinstalar desde cero.
- **Reinstalar la app borra la credencial guardada**, porque vive en el Llavero
  del iPad y iOS lo borra junto con la app. Te la volverá a pedir.

Puedes poner la tuya en cualquier momento:

```bash
./serve.sh --password "tu-contraseña"
```

Usado junto con `--install-service`, se escribe en `~/.ivscode/password` antes de
que arranque el servicio, así que el servicio también la recoge.

### 4. Conectar desde el iPad

Abre BosonCode. Tu equipo aparece solo en la cuadrícula: tócalo, escribe la
contraseña una vez y queda guardada en el Llavero del iPad.

Si no aparece, añádelo a mano. Basta el **nombre de Tailscale** —`mi-pc`— y la
app le pone el sufijo del tailnet y el puerto; también acepta la dirección
completa que imprime `setup.sh`.

> **Con el iPad en otra red, el descubrimiento automático no puede funcionar.**
> Es mDNS, que es multicast local, y Tailscale no lo transporta. Añadirlo por su
> nombre es entonces la única vía, y funciona desde cualquier sitio.

---

## La ventana del simulador

`⌃⌥S`, o el botón de móvil junto al de la terminal, abre una ventana con un
simulador corriendo **en tu equipo**. Elige el dispositivo en la cabecera; si
está apagado, se arranca.

El martillo compila la carpeta que le indiques, instala el resultado y lo lanza
— el registro va apareciendo mientras trabaja, con los errores aparte y arriba.
Los proyectos que ya compilaste se recuerdan por equipo y se comprueban contra
él, así que una entrada que ya no existe lo dice en vez de fallar al pulsarla.

Lo que puede ofrecer cada máquina no es lo mismo:

| | iOS | Android |
|---|---|---|
| **Equipo macOS** | Sí | Sí |
| **Equipo Linux** | **Nunca** | Sí, y más rápido |

El Simulador de iOS es de Apple y no existe fuera de macOS — ningún contenedor
ni capa de compatibilidad cambia eso. Android va al revés: en una máquina Linux
con GPU y KVM el emulador corre mejor que en un Mac.

Los fotogramas viajan como imágenes y no como vídeo. Peor para las animaciones y
mucho más simple: sin códecs, sin negociación, sin un proceso por cliente. Se
encogen antes de salir del equipo — la pantalla de un iPhone 17 Pro son
1206×2622 y 2,9 MB en PNG, que a tres por segundo serían 9 MB/s por el túnel; a
640 px y JPEG el mismo fotograma pesa 29 KB.

### Qué necesita cada equipo

**Para Android**, en cualquiera de las dos plataformas: `adb`, y además un móvil
conectado por USB o una imagen de emulador. Nada más — un móvil conectado
aparece solo.

**Para iOS**, en un Mac: Xcode, que ya tienes si desarrollas para iPhone. Mirar
funciona de inmediato; **tocar necesita `idb`**, que no viene con Xcode:

```bash
./serve.sh --install-idb
```

Es una opción aparte y no forma parte del arranque porque uno de sus pasos es
`brew trust`, que autoriza a un repositorio de terceros a ejecutar código en tu
equipo. Eso no debe ocurrir en silencio mientras crees que solo estás levantando
un editor. La app ofrece lo mismo como botón cuando ya estás en el iPad y no lo
ejecutaste antes.

> Si el simulador no aparece o `simctl` dice *unable to find utility*, tu
> `xcode-select` apunta a las Command Line Tools, que no lo incluyen. El gestor
> lo resuelve por su cuenta, pero el resto de tus herramientas no:
> `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`

### Emulador de Android en un equipo Linux

Todo se instala bajo tu carpeta personal; solo el grupo KVM necesita root.

```bash
# JDK, adb y las herramientas de línea de comandos del SDK
mkdir -p ~/Android/Sdk && cd ~/Android/Sdk
curl -fsSL -o /tmp/jdk.tgz "https://api.adoptium.net/v3/binary/latest/21/ga/linux/x64/jdk/hotspot/normal/eclipse"
mkdir -p ~/.jdk && tar xzf /tmp/jdk.tgz -C ~/.jdk --strip-components=1
curl -fsSL -o /tmp/pt.zip https://dl.google.com/android/repository/platform-tools-latest-linux.zip
unzip -q /tmp/pt.zip -d ~/Android/Sdk
curl -fsSL -o /tmp/cmd.zip https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip
mkdir -p cmdline-tools && unzip -q /tmp/cmd.zip -d cmdline-tools && mv cmdline-tools/cmdline-tools cmdline-tools/latest

export JAVA_HOME=~/.jdk ANDROID_HOME=~/Android/Sdk
export PATH=$JAVA_HOME/bin:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$PATH

# emulador e imagen de sistema (varios GB)
yes | sdkmanager --licenses
sdkmanager --install emulator platform-tools "platforms;android-35" \
                    "system-images;android-35;google_apis;x86_64"
echo no | avdmanager create avd -n BosonCode \
        -k "system-images;android-35;google_apis;x86_64" -d pixel_7
```

La app arranca el emulador **sin ventana**, y eso no es un ahorro: el gestor
corre como servicio y no tiene `DISPLAY`, así que un emulador que intente abrir
ventana muere nada más nacer. La pantalla se captura por `adb`, que funciona
igual sin ella — y una ventana en la máquina Linux no le sirve de nada a quien
está mirando un iPad. Su salida queda en `~/.ivscode/emulator-<nombre>.log`.

Y luego, una vez, para que el emulador use aceleración por hardware:

```bash
sudo usermod -aG kvm "$USER"     # cierra sesión y vuelve a entrar después
```

**El grupo no es opcional, aunque `-accel-check` diga que hay aceleración.** Ese
comprobante pasa porque `systemd-logind` concede a tu *sesión de login* una ACL
sobre `/dev/kvm`. El servidor corre como servicio con *linger* y sin sesión, así
que nunca recibe esa ACL — el emulador arranca y muere un segundo después con
*«This user doesn't have permissions to use KVM»*. La pertenencia al grupo es
permanente; la ACL no.

Comprueba que de verdad se aplicó, porque un `sudo` fallido no deja rastro:

```bash
getent group kvm       # debe terminar con tu usuario: kvm:x:992:tuusuario
```

Y si prefieres no reiniciar todavía, esto da acceso al instante:

```bash
sudo setfacl -m u:$USER:rw /dev/kvm
```

Se pierde al reiniciar, así que sirve para probarlo ahora — el `usermod` sigue
siendo lo que lo hace permanente.

`adb` tiene que estar en el `PATH` del proceso que ejecuta `serve.sh`. Si lo
instalaste bajo tu carpeta personal, añádelo a tu perfil — un servicio arrancado
al encender no hereda el `PATH` de una shell interactiva:

```bash
echo 'export PATH="$HOME/Android/Sdk/platform-tools:$PATH"' >> ~/.profile
```

(`setup.sh` hace esto por ti, y además lo añade al entorno del servicio.)

---

## Opcional: contenedores con GPU

`setup-machine.sh` prepara una imagen de contenedor con CUDA, PyTorch y Julia.
Una vez lista, la app puede crear y gestionar máquinas desde el botón *Máquinas*
de la tarjeta de un equipo. Los contenedores se arrancan con `--gpus all`, así
que `nvidia-smi` funciona dentro.

`bridge.sh` reenvía un superordenador o un clúster compartido al que solo
llegues por SSH — para equipos donde no puedes instalar Tailscale ni ejecutar
nada como root.

---

## Compilar las apps

Necesitas Xcode 15 o superior,
[XcodeGen](https://github.com/yonaskolb/XcodeGen) y una cuenta de desarrollador
de Apple (con la gratuita basta para tus propios dispositivos).

```bash
brew install xcodegen
cd ipad
xcodegen generate
open iVsCode.xcodeproj
```

Pon tu propio equipo en `project.yml` (`DEVELOPMENT_TEAM`) antes de compilar.

### Añadir tu tailnet (hace falta para los notebooks)

El editor, la terminal y todo lo demás funcionan tal cual en cualquier tailnet.
**Los notebooks son la excepción** y necesitan un cambio.

Dependen de Service Workers, que WKWebView solo permite en los dominios listados
en `WKAppBoundDomains`, dentro de `ipad/iVsCode/Info.plist`. Añade el tuyo:

```bash
tailscale status --json | grep MagicDNSSuffix
```

```xml
<key>WKAppBoundDomains</key>
<array>
    <string>vscode.dev</string>
    <string>github.dev</string>
    <string>tu-tailnet.ts.net</string>   <!-- añade esto -->
</array>
```

**No hay comodines, y `ts.net` por sí solo no vale.** WebKit compara el dominio
*registrable*, y como `ts.net` está en la
[Public Suffix List](https://publicsuffix.org/), cada tailnet cuenta como
dominio propio. Comprobado en un dispositivo: con solo `ts.net` la página se
negaba a cargar; añadiendo el tailnet completo funcionó al instante.

La app se degrada en vez de fallar: activa la marca App-Bound solo para los
dominios listados, así que un tailnet sin listar sigue abriendo el editor —
solo pierdes los notebooks hasta que lo añadas. La lista admite 10 entradas.

**Borra la app del dispositivo después de editar esta lista.** WebKit lee
`WKAppBoundDomains` al instalar la app y no vuelve a leerla. Instalar encima
deja un estado incoherente en el que la app se considera no app-bound y se
deniega en silencio la inyección de scripts — el editor carga pero deja de
responder al teclado, y ⌃⌥T muere, porque el reenvío de teclas pasa por
`evaluateJavaScript`. Reinstalar de cero lo arregla.

---

## Estructura del repositorio

```
bosoncode/
├── setup.sh              # empieza aquí: instala todo y arranca el servidor
├── serve.sh              # servidor del equipo: code-server + HTTPS + anuncio mDNS
├── setup-machine.sh      # prepara una imagen con GPU (se ejecuta DENTRO de una máquina)
├── bridge.sh             # puente SSH para equipos sin Tailscale
├── backend/              # Docker Compose opcional con paso de GPU
└── ipad/
    ├── project.yml       # manifiesto de XcodeGen → genera el .xcodeproj
    ├── iVsCode/          # BosonCode (cliente del editor + terminal)
    └── iFinder/          # ZeroSpin (gestor de archivos)
```

Los dos objetivos salen de un mismo proyecto. `Server.swift`,
`DockerMachines.swift` e `IncomingDrop.swift` se compilan en ambos: la lista de
equipos, el cliente del gestor y el arrastrar y soltar son el mismo problema en
las dos apps. Comparten además un App Group y un grupo de Llavero, que es cómo
ZeroSpin ve las máquinas que añadiste en BosonCode.

Los nombres de carpeta `ipad/iVsCode` e `ipad/iFinder` son anteriores a los
nombres actuales de las apps y se conservan para que las rutas de compilación no
cambien.

---

## Si algo va mal

**No se descubre el equipo.** El mDNS necesita quien lo publique: `avahi-daemon`
en Linux o el `dns-sd` que trae macOS. `serve.sh` recurre a D-Bus y a `zeroconf`
de Python, y avisa cuando no hay ninguno. Añadir el equipo a mano funciona
siempre — y es la única vía si el iPad está en otra red, porque el mDNS no la
cruza.

**Rechaza la contraseña.** La que recuerda la app ya no coincide con la del
equipo. Léela con `./setup.sh --password` y vuelve a escribirla. Pasa siempre
que se haya borrado o movido `~/.ivscode`.

**Los notebooks no abren.** Casi siempre es el HTTPS o los App-Bound Domains.
Comprueba que `tailscale serve status` enseñe el mapeo y que `WKAppBoundDomains`
coincida con tu tailnet.

**Una máquina aparece pero no abre.** Si es un contenedor creado antes de que se
regenerara la contraseña del equipo, ya no coinciden. *Máquinas → … → Reparar
contraseña* rehace el contenedor con la actual y conserva su disco.

**El emulador de Android no arranca.** La app te dirá el motivo. Si menciona
KVM, es el grupo: mira más arriba, en la sección del emulador.

**Se alcanzó el límite de inotify.** code-server vigila muchos archivos:

```bash
echo fs.inotify.max_user_watches=524288 | sudo tee -a /etc/sysctl.conf && sudo sysctl -p
```

---

## Créditos

Construido sobre [code-server](https://github.com/coder/code-server) (MIT), de
Coder, que a su vez se apoya en
[Visual Studio Code](https://github.com/microsoft/vscode) (MIT), de Microsoft.
Emulación de terminal con
[SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) (MIT).

© 2026 BosonCode.
