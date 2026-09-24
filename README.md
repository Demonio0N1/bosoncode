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

### Installing

Three lines on the computer:

```bash
git clone https://github.com/Demonio0N1/bosoncode.git
cd bosoncode
./setup.sh
```

And one thing on the tablet or phone: install
[Tailscale](https://apps.apple.com/app/tailscale/id1470499037) and sign in with
**the same account**. This is the step most people skip, and its absence shows
up as *"my computer doesn't appear"*, which sends you looking for the problem in
the wrong place.

**No `sudo` in front.** The script asks for it itself, at the one moment it is
needed. Running the whole thing as root would leave the editor, its settings and
every file you create owned by root — and from then on everything asks for
permissions that should not be needed.

#### What it will ask you

The first time, and only the first time:

1. **Sign in to Tailscale.** It opens a page; you sign in with your account.
2. **Enable Serve**, if the account is new. Another link, one click. It is a
   permission on the account and covers all of your machines.
3. **Your `sudo` password**, so your user is allowed to publish the HTTPS.

The rest runs on its own: it downloads code-server, installs the extensions,
publishes the machine and leaves it starting on boot. The first run spends a few
minutes downloading; you do not have to watch it, and if you interrupt it, it
picks up where it left off.

#### And when it finishes

```
  ┌─ To add this computer in BosonCode ─────────────────────────────
  │  Address:    https://your-host.tailXXXX.ts.net:9443
  │  Name:       your-host
  │  Password:   ················
  └──────────────────────────────────────────────────────────────────
```

That is what you type into the app. In ZeroSpin: sidebar → **Add a Computer…** →
paste the address → the password → **Connect**. If the tablet is on the same
network the computer shows up by itself under *Found on your network*, and all
you need is the password.

It is kept in the Keychain and never asked for again.

If you lose that box, `./setup.sh --password` brings it back.

#### Optional: Claude Sessions Monitor

After the editor is running, the script offers one more thing:
[Claude Sessions Monitor](https://github.com/Demonio0N1/claude-sessions-monitor),
a web panel with the Claude Code sessions of all your machines on one page,
which also lets you answer them from your phone. BosonCode does not need it.

If you say yes, it is downloaded to `~/.ivscode/csm` and **its own** installer
runs, asking whether this machine gets its own panel or joins the panel of
another machine (it lists the ones it finds on your tailnet). It needs Node, Go
and tmux, and installs them if they are missing, which may ask for `sudo`. When
it is done, the summary prints the panel address; open it once on each device —
the link carries the pairing token.

If it is already installed and running, nothing is reinstalled. If its
installation fails, the editor is not affected: the reason is shown and so is
the command to retry.

#### Optional: an AI assistant in the editor

Last, it asks which assistant to add to code-server:

```
      [1] Continue        (default)
      [2] GitHub Copilot
      [3] none
```

- **Continue** is installed from Open VSX and gets a starting config in
  `~/.continue/config.yaml`: **Claude Opus 5.5** (`claude-opus-5-5`) for chat
  and edits, and for autocomplete, which has to be fast, a **local** model if
  Ollama is running on the machine (one with "coder" in its name if there is
  one) or else **Claude Haiku 4.5** (`claude-haiku-4-5-20251001`). Model IDs are
  the ones in [Anthropic's models overview](https://platform.claude.com/docs/en/about-claude/models/overview).
  Two caveats about Haiku for autocomplete are written into the file itself:
  Continue's documentation says chat models such as Claude are not trained on
  the fill-in-the-middle format autocomplete uses (it recommends QwenCoder via
  Ollama, or Codestral), and Anthropic lists Haiku 4.5 for retirement *not
  sooner than October 15, 2026*. An existing `config.yaml` is never touched.

  **Claude in Continue uses an Anthropic API key, which is paid per use** with
  prepaid credits. It is **not** your Claude subscription: Pro, Max and Team do
  not include the API ([Claude Help Center](https://support.claude.com/en/articles/9876003-i-have-a-paid-claude-subscription-pro-max-team-or-enterprise-plans-why-do-i-have-to-pay-separately-to-use-the-claude-api-and-console)).
  Create the key in the Claude Console under
  [Settings → API keys](https://platform.claude.com/settings/keys) and put it in
  `~/.continue/.env` as `ANTHROPIC_API_KEY=sk-ant-…` — never in `config.yaml`.
  That file is left with mode 600. Ollama's local models need no key and cost
  nothing.
- **GitHub Copilot** needs nothing installed on a current code-server: since
  VS Code opened up Copilot Chat, code-server ships it built in. You sign in from
  the chat with a one-time code at `github.com/login/device`. Only on an old
  code-server without it is it downloaded from Microsoft's Marketplace — see the
  caveats below.

If an assistant is already there, nothing is reinstalled. If the step fails,
the editor keeps working and the retry command is printed. On a brand-new
machine the step waits for the service to finish setting up code-server, which
takes a few minutes the first time.

**What was checked, and on which versions** (September 2026):

| | code-server 4.133 / 4.134 (VS Code 1.133 / 1.135) | code-server before 4.108 |
|---|---|---|
| Continue 2.0 | Installs from Open VSX, activates, loads the starting config; the generated YAML was validated with and without Ollama | Same (it asks for VS Code ≥ 1.70); not tried |
| Copilot | Built in (Copilot Chat 0.61 / 0.63). The chat opens and the sign-in offers the device code, which is the flow that works in a web editor | Downloaded from the Marketplace: Copilot Chat + Copilot, the newest compatible (0.35.3 + 1.388.0 on 4.107.1). The chat activates and asks you to sign in; the log reports *Copilot extension not found* |

Not checked: answers from Claude with a real key, or from Copilot with a signed-in
account — both need your own credentials.

**About installing Copilot by hand** on an old code-server: it is a licensing
grey area — the Marketplace terms reserve its extensions for Microsoft products,
and code-server is not one — and, depending on the version, the chat may install
and still not work. The clean fix is to update code-server, which already
includes it.

---

It stays put: it survives closing the terminal and comes back on boot. That is
what keeps the iPad from losing its server because a window was closed.

```bash
./setup.sh --check        # diagnose only, touches nothing
./setup.sh --foreground   # run it tied to this terminal (for debugging)
./setup.sh --password     # show this machine's password again
./setup.sh --csm          # install Claude Sessions Monitor without asking
./setup.sh --no-csm       # skip that step
./setup.sh -y             # yes to everything: Claude Sessions Monitor and Continue
./setup.sh --ai continue  # add Continue without asking (or: --ai copilot)
./setup.sh --no-ai        # skip the AI assistant step
./setup.sh --uninstall    # remove everything this script installed…
./setup.sh --uninstall --csm   # …and Claude Sessions Monitor as well
```

`--uninstall` leaves Claude Sessions Monitor alone unless you add `--csm`: it is
a separate installation that may be serving the panel of other machines. With
`--csm` it uses CSM's own uninstallers and keeps its token, so re-installing does
not force you to pair your devices again; `--purge` removes that too.

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
- **The same Tailscale account on both.** Having Tailscale on each is not
  enough: two accounts are two separate private networks and cannot see each
  other. If the computer belongs to work and the tablet is yours, share the
  machine from the Tailscale admin panel (*Share*) instead of moving either one
  to a different account.
- **Serve enabled on that account.** It ships disabled, so a brand-new account
  needs it switched on once. `setup.sh` detects this and hands you the link —
  see below.

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

#### Enabling Serve the first time

`tailscale serve` is **disabled on every new account**. The first time you set
this up on a freshly created one you will see:

```
Serve is not enabled on your tailnet.
To enable, visit:
   https://login.tailscale.com/f/serve?node=…
```

`tailscale` generates that link for *that* machine. Open it, switch Serve on,
and you are done: it is a permission on the **account**, not on the machine, and
it is granted once for all of your computers.

`setup.sh` recognises this case, shows you the link, waits for you to click it
and retries on its own. It cannot do it for you — it is a button in a browser.

If you also see `Access denied: serve config denied`, the operator is missing.
`setup.sh` sets it itself; by hand it is `sudo tailscale set --operator=$USER`.

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

**The tablet cannot see the computer, not even by typing the address.** First
rule out that they are on **different tailnets**. Check the name on each:

```bash
tailscale status --json | grep DNSName   # on the computer
```

If the suffixes differ — a different `tailXXXX.ts.net` — they are two separate
private networks and no address will work. Share the machine between accounts,
or put both on the same one.

**There is no `https://` address.** Check what the computer publishes:

```bash
tailscale serve status
```

If it comes back empty, Serve is not enabled on that account: see *Enabling
Serve the first time* above. If it shows an `https://…:9443` line, that line is
exactly the address to type into the app.

**Do not use the Tailscale IP in the app.** The certificate is issued for the
DNS name, not for the IP, so `https://100.x.y.z:9443` always fails. It has to be
`https://your-host.tailXXXX.ts.net:9443`.

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
