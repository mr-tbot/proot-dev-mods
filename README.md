# Proot Dev Mods — Ubuntu & Development on Android via Termux

Run a full **XFCE desktop** with **VSCode**, **Chromium/Firefox**, **Chrome if on compatible chipset**, development tools, media editors, network utilities, **Wine**, and **cloud storage** (Google Drive & Dropbox) on Android — no root required.


![proot-dev-mods](https://github.com/user-attachments/assets/84dfd64c-6c12-4857-b03f-79859d68243a)
Runs on majority of Android hardware - including this tiny phone!


Uses `proot-distro` to install Ubuntu, then applies sandbox/GPU/keyring mods that Electron, Chromium, and Wine need to function inside proot.

---

## ❤️ Support ongoing MR-TBOT.com / CODEDATDA.casa Development — Keep the Lights On

Proot-Dev-Mods is built and maintained by **one developer** with the help of AI tools. There is no corporate sponsor, no VC funding — just late nights, community feedback, and a passion for open-source software.

If Proot-Dev-Mods has been useful to you — **please consider making a donation.** Every contribution, no matter the size, directly fuels continued development, bug fixes, and keeping this project free and open-source for everyone.

### Donate via PayPal (Preferred)

[![Donate via PayPal](https://img.shields.io/badge/Donate-PayPal-blue.svg?logo=paypal&style=for-the-badge)](https://www.paypal.com/donate/?business=7DQWLBARMM3FE&no_recurring=0&item_name=Support+the+development+and+growth+of+innovative+MR_TBOT+projects.&currency_code=USD)

[**Click here to donate via PayPal**](https://www.paypal.com/donate/?business=7DQWLBARMM3FE&no_recurring=0&item_name=Support+the+development+and+growth+of+innovative+MR_TBOT+projects.&currency_code=USD)

---

## What You Get

| Category | Apps & Features |
|---|---|
| **OS** | Ubuntu 22.04 LTS or latest (as of writing - 25.10) (user choice) via `proot-distro` |
| **Desktop** | XFCE4 — dark theme, Humanity icons, bottom dock panel, solid black wallpaper |
| **Display** | TigerVNC (preferred) or Termux:X11 — interactive resolution presets |
| **Browsers** | Chromium v89 and/or Firefox (user choice) + Google Chrome — all with proot flags |
| **Code Editor** | Visual Studio Code with `--no-sandbox`, `password-store=basic` |
| **Office** | LibreOffice (Writer, Calc, Impress, Draw, Base) |
| **Graphics** | GIMP, Blender (software rendering) |
| **Video** | Kdenlive, Shotcut, OBS Studio |
| **Email** | Thunderbird |
| **Music** | Spotify (official client on amd64, spotifyd + spotify-tui on arm64) |
| **App Store** | GNOME Software (or GNOME PackageKit fallback) — graphical package manager |
| **VPN** | WireGuard (`wg`, `wg-quick`) |
| **System Monitor** | Conky desktop widgets (CPU, RAM, Storage, Network, Top Processes) |
| **Network** | nmap, traceroute, whois, dig, Angry IP Scanner |
| **Windows** | Wine (+ box64 on arm64), Notepad++ |
| **Cloud** | Google Drive & Dropbox via rclone WebDAV — browse on-demand in Thunar, nothing stored locally |
| **Dev Tools** | Android SDK (full: cmdline-tools, sdkmanager, platform-tools, build-tools), ADB, Node.js, Arduino CLI + IDE, cmake, gdb, clang, make, tmux, jq, sqlite3, Java JDK, Ruby, Python 3 |
| **Sound** | PulseAudio over TCP (plays through Android speakers) |
| **USB** | OTG devices via bind-mounted `/dev/bus/usb` |
| **SSH** | OpenSSH server on port 2222 (optional, configured during setup) |
| **Hostname** | Custom hostname configured during setup (with proot-compatible env export) |
| **Panel** | Applications &#124; Settings &#124; Terminal &#124; Thunar &#124; Chromium/Firefox &#124; Chrome &#124; Thunderbird &#124; VSCode &#124; LibreOffice &#124; GIMP &#124; Blender &#124; Spotify &#124; Tasklist &#124; Volume &#124; Clock (LCD) |
| **Architecture** | arm64 primary, amd64/armhf fallback |

---

## Repository Contents

| File | Where to Run | Purpose |
|---|---|---|
| `setup-termux.sh` | Termux | Installs proot-distro, Ubuntu, creates VNC/X11 launchers |
| `setup-proot.sh` | Inside proot | Installs ~30 apps + XFCE desktop customization + SSH + hostname |
| `chromium-repair.sh` | Inside proot | Reinstalls Chromium v89 + Firefox with proot wrappers |
| `vscode-repair.sh` | Inside proot | Restores proot wrapper after VSCode auto-updates |
| `gdrive-mount.sh` | Inside proot | Google Drive access via rclone WebDAV (browse in Thunar) |
| `dropbox-mount.sh` | Inside proot | Dropbox access via rclone WebDAV (browse in Thunar) |
| `proot-backup.sh` | Termux | Backup & restore the entire proot environment |
| `instructions.md` | — | Comprehensive step-by-step guide |

All scripts are **idempotent** — safe to re-run. They detect existing installs and skip what's already present.

---

## Quick Start

### 1. Install F-Droid and Termux

**First, install F-Droid** (open-source app store):
1. Go to **https://f-droid.org** on your Android browser
2. Download and install the F-Droid APK
3. Android may warn about "unknown sources" — allow it (this is expected for apps outside the Play Store)
4. You may need to disable **Google Play Protect** temporarily if it blocks the install

**Then install Termux from F-Droid** — **NOT** the Play Store version (it's outdated and will not work). The Termux developer officially recommends the F-Droid build.

Also install **Termux:API** from F-Droid and a VNC viewer — **RealVNC Viewer** (Play Store) is recommended.

> **Android 12+ users**: You must disable the Phantom Process Killer or Termux will be killed randomly. See [instructions.md](instructions.md) Section 3 for the full fix.

### 2. Clone the repo

```bash
pkg update && pkg upgrade -y
pkg install git -y
git clone https://github.com/user/proot-dev-mods.git
```

### 3. Run the Termux setup

```bash
cd proot-dev-mods
chmod +x setup-termux.sh
bash setup-termux.sh
```

Follow the on-screen instructions — the script will:
- Install `proot-distro`, TigerVNC, PulseAudio, Termux:X11 support
- Download and install Ubuntu (you choose the version)
- Copy scripts into the proot environment
- Let you configure resolution presets for your device(s)
- Create launcher scripts in your Termux home (`~/`)

### 4. Set up the desktop inside Ubuntu

```bash
proot-distro login ubuntu-oldlts    # (or your chosen alias)
bash /root/setup-proot.sh           # Installs ~30 apps + desktop customization
```

Follow the prompts — you'll choose browsers, hostname, and whether to enable SSH.

### 5. Exit proot and start the desktop

```bash
exit
cd ..                               # (back to Termux home)
bash ~/start-ubuntu-vnc.sh          # Starts VNC in the background
```

Open **RealVNC Viewer** → New Connection → `localhost:5901` or `127.0.0.1:5901`  (You can also connect from a remote PC by replacing `localhost` with your device's IP address)

The VNC server runs **in the background** — your Termux shell stays usable. Use `bash ~/stop-ubuntu.sh` when you're done.

### 6. (Optional) Set up cloud storage

```bash
proot-distro login ubuntu-oldlts
bash /root/gdrive-mount.sh          # Google Drive via WebDAV
bash /root/dropbox-mount.sh         # Dropbox via WebDAV
```

After setup, browse Google Drive in Thunar at `dav://localhost:8880/` and Dropbox at `dav://localhost:8881/` — or use the `gdrive` / `dbx` CLI commands.

---

## Cloud Storage (Google Drive & Dropbox)

FUSE mounting (`rclone mount`) is **not available** inside proot (no kernel module). Instead, these scripts use rclone's built-in **WebDAV server** to expose cloud storage as a browsable network location. Files are accessed on-demand — nothing is synced or stored locally.

### Google Drive (`gdrive-mount.sh`)

| Port | Thunar Address | CLI Command |
|---|---|---|
| 8880 | `dav://localhost:8880/` | `gdrive` |

### Dropbox (`dropbox-mount.sh`)

| Port | Thunar Address | CLI Command |
|---|---|---|
| 8881 | `dav://localhost:8881/` | `dbx` |

### CLI Quick Reference

Both `gdrive` and `dbx` share the same subcommands:

| Command | Description |
|---|---|
| `gdrive ls [path]` | List files/folders |
| `gdrive tree [path]` | Tree view |
| `gdrive get <remote> [local]` | Download file or folder |
| `gdrive put <local> <remote>` | Upload file or folder |
| `gdrive mkdir <path>` | Create folder |
| `gdrive rm <path>` | Delete file/folder |
| `gdrive mv <from> <to>` | Move/rename |
| `gdrive cp <from> <to>` | Copy |
| `gdrive cat <file>` | Print file to stdout |
| `gdrive search <name>` | Search by name |
| `gdrive open [path]` | Open in Thunar via WebDAV |
| `gdrive start` | Start WebDAV server |
| `gdrive stop` | Stop WebDAV server |
| `gdrive status` | Show status & quota |
| `gdrive help` | Show all commands |

Replace `gdrive` with `dbx` for Dropbox — identical usage.

### OAuth Authentication

During setup, two methods are available:

- **Option A — Browser**: rclone opens the installed browser for sign-in (requires VNC desktop running)
- **Option B — Manual token**: rclone prints a URL; open it on any device, sign in, paste the token back

---

## Repair Scripts

### `chromium-repair.sh` — Browser Repair

Reinstalls Chromium v89 from Debian Buster and/or Firefox from Mozilla APT with all proot compatibility flags. Run if Chromium/Firefox break or won't launch.

```bash
bash /root/chromium-repair.sh    # Inside proot
```

### `vscode-repair.sh` — VSCode Repair

VSCode auto-updates regularly overwrite the proot wrapper (`/usr/bin/code`), `.desktop` files, and flags. This script restores everything in seconds.

```bash
bash /root/vscode-repair.sh      # Inside proot
```

---

## Backup & Restore

Run **in Termux** (not inside proot):

```bash
bash ~/proot-backup.sh backup           # Full backup → Internal Storage/proot-backups/
bash ~/proot-backup.sh backup --quick   # Skip caches/tmp (smaller, faster)
bash ~/proot-backup.sh restore <file>   # Restore from archive
bash ~/proot-backup.sh list             # List available backups
bash ~/proot-backup.sh info <file>      # Show backup metadata
```

Backups are saved to `Internal Storage/proot-backups/` — accessible from Android's file manager, USB, ADB, or rclone.

---

## Display Options

| Feature | VNC (Recommended) | Termux:X11 |
|---|---|---|
| **Start command** | `bash ~/start-ubuntu-vnc.sh` | `bash ~/start-ubuntu-x11.sh` |
| **Viewer** | RealVNC Viewer → `localhost:5901` | Termux:X11 app |
| **Setup effort** | Lower — just install RealVNC | Needs sideloaded APK |
| **Performance** | Good | Better (native Wayland) |
| **Audio** | PulseAudio TCP → Android speakers | Same |
| **Stop** | `bash ~/stop-ubuntu.sh` | `bash ~/stop-ubuntu.sh` |

### Adding Resolution Presets

Resolution presets are stored in `~/.proot-resolutions.conf` **in Termux** (not inside the proot). The initial setup prompts you to configure them, but you can add or change presets at any time:

```bash
nano ~/.proot-resolutions.conf
```

The format is one preset per line — `LABEL|WIDTHxHEIGHT`:

```
Full HD|1920x1080
Tablet|1280x800
Portrait|1080x1920
Small|1280x720
```

Save with `Ctrl+O`, exit with `Ctrl+X`, then restart the VNC session to use the new resolution.

---

## Sound & USB

### Sound

PulseAudio runs in Termux and streams audio to Android speakers over TCP. VNC does **not** carry audio — sound plays directly through the device (which works perfectly since you're on the same physical device).

```bash
paplay /usr/share/sounds/freedesktop/stereo/bell.oga   # Test sound
pavucontrol                                              # Volume mixer
```

### USB

USB OTG devices are bind-mounted into proot by the launcher scripts. When you plug in a USB device, Android prompts you to grant access to Termux.

```bash
lsusb                # List USB devices (inside proot)
termux-usb -l        # List USB devices (in Termux)
```

> **Note**: Raw USB access works (libusb, serial). Kernel-level auto-mounting requires Android root.

---

## Quick Reference

```bash
# ── Start / Stop ──────────────────────────────────────
bash ~/start-ubuntu-vnc.sh       # Start VNC desktop (background)
bash ~/start-ubuntu-x11.sh      # Start X11 desktop (background)
bash ~/stop-ubuntu.sh            # Stop everything
bash ~/login-ubuntu.sh           # Shell only (no desktop)

# ── Inside Proot ──────────────────────────────────────
bash /root/setup-proot.sh        # (Re)run proot setup
bash /root/chromium-repair.sh    # Fix browsers
bash /root/vscode-repair.sh      # Fix VSCode after updates

# ── Cloud Storage ─────────────────────────────────────
bash /root/gdrive-mount.sh       # Set up Google Drive
bash /root/dropbox-mount.sh      # Set up Dropbox
gdrive ls                        # Browse Google Drive
dbx ls                           # Browse Dropbox
gdrive open                      # Open Drive in Thunar
dbx open                         # Open Dropbox in Thunar

# ── Backup / Restore (Termux) ────────────────────────
bash ~/proot-backup.sh backup           # Full backup
bash ~/proot-backup.sh backup --quick   # Quick backup
bash ~/proot-backup.sh restore <file>   # Restore
bash ~/proot-backup.sh list             # List backups
```

---

## Detailed Guide

See **[instructions.md](instructions.md)** for the comprehensive setup guide covering:

- Prerequisites and Android configuration
- Phantom Process Killer fix (Android 12+)
- Detailed script-by-script documentation
- XFCE desktop customization details
- Development tools usage
- Full troubleshooting guide
- What works / what doesn't in proot

---

## Known Limitations

| What | Why |
|---|---|
| No `systemd` | proot is not a real VM — use `service` commands instead |
| No `snap` packages | Snap requires systemd + kernel features |
| No `docker` | Needs kernel namespaces — use remote Docker |
| No FUSE mounts | No kernel FUSE module — use rclone WebDAV server instead |
| No GDM/LightDM | Display managers need PAM/logind/systemd |
| No GPU acceleration | Software rendering only (`LIBGL_ALWAYS_SOFTWARE=1`) |
| USB auto-mount | Raw libusb access works; kernel-level mount needs root |
| Harmless sandbox warnings | "Failed to move to new namespace" — expected, ignore |

---

## License

MIT
