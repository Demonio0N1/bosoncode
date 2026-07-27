# BosonCode

**A native iPadOS client for [code-server](https://github.com/coder/code-server).**
Edit on the iPad, compute on your workstation — over Tailscale, with no open ports.

The repository also contains **ZeroSpin**, a macOS-Finder-style file manager for
iPadOS that shares the same backend client.

> BosonCode is an independent client for code-server. Visual Studio Code is a
> trademark of Microsoft Corporation. Not affiliated with or endorsed by Microsoft.

---

## What you get

| | |
|---|---|
| **Full VS Code** | Extensions, Jupyter notebooks, integrated terminal |
| **Your hardware** | Python, Julia, PyTorch and CUDA run on the host, not the tablet |
| **Native terminal** | SwiftTerm over a PTY channel, in its own iPadOS window |
| **Zero-config discovery** | Hosts announce themselves over mDNS; the app finds them |
| **Docker machines** | Create, start, stop and delete containers from the app |
| **No open ports** | Tailscale only — the host is never exposed to the internet |

---

## Host setup

### Requirements

- Linux or macOS. No root and no Docker needed for the basic setup.
- [Tailscale](https://tailscale.com/download) installed and signed in on both
  the host **and** the iPad.

### 1. Tailscale

Install it and sign in with the same account on both devices:

```bash
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up
```

Then let your user manage `tailscale serve`, which is what publishes HTTPS:

```bash
sudo tailscale set --operator=$USER
```

**HTTPS is not optional here.** Jupyter notebooks inside code-server rely on
Service Workers, and browsers refuse to register those over plain HTTP.
`serve.sh` uses `tailscale serve` to obtain a real certificate for your
`*.ts.net` hostname.

### 2. Run the backend

```bash
git clone https://github.com/Demonio0N1/bosoncode.git
cd bosoncode
./serve.sh
```

That is the whole setup. The script downloads a standalone `code-server` into
`~/.ivscode`, starts it, publishes it over HTTPS through Tailscale, and announces
the host over mDNS so the app lists it automatically.

Options:

```bash
./serve.sh --name "Lab workstation"   # name shown on the card in the app
./serve.sh --port 8443                # local port (default 8443)
./serve.sh --password "…"             # default: generated once, kept on disk
./serve.sh --install-service          # start automatically on boot
./serve.sh --help
```

`--install-service` installs a systemd **user** service on Linux (with lingering
enabled, so it survives logout) or a LaunchAgent on macOS.

The password is generated on first run and stored in `~/.ivscode/password` with
mode `600`. Print it with:

```bash
cat ~/.ivscode/password
```

### 3. Connect from the iPad

Open BosonCode. Your machine appears in the grid on its own — tap it, enter the
password once, and it is stored in the iPad Keychain.

If it does not show up, add it manually using the URL that `serve.sh` prints on
startup.

---

## Optional: GPU containers

`setup-machine.sh` provisions a container image with CUDA, PyTorch and Julia.
Once it is in place, the app can create and manage machines from the *Machines*
button on a host card. Containers are started with `--gpus all`, so `nvidia-smi`
works inside them.

`bridge.sh` forwards a supercomputer or shared cluster that you can only reach
over SSH — for hosts where you cannot install Tailscale or run anything as root.

---

## Building the apps

Requires Xcode 15+, [XcodeGen](https://github.com/yonaskolb/XcodeGen) and an
Apple developer account (a free one is enough for your own devices).

```bash
brew install xcodegen
cd ipad
xcodegen generate
open iVsCode.xcodeproj
```

Set your own team in `project.yml` (`DEVELOPMENT_TEAM`) before building.

### One thing you must change

`ipad/iVsCode/Info.plist` declares `WKAppBoundDomains`, which is what allows
Service Workers — and therefore Jupyter notebooks — inside the web view. It
currently holds the original author's tailnet domain. **Replace it with yours**
or notebooks will not open:

```bash
tailscale status --json | grep MagicDNSSuffix
```

```xml
<key>WKAppBoundDomains</key>
<array>
    <string>your-tailnet.ts.net</string>
</array>
```

---

## Repository layout

```
bosoncode/
├── serve.sh              # host backend: code-server + HTTPS + mDNS announce
├── setup-machine.sh      # provisions a GPU container image
├── bridge.sh             # SSH bridge for hosts without Tailscale
├── backend/              # optional Docker Compose setup with GPU passthrough
└── ipad/
    ├── project.yml       # XcodeGen manifest → generates the .xcodeproj
    ├── iVsCode/          # BosonCode (editor client + terminal)
    └── iFinder/          # ZeroSpin (file manager)
```

The `ipad/iVsCode` and `ipad/iFinder` directory names predate the current app
names and are kept so build paths stay stable.

---

## Troubleshooting

**The host is not discovered.** mDNS needs a publisher: `avahi-daemon` on Linux
or the built-in `dns-sd` on macOS. `serve.sh` falls back to D-Bus and to Python
`zeroconf`, and warns when none is available. Adding the host manually always
works.

**Notebooks do not open.** Almost always HTTPS or App-Bound Domains. Check that
`tailscale serve status` shows the mapping and that `WKAppBoundDomains` matches
your tailnet.

**inotify limit reached.** code-server watches a lot of files:

```bash
echo fs.inotify.max_user_watches=524288 | sudo tee -a /etc/sysctl.conf && sudo sysctl -p
```

---

## Credits

Built on [code-server](https://github.com/coder/code-server) (MIT) by Coder,
which is itself built on [Visual Studio Code](https://github.com/microsoft/vscode)
(MIT) by Microsoft. Terminal emulation by
[SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) (MIT).

© 2026 BosonCode.
