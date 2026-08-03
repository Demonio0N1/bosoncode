# App Store — textos de la ficha

Listo para pegar en App Store Connect. Los límites de Apple van anotados; el
script del final los comprueba.

Una decisión que atraviesa los dos textos: **el requisito va delante, no
escondido**. BosonCode no sirve de nada sin un equipo propio, y quien lo
descubre después de descargarla deja una reseña de una estrella que no se puede
retirar. Decirlo en la primera línea pierde alguna descarga y evita todas esas.

---

## BosonCode

**Nombre** (30): `BosonCode`
**Subtítulo** (30): `Tu PC, editando desde el iPad`

**Texto promocional** (170):
```
Edita en el iPad y ejecuta en tu propio ordenador: Python, CUDA y notebooks
corren en tu máquina, con la batería y el silencio del iPad.
```

**Descripción** (4000):
```
BosonCode conecta tu iPad con el ordenador que ya tienes. El editor y el
terminal se ven en la tableta; el trabajo pesado ocurre en tu máquina.

REQUIERE UN ORDENADOR PROPIO
Esta app es un cliente: necesitas un Linux o un macOS tuyo ejecutando
code-server mediante el script gratuito y de código abierto del proyecto, más
Tailscale en ambos dispositivos. Sin eso, BosonCode no tiene a qué conectarse.
La instalación en el equipo es un comando.

QUÉ CONSIGUES
· El entorno de tu ordenador, con sus extensiones, sus intérpretes y su GPU.
· Notebooks de Jupyter que se ejecutan de verdad, con su kernel y sus gráficas.
· Un terminal nativo en su propia ventana, no uno dentro de una web.
· Varias ventanas, cada una en una máquina distinta, a la vez.
· Contenedores Docker que se crean y se administran desde la app.
· SSH desde un equipo hacia cualquier otro que alcance.

PENSADO PARA EL IPAD
Los atajos de teclado funcionan como esperas. El terminal se desplaza con dos
dedos y arrastra su historial con inercia. Puedes soltar un archivo sobre él y
su ruta aparece escrita en el prompt, lista para el comando siguiente.

SIN ABRIR PUERTOS
Todo viaja por tu red privada de Tailscale. Tu ordenador nunca queda expuesto a
internet, y no hay servidores intermedios: la conexión es entre tus dos
dispositivos.

SIN CUENTAS NI SEGUIMIENTO
No hay registro, ni analítica, ni SDK de terceros. La contraseña de tu equipo se
guarda en el Llavero del iPad y no sale de ahí.

BosonCode es un cliente independiente de code-server. Visual Studio Code es una
marca registrada de Microsoft Corporation. Sin afiliación ni respaldo de
Microsoft.
```

**Palabras clave** (100, separadas por comas, sin espacios):
```
ssh,terminal,código,python,jupyter,notebook,servidor,remoto,desarrollo,tailscale,shell,programar
```

---

## ZeroSpin

**Nombre** (30): `ZeroSpin`
**Subtítulo** (30): `Archivos, columnas y ventanas`

**Texto promocional** (170):
```
Un explorador de archivos para el iPad con la disposición del Finder: columnas,
barra lateral y ventanas de verdad.
```

**Descripción** (4000):
```
ZeroSpin es un gestor de archivos para iPad con la disposición a la que estás
acostumbrado en el escritorio: columnas, lista o iconos, barra lateral con tus
ubicaciones y ventanas independientes.

NAVEGAR
· Vista de columnas, de lista y de iconos, con el ancho ajustable.
· Barra lateral con tus carpetas, tus nubes y tus unidades externas.
· Ordena por nombre, tamaño, fecha o tipo.
· Buscar dentro de la carpeta abierta.

ABRIR Y EDITAR
· Editor de texto con tipografía monoespaciada y resaltado de sintaxis, para
  scripts y configuraciones. Guarda en el propio archivo.
· Notebooks de Jupyter mostrados con sus celdas, su Markdown y sus resultados.
· Dibuja sobre una imagen y guarda el resultado.
· Vista previa de documentos, hojas de cálculo y presentaciones.
· Cada archivo se abre en su propia ventana, no en una pestaña atrapada dentro
  de la principal.

ORGANIZAR
· Copiar, mover, duplicar, renombrar y comprimir.
· Papelera con restauración: lo borrado vuelve a su carpeta de origen.
· Arrastrar y soltar en los dos sentidos, con cualquier otra app del iPad.

TUS NUBES
Monta OneDrive, Google Drive, Dropbox o cualquier proveedor instalado, y
renómbralos para distinguir dos cuentas del mismo servicio. El permiso se
concede una vez y se conserva.

CON TUS ORDENADORES
Si usas BosonCode, del mismo desarrollador, ZeroSpin ve los equipos que ya has
añadido: puedes mandarles un notebook o un script y abrirlo allí.

SIN CUENTAS NI SEGUIMIENTO
No hay registro, ni analítica, ni SDK de terceros. El acceso a tus carpetas se
pide una a una con el selector del sistema, y ZeroSpin nunca enumera archivos
que no le hayas concedido.
```

**Palabras clave** (100):
```
archivos,explorador,carpetas,gestor,columnas,finder,onedrive,drive,dropbox,editor,texto,notebook
```

---

## Comprobar los límites

```bash
python3 docs/check-listing.py
```
