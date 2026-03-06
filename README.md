# Proot Mods — Ubuntu Desktop on Android via Termux

Run a full **XFCE desktop** with **Visual Studio Code** and **Chromium** on Android — no root required.

Uses `proot-distro` to install Ubuntu, then applies the sandbox/GPU/keyring mods that Electron and Chromium need to function inside proot.

## What You Get

| Feature | Details |
|---|---|
| **OS** | Ubuntu 22.04+ via `proot-distro` |
| **Desktop** | XFCE4 (dark theme, solid black wallpaper) |
| **Display** | TigerVNC (preferred) or Termux:X11 |
| **Editor** | VSCode with `--no-sandbox` wrapper + `password-store=basic` |
| **Browser** | Chromium with `--no-sandbox` + `--no-zygote` wrapper |
| **Sound** | PulseAudio over TCP (plays through Android speakers) |
| **USB** | OTG devices accessible via bind-mounted `/dev/bus/usb` |
| **Panel** | App Menu · Terminal · Files · Chromium · VSCode · Tasklist · Volume · Clock |
| **Architecture** | arm64 primary, amd64/armhf fallback |

## Quick Start

```bash
# 1. Clone / copy this folder into Termux
# 2. Run the Termux-side setup
bash setup-termux.sh

# 3. It will automatically:
#    - Install proot-distro + Ubuntu
#    - Copy setup-proot.sh into the proot
#    - Run it to install XFCE, VSCode, Chromium
#    - Create launcher scripts in ~/

# 4. Start the desktop
bash ~/start-ubuntu-vnc.sh     # VNC → connect RealVNC to localhost:5901
# or
bash ~/start-ubuntu-x11.sh     # Termux:X11 app

# 5. Stop
bash ~/stop-ubuntu.sh
```

## File Structure

```
proot-mods/
├── setup-termux.sh      # Step 1: Run in Termux — installs Ubuntu + creates launchers
├── setup-proot.sh       # Step 2: Runs inside proot — installs desktop + apps + mods
├── proot-backup.sh      # Backup/restore the entire Ubuntu environment
├── instructions.md      # Full documentation (architecture, troubleshooting, etc.)
└── README.md            # This file
```

### setup-termux.sh
Runs in Termux. Installs `proot-distro`, downloads Ubuntu, copies the proot setup script in, runs it, and creates convenience launcher scripts:
- `~/start-ubuntu-vnc.sh` — Start VNC server + login
- `~/start-ubuntu-x11.sh` — Start via Termux:X11
- `~/stop-ubuntu.sh` — Kill VNC / X11 sessions
- `~/login-ubuntu.sh` — Shell-only login (no desktop)

### setup-proot.sh
Runs inside Ubuntu proot. Installs and configures:
- XFCE4 desktop + TigerVNC
- VSCode with proot wrapper (`--no-sandbox`, `--password-store=basic`, etc.)
- Chromium with proot wrapper (`--no-sandbox`, `--no-zygote`, etc.)
- Environment variables (`ELECTRON_DISABLE_SANDBOX`, `LIBGL_ALWAYS_SOFTWARE`, etc.)
- Desktop customization (black background, dark theme, dock bar with Code + Chromium)

### proot-backup.sh
Run in Termux (not inside proot):
```bash
bash proot-backup.sh backup          # Full backup → ~/storage/shared/proot-backups/
bash proot-backup.sh backup --quick  # Skip caches/tmp
bash proot-backup.sh restore <file>  # Restore from archive
bash proot-backup.sh list            # List available backups
bash proot-backup.sh info <file>     # Show backup metadata
```

## Sound

PulseAudio runs in Termux and streams audio to Android speakers over TCP. Both VNC and X11 methods use the same approach.

- Volume control widget is in the XFCE panel
- Run `pavucontrol` for advanced mixing
- Test: `paplay /usr/share/sounds/freedesktop/stereo/bell.oga`

> VNC does NOT carry audio — sound plays directly through the device. Since you're on the same physical device, this works perfectly.

## USB

USB OTG devices are bind-mounted into proot automatically by the launcher scripts.

```bash
# Inside proot
lsusb              # list connected USB devices

# In Termux
termux-usb -l      # list USB devices Android sees
```

When you plug in a USB device, Android will prompt you to grant access to Termux — tap Allow.

## Display Options

### VNC (Recommended)
1. Install **RealVNC Viewer** from Play Store
2. `bash ~/start-ubuntu-vnc.sh`
3. Connect to `localhost:5901`
4. Set VNC password on first run when prompted

### Termux:X11
1. Install **Termux:X11** companion app
2. `bash ~/start-ubuntu-x11.sh`
3. Switch to the Termux:X11 app

## Known Limitations

| What | Why |
|---|---|
| No `systemd` | proot is not a real VM — use `service` commands instead |
| No `snap` packages | Snap requires systemd + kernel features |
| No GDM/LightDM login screen | Display managers need PAM/logind/systemd |
| Harmless sandbox warnings | "Failed to move to new namespace" — expected, can ignore |
| No GPU acceleration | Software rendering only (`LIBGL_ALWAYS_SOFTWARE=1`) |
| USB auto-mount | Raw libusb access works; kernel-level mount needs manual steps |
| VSCode keyring dialog | Cancel it — `password-store=basic` is already active |

## Troubleshooting

See [instructions.md](instructions.md) Section 9 for detailed troubleshooting, including:
- VNC black screen fixes
- VSCode crash resolution
- Chromium launch failures
- apt/dpkg lock issues
- Storage permission problems

## License

MIT
