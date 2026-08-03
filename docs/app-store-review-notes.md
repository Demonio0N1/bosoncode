# App Store — notas para el revisor

Texto listo para pegar en **App Review Information → Notes** de App Store
Connect. Va en inglés porque es el idioma del equipo de revisión.

El problema que resuelven estas notas es concreto: **BosonCode no hace nada sin
un equipo con `serve.sh` corriendo**, y el revisor no va a montar uno. Sin
explicarlo, abre la app, ve una lista vacía y la marca como rota. Por eso lo
primero que dice la nota es cómo probarla sin nada montado.

---

## BosonCode

```
WHAT THIS APP IS

BosonCode is a client for code-server (https://github.com/coder/code-server),
an open-source editor that the user runs on their OWN computer. The app does
not host, download or execute any code itself: it connects to a server the
user already controls, over their private Tailscale network.

HOW TO REVIEW IT WITHOUT SETTING UP A SERVER

No account, login or hardware is needed to evaluate the app.

On the launch screen, tap the card labelled "Try vscode.dev". It opens
Microsoft's public web editor and exercises the same code path as a real
connection — the editor view, the window management and the UI. This card
exists specifically so the app can be evaluated with nothing installed.

The rest of the screen will be empty, and that is expected: it lists the
reviewer's own computers, and there are none. The "Scanning for devices…"
message is the app looking for them on the local network.

PERMISSIONS

- Local Network: the app discovers the user's own computers via mDNS
  (_ivscode._tcp) so they appear without typing an address. Declining it only
  means machines must be added manually.

There is no other permission request, no account system, no analytics and no
third-party SDKs. The privacy manifest declares UserDefaults as the only
accessed API category, and no data is collected.

ABOUT THE TRADEMARK

The app is an independent client. It is not affiliated with or endorsed by
Microsoft, and says so verbatim on the launch screen, next to the copyright
notice. "Visual Studio Code" appears only in that attribution.

ABOUT REMOTE CONTENT (2.5.2 / 4.7)

The app does not download, install or execute code. It renders a web editor
that the user runs on their own machine, in the same way a remote-desktop or
SSH client shows a session hosted elsewhere. There is no store, no plug-in
marketplace and no way for the app to fetch executable content.

The companion app ZeroSpin (same developer) is a file manager and is submitted
separately; the two share a saved list of the user's machines through an App
Group, which is why both request the same App Group entitlement.
```

---

## ZeroSpin

```
WHAT THIS APP IS

ZeroSpin is a file manager for iPadOS: it browses the files the user has
granted access to, previews and edits them, and can send them to a computer
the user owns.

HOW TO REVIEW IT

It works standalone, with no account and no server. On first launch it asks
for a folder through the system document picker — choosing "On My iPad" is
enough to see the whole interface. Files can then be previewed, renamed,
compressed, edited as text, or drawn on if they are images.

The "Computers" section of the sidebar will be empty for the reviewer. It
lists machines added in the companion app BosonCode (same developer), shared
through an App Group. Its absence does not affect anything else.

PERMISSIONS

- Local Network: only used to reach the computers described above, if any were
  added. It is not needed to review the app.
- File access is requested through the system document picker, per folder, and
  kept with a security-scoped bookmark. The app never enumerates files the user
  did not grant.

No account system, no analytics, no third-party SDKs, no data collected.
```

---

## Antes de enviar

- **Capturas**: obligatorias para iPad de 13" y de 11".
- **App Group**: `group.com.garyguaman.boson` debe estar asociado a los dos App
  ID en el portal de desarrollador, o la subida se rechaza por *entitlements*
  antes de llegar a revisión.
- **Bundle IDs**: `com.garyguaman.ivscode` y `com.garyguaman.ifinder`.
- La casilla de cifrado ya está resuelta en el proyecto
  (`ITSAppUsesNonExemptEncryption = false`), así que App Store Connect no
  volverá a preguntarlo en cada subida.
