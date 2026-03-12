# Proot Dev Mods — Ubuntu Desktop Environment — Full Setup Guide

> **Goal**: Install Ubuntu (22.04 or latest) via Termux `proot-distro`, set up a full XFCE desktop with VSCode, Chromium/Firefox (user choice), Chrome, development tools, media editors, network utilities, Wine, and more — all working correctly inside proot — accessible via **TigerVNC** (recommended) or **Termux:X11**.

---

## Table of Contents

1. [Prerequisites](#1-prerequisites)
2. [Install F-Droid, Termux & Companion Apps](#2-install-f-droid-termux--companion-apps)
3. [Android 12+ Phantom Process Killer Fix](#3-android-12-phantom-process-killer-fix)
4. [Termux-Side Setup (setup-termux.sh)](#4-termux-side-setup)
5. [Proot-Side Setup (setup-proot.sh)](#5-proot-side-setup)
6. [Google Drive Sync (gdrive-mount.sh)](#6-google-drive-sync)
7. [Display Access Options](#7-display-access-options)
8. [XFCE Desktop Customization](#8-xfce-desktop-customization)
9. [Daily Usage](#9-daily-usage)
10. [Sound & USB](#10-sound--usb)
11. [Backup & Restore](#11-backup--restore)
12. [Troubleshooting](#12-troubleshooting)
13. [What Works / What Doesn't in Proot](#13-what-works--what-doesnt-in-proot)

---

## 1. Prerequisites

| Requirement | Details |
|---|---|
| **Android device** | ARM64 (aarch64) — most modern phones/tablets |
| **Android version** | Android 7+ (Android 12+ requires Phantom Process Killer fix — see Section 3) |
| **Free storage** | ~6-10 GB minimum (more for all apps) |
| **F-Droid** | Third-party app store — required to install the correct version of Termux |
| **Termux** | From **F-Droid** (recommended) or GitHub releases — **NOT** the Play Store |
| **VNC viewer** | RealVNC Viewer (recommended) or AVNC |
| *OR* **Termux:X11** | Alternative display method (from F-Droid/GitHub) |

---

## 2. Install F-Droid, Termux & Companion Apps

### Step 1: Install F-Droid

**F-Droid** is an open-source app store for Android. You need it to install the correct version of Termux.

1. Open your browser on Android and go to: **https://f-droid.org**
2. Tap **Download F-Droid** to get the APK
3. Android may warn that the app is from an "unknown source" or "unsafe" — **this is expected for any app installed outside the Play Store**
4. You may need to:
   - **Allow installation from unknown sources** for your browser (Settings → Apps → Your Browser → Install unknown apps)
   - **Turn off app protection** or **Google Play Protect** temporarily if it blocks the install (Play Store → Profile → Play Protect → Settings → Turn off)
   - On some devices: Settings → Security → Allow third-party app installs
5. Install and open F-Droid — let it update its repository index on first launch

> **Why F-Droid?** Google has been restricting APK sideloading, and the Termux developer has explicitly stated on their documentation that the F-Droid version is the officially supported distribution. The Play Store version of Termux is outdated, unmaintained, and **will not work** with this project. We support open app distribution and third-party app stores.

### Step 2: Install Termux from F-Droid

> **Do NOT use the Play Store version of Termux** — it is outdated, no longer maintained, and will not work. The Termux developer officially recommends the F-Droid build.

1. Open **F-Droid**
2. Search for **Termux**
3. Install **Termux** (by Fredrik Fornwall)
4. Also install **Termux:API** from F-Droid (enables wake-lock to prevent Android from killing the session)

Alternatively, you can download Termux directly from GitHub:
- **GitHub Releases**: https://github.com/termux/termux-app/releases

After first launch:
```bash
termux-setup-storage    # Grant storage permission — tap 'Allow' on the Android prompt
pkg update && pkg upgrade -y
```

### VNC Viewer (Pick One)

| App | Notes |
|---|---|
| **RealVNC Viewer** | Play Store — polished, reliable, author's preference |
| **AVNC** | F-Droid — open source, supports `vnc://` URIs |

### OR: Termux:X11 (Alternative to VNC)

- **GitHub**: https://github.com/niceforbear/niceforbear.apk/blob/main/niceforbear-termux-x11-arm64-v8a-debug-1.02.apk
- Better performance than VNC but requires the companion Termux package (installed by the script)

---

## 3. Android 12+ Phantom Process Killer Fix

> **If you're on Android 12 or newer, you MUST do this step or Termux will be killed randomly.**

### The Problem

Android 12 introduced a "Phantom Process Killer" that monitors child processes spawned by apps. If an app exceeds the default limit of **32 child processes**, Android silently kills them. This causes Termux, Andronix, Tasker, Debian NoRoot, and other power apps to crash with **"Process completed (signal 9) — press Enter"**.

There is nothing app developers can do about this — it's baked into AOSP. The fix must be applied on your device.

> **More info**: [Android 12 Phantom Processes Killed (Termux issue tracker)](https://github.com/termux/termux-app/issues/2366)

### Fix for Stock Android 12L+ (Pixel, Android One, etc.)

Google added a toggle in Android 12L and 13+ to disable the Phantom Process Killer via Developer Options. **Note:** Some OEMs (Samsung, Xiaomi, Oppo, etc.) do not include this toggle in their custom skins — if these steps don't work for you, skip to the ADB fix below.

1. **Enable Developer Options**
   - Go to **Settings → About Phone**
   - Find **Build Number** and tap it **7 times** rapidly
   - You'll see a toast: *"You are now a developer!"*
   - You may be asked to authenticate (PIN/fingerprint) — do so

2. **Open Developer Options**
   - Go to **Settings → System → Developer Options**
   - Make sure the toggle at the top is **ON**

3. **Find Feature Flags**
   - Scroll down to find **Feature Flags** and tap it

4. **Disable the Phantom Process Killer**
   - Find the toggle for **`settings_enable_monitor_phantom_procs`**
   - Turn it **OFF**

5. Done! Termux will no longer be killed for exceeding the child process limit.

### Fix for OneUI (Samsung), MIUI (Xiaomi), ColorOS (Oppo), and Other Custom ROMs

OEMs like Samsung, Xiaomi, and Oppo often do **not** include Google's Feature Flags toggle. You need to use **ADB** (Android Debug Bridge) to disable the Phantom Process Killer.

#### Option A: ADB from a computer

1. **Install ADB** on your computer (Windows, macOS, or Linux)
   - Follow the [XDA Developers ADB installation guide](https://www.xda-developers.com/install-adb-windows-macos-linux/)

2. **Enable USB Debugging** on your Android device
   - Settings → System → Developer Options → USB Debugging → ON
   - (Enable Developer Options first if you haven't — see steps above)

3. **Connect your device** via USB and confirm the ADB authorization prompt on your phone

4. **Verify connection**:
   ```bash
   adb devices
   ```
   You should see your device listed.

5. **Run these commands** to disable the Phantom Process Killer:
   ```bash
   adb shell "/system/bin/device_config set_sync_disabled_for_tests persistent"
   adb shell "/system/bin/device_config put activity_manager max_phantom_processes 2147483647"
   adb shell settings put global settings_enable_monitor_phantom_procs false
   ```

6. Done! The phantom process limit is now set to the maximum possible value and the monitor is disabled.

#### Option B: ADB from the Android device itself (no computer needed)

If you don't have a computer, you can install ADB directly on your Android device using **LADB** or **Shizuku**:

- **LADB** (F-Droid / Play Store) — runs ADB over WiFi on-device
- **Shizuku** (GitHub / Play Store) — runs ADB commands from Android

Then run the same three commands from Option A in the ADB shell.

### Verifying the Fix

After applying either fix, open Termux and run a moderately heavy workload (e.g., start the proot desktop). If it stays running for more than a few minutes without "signal 9" errors, the fix is working.

> **Note**: This fix persists across reboots on most devices. However, some OEMs may reset it after a system update — just re-run the ADB commands if that happens.

---

## 4. Termux-Side Setup

> **Script:** `setup-termux.sh` — Run in Termux (NOT inside proot).

### What It Does

The script is fully idempotent (safe to re-run). It performs these steps:

| Section | Description |
|---|---|
| **1. Update Termux** | `pkg update && pkg upgrade` |
| **2. Install packages** | `proot-distro`, `pulseaudio`, `tigervnc`, `termux-x11-nightly`, `termux-api` — skips if already present |
| **2b. Storage** | Runs `termux-setup-storage` to grant Android storage permission |
| **3. Install Ubuntu** | Offers Ubuntu version choice (22.04 LTS or latest). If Ubuntu is already installed, prompts to **re-use** or **wipe and reinstall** |
| **4. Copy scripts** | Copies `setup-proot.sh`, `gdrive-mount.sh`, `proot-backup.sh`, `chromium-repair.sh`, and `vscode-repair.sh` into the proot rootfs |
| **5. Resolution presets** | Interactive resolution chooser — add as many device presets as you like (phone, tablet, fold, desktop) |
| **6. VNC launcher** | Creates `~/start-ubuntu-vnc.sh` — starts VNC **in the background**, returns shell to user |
| **7. X11 launcher** | Creates `~/start-ubuntu-x11.sh` — starts Termux:X11 **in the background**, returns shell to user |
| **8. Stop script** | Creates `~/stop-ubuntu.sh` — kills VNC/X11/PulseAudio, releases wake-lock |
| **9. Shell login** | Creates `~/login-ubuntu.sh` — shell-only (no desktop) |

### Re-run Detection

- Checks if core Termux packages are already installed and skips `pkg install` if so
- Detects if Ubuntu is already installed via `proot-distro list --installed`
- Offers interactive choice: "Use existing" (default) or "Remove and reinstall"

### Running

```bash
# In Termux — clone the repo and run the setup script:
pkg install git -y
git clone https://github.com/user/proot-dev-mods.git
cd proot-dev-mods
chmod +x setup-termux.sh
bash setup-termux.sh
```

Follow the on-screen prompts — the script handles everything interactively.

### Created Launcher Scripts

After running, you'll have these in `~/` (Termux home):

| Script | Purpose |
|---|---|
| `~/start-ubuntu-vnc.sh` | Start VNC desktop **in the background** — choose resolution, starts PulseAudio + proot + VNC on :1. Returns to shell immediately. |
| `~/start-ubuntu-x11.sh` | Start via Termux:X11 **in the background** — same setup but uses X11 display. Returns to shell immediately. |
| `~/stop-ubuntu.sh` | Kill all sessions (VNC + X11 + PulseAudio), release wake-lock |
| `~/login-ubuntu.sh` | Shell-only login — no desktop, just bash in proot |

### VNC Launcher Features

- **Background mode**: Desktop launches in the background — your Termux shell stays usable
- **Resolution picker**: Shows saved presets on each launch, option to add new ones
- **Battery warning**: Reminds to disable battery optimization for Termux
- **Lock cleanup**: Removes stale VNC/X lock files before starting
- **PulseAudio**: Starts TCP server for audio passthrough to Android
- **Stop cleanly**: Use `bash ~/stop-ubuntu.sh` to shut everything down

---

## 5. Proot-Side Setup

> **Script:** `setup-proot.sh` — Run inside the Ubuntu proot environment.

### What It Does

The script is fully idempotent (safe to re-run). Uses `_is_installed()` / `_all_installed()` helpers to skip already-installed packages.

#### Section 0: System Setup
- Fixes apt sources.list (replaces ftp mirrors, removes duplicates)
- Conditional `apt update && apt upgrade` (skips if recently done)
- Creates `/dev/shm` (needed for Electron/browser shared memory)

#### Section 1: XFCE Desktop + VNC
- Installs: `xfce4`, `xfce4-terminal`, selected xfce4 plugins, `dbus-x11`, `tigervnc-standalone-server`, fonts, locale
- Configures VNC xstartup with dbus and `startxfce4`
- Creates `~/.Xauthority` (needed for X11 session)

#### Section 2: Icon Themes
- Installs `humanity-icon-theme`, `adwaita-icon-theme-full`, and `hicolor-icon-theme`
- Skips `elementary-xfce-icon-theme` (10k+ files hang dpkg in proot)
- Skips if already present

#### Section 3: Browser Installation (User Choice)
**Interactive prompt** — choose Chromium v89, Firefox, or Both:

1. Removes snap browser stubs (Firefox, Chromium) — snapd itself is kept
2. Blocks snap-stub chromium + firefox permanently via APT preferences (`no-snap-chromium.pref`, `no-snap-firefox.pref`)

**If Chromium selected** — installed from Debian Buster archive (NOT snap):
3. Downloads Chromium v89 .debs + 14 Buster compat libraries directly from `archive.debian.org`
4. Installs compat libs with `dpkg --force-depends` (different sonames from Ubuntu's; coexist safely)
5. Installs Chromium v89 with `dpkg --force-depends`
6. Fixes gdk-pixbuf symlink
7. Configures proot flags via `/etc/chromium.d/proot-flags`
8. Holds packages to prevent accidental upgrades
9. Cleans up any stale Buster apt repo entries

**Why v89?** Chromium v120 (Debian Bullseye) segfaults under proot when renderer
processes communicate via IPC. Chromium v89 (Debian Buster) has a simpler
multiprocess model that works reliably, including Google login.

**Proot flags** (sourced by `/usr/bin/chromium` from `/etc/chromium.d/proot-flags`):
- `--no-sandbox`, `--no-zygote`, `--disable-setuid-sandbox`, `--disable-seccomp-filter-sandbox`
- `--disable-dev-shm-usage`, `--in-process-gpu`, `--renderer-process-limit=2`
- `--disable-gpu`, `--disable-gpu-compositing`, `--disable-software-rasterizer`
- `--disable-features=VizDisplayCompositor,WebAuthentication,WebAuthn,...` (single flag — Chromium uses only the LAST `--disable-features`)
- `--password-store=basic`, `--use-mock-keychain`, `--no-first-run`

**Chromium launch chain** (3-layer, no wrapper — stock launcher handles everything):
```
/usr/bin/chromium            ← stock Debian launcher (sources /etc/chromium.d/*)
/etc/chromium.d/proot-flags  ← comprehensive proot flags inc. --disable-features (sourced as env vars)
/usr/lib/chromium/chromium   ← actual ELF binary
```
**Important**: `--disable-features` is ONLY in `/etc/chromium.d/proot-flags`.
Chromium uses only the LAST `--disable-features` on the command line.

Plus `/usr/local/bin/chromium-default` — debug/XFCE helper wrapper with logging to `/tmp/chromium-default.log`.

**If Firefox selected** — installed from Mozilla official APT:
3. Adds Mozilla GPG key (robust download with temp file + size verification) + APT repository (`packages.mozilla.org/apt`)
4. Pins Mozilla Firefox with priority 1001 (overrides Ubuntu snap stub)
5. Installs `firefox` package (re-run safe — skips if already installed via dpkg)
6. Creates proot wrapper with `MOZ_FAKE_NO_SANDBOX=1` and sandbox-disable env vars
7. The wrapper calls `/usr/bin/firefox.real` (the actual Mozilla binary)

Sets the primary browser as default via `xdg-settings`, `update-alternatives`, and `mimeapps.list`.
If both selected, Chromium is the default browser.

#### Section 3b: Google Chrome
- Downloads `google-chrome-stable` .deb directly from `dl.google.com`
- Installs with `dpkg` (amd64 only — skipped on arm64/armhf)
- Removes any Google apt repo left behind after install
- Creates `--no-sandbox` wrapper for proot compatibility

#### Section 4: Visual Studio Code
- Installs from Microsoft apt repo
- Creates wrapper with `--no-sandbox --password-store=basic --disable-gpu`
- Patches `argv.json` for basic password store (disable HW accel, disable chromium sandbox)
- Writes `settings.json` (disable signature verification, disable workspace trust)
- Patches `.desktop` files with proot flags
- Adds `~/.bashrc` alias for terminal usage

> **After VSCode updates**: VSCode auto-updates overwrite the proot wrapper and `.desktop` files. Run `bash /root/vscode-repair.sh` inside proot to restore all fixes instantly.

#### Section 5: Productivity & Media Apps

| App | Package / Method |
|---|---|
| **Blender** | `apt install blender` |
| **GIMP** | `apt install gimp` |
| **LibreOffice** | `apt install libreoffice` |
| **GParted** | `apt install gparted` |
| **Kdenlive** | `apt install kdenlive` |
| **Shotcut** | `apt install shotcut` |
| **OBS Studio** | `apt install obs-studio` |
| **Thunderbird** | `apt install thunderbird` |
| **Spotify** | Official client (amd64) or spotifyd + spotify-tui (arm64) |
| **App Store** | GNOME Software (or GNOME PackageKit fallback) |
| **Python 3** | `apt install python3 python3-pip python3-venv` |
| **Build tools** | `build-essential`, `pkg-config`, etc. |

Each app is skip-checked — won't reinstall if already present.

#### Section 5b: Developer Tools

| Tool | Method |
|---|---|
| **Android SDK** | Full SDK: cmdline-tools from Google + sdkmanager |
| **ADB / fastboot** | `android-tools-adb android-tools-fastboot` packages |
| **Node.js + npm** | System repositories (`apt install nodejs npm`) |
| **Arduino CLI** | Official GitHub release binary |
| **cmake** | `apt install cmake` |
| **gdb** | `apt install gdb` |
| **clang** | `apt install clang` |
| **make** | `apt install make` |
| **tmux** | `apt install tmux` |
| **jq** | `apt install jq` |
| **sqlite3** | `apt install sqlite3` |
| **Java (JDK)** | `default-jdk-headless` |
| **Ruby** | `apt install ruby` |

#### Section 5d: Spotify

Tiered install — tries official repo first (amd64), then spotify-launcher via Cargo, then spotifyd + spotify-tui for arm64.

#### Section 5e: App Store, VPN, SDK, Arduino IDE, System Widgets

| Tool | Method |
|---|---|
| **App Store** | `gnome-software` (primary) or `gnome-packagekit` (fallback) — graphical package manager |
| **WireGuard** | `wireguard-tools` — VPN client (`wg`, `wg-quick`) |
| **Android SDK (Full)** | cmdline-tools from dl.google.com, sdkmanager installs platform-tools, build-tools;34.0.0, platforms;android-34. Installed to `/opt/android-sdk` |
| **Arduino IDE** | `arduino` apt package, or Arduino IDE 2.x from GitHub releases (AppImage/zip) |
| **Conky** | `conky-all` — desktop system monitor with custom config (CPU, RAM, Storage, Network, Top Processes) + autostart |

#### Section 5c: Network & Windows Tools

| Tool | Method |
|---|---|
| **nmap** | `apt install nmap` |
| **traceroute** | `apt install traceroute` |
| **whois** | `apt install whois` |
| **dnsutils** (dig) | `apt install dnsutils` |
| **Angry IP Scanner** | Latest `.deb` from GitHub releases |
| **Wine** | `apt install wine` (+ box64 on arm64 for x86 translation) |
| **Notepad++** | Silent install via Wine + .desktop shortcut |

#### Section 6: Environment Tweaks
- `/etc/environment`: `LIBGL_ALWAYS_SOFTWARE=1`, `ELECTRON_DISABLE_SANDBOX=1`, `NO_AT_BRIDGE=1`, etc.
- `~/.bashrc`: Same exports + PulseAudio server address

#### Section 7: XFCE Customization
- **Background**: Solid black
- **Panel**: Bottom dock bar (40px) with launchers for ALL installed apps
- **Theme**: Adwaita-dark with Humanity icon theme
- **Session**: xfce4-session config for clean startup

#### Section 8: Validation
- Checks every installed component (binaries, wrappers, .desktop files, configs)
- Reports what's present and what's missing
- Prints helpful next-steps and expected harmless warnings

#### Section 8b: SSH Server (Optional)
- Interactive prompt: install OpenSSH server? (yes/no)
- Configures sshd for proot: port 2222, PermitRootLogin yes, UsePAM no
- Generates host keys, creates `/run/sshd`
- Prompts user to set root password
- Creates `/usr/local/bin/start-sshd` helper script
- Optional: auto-start SSH on each proot login (added to `.bashrc`)
- VNC/X11 launchers also auto-start sshd if installed
- **Connect from another device**: `ssh root@<device-ip> -p 2222`
- **Note**: proot can't bind port 22, so port 2222 is used instead

### Running

```bash
# Enter the proot:
proot-distro login ubuntu-oldlts   # (or your chosen alias)

# Run the setup:
bash /root/setup-proot.sh
```

The script takes 15-30 minutes depending on internet speed and device.

---

## 6. Google Drive Sync

> **Script:** `gdrive-mount.sh` — Run inside the Ubuntu proot environment.

### Why Sync Instead of Mount?

FUSE mounting (`rclone mount`) requires a kernel FUSE module, which is **not available** inside proot. Instead, this script uses rclone's **sync/copy/bisync** commands to transfer files between Google Drive and a local `~/GoogleDrive` directory.

### What It Does

| Section | Description |
|---|---|
| **1. Install rclone** | Via apt or official installer script |
| **2. Create directory** | `~/GoogleDrive` local sync folder |
| **3. Configure remote** | Interactive OAuth setup — works with VNC browser or manual token paste |
| **4. Test connection** | Lists top-level Drive folders to confirm access |
| **5. Sync scripts** | Creates 5 wrapper commands in `~/.local/bin/` |
| **6. Thunar bookmark** | Adds GoogleDrive to file manager sidebar |
| **7. Desktop shortcut** | Interactive menu: open folder, pull, push, bisync, status, config |
| **8. Auto-sync** | Optional: auto-pull from Drive on each proot login |

### OAuth Authentication

Two methods available during setup:

**Option A — Browser (if VNC desktop is running):**
rclone opens the installed browser inside the proot for Google sign-in.

**Option B — Manual token (headless):**
rclone prints a URL. Open it on any device (phone, laptop), sign in, paste the token back.

### Sync Commands

After setup, these commands are available from anywhere in the proot:

| Command | Description |
|---|---|
| `gdrive-pull` | Download Google Drive → `~/GoogleDrive` |
| `gdrive-pull Documents` | Sync only a specific subfolder |
| `gdrive-push` | Upload `~/GoogleDrive` → Google Drive (**destructive** — deletes remote files not present locally) |
| `gdrive-push Projects` | Push only a specific subfolder |
| `gdrive-copy ~/file Drive/path` | One-way copy (safe, no deletes) |
| `gdrive-bisync` | Two-way bidirectional sync |
| `gdrive-bisync --resync` | First-time bisync (resolves conflicts) |
| `gdrive-status` | Show Drive connection info, usage, top folders |

### Running

```bash
# Enter the proot:
proot-distro login ubuntu-oldlts

# Run the setup:
bash /root/gdrive-mount.sh
```

### Direct rclone Commands

You can also use rclone directly for advanced operations:

```bash
rclone ls gdrive:               # List all files
rclone lsd gdrive:              # List directories
rclone copy file.txt gdrive:    # Upload a single file
rclone config                   # Reconfigure remotes
rclone config show              # Show current config
rclone about gdrive:            # Show storage usage
```

---

## 7. Display Access Options

### Option A: TigerVNC + RealVNC Viewer (Recommended)

This is the author's preferred method. Reliable, works well over local connections.

**Start:**
```bash
# In Termux:
bash ~/start-ubuntu-vnc.sh
```

**Connect:**
1. Open **RealVNC Viewer** on Android
2. Add new connection: `localhost:5901`
3. Connect — set VNC password on first run when prompted

**Custom resolution:**
Resolution presets are configured during setup (Section 4 step 5). You'll be offered a choice each time you start. To add more presets later, edit `~/.proot-resolutions.conf`.

**Manual VNC start** (inside proot, for debugging):
```bash
vncserver :1 -geometry 1920x1080 -depth 24 -localhost no
```

### Option B: Termux:X11

Better performance than VNC but requires the companion app.

**Start:**
```bash
# In Termux:
bash ~/start-ubuntu-x11.sh
```

Then switch to the **Termux:X11** app on Android.

### Comparison

| Feature | VNC | Termux:X11 |
|---|---|---|
| Setup effort | Lower — just install RealVNC | Needs sideloaded APK |
| Performance | Good | Better (native Wayland) |
| Multi-display | Yes (multiple :display) | No |
| Copy-paste | Bidirectional | One-way (X11→Android) |
| Audio | Via PulseAudio TCP | Same |
| Recommended for | Most users | Performance-sensitive use |

---

## 8. XFCE Desktop Customization

The setup script auto-configures the desktop:

### Background
Solid black — set via `xfce4-desktop.xml` for all 4 workspaces.

### Panel (Bottom Dock)
A single bottom panel (40px height) with these items:

| Position | Plugin | Details |
|---|---|---|
| 1 | Applications | `applicationsmenu` — shows "Applications" text label |
| 2 | Settings | Launcher → `xfce4-settings-manager` |
| 3 | Terminal | `xfce4-terminal` |
| 4 | Thunar | File manager |
| 5 | Primary Browser | Launcher → Chromium or Firefox (whichever is default) |
| 6 | Firefox | (only present when both browsers installed) |
| 7 | Chrome | Launcher → `google-chrome-stable` |
| 8 | Thunderbird | Email client |
| 9 | VSCode | Launcher → `code` wrapper |
| 10 | LibreOffice | `libreoffice-startcenter` |
| 11 | GIMP | Image editor |
| 12 | Blender | 3D modeling |
| 13 | Spotify | Music streaming |
| 14 | Task List | `tasklist` — window list |
| 15 | Separator | Expandable spacer |
| 16 | Systray | `systray` |
| 17 | PulseAudio | Volume control |
| 18 | Clock | `clock` (LCD mode) |

### Theme
- **Window theme**: Adwaita-dark
- **Icon theme**: Humanity (with Adwaita and hicolor available)
- **Clock**: LCD mode
- **App menu**: Shows "Applications" text label
- **Display power management**: Disabled (DPMS off)
- **Compositing**: Disabled (not useful in VNC/proot)

### Manual Customization
```bash
# Inside proot:
xfce4-settings-manager  # Full settings GUI
xfce4-panel --preferences  # Panel preferences
xfconf-query -c xfce4-desktop -p /backdrop/screen0/monitorscreen/workspace0/last-image -s ""  # Remove wallpaper
```

---

## 9. Daily Usage

### Starting Your Session
```bash
# In Termux:
bash ~/start-ubuntu-vnc.sh

# Open RealVNC Viewer → localhost:5901
```

### Working in the Desktop
- **VSCode**: Panel icon or `code /path/to/project` in terminal
- **Chromium/Firefox**: Panel icon or `chromium` / `firefox` in terminal
- **Chrome**: Panel icon or `google-chrome-stable` in terminal
- **Terminal**: Panel icon or right-click desktop → Terminal
- **File Manager**: Thunar panel icon or `thunar` in terminal
- **Blender**: Panel icon or `blender` in terminal
- **GIMP**: Panel icon or `gimp` in terminal
- **LibreOffice**: Panel icon or `libreoffice` in terminal
- **Kdenlive**: Panel icon or `kdenlive` in terminal
- **Shotcut**: Panel icon or `shotcut` in terminal
- **Thunderbird**: Panel icon or `thunderbird` in terminal
- **Spotify**: Panel icon or `spotify` in terminal
- **Notepad++**: Desktop shortcut or `wine ~/.wine/drive_c/Program\ Files/Notepad++/notepad++.exe`
- **Angry IP Scanner**: `ipscan` or Angry IP Scanner desktop shortcut
- **App Store**: GNOME Software from panel or `gnome-software` in terminal
- **WireGuard**: `wg show` to list interfaces, `wg-quick up wg0` to connect
- **Conky**: Auto-starts on desktop — shows CPU, RAM, Storage, Network, Top Processes
- **Settings**: Panel icon or `xfce4-settings-manager` in terminal

### Google Drive Sync
```bash
gdrive-pull              # Download from Drive
gdrive-push              # Upload to Drive (destructive)
gdrive-copy ~/file dst   # Safe copy to Drive
gdrive-bisync            # Two-way sync
gdrive-status            # Connection info
```

### Development Tools
```bash
# Android SDK
adb devices              # List connected devices
sdkmanager --list        # List available SDK packages
sdkmanager --update      # Update installed packages

# Node.js
node --version && npm --version

# Arduino
arduino-cli version
arduino-cli board list
arduino                  # Launch Arduino IDE (if installed)

# WireGuard VPN
wg show                  # Show VPN interfaces
wg-quick up wg0          # Start VPN (after config)

# Build tools
cmake --version
make --version
gcc --version
clang --version
gdb --version

# Languages
java -version
ruby --version
python3 --version

# Utilities
tmux                     # Terminal multiplexer
jq --version             # JSON processor
sqlite3 --version        # SQLite database
```

### Network Tools
```bash
nmap -sP 192.168.1.0/24       # Scan local network
traceroute google.com          # Trace route
dig google.com                 # DNS lookup
whois example.com              # WHOIS lookup
```

### Shell-Only Access (No Desktop)
```bash
# In Termux:
bash ~/login-ubuntu.sh
# or:
proot-distro login ubuntu-oldlts
```

### Stopping Your Session
```bash
# In Termux:
bash ~/stop-ubuntu.sh
```

---

## 10. Sound & USB

### Sound (PulseAudio)

PulseAudio runs in Termux and streams audio to Android speakers over TCP. Both VNC and X11 methods use the same approach.

```
Termux PulseAudio → TCP socket → Proot apps → Android speakers
```

- Volume control widget is in the XFCE panel (PulseAudio Plugin)
- Run `pavucontrol` for advanced mixing
- Test: `paplay /usr/share/sounds/freedesktop/stereo/bell.oga`

> VNC does NOT carry audio — sound plays directly through the device. Since you're on the same physical device, this works perfectly.

**Troubleshooting sound:**
```bash
# In Termux (make sure it's running):
pulseaudio --start

# Inside proot (check connection):
pactl info | grep "Server Name"
paplay /usr/share/sounds/freedesktop/stereo/bell.oga
```

### USB

USB OTG devices are bind-mounted into proot automatically by the launcher scripts.

```bash
# Inside proot
lsusb              # List connected USB devices

# In Termux
termux-usb -l      # List USB devices Android sees
```

When you plug in a USB device, Android will prompt you to grant access to Termux — tap Allow.

**USB Device Compatibility:**

| Device Type | Works? | Notes |
|---|---|---|
| USB keyboard/mouse | ✔ | Android handles input directly |
| USB drive | ⚠ | Raw access via libusb; kernel-level mount needs root |
| Arduino (serial) | ✔ | Via `/dev/ttyUSB*` or `/dev/ttyACM*` |
| ADB device | ✔ | Via `adb` in proot |
| USB camera | ⚠ | Depends on Android USB API |

---

## 11. Backup & Restore

> **Script:** `proot-backup.sh` — Run in Termux (NOT inside proot).

### Setup

The script is placed at `~/proot-backup.sh` automatically by `setup-termux.sh`. Make sure storage permission is granted:
```bash
termux-setup-storage    # If not already done
chmod +x ~/proot-backup.sh
```

### Commands

```bash
bash ~/proot-backup.sh backup          # Full backup → ~/storage/shared/proot-backups/
bash ~/proot-backup.sh backup --quick  # Skip caches/tmp (smaller, faster)
bash ~/proot-backup.sh restore <file>  # Restore from archive
bash ~/proot-backup.sh list            # List available backups
bash ~/proot-backup.sh info <file>     # Show backup metadata
```

### Backup Details

- **Location**: `Internal Storage/proot-backups/` (accessible from Android file manager)
- **Format**: `.tar.gz` with `.meta.txt` sidecar containing metadata
- **Typical sizes**: 1.5–2.5 GB (quick), 2.5–4 GB (full)

### Getting Backups Off Device

| Method | Command / Steps |
|---|---|
| Android file manager | Browse to `Internal Storage/proot-backups/` |
| USB to PC | Connect USB, browse to `proot-backups/` |
| ADB pull | `adb pull /sdcard/proot-backups/ ./` |
| SCP | `scp ~/storage/shared/proot-backups/*.tar.gz user@host:~/` |
| rclone (Google Drive) | `rclone copy ~/storage/shared/proot-backups/ gdrive:proot-backups/` |
| termux-share | `termux-share ~/storage/shared/proot-backups/*.tar.gz` |

### Restoring on a Different Device

1. Install Termux on the new device
2. Run `setup-termux.sh` to install proot-distro and Ubuntu
3. Transfer the `.tar.gz` backup to `Internal Storage/proot-backups/`
4. Run `bash ~/proot-backup.sh restore <filename>`
5. Choose "wipe and replace" or "overwrite/merge" when prompted
6. Start desktop: `bash ~/start-ubuntu-vnc.sh`

### Custom Distro

```bash
PROOT_DISTRO=debian bash ~/proot-backup.sh backup
PROOT_BACKUP_DIR=~/my-backups bash ~/proot-backup.sh backup
```

---

## 12. Troubleshooting

### Common Issues

| Issue | Solution |
|---|---|
| **VSCode crashes on launch** | Run `code --verbose --no-sandbox` to see errors. Usually missing libs: `apt install libnss3 libxss1 libatk-bridge2.0-0 libgtk-3-0 libgbm1 libasound2` |
| **Keyring unlock popup** | Cancel it — `password-store=basic` is already configured |
| **Chromium won't start** | Run `chromium` in terminal to see errors. Check `ldd /usr/lib/chromium/chromium \| grep 'not found'` for missing libs. Check `/etc/chromium.d/proot-flags` exists. Run `bash /root/chromium-repair.sh` to reinstall |
| **VSCode broken after update** | VSCode updates overwrite the proot wrapper and .desktop files. Run `bash /root/vscode-repair.sh` inside proot to restore all fixes |
| **Browser is snap (won't launch)** | Ubuntu ships snap-stub browsers that are non-functional in proot. Run `bash /root/chromium-repair.sh` to remove snap and install Chromium v89 from Debian Buster. Or re-run `setup-proot.sh` which blocks snap automatically |
| **Black screen in VNC** | Kill & restart: stop script + start script. Or manually: `vncserver -kill :1` then re-run |
| **Icons missing in panel** | `apt install adwaita-icon-theme-full hicolor-icon-theme humanity-icon-theme && gtk-update-icon-cache /usr/share/icons/Adwaita` |
| **Panel not showing correctly** | Delete `~/.config/xfce4/panel/` and `~/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml`, then restart session |
| **"SUID sandbox helper" error** | Normal proot noise — harmless, ignore it |
| **apt update errors** | Re-run `setup-proot.sh` or manually fix `/etc/apt/sources.list` |
| **No audio** | Start PulseAudio in Termux first: `pulseaudio --start`. Inside proot: `pactl info` |
| **Termux:X11 blank screen** | `pkill -f termux.x11; bash ~/start-ubuntu-x11.sh` |
| **VNC "connection refused"** | VNC may not have started. Enter proot and run `vncserver :1 -geometry 1920x1080 -depth 24 -localhost no` |
| **Error 9 / Signal 9 (Termux killed)** | Android's Phantom Process Killer is terminating Termux. **See Section 3** for the full fix. Quick version: enable Developer Options, disable `settings_enable_monitor_phantom_procs` in Feature Flags, or run the ADB commands. Also disable battery optimization for Termux: Settings → Apps → Termux → Battery → Unrestricted |
| **Wine/Notepad++ not working** | On arm64, needs box64: check `dpkg -l box64`. Reinstall if missing from ryanfortner repo |
| **Angry IP Scanner missing** | Re-run `setup-proot.sh` — it auto-downloads the latest from GitHub |
| **Google Drive auth failed** | Run `rclone config` inside proot to reconfigure. Use manual token if browser doesn't work |
| **gdrive-pull/push not found** | Ensure `~/.local/bin` is in PATH: `export PATH="$HOME/.local/bin:$PATH"` |
| **Conky not showing** | Kill and restart: `killall conky; sleep 2; conky -d -c ~/.config/conky/conky.conf` |
| **Android SDK not found** | Source the profile: `source /etc/profile.d/android-sdk.sh` or check `/opt/android-sdk/cmdline-tools/` |
| **WireGuard no interface** | Create config at `/etc/wireguard/wg0.conf` first, then `wg-quick up wg0` |
| **Arduino IDE won't start** | Run `arduino` in terminal for errors. On arm64, the IDE 2.x may need `--no-sandbox` |

### Harmless Proot Warnings (Ignore These)

```
Failed to move to new namespace: PID namespaces supported, ...
dbus / netlink / udev / inotify warnings
SUID sandbox helper binary not found
Received signal 11 (rare — retry launch)
libGL error: failed to open /dev/dri/...
```

### Debug Chromium

The `chromium-default` wrapper logs full environment info:
```bash
# Check the debug log:
cat /tmp/chromium-default.log

# Run with verbose output:
chromium-default 2>&1 | head -50
```

---

## 13. What Works / What Doesn't in Proot

### Works

- **Desktop**: XFCE4 with bottom dock, dark theme, Humanity icons
- **Browsers**: Chromium v89 (direct .deb from archive.debian.org) and/or Firefox (Mozilla APT) + Google Chrome — all with proot sandbox-disable wrappers
- **Code editors**: VSCode (with `--no-sandbox --password-store=basic`)
- **Office**: LibreOffice (Writer, Calc, Impress, Draw, Base)
- **Graphics**: GIMP, Blender (software rendering)
- **Video**: Kdenlive, Shotcut, OBS Studio
- **Email**: Thunderbird
- **Music**: Spotify (official client on amd64, spotifyd + spotify-tui on arm64)
- **Network**: nmap, traceroute, whois, dig, Angry IP Scanner
- **Windows apps**: Wine + Notepad++ (box64 on arm64)
- **Cloud**: Google Drive via rclone sync/copy/bisync
- **Sound**: PulseAudio over TCP (plays through Android speakers)
- **USB**: OTG devices via bind-mounted `/dev/bus/usb`
- **Languages**: Python 3, Node.js, Java (JDK), Ruby
- **Dev tools**: Android SDK (full), ADB, Arduino CLI + IDE, cmake, gdb, clang, make, tmux, jq, sqlite3
- **VPN**: WireGuard (`wg`, `wg-quick`)
- **System monitor**: Conky desktop widgets (CPU, RAM, Storage, Network, Top Processes)
- **App store**: GNOME Software (graphical package manager)
- **Version control**: Git, SSH, GPG
- **Build systems**: Gradle, Flutter CLI, npm, pip, gem, Maven

### Does NOT Work

| Tool | Why | Alternative |
|---|---|---|
| Docker | Needs kernel namespaces | Remote Docker or Podman (limited) |
| Snap | Needs systemd | Use apt or .deb packages |
| Android Emulator | Needs KVM | Use physical device via ADB |
| Hardware GPU | No `/dev/dri` in proot | Software rendering (`LIBGL_ALWAYS_SOFTWARE=1`) |
| FUSE mounts | No kernel FUSE module | Use rclone sync/copy instead of rclone mount |
| USB auto-mount | Needs kernel driver | Manual mount or raw libusb access |
| GDM/LightDM | Display managers need systemd | VNC xstartup with `startxfce4` |
| systemd services | No systemd in proot | Use `service` commands instead |

> **Note on GDM**: GDM (GNOME Display Manager) cannot run in proot because it requires systemd, PAM, and logind — none of which work in proot. XFCE launched directly via `startxfce4` in the VNC xstartup is the correct approach.

> **Note on FUSE**: `rclone mount` requires FUSE, which needs a kernel module not available in proot. Use `gdrive-pull` / `gdrive-push` / `gdrive-bisync` for Google Drive sync instead.

---

## Quick Reference Card

```bash
# ── Start / Stop (background — shell stays usable) ───
bash ~/start-ubuntu-vnc.sh       # Start VNC desktop (background)
bash ~/start-ubuntu-x11.sh      # Start X11 desktop (background)
bash ~/stop-ubuntu.sh            # Stop everything
bash ~/login-ubuntu.sh           # Shell only (no desktop)

# ── Inside Proot ──────────────────────────────────────
bash /root/setup-proot.sh        # (Re)run proot setup
bash /root/gdrive-mount.sh       # Set up Google Drive sync
bash /root/chromium-repair.sh    # Fix Chromium after issues
bash /root/vscode-repair.sh      # Fix VSCode after updates

# ── Google Drive ──────────────────────────────────────
gdrive-pull                      # Download Drive → ~/GoogleDrive
gdrive-push                      # Upload ~/GoogleDrive → Drive
gdrive-copy ~/file Drive/path    # Safe copy (no deletes)
gdrive-bisync                    # Two-way sync
gdrive-status                    # Connection info

# ── Backup / Restore (Termux) ────────────────────────
bash ~/proot-backup.sh backup           # Full backup
bash ~/proot-backup.sh backup --quick   # Quick backup
bash ~/proot-backup.sh restore <file>   # Restore
bash ~/proot-backup.sh list             # List backups

# ── Sound ─────────────────────────────────────────────
paplay /usr/share/sounds/freedesktop/stereo/bell.oga   # Test
pavucontrol                      # Volume mixer

# ── USB ───────────────────────────────────────────────
lsusb                            # List USB devices (proot)
termux-usb -l                    # List USB devices (Termux)
```
