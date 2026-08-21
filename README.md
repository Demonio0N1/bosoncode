# BosonCode

*[Léeme en español](README.es.md)*

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
| **Independent windows** | Each window holds a different machine; the list is shared, the selection is not |
| **Zero-config discovery** | Hosts announce themselves over mDNS; the app finds them |
| **Docker machines** | Create, start, stop and delete containers from the app |
| **SSH** | Jump from a host to any machine it can reach |
| **Simulator window** | Your machine's iOS Simulator or Android emulator, on the iPad, with touch |
| **No open ports** | Tailscale only — the host is never exposed to the internet |

### In the terminal

- `⌃⌥T` opens a terminal in its own window, from the moment you enter a machine.
- Each window gets its own tmux session, so shells are independent rather than
  mirrored.
- Two-finger scroll moves through tmux history, with momentum. One finger
  selects.
- **Drop a file on it** — from Files, Photos, anywhere — and it is uploaded to
  the machine and its remote path is typed into the prompt, ready for a command.
- Light/dark follows the iPad, and the palette and typeface are configurable.

---

## ZeroSpin

A Finder-style file manager for iPadOS, in the same repository and sharing the
same backend client. It reads the host list from BosonCode, so the machines you
have already added are available to it.

| | |
|---|---|
| **Finder layout** | Columns, list and icons; a floating sidebar with bubble selection |
| **Windows, not sheets** | Previews, the text editor and notebooks each open as their own iPadOS window |
| **Text and script editor** | Monospaced, syntax-highlighted, `⌘S`, saves in place |
| **Notebook viewer** | `.ipynb` rendered with its cells, Markdown and outputs |
| **Image editor** | Draw on an image with PencilKit and save it back |
| **Cloud mounts** | OneDrive, Drive, Dropbox… granted once and kept |
| **Drag and drop** | Both ways, including photos, which arrive as image data rather than files |
| **Run in BosonCode** | Send a notebook or script to a machine and open it there |

### What iPadOS does not allow

Two limits worth stating, because they are asked about often and no amount of
code gets around them:

- **An app cannot set the system wallpaper.** ZeroSpin's "use as background"
  changes its own window background. Only Settings and Photos can change the
  device one.
- **An app cannot launch a file in another app silently.** There is no
  type → app association to consult, and `UIApplication.open` refuses `file://`
  URLs. The Files app manages it through system privileges that third-party
  apps do not receive — `UIDocumentBrowserViewController` does not grant them
  either; its own documentation says it opens documents *in your* application.
  "Open with…" shows the system's own list of capable apps, which is as close
  as a third-party app gets.

---

## Host setup

### One command

```bash
git clone https://github.com/Demonio0N1/bosoncode.git
cd bosoncode
./setup.sh
```

That installs Tailscale if it is missing, checks you are signed in, installs
code-server, starts the backend and announces the machine. When it finishes it
prints the URL and the password, and your machine shows up in the app on its
own.

```bash
./setup.sh --check      # diagnose only, touches nothing
./setup.sh --service    # also start on every boot
./setup.sh --password   # show this machine's password again
```

The password is generated once and shown when the server starts. That moment is
usually weeks before you need it again — adding another iPad, reinstalling the
app — so `--password` prints it any time. It also lives in
`~/.ivscode/password`.

**Install Tailscale on the iPad too**, signed in with the same account —
[App Store](https://apps.apple.com/app/tailscale/id1470499037). This is the step
people skip, and its absence shows up as *"my machine doesn't appear"*, which
sends you looking in the wrong place. Both ends or nothing: it is what replaces
opening a port.

The rest of this section is what `setup.sh` does, for when you want to do it by
hand or something goes wrong.

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
./serve.sh --install-idb              # (macOS) touch in the iOS Simulator
./serve.sh --help
```

`--install-service` installs a systemd **user** service on Linux (with lingering
enabled, so it survives logout) or a LaunchAgent on macOS.

### 3. Your password

`serve.sh` generates a random password on first run and stores it in
`~/.ivscode/password` with mode `600`. It is never printed to the logs, so read
it from the host whenever you need it:

```bash
./setup.sh --password        # shows it along with the name and address
cat ~/.ivscode/password      # or the file itself
```

Two things worth knowing before they surprise you:

- **The password is tied to `~/.ivscode`.** Delete that directory and the next
  run generates a *new* password — the old one stops working. This is the most
  common reason a login suddenly fails after a clean reinstall.
- **Reinstalling the app clears the saved credential**, because it lives in the
  iPad Keychain and iOS wipes it with the app. You will be asked for the
  password again.

Set your own instead of the generated one at any time:

```bash
./serve.sh --password "your-password"
```

Used together with `--install-service`, it is written to `~/.ivscode/password`
before the service starts, so the service picks it up too.

### 4. Connect from the iPad

Open BosonCode. Your machine appears in the grid on its own — tap it, enter the
password once, and it is stored in the iPad Keychain.

If it does not show up, add it manually. The **Tailscale name** is enough —
`my-pc` — and the app appends the tailnet suffix and the port; it also takes the
full address that `setup.sh` prints.

> **With the iPad on a different network, automatic discovery cannot work.** It
> is mDNS, which is link-local multicast, and Tailscale does not carry it.
> Adding by name is then the only route, and it works from anywhere.

---

## The simulator window

`⌃⌥S`, or the phone button next to the terminal one, opens a window showing a
simulator running **on your machine**. Pick a device from the header; if it is
off, it boots.

The hammer builds the folder you point it at, installs the result and launches
it — the log streams while it works, with the errors pulled out on top. Projects
you have built are remembered per machine and checked against it, so an entry
that no longer exists says so instead of failing when you tap it.

What each machine can offer is not the same:

| | iOS | Android |
|---|---|---|
| **macOS host** | Yes | Yes |
| **Linux host** | **Never** | Yes, and faster |

The iOS Simulator is Apple's and does not exist outside macOS — no container or
compatibility layer changes that. Android goes the other way: on a Linux box
with a GPU and KVM the emulator runs better than on a Mac.

Frames are sent as images rather than video. Worse for animation, far simpler:
no codecs, no negotiation, no per-client process. They are scaled down before
leaving the machine — an iPhone 17 Pro screen is 1206×2622 and 2.9 MB as PNG,
which at three per second would be 9 MB/s through the tunnel; at 640 px as JPEG
the same frame is 29 KB.

### What each host needs

**For Android**, on either platform: `adb`, plus either a phone connected over
USB or an emulator image. Nothing else — a connected phone shows up on its own.

**For iOS**, on a Mac: Xcode, which you already have if you build iOS apps.
Watching works immediately; **touch needs `idb`**, which does not ship with
Xcode:

```bash
./serve.sh --install-idb
```

It is a separate flag and not part of startup because one of its steps is
`brew trust`, which authorises a third-party tap to run code on your machine.
That should not happen quietly while you believe you are only starting an
editor. The app offers the same thing as a button when you are already on the
iPad and did not run it beforehand.

> If the simulator is missing or `simctl` reports *unable to find utility*, your
> `xcode-select` is pointing at the Command Line Tools, which do not include it.
> The manager works around it, but the rest of your toolchain will not:
> `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`

### Android emulator on a Linux host

Everything installs under your home directory; only the KVM group needs root.

```bash
# JDK, adb and the SDK command-line tools
mkdir -p ~/Android/Sdk && cd ~/Android/Sdk
curl -fsSL -o /tmp/jdk.tgz "https://api.adoptium.net/v3/binary/latest/21/ga/linux/x64/jdk/hotspot/normal/eclipse"
mkdir -p ~/.jdk && tar xzf /tmp/jdk.tgz -C ~/.jdk --strip-components=1
curl -fsSL -o /tmp/pt.zip https://dl.google.com/android/repository/platform-tools-latest-linux.zip
unzip -q /tmp/pt.zip -d ~/Android/Sdk
curl -fsSL -o /tmp/cmd.zip https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip
mkdir -p cmdline-tools && unzip -q /tmp/cmd.zip -d cmdline-tools && mv cmdline-tools/cmdline-tools cmdline-tools/latest

export JAVA_HOME=~/.jdk ANDROID_HOME=~/Android/Sdk
export PATH=$JAVA_HOME/bin:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$PATH

# emulator and a system image (several GB)
yes | sdkmanager --licenses
sdkmanager --install emulator platform-tools "platforms;android-35" \
                    "system-images;android-35;google_apis;x86_64"
echo no | avdmanager create avd -n BosonCode \
        -k "system-images;android-35;google_apis;x86_64" -d pixel_7
```

The emulator is started **headless** by the app, and that is not an
optimisation: the manager runs as a service with no `DISPLAY`, so an emulator
that tries to open a window dies the moment it starts. The screen is captured
through `adb`, which works fine without one — and a window on the Linux box is
no use to someone looking at an iPad. Its output is kept in
`~/.ivscode/emulator-<name>.log`.

Then, once, so the emulator can use hardware acceleration:

```bash
sudo usermod -aG kvm "$USER"     # log out and back in afterwards
```

**The group is not optional, even if `-accel-check` says acceleration is
available.** That check passes because `systemd-logind` grants your *login
session* an ACL on `/dev/kvm`. The backend runs as a lingering service with no
session, so it never gets that ACL — the emulator starts and dies one second
later with *"This user doesn't have permissions to use KVM"*. Group membership
is permanent; the ACL is not.

Check it actually took, because a failed `sudo` leaves no trace:

```bash
getent group kvm       # must end with your username: kvm:x:992:youruser
```

If you would rather not reboot yet, this grants access immediately:

```bash
sudo setfacl -m u:$USER:rw /dev/kvm
```

It is lost on the next boot, so it is for trying things now — `usermod` is
still what makes it stick.

`adb` has to be on the `PATH` of the process running `serve.sh`. If you
installed it under your home directory, add it to your shell profile — a
service started at boot does not inherit an interactive shell's `PATH`:

```bash
echo 'export PATH="$HOME/Android/Sdk/platform-tools:$PATH"' >> ~/.profile
```

(`setup.sh` does this for you, and adds it to the service environment too.)

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

### Add your tailnet (needed for Jupyter notebooks)

The editor, the terminal and everything else work out of the box on any
tailnet. **Notebooks are the exception** and need one edit.

Notebooks rely on Service Workers, which WKWebView only allows on domains
listed under `WKAppBoundDomains` in `ipad/iVsCode/Info.plist`. Add yours:

```bash
tailscale status --json | grep MagicDNSSuffix
```

```xml
<key>WKAppBoundDomains</key>
<array>
    <string>vscode.dev</string>
    <string>github.dev</string>
    <string>your-tailnet.ts.net</string>   <!-- add this -->
</array>
```

**There is no wildcard, and `ts.net` on its own does not work.** WebKit matches
the *registrable* domain, and since `ts.net` is on the
[Public Suffix List](https://publicsuffix.org/), every tailnet counts as its own
domain. Verified on a device: with only `ts.net` listed the page refused to
load; adding the full tailnet fixed it immediately.

The app degrades gracefully rather than failing: it turns the App-Bound flag on
only for listed domains, so an unlisted tailnet still opens the editor — you
just lose notebooks until you add it. The list caps at 10 entries.

**Delete the app from the device after editing this list.** WebKit reads
`WKAppBoundDomains` when the app is installed and does not re-read it.
Installing over the top leaves a stale state where the app counts as
non-app-bound and script injection is silently denied — the editor loads but
stops responding to the keyboard, and ⌃⌥T dies, because key forwarding goes
through `evaluateJavaScript`. A clean reinstall fixes it.

---

## Repository layout

```
bosoncode/
├── setup.sh              # start here: installs everything and runs the backend
├── serve.sh              # host backend: code-server + HTTPS + mDNS announce
├── setup-machine.sh      # provisions a GPU container image (runs INSIDE a machine)
├── bridge.sh             # SSH bridge for hosts without Tailscale
├── backend/              # optional Docker Compose setup with GPU passthrough
└── ipad/
    ├── project.yml       # XcodeGen manifest → generates the .xcodeproj
    ├── iVsCode/          # BosonCode (editor client + terminal)
    └── iFinder/          # ZeroSpin (file manager)
```

Both targets are built from one project. `Server.swift`, `DockerMachines.swift`
and `IncomingDrop.swift` are compiled into both: the host list, the manager
client and drag-and-drop handling are the same problem in either app. The two
apps also share an App Group and a Keychain access group, which is how ZeroSpin
sees the machines you added in BosonCode.

The `ipad/iVsCode` and `ipad/iFinder` directory names predate the current app
names and are kept so build paths stay stable.

---

## Troubleshooting

**The host is not discovered.** mDNS needs a publisher: `avahi-daemon` on Linux
or the built-in `dns-sd` on macOS. `serve.sh` falls back to D-Bus and to Python
`zeroconf`, and warns when none is available. Adding the host manually always
works — and it is the only route when the iPad is on a different network, since
mDNS does not cross one.

**The password is rejected.** The one the app remembers no longer matches the
host. Read the current one with `./setup.sh --password` and enter it again. This
happens whenever `~/.ivscode` has been deleted or moved.

**Notebooks do not open.** Almost always HTTPS or App-Bound Domains. Check that
`tailscale serve status` shows the mapping and that `WKAppBoundDomains` matches
your tailnet.

**A machine is listed but will not open.** If it is a container that was
created before the host password was regenerated, the two no longer match.
*Machines → … → Repair password* rebuilds the container with the current one and
keeps its disk.

**The Android emulator will not start.** The app tells you why. If it mentions
KVM, it is the group — see the emulator section above.

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
