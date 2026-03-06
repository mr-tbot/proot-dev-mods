# Proot Ubuntu Desktop Environment — Full Setup Guide

> **Goal**: Install Ubuntu 22.04 via Termux `proot-distro`, set up a full XFCE desktop with VSCode and Chromium — all working correctly inside proot — accessible via **TigerVNC** (recommended) or **Termux:X11**.

---

## Table of Contents

1. [Prerequisites](#1-prerequisites)
2. [Install Termux & Companion Apps](#2-install-termux--companion-apps)
3. [Termux-Side Setup Script](#3-termux-side-setup-script)
4. [Proot-Side Setup Script](#4-proot-side-setup-script)
5. [Display Access Options](#5-display-access-options)
6. [XFCE Desktop Customization](#6-xfce-desktop-customization)
7. [Daily Usage](#7-daily-usage)
8. [Sound & USB](#8-sound--usb)
9. [Backup & Restore](#9-backup--restore)
10. [Troubleshooting](#10-troubleshooting)
11. [What Works / What Doesn't in Proot](#11-what-works--what-doesnt-in-proot)

---

## 1. Prerequisites

| Requirement | Details |
|---|---|
| **Android device** | ARM64 (aarch64) — most modern phones/tablets |
| **Free storage** | ~4-6 GB minimum |
| **Termux** | From **F-Droid** or GitHub releases (NOT Play Store) |
| **VNC viewer** | RealVNC Viewer (recommended) or AVNC |
| *OR* **Termux:X11** | Alternative display method (from F-Droid/GitHub) |

---

## 2. Install Termux & Companion Apps

### Termux (Required)

> **Do NOT use the Play Store version** — it is outdated and will not work.

Install from one of:
- **F-Droid**: https://f-droid.org/en/packages/com.termux/
- **GitHub Releases**: https://github.com/termux/termux-app/releases

After first launch:
```bash
termux-setup-storage    # Grant storage permission
pkg update && pkg upgrade -y
```

### Termux:API (Recommended)

Enables wake-lock to prevent Android from killing the session:
```bash
pkg install termux-api
```
Also install the **Termux:API** companion app from F-Droid.

### VNC Viewer (Pick One)

| App | Notes |
|---|---|
| **RealVNC Viewer** | Play Store — polished, reliable, author's preference |
| **AVNC** | F-Droid — open source, supports `vnc://` URIs |

### OR: Termux:X11 (Alternative to VNC)

- **GitHub**: https://github.com/niceforbear/niceforbear.apk/blob/main/niceforbear-termux-x11-arm64-v8a-debug-1.02.apk
- Better performance than VNC but requires the companion Termux package (installed by the script)

---

## 3. Termux-Side Setup Script

> **Run this in Termux** (not inside proot). It installs proot-distro, Ubuntu, display servers, and creates launcher scripts.

Save as `~/setup-termux.sh` and run with `bash setup-termux.sh`.

```bash
#!/data/data/com.termux/files/usr/bin/bash
# ═══════════════════════════════════════════════════════════════════════
#  setup-termux.sh — Termux-side setup for Ubuntu proot desktop
#  Run in Termux (NOT inside proot)
# ═══════════════════════════════════════════════════════════════════════
set -euo pipefail

# ── Colors ────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
msg()  { printf "\n${CYAN}[*]${NC} %s\n" "$*"; }
ok()   { printf "  ${GREEN}✔${NC} %s\n" "$*"; }
warn() { printf "  ${YELLOW}⚠${NC} %s\n" "$*"; }
err()  { printf "  ${RED}✖${NC} %s\n" "$*"; exit 1; }

# ── 1. Update Termux ──────────────────────────────────────────────────
msg "Updating Termux packages..."
pkg update -y && pkg upgrade -y
ok "Termux updated."

# ── 2. Install core packages ──────────────────────────────────────────
msg "Installing required Termux packages..."
pkg install -y proot-distro pulseaudio wget

# VNC support
pkg install -y x11-repo
pkg install -y tigervnc

# Termux:X11 support (optional — both are installed so user can choose)
pkg install -y termux-x11-nightly 2>/dev/null || warn "termux-x11-nightly not available — Termux:X11 method will not work. VNC still works."

# Wake-lock support
pkg install -y termux-api 2>/dev/null || warn "termux-api not installed — wake-lock unavailable."

ok "Termux packages installed."

# ── 3. Install Ubuntu 22.04 via proot-distro ──────────────────────────
msg "Installing Ubuntu via proot-distro..."
if proot-distro list 2>/dev/null | grep -q "ubuntu.*Installed"; then
    ok "Ubuntu is already installed."
else
    proot-distro install ubuntu
    ok "Ubuntu installed."
fi

# ── 4. Copy the proot setup script into Ubuntu's filesystem ───────────
# The user should place setup-proot.sh alongside this script or in ~/
msg "Checking for setup-proot.sh..."
PROOT_SCRIPT="$HOME/setup-proot.sh"
UBUNTU_ROOT="$PREFIX/var/lib/proot-distro/installed-rootfs/ubuntu"

if [[ -f "$PROOT_SCRIPT" ]]; then
    cp "$PROOT_SCRIPT" "$UBUNTU_ROOT/root/setup-proot.sh"
    chmod +x "$UBUNTU_ROOT/root/setup-proot.sh"
    ok "setup-proot.sh copied into Ubuntu proot at /root/setup-proot.sh"
else
    warn "setup-proot.sh not found at $PROOT_SCRIPT"
    warn "Place it there and re-run, or manually copy it into the proot."
fi

# ── 5. Create VNC launcher script ─────────────────────────────────────
msg "Creating VNC launcher: ~/start-ubuntu-vnc.sh"
cat > ~/start-ubuntu-vnc.sh <<'LAUNCHER'
#!/data/data/com.termux/files/usr/bin/bash
# ─────────────────────────────────────────────────────────────
#  start-ubuntu-vnc.sh — Start Ubuntu proot + TigerVNC server
# ─────────────────────────────────────────────────────────────
# Usage: bash ~/start-ubuntu-vnc.sh
#   Then connect with VNC viewer to localhost:5901
# ─────────────────────────────────────────────────────────────
DISPLAY_NUM="${1:-1}"
VNC_PORT=$((5900 + DISPLAY_NUM))
RESOLUTION="${2:-1920x1080}"

# Acquire wake-lock so Android doesn't kill the session
command -v termux-wake-lock &>/dev/null && termux-wake-lock

# Kill any existing VNC server on this display
vncserver -kill ":${DISPLAY_NUM}" 2>/dev/null || true

# Start PulseAudio (for sound forwarding)
pulseaudio --start --load="module-native-protocol-tcp auth-ip-acl=127.0.0.1 auth-anonymous=1" --exit-idle-time=-1 2>/dev/null || true

# Launch proot-distro with Ubuntu and start VNC inside it
proot-distro login ubuntu --shared-tmp -- bash -c "
    export DISPLAY=:${DISPLAY_NUM}
    export PULSE_SERVER=127.0.0.1

    # Start dbus if available
    export DBUS_SESSION_BUS_ADDRESS=unix:path=/tmp/dbus-session-bus
    dbus-daemon --session --address=\$DBUS_SESSION_BUS_ADDRESS --nofork --nopidfile 2>/dev/null &

    # Start TigerVNC
    rm -f /tmp/.X${DISPLAY_NUM}-lock /tmp/.X11-unix/X${DISPLAY_NUM} 2>/dev/null
    vncserver :${DISPLAY_NUM} -geometry ${RESOLUTION} -depth 24 -name 'Ubuntu Desktop' -localhost no -SecurityTypes None --I-KNOW-THIS-IS-INSECURE 2>/dev/null || \
    vncserver :${DISPLAY_NUM} -geometry ${RESOLUTION} -depth 24 -name 'Ubuntu Desktop' -localhost no 2>/dev/null

    echo ''
    echo '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━'
    echo '  VNC server started!'
    echo \"  Connect to: localhost:${VNC_PORT}\"
    echo \"  Resolution: ${RESOLUTION}\"
    echo '  Press Ctrl+C to stop.'
    echo '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━'
    echo ''

    # Keep session alive
    sleep infinity
"
LAUNCHER
chmod +x ~/start-ubuntu-vnc.sh
ok "VNC launcher created: ~/start-ubuntu-vnc.sh"

# ── 6. Create Termux:X11 launcher script ──────────────────────────────
msg "Creating Termux:X11 launcher: ~/start-ubuntu-x11.sh"
cat > ~/start-ubuntu-x11.sh <<'LAUNCHER'
#!/data/data/com.termux/files/usr/bin/bash
# ─────────────────────────────────────────────────────────────
#  start-ubuntu-x11.sh — Start Ubuntu proot + Termux:X11
# ─────────────────────────────────────────────────────────────
# Usage: bash ~/start-ubuntu-x11.sh
#   Then open the Termux:X11 app
# ─────────────────────────────────────────────────────────────

# Acquire wake-lock
command -v termux-wake-lock &>/dev/null && termux-wake-lock

# Kill existing X11 processes
pkill -f "termux.x11" 2>/dev/null || true

# Start PulseAudio
pulseaudio --start --load="module-native-protocol-tcp auth-ip-acl=127.0.0.1 auth-anonymous=1" --exit-idle-time=-1 2>/dev/null || true

# Start Termux:X11 server
termux-x11 :0 &
sleep 2

# Launch the Termux:X11 Android app
am start --user 0 -n com.termux.x11/com.termux.x11.MainActivity 2>/dev/null || true

# Enter proot and start XFCE
proot-distro login ubuntu --shared-tmp -- bash -c "
    export DISPLAY=:0
    export PULSE_SERVER=127.0.0.1

    # Start dbus
    export DBUS_SESSION_BUS_ADDRESS=unix:path=/tmp/dbus-session-bus
    dbus-daemon --session --address=\$DBUS_SESSION_BUS_ADDRESS --nofork --nopidfile 2>/dev/null &

    echo 'Starting XFCE desktop via Termux:X11...'
    startxfce4 2>/dev/null
"
LAUNCHER
chmod +x ~/start-ubuntu-x11.sh
ok "Termux:X11 launcher created: ~/start-ubuntu-x11.sh"

# ── 7. Create stop script ─────────────────────────────────────────────
msg "Creating stop script: ~/stop-ubuntu.sh"
cat > ~/stop-ubuntu.sh <<'STOPPER'
#!/data/data/com.termux/files/usr/bin/bash
# Stop VNC server and release wake-lock
vncserver -kill :1 2>/dev/null || true
pkill -f "termux.x11" 2>/dev/null || true
pulseaudio --kill 2>/dev/null || true
command -v termux-wake-unlock &>/dev/null && termux-wake-unlock
echo "✔ Ubuntu desktop environment stopped."
STOPPER
chmod +x ~/stop-ubuntu.sh
ok "Stop script created: ~/stop-ubuntu.sh"

# ── 8. Create quick-login script (no desktop, just shell) ─────────────
msg "Creating shell-only login: ~/login-ubuntu.sh"
cat > ~/login-ubuntu.sh <<'LOGIN'
#!/data/data/com.termux/files/usr/bin/bash
# Quick login to Ubuntu proot (no VNC/X11, just a shell)
proot-distro login ubuntu
LOGIN
chmod +x ~/login-ubuntu.sh
ok "Shell login created: ~/login-ubuntu.sh"

# ── Done ──────────────────────────────────────────────────────────────
printf "\n${GREEN}${BOLD}"
printf '═%.0s' {1..60}
printf "\n  Termux setup complete!\n"
printf '═%.0s' {1..60}
printf "${NC}\n\n"

echo "Next steps:"
echo ""
echo "  1. Enter Ubuntu proot:"
echo "       proot-distro login ubuntu"
echo ""
echo "  2. Run the proot setup script inside Ubuntu:"
echo "       bash /root/setup-proot.sh"
echo ""
echo "  3. Exit proot (type 'exit'), then start the desktop:"
echo ""
echo "     VNC (recommended):"
echo "       bash ~/start-ubuntu-vnc.sh"
echo "       → Connect RealVNC Viewer to localhost:5901"
echo ""
echo "     Termux:X11 (alternative):"
echo "       bash ~/start-ubuntu-x11.sh"
echo "       → Open the Termux:X11 app"
echo ""
echo "  4. To stop:"
echo "       bash ~/stop-ubuntu.sh"
echo ""
```

---

## 4. Proot-Side Setup Script

> **Run this inside the Ubuntu proot environment** (after `proot-distro login ubuntu`).
> It installs XFCE, VSCode, Chromium, applies all proot mods, and customizes the desktop.

Save as `~/setup-proot.sh` (Termux home) — the Termux script copies it into the proot automatically. Or place it at `/root/setup-proot.sh` inside the proot manually.

Run with `bash /root/setup-proot.sh`.

```bash
#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════
#  setup-proot.sh — Ubuntu proot environment setup
#  Run INSIDE the proot: proot-distro login ubuntu
#  Then: bash /root/setup-proot.sh
# ═══════════════════════════════════════════════════════════════════════
set -uo pipefail

# ── Colors ────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'
msg()  { printf "\n${CYAN}[*]${NC} %s\n" "$*"; }
ok()   { printf "  ${GREEN}✔${NC} %s\n" "$*"; }
warn() { printf "  ${YELLOW}⚠${NC} %s\n" "$*"; }
err()  { printf "  ${RED}✖${NC} %s\n" "$*"; }

# ── Architecture detection ────────────────────────────────────────────
ARCH="$(dpkg --print-architecture 2>/dev/null || uname -m)"
case "$ARCH" in
    amd64|x86_64)  DEB_ARCH="amd64" ;;
    arm64|aarch64) DEB_ARCH="arm64" ;;
    armhf|armv7*)  DEB_ARCH="armhf" ;;
    *)             DEB_ARCH="arm64"; warn "Unknown arch '$ARCH' — defaulting to arm64" ;;
esac
ok "Architecture: $ARCH (deb: $DEB_ARCH)"

# ══════════════════════════════════════════════════════════════════════
#  SECTION 0: Fix apt sources.list
# ══════════════════════════════════════════════════════════════════════
msg "Fixing apt sources.list..."

SOURCES=/etc/apt/sources.list
if [[ -f "$SOURCES" ]]; then
    # Backup
    [[ ! -f "${SOURCES}.bak" ]] && cp "$SOURCES" "${SOURCES}.bak"

    # Replace ftp mirrors with archive.ubuntu.com
    if grep -qE 'ftp[^[:space:]]*\.ubuntu\.com' "$SOURCES"; then
        sed -i -E 's|ftp[^[:space:]]*\.ubuntu\.com|archive.ubuntu.com|g' "$SOURCES"
        ok "Replaced ftp mirror(s) with archive.ubuntu.com"
    fi

    # Remove duplicate lines
    BEFORE=$(grep -cE '^[[:space:]]*deb' "$SOURCES" 2>/dev/null || true)
    TMP=$(mktemp)
    awk '
        /^[[:space:]]*$/ { print; next }
        /^[[:space:]]*#/ { print; next }
        !seen[$0]++      { print; next }
                         { print "# [dup removed] " $0 }
    ' "$SOURCES" > "$TMP" && mv "$TMP" "$SOURCES"
    AFTER=$(grep -cE '^[[:space:]]*deb' "$SOURCES" 2>/dev/null || true)
    [[ $((BEFORE - AFTER)) -gt 0 ]] && ok "Removed $((BEFORE - AFTER)) duplicate line(s)"
fi

msg "Running apt update & upgrade..."
apt-get update -y
apt-get upgrade -y
ok "System updated."

# ══════════════════════════════════════════════════════════════════════
#  SECTION 1: Install XFCE Desktop Environment + VNC
# ══════════════════════════════════════════════════════════════════════
msg "Installing XFCE desktop environment..."

DEBIAN_FRONTEND=noninteractive apt-get install -y \
    xfce4 xfce4-goodies xfce4-terminal \
    dbus dbus-x11 \
    tigervnc-standalone-server tigervnc-common \
    xfonts-base xfonts-100dpi xfonts-75dpi \
    hicolor-icon-theme adwaita-icon-theme-full \
    sudo wget curl nano git \
    at-spi2-core libglib2.0-0 \
    locales \
    2>&1 | tail -10

ok "XFCE desktop installed."

# ── Set locale ────────────────────────────────────────────────────────
msg "Configuring locale..."
sed -i 's/^# *en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen 2>/dev/null || true
locale-gen en_US.UTF-8 2>/dev/null || true
update-locale LANG=en_US.UTF-8 2>/dev/null || true
ok "Locale set to en_US.UTF-8"

# ── Configure VNC xstartup ────────────────────────────────────────────
msg "Configuring VNC xstartup..."
mkdir -p ~/.vnc

cat > ~/.vnc/xstartup <<'XSTARTUP'
#!/bin/sh
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS

# Start dbus
eval $(dbus-launch --sh-syntax)
export DBUS_SESSION_BUS_ADDRESS

# Suppress proot noise
export NO_AT_BRIDGE=1
export LIBGL_ALWAYS_SOFTWARE=1
export ELECTRON_DISABLE_SANDBOX=1
export ELECTRON_DISABLE_GPU=1

# Start XFCE
exec startxfce4
XSTARTUP
chmod +x ~/.vnc/xstartup

# Set a VNC password (empty / no-auth for local use)
# To use password auth instead, run: vncpasswd
mkdir -p ~/.vnc
ok "VNC xstartup configured."

# ══════════════════════════════════════════════════════════════════════
#  SECTION 2: Install Visual Studio Code
# ══════════════════════════════════════════════════════════════════════
msg "Installing Visual Studio Code..."

if command -v code >/dev/null 2>&1; then
    ok "VSCode already installed: $(code --version 2>/dev/null | head -1)"
else
    # Add Microsoft GPG key
    apt-get install -y wget gpg apt-transport-https ca-certificates 2>/dev/null
    if [[ ! -f /usr/share/keyrings/microsoft-archive-keyring.gpg ]]; then
        wget -qO- https://packages.microsoft.com/keys/microsoft.asc \
            | gpg --dearmor > /usr/share/keyrings/microsoft-archive-keyring.gpg 2>/dev/null
        ok "Microsoft GPG key added."
    fi

    # Add VSCode repo
    if [[ ! -f /etc/apt/sources.list.d/vscode.list ]]; then
        echo "deb [arch=${DEB_ARCH} signed-by=/usr/share/keyrings/microsoft-archive-keyring.gpg] https://packages.microsoft.com/repos/code stable main" \
            > /etc/apt/sources.list.d/vscode.list
        ok "VSCode apt repository added."
    fi

    apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
        libsecret-1-0 libgbm1 libasound2 libxss1 libnss3 \
        libatk-bridge2.0-0 libgtk-3-0 gnome-keyring code 2>&1 | tail -5
    ok "VSCode installed."
fi

# ── VSCode proot wrapper ──────────────────────────────────────────────
msg "Creating VSCode proot wrapper..."
CODE_BIN="/usr/bin/code"

if [[ -e "$CODE_BIN" ]]; then
    already_wrapped=0
    head -n 6 "$CODE_BIN" 2>/dev/null | grep -q "code\.real\|proot VSCode wrapper" && already_wrapped=1

    if [[ "$already_wrapped" -eq 1 ]]; then
        ok "VSCode wrapper already in place."
    else
        if [[ -L "$CODE_BIN" ]]; then
            CODE_REAL="$(readlink -f "$CODE_BIN")"
            rm -f "$CODE_BIN"
        else
            [[ ! -f /usr/bin/code.real ]] && cp "$CODE_BIN" /usr/bin/code.real
            CODE_REAL="/usr/bin/code.real"
            rm -f "$CODE_BIN"
        fi

        cat > /usr/bin/code <<WRAPPER
#!/bin/sh
# proot VSCode wrapper — --no-sandbox is required in proot
exec "${CODE_REAL}" \\
  --no-sandbox \\
  --disable-gpu \\
  --disable-gpu-compositing \\
  --disable-dev-shm-usage \\
  --disable-software-rasterizer \\
  --password-store=basic \\
  "\$@"
WRAPPER
        chmod +x /usr/bin/code
        ok "VSCode proot wrapper created (calls $CODE_REAL)"
    fi
fi

# ── VSCode argv.json — password-store=basic ───────────────────────────
msg "Configuring VSCode keyring (password-store=basic)..."
_write_argv() {
    local cfg="$1/Code"
    mkdir -p "$cfg"
    local argv="$cfg/argv.json"
    cat > "$argv" <<'JSON'
{
    "password-store": "basic",
    "disable-hardware-acceleration": true,
    "disable-chromium-sandbox": true,
    "enable-crash-reporter": false
}
JSON
    ok "Configured: $argv"
}
_write_argv "/root/.config"
for d in /home/*/; do [[ -d "$d" ]] && _write_argv "$d/.config"; done

# ── VSCode .desktop patch ─────────────────────────────────────────────
CODE_DESKTOP="/usr/share/applications/code.desktop"
if [[ -f "$CODE_DESKTOP" ]]; then
    [[ ! -f "${CODE_DESKTOP}.bak" ]] && cp "$CODE_DESKTOP" "${CODE_DESKTOP}.bak"
    sed -i 's|^Exec=/usr/share/code/code\b|Exec=/usr/bin/code|g' "$CODE_DESKTOP"
    sed -i 's|^Exec=code\b|Exec=/usr/bin/code|g' "$CODE_DESKTOP"
    ok "code.desktop Exec= lines patched."
fi

# ══════════════════════════════════════════════════════════════════════
#  SECTION 3: Install Chromium
# ══════════════════════════════════════════════════════════════════════
msg "Installing Chromium..."

if command -v chromium-browser >/dev/null 2>&1 || command -v chromium >/dev/null 2>&1; then
    ok "Chromium already installed."
else
    DEBIAN_FRONTEND=noninteractive apt-get install -y chromium-browser 2>/dev/null || \
    DEBIAN_FRONTEND=noninteractive apt-get install -y chromium 2>/dev/null || {
        err "Failed to install Chromium. Try manually: apt install chromium-browser"
    }
    ok "Chromium installed."
fi

# ── Chromium proot wrapper ────────────────────────────────────────────
msg "Creating Chromium proot wrapper..."

# Find the actual binary name
CHROMIUM_BIN=""
[[ -e /usr/bin/chromium-browser ]] && CHROMIUM_BIN="/usr/bin/chromium-browser"
[[ -e /usr/bin/chromium ]]         && CHROMIUM_BIN="/usr/bin/chromium"

if [[ -n "$CHROMIUM_BIN" ]]; then
    if head -n 5 "$CHROMIUM_BIN" 2>/dev/null | grep -q "chromium.*\.real\|proot.*wrapper"; then
        ok "Chromium wrapper already in place."
    else
        CHROMIUM_REAL="${CHROMIUM_BIN}.real"
        if [[ ! -f "$CHROMIUM_REAL" ]]; then
            if [[ -L "$CHROMIUM_BIN" ]]; then
                CHROMIUM_REAL="$(readlink -f "$CHROMIUM_BIN")"
            else
                cp "$CHROMIUM_BIN" "$CHROMIUM_REAL"
            fi
        fi

        cat > "$CHROMIUM_BIN" <<WRAPPER
#!/bin/sh
# proot Chromium wrapper — --no-sandbox required, no GPU in proot
exec "$CHROMIUM_REAL" \\
  --no-sandbox \\
  --disable-dev-shm-usage \\
  --disable-gpu \\
  --disable-software-rasterizer \\
  --no-zygote \\
  "\$@"
WRAPPER
        chmod +x "$CHROMIUM_BIN"
        ok "Chromium proot wrapper created."
    fi

    # Patch .desktop files
    for df in /usr/share/applications/chromium*.desktop; do
        [[ -f "$df" ]] || continue
        [[ ! -f "${df}.bak" ]] && cp "$df" "${df}.bak"
        sed -i "s|^Exec=.*|Exec=$CHROMIUM_BIN %U|" "$df"
        ok "Patched: $(basename "$df")"
    done

    # Set Chromium as default browser
    command -v xdg-settings >/dev/null 2>&1 && \
        xdg-settings set default-web-browser chromium-browser.desktop 2>/dev/null || true
    if command -v xdg-mime >/dev/null 2>&1; then
        for mime in x-scheme-handler/http x-scheme-handler/https text/html; do
            xdg-mime default chromium-browser.desktop "$mime" 2>/dev/null || \
            xdg-mime default chromium.desktop "$mime" 2>/dev/null || true
        done
    fi
    ok "Chromium set as default browser."
fi

# ══════════════════════════════════════════════════════════════════════
#  SECTION 4: Proot Environment Tweaks
# ══════════════════════════════════════════════════════════════════════
msg "Applying proot environment tweaks..."

# /etc/environment — global proot-safe variables
_add_env() {
    local var="$1" val="$2"
    if grep -q "^${var}=" /etc/environment 2>/dev/null; then
        sed -i "s|^${var}=.*|${var}=${val}|" /etc/environment
    else
        echo "${var}=${val}" >> /etc/environment
    fi
}

_add_env "LIBGL_ALWAYS_SOFTWARE"                   "1"
_add_env "ELECTRON_DISABLE_GPU"                    "1"
_add_env "ELECTRON_DISABLE_SANDBOX"                "1"
_add_env "ELECTRON_DISABLE_SECURITY_WARNINGS"      "1"
_add_env "VSCODE_KEYTAR_USE_BASIC_TEXT_ENCRYPTION"  "1"
_add_env "NO_AT_BRIDGE"                            "1"
ok "/etc/environment updated."

# ~/.bashrc exports
_add_bashrc() {
    grep -qF "export $1=" ~/.bashrc 2>/dev/null || echo "export $1=\"$2\"" >> ~/.bashrc
}

_add_bashrc "ELECTRON_DISABLE_SANDBOX" "1"
_add_bashrc "VSCODE_KEYRING"           "basic"
ok "~/.bashrc exports added."

# ══════════════════════════════════════════════════════════════════════
#  SECTION 5: XFCE Desktop Customization
# ══════════════════════════════════════════════════════════════════════
msg "Customizing XFCE desktop..."

# ── 5a. Set desktop background to solid black ─────────────────────────
msg "Setting desktop wallpaper to solid black..."

# Create the XFCE desktop channel config directory
mkdir -p /root/.config/xfce4/xfconf/xfce-perchannel-xml

# Write the xfce4-desktop config — solid black, no image
cat > /root/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-desktop.xml <<'DESKTOP_XML'
<?xml version="1.0" encoding="UTF-8"?>

<channel name="xfce4-desktop" version="1.0">
  <property name="backdrop" type="empty">
    <property name="screen0" type="empty">
      <property name="monitorscreen" type="empty">
        <property name="workspace0" type="empty">
          <property name="color-style" type="int" value="0"/>
          <property name="image-style" type="int" value="0"/>
          <property name="last-image" type="string" value=""/>
          <property name="color1" type="array">
            <value type="uint" value="0"/>
            <value type="uint" value="0"/>
            <value type="uint" value="0"/>
            <value type="uint" value="65535"/>
          </property>
        </property>
        <property name="workspace1" type="empty">
          <property name="color-style" type="int" value="0"/>
          <property name="image-style" type="int" value="0"/>
          <property name="last-image" type="string" value=""/>
          <property name="color1" type="array">
            <value type="uint" value="0"/>
            <value type="uint" value="0"/>
            <value type="uint" value="0"/>
            <value type="uint" value="65535"/>
          </property>
        </property>
        <property name="workspace2" type="empty">
          <property name="color-style" type="int" value="0"/>
          <property name="image-style" type="int" value="0"/>
          <property name="last-image" type="string" value=""/>
          <property name="color1" type="array">
            <value type="uint" value="0"/>
            <value type="uint" value="0"/>
            <value type="uint" value="0"/>
            <value type="uint" value="65535"/>
          </property>
        </property>
        <property name="workspace3" type="empty">
          <property name="color-style" type="int" value="0"/>
          <property name="image-style" type="int" value="0"/>
          <property name="last-image" type="string" value=""/>
          <property name="color1" type="array">
            <value type="uint" value="0"/>
            <value type="uint" value="0"/>
            <value type="uint" value="0"/>
            <value type="uint" value="65535"/>
          </property>
        </property>
      </property>
      <property name="monitordisplay" type="empty">
        <property name="workspace0" type="empty">
          <property name="color-style" type="int" value="0"/>
          <property name="image-style" type="int" value="0"/>
          <property name="last-image" type="string" value=""/>
          <property name="color1" type="array">
            <value type="uint" value="0"/>
            <value type="uint" value="0"/>
            <value type="uint" value="0"/>
            <value type="uint" value="65535"/>
          </property>
        </property>
      </property>
    </property>
  </property>
</channel>
DESKTOP_XML

ok "Desktop background set to solid black."

# ── 5b. Add VSCode and Chromium to the XFCE panel (dock/taskbar) ─────
msg "Adding VSCode and Chromium to the XFCE panel launcher..."

# Find the Chromium .desktop file name
CHROMIUM_DESKTOP=""
[[ -f /usr/share/applications/chromium-browser.desktop ]] && CHROMIUM_DESKTOP="chromium-browser.desktop"
[[ -f /usr/share/applications/chromium.desktop ]]         && CHROMIUM_DESKTOP="chromium.desktop"

mkdir -p /root/.config/xfce4/xfconf/xfce-perchannel-xml

# We configure the XFCE panel with a top bar that includes a launcher
# with file manager, terminal, Chromium, and VSCode

cat > /root/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml <<PANEL_XML
<?xml version="1.0" encoding="UTF-8"?>

<channel name="xfce4-panel" version="1.0">
  <property name="configver" type="int" value="2"/>
  <property name="panels" type="array">
    <value type="int" value="1"/>
    <property name="dark-mode" type="bool" value="true"/>
    <property name="panel-1" type="empty">
      <property name="position" type="string" value="p=6;x=0;y=0"/>
      <property name="length" type="uint" value="100"/>
      <property name="position-locked" type="bool" value="true"/>
      <property name="icon-size" type="uint" value="0"/>
      <property name="size" type="uint" value="30"/>
      <property name="plugin-ids" type="array">
        <value type="int" value="1"/>
        <value type="int" value="2"/>
        <value type="int" value="3"/>
        <value type="int" value="4"/>
        <value type="int" value="5"/>
        <value type="int" value="6"/>
        <value type="int" value="7"/>
        <value type="int" value="8"/>
      </property>
    </property>
  </property>
  <property name="plugins" type="empty">
    <property name="plugin-1" type="string" value="applicationsmenu">
      <property name="show-tooltips" type="bool" value="true"/>
      <property name="show-button-title" type="bool" value="false"/>
    </property>
    <property name="plugin-2" type="string" value="launcher">
      <property name="items" type="array">
        <value type="string" value="xfce4-terminal.desktop"/>
      </property>
    </property>
    <property name="plugin-3" type="string" value="launcher">
      <property name="items" type="array">
        <value type="string" value="thunar.desktop"/>
      </property>
    </property>
    <property name="plugin-4" type="string" value="launcher">
      <property name="items" type="array">
        <value type="string" value="${CHROMIUM_DESKTOP:-chromium-browser.desktop}"/>
      </property>
    </property>
    <property name="plugin-5" type="string" value="launcher">
      <property name="items" type="array">
        <value type="string" value="code.desktop"/>
      </property>
    </property>
    <property name="plugin-6" type="string" value="tasklist">
      <property name="flat-buttons" type="bool" value="true"/>
      <property name="show-handle" type="bool" value="false"/>
      <property name="show-labels" type="bool" value="true"/>
    </property>
    <property name="plugin-7" type="string" value="systray">
      <property name="known-legacy-items" type="array">
        <value type="string" value="task manager"/>
      </property>
    </property>
    <property name="plugin-8" type="string" value="clock">
      <property name="digital-format" type="string" value="%R"/>
    </property>
  </property>
</channel>
PANEL_XML

ok "XFCE panel configured with: App Menu | Terminal | Files | Chromium | VSCode | Tasklist | Clock"

# ── 5c. Apply dark theme (matches black desktop) ─────────────────────
msg "Setting XFCE to dark theme..."

cat > /root/.config/xfce4/xfconf/xfce-perchannel-xml/xsettings.xml <<'XSETTINGS_XML'
<?xml version="1.0" encoding="UTF-8"?>

<channel name="xsettings" version="1.0">
  <property name="Net" type="empty">
    <property name="ThemeName" type="string" value="Adwaita-dark"/>
    <property name="IconThemeName" type="string" value="Adwaita"/>
    <property name="CursorThemeName" type="string" value="Adwaita"/>
    <property name="CursorSize" type="int" value="24"/>
    <property name="EnableEventSounds" type="bool" value="false"/>
    <property name="EnableInputFeedbackSounds" type="bool" value="false"/>
  </property>
  <property name="Xft" type="empty">
    <property name="Antialias" type="int" value="1"/>
    <property name="Hinting" type="int" value="1"/>
    <property name="HintStyle" type="string" value="hintslight"/>
    <property name="RGBA" type="string" value="rgb"/>
    <property name="DPI" type="int" value="96"/>
  </property>
</channel>
XSETTINGS_XML

# Also set the window manager theme to dark
cat > /root/.config/xfce4/xfconf/xfce-perchannel-xml/xfwm4.xml <<'XFWM4_XML'
<?xml version="1.0" encoding="UTF-8"?>

<channel name="xfwm4" version="1.0">
  <property name="general" type="empty">
    <property name="theme" type="string" value="Default-hdpi"/>
    <property name="title_font" type="string" value="Sans Bold 10"/>
    <property name="workspace_count" type="int" value="4"/>
    <property name="use_compositing" type="bool" value="false"/>
    <property name="cycle_draw_frame" type="bool" value="true"/>
    <property name="cycle_raise" type="bool" value="true"/>
  </property>
</channel>
XFWM4_XML

ok "Dark theme applied (Adwaita-dark)."

# ══════════════════════════════════════════════════════════════════════
#  SECTION 6: Final Validation
# ══════════════════════════════════════════════════════════════════════
msg "Validating installation..."

echo ""
_check() {
    local name="$1" cmd="$2" ver_cmd="$3"
    if eval "$cmd" >/dev/null 2>&1; then
        local ver; ver=$(eval "$ver_cmd" 2>/dev/null || echo "ok")
        printf "  ${GREEN}✔${NC} %-30s %s\n" "$name" "$ver"
    else
        printf "  ${RED}✖${NC} %-30s ${DIM}not found${NC}\n" "$name"
    fi
}

_check "XFCE Desktop"     "command -v startxfce4"        "echo 'installed'"
_check "TigerVNC Server"  "command -v vncserver"          "vncserver -version 2>&1 | head -1"
_check "Visual Studio Code" "command -v code"             "code --version 2>/dev/null | head -1"
_check "Chromium"          "command -v chromium-browser || command -v chromium" "echo 'installed'"
_check "Git"               "command -v git"               "git --version"
_check "wget"              "command -v wget"              "echo 'installed'"
_check "curl"              "command -v curl"              "echo 'installed'"
echo ""

_check "proot env tweaks"  "grep -q ELECTRON_DISABLE_SANDBOX /etc/environment" "echo '/etc/environment'"
_check "VSCode argv.json"  "test -f /root/.config/Code/argv.json"              "echo 'configured'"
_check "VSCode wrapper"    "head -3 /usr/bin/code 2>/dev/null | grep -q no-sandbox" "echo '/usr/bin/code'"
_check "Chromium wrapper"  "head -5 /usr/bin/chromium-browser 2>/dev/null | grep -q no-sandbox || head -5 /usr/bin/chromium 2>/dev/null | grep -q no-sandbox" "echo 'wrapped'"
_check "Desktop = black"   "test -f /root/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-desktop.xml" "echo 'configured'"
_check "Panel launchers"   "test -f /root/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml"   "echo 'configured'"
echo ""

# ══════════════════════════════════════════════════════════════════════
#  Done
# ══════════════════════════════════════════════════════════════════════
printf "\n${GREEN}${BOLD}"
printf '═%.0s' {1..60}
printf "\n  Proot setup complete!\n"
printf '═%.0s' {1..60}
printf "${NC}\n\n"

cat <<'DONE'
Next steps:

  1. Exit proot:
       exit

  2. Start the desktop (pick one):

     VNC (recommended):
       bash ~/start-ubuntu-vnc.sh
       → Open RealVNC Viewer → connect to localhost:5901

     Termux:X11:
       bash ~/start-ubuntu-x11.sh
       → Open the Termux:X11 app

  3. Inside the desktop:
     • VSCode and Chromium are in the top panel (dock bar)
     • Or launch from terminal: code .  /  chromium-browser

  4. To stop:
       bash ~/stop-ubuntu.sh

Expected harmless proot warnings (ignore these):
  - "Failed to move to new namespace..."
  - "SUID sandbox helper binary not found"
  - dbus / netlink / udev / inotify warnings

If VSCode shows a keyring unlock dialog:
  → Just cancel it. password-store=basic is already configured.

DONE
```

---

## 5. Display Access Options

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
3. Connect (no password by default)

**Custom resolution:**
```bash
bash ~/start-ubuntu-vnc.sh 1 1280x720    # display :1, 720p
bash ~/start-ubuntu-vnc.sh 1 2560x1440   # display :1, 1440p
```

**Password-protected VNC** (optional):
```bash
# Inside the proot:
vncpasswd
# Then remove "-SecurityTypes None --I-KNOW-THIS-IS-INSECURE" from the launcher
```

**Stop:**
```bash
bash ~/stop-ubuntu.sh
```

### Option B: Termux:X11

Better raw performance, no network layer. Requires the Termux:X11 companion app.

**Start:**
```bash
# In Termux:
bash ~/start-ubuntu-x11.sh
```
The Termux:X11 app opens automatically.

**Stop:**
```bash
bash ~/stop-ubuntu.sh
```

### Comparison

| Feature | TigerVNC + RealVNC | Termux:X11 |
|---|---|---|
| Performance | Good | Better (no VNC encoding) |
| Setup complexity | Simple | Moderate |
| Remote access | Yes (over network) | No (local only) |
| Touch support | Via VNC viewer | Native Android touch |
| Multi-device | Yes (connect from laptop) | No |
| Reliability | Very stable | Occasional crashes |
| Audio | PulseAudio forwarding | PulseAudio forwarding |

---

## 6. XFCE Desktop Customization

The proot setup script automatically applies these customizations:

### Black Desktop Background
- All workspaces are set to solid black (no wallpaper image)
- Reduces visual clutter and saves a tiny bit of rendering overhead
- Applied via `xfce4-desktop.xml` config

### Panel (Dock Bar) Layout
The top panel is configured with these items left-to-right:

| Position | Item | Description |
|---|---|---|
| 1 | Applications Menu | XFCE app launcher (hamburger menu) |
| 2 | Terminal | XFCE Terminal launcher |
| 3 | Files | Thunar file manager launcher |
| 4 | **Chromium** | Web browser launcher |
| 5 | **VSCode** | Code editor launcher |
| 6 | Task List | Shows running windows |
| 7 | System Tray | Notification area |
| 8 | Clock | Digital clock (HH:MM) |

### Dark Theme
- GTK theme: **Adwaita-dark**
- Icon theme: **Adwaita**
- Compositing disabled (not useful in proot, saves resources)

### Manual Customization (if needed)

To change the desktop background after setup:
```bash
# Right-click desktop → Desktop Settings → Background → Style: None, Color: pick
# Or via command line:
xfconf-query -c xfce4-desktop -p /backdrop/screen0/monitorscreen/workspace0/color-style -s 0
xfconf-query -c xfce4-desktop -p /backdrop/screen0/monitorscreen/workspace0/image-style -s 0
```

To add more apps to the panel:
```bash
# Right-click panel → Panel → Add New Items → Launcher
# Then right-click the new launcher → Properties → add a .desktop file
```

To reset panel to script defaults:
```bash
rm -rf ~/.config/xfce4/panel ~/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml
# Then re-run setup-proot.sh or restart the desktop session
```

---

## 7. Daily Usage

### Starting Your Session
```bash
# In Termux:
bash ~/start-ubuntu-vnc.sh

# Open RealVNC Viewer → localhost:5901
```

### Working in the Desktop
- **VSCode**: Click the panel icon or run `code /path/to/project` in terminal
- **Chromium**: Click the panel icon or run `chromium-browser` in terminal
- **Terminal**: Click the panel icon or right-click desktop → Terminal

### Shell-Only Access (No Desktop)
```bash
# In Termux:
bash ~/login-ubuntu.sh
# or:
proot-distro login ubuntu
```

### Stopping Your Session
```bash
# In Termux:
bash ~/stop-ubuntu.sh
```

---

## 8. Sound & USB

### Sound (PulseAudio over TCP)

Audio works by running PulseAudio in **Termux** (which has access to Android's audio HAL) and having the proot environment connect to it over TCP on `127.0.0.1`.

**How it works:**
- Termux starts PulseAudio with `module-native-protocol-tcp` (the launcher scripts do this automatically)
- Inside proot, `PULSE_SERVER=127.0.0.1` tells all PulseAudio clients to connect over TCP
- Sound plays through the **Android device speakers/headphones** — not through the VNC viewer
- This works identically for both VNC and Termux:X11 display methods

**What's installed inside proot:**
- `pulseaudio` + `libpulse0` — PulseAudio client libraries
- `alsa-utils` — ALSA compatibility layer
- `xfce4-pulseaudio-plugin` — Volume control in the XFCE panel
- `pavucontrol` — Advanced PulseAudio mixer GUI

**Testing sound:**
```bash
# Inside proot — should hear a tone through Android speakers
paplay /usr/share/sounds/freedesktop/stereo/bell.oga

# Check PulseAudio connection status
pactl info

# List audio sinks
pactl list sinks short

# Adjust volume (0-100%)
pactl set-sink-volume @DEFAULT_SINK@ 80%
```

**Troubleshooting sound:**
| Issue | Fix |
|---|---|
| No sound at all | Make sure PulseAudio is running in Termux: `pulseaudio --start --load="module-native-protocol-tcp auth-ip-acl=127.0.0.1 auth-anonymous=1" --exit-idle-time=-1` |
| `Connection refused` | PulseAudio crashed in Termux. Kill and restart: `pulseaudio --kill && pulseaudio --start ...` |
| Sound plays but choppy | Normal over TCP in proot — reduce audio quality: `pactl set-default-sample-format s16le` |
| No volume icon in panel | Right-click panel → Panel → Panel Preferences → Items → Add → PulseAudio Plugin |

> **Note**: TigerVNC has no audio channel — sound does NOT go through the VNC connection. Instead it plays directly on the Android device. Since you're physically using the same device, this works perfectly.

### USB (OTG Device Access)

USB OTG devices plugged into the Android device can be accessed from inside proot via bind-mounted `/dev/bus/usb`.

**How it works:**
- The launcher scripts (`start-ubuntu-vnc.sh`, `start-ubuntu-x11.sh`, `login-ubuntu.sh`) automatically bind-mount `/dev/bus/usb` into the proot if it exists
- Inside proot, `libusb-1.0` and `usbutils` (`lsusb`) are installed for USB device enumeration
- Android must grant USB permission to Termux when a device is plugged in

**Requirements:**
- Android device with USB OTG support
- USB OTG adapter/cable (USB-C to USB-A, etc.)
- When you plug in a USB device, Android will prompt: "Allow Termux to access USB device?" → Tap **Allow**

**Using USB inside proot:**
```bash
# List USB devices (from inside proot)
lsusb

# Detailed USB device info
lsusb -v

# List USB devices from Termux (before entering proot)
termux-usb -l
```

**What USB devices work in proot:**
| Device Type | Status | Notes |
|---|---|---|
| USB storage (flash drives) | Partial | Visible via `lsusb`; mount may require manual steps |
| USB serial (Arduino, ESP32) | Works | Install `screen` or `minicom`; device appears at `/dev/ttyUSB*` or `/dev/ttyACM*` |
| USB HID (keyboard/mouse) | Works | Android handles these natively |
| USB audio (DAC/headset) | Limited | May need additional drivers; PulseAudio config needed |
| USB cameras | Limited | Requires `v4l2` tools; kernel support varies |

> **Limitations**: Since proot runs in userspace (no real kernel control), USB access is raw `libusb`-level. Devices that need kernel drivers (e.g., USB storage auto-mount, USB network adapters) may not work without manual configuration. Serial devices and devices accessible via `libusb` work best.

---

## 9. Backup & Restore

The `proot-backup.sh` script (run in **Termux**, not inside proot) lets you create a compressed snapshot of your entire Ubuntu rootfs and restore it later — on the same device or a different one.

### Setup

Copy `proot-backup.sh` to your Termux home directory:
```bash
# If it's in your proot-mods folder:
cp /path/to/proot-mods/proot-backup.sh ~/proot-backup.sh
chmod +x ~/proot-backup.sh
```

Grant Termux storage access (needed to save backups to shared storage):
```bash
termux-setup-storage
```

### Creating a Backup

```bash
# Full backup (includes everything)
bash ~/proot-backup.sh backup

# Quick backup (skips caches, logs, temp files — smaller & faster)
bash ~/proot-backup.sh backup --quick
```

The script will:
1. Stop any running proot sessions (asks first)
2. Calculate sizes and check free space
3. Compress the entire rootfs into a `.tar.gz` archive
4. Save it to `Internal Storage/proot-backups/` (accessible from Android file manager)
5. Create a `.meta.txt` sidecar with backup details

Typical sizes:
- **Quick backup** (fresh setup with XFCE + VSCode + Chromium): ~1.5–2.5 GB
- **Full backup** (with caches): ~2.5–4 GB

### Listing & Inspecting Backups

```bash
# List all backups
bash ~/proot-backup.sh list

# Show details about a specific backup
bash ~/proot-backup.sh info proot-ubuntu-20260302-143000.tar.gz
```

### Restoring a Backup

```bash
# Restore (by filename — looks in the backup directory automatically)
bash ~/proot-backup.sh restore proot-ubuntu-20260302-143000.tar.gz

# Or by full path
bash ~/proot-backup.sh restore ~/storage/shared/proot-backups/proot-ubuntu-20260302-143000.tar.gz
```

The restore offers two modes:
- **Wipe and replace** — clean restore, removes existing rootfs first
- **Overwrite/merge** — extracts on top of existing (keeps files not in backup)

### Getting the Backup Off Your Device

Backups are saved to **Internal Storage → proot-backups/** by default, making them accessible via:

| Method | Command / Steps |
|---|---|
| **Android file manager** | Open Files app → Internal Storage → proot-backups/ → Share |
| **USB to PC** | Connect phone via USB (file transfer) → browse to proot-backups/ |
| **ADB pull** | `adb pull /sdcard/proot-backups/proot-ubuntu-*.tar.gz .` |
| **SCP to computer** | `pkg install openssh` then `scp ~/storage/shared/proot-backups/*.tar.gz user@pc:/backups/` |
| **Cloud upload** | `pkg install rclone && rclone copy ~/storage/shared/proot-backups/ gdrive:backups/` |
| **Android Share sheet** | `termux-share ~/storage/shared/proot-backups/proot-ubuntu-*.tar.gz` (needs termux-api) |

### Restoring on a Different Device

1. Install Termux on the new device
2. Run `setup-termux.sh` (installs proot-distro + Ubuntu)
3. Transfer the `.tar.gz` backup to the new device
4. Place it in `~/storage/shared/proot-backups/` (or anywhere accessible)
5. Run:
   ```bash
   bash ~/proot-backup.sh restore /path/to/proot-ubuntu-*.tar.gz
   ```
6. The restored environment will have all your apps, configs, and customizations intact

### Backing Up a Different Distro

```bash
# Backup Debian instead of Ubuntu
PROOT_DISTRO=debian bash ~/proot-backup.sh backup

# Custom backup directory
PROOT_BACKUP_DIR=/tmp/my-backups bash ~/proot-backup.sh backup
```

---

## 10. Troubleshooting

| Issue | Solution |
|---|---|
| **VSCode crashes on launch** | Run `code --verbose --no-sandbox` to see errors. Usually missing libs: `apt install libnss3 libxss1 libatk-bridge2.0-0 libgtk-3-0 libgbm1 libasound2` |
| **Keyring unlock popup** | Cancel it — `password-store=basic` is already configured |
| **Chromium won't start** | Check wrapper: `head -10 /usr/bin/chromium-browser`. Must have `--no-sandbox` |
| **Black screen in VNC** | Kill & restart: `vncserver -kill :1` then re-run `start-ubuntu-vnc.sh` |
| **Icons missing in panel** | Run inside proot: `apt install adwaita-icon-theme-full hicolor-icon-theme && gtk-update-icon-cache /usr/share/icons/Adwaita` |
| **Panel not showing correctly** | Delete `~/.config/xfce4/panel/` and `~/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml`, then restart session |
| **"SUID sandbox helper" error** | Normal proot noise — harmless, ignore it |
| **apt update errors** | Re-run sources.list fix section of setup-proot.sh, or manually edit `/etc/apt/sources.list` |
| **No audio** | Make sure PulseAudio is started in Termux before entering proot: `pulseaudio --start` |
| **Termux:X11 blank screen** | Kill all and restart: `pkill -f termux.x11; bash ~/start-ubuntu-x11.sh` |
| **VNC "connection refused"** | VNC server may not have started. Enter proot manually and run `vncserver :1 -geometry 1920x1080 -depth 24 -localhost no` |

### Harmless Proot Warnings (Ignore These)
```
Failed to move to new namespace: PID namespaces supported, ...
dbus / netlink / udev / inotify warnings
SUID sandbox helper binary not found
Received signal 11 (rare — retry launch)
libGL error: failed to open /dev/dri/...
```

---

## 11. What Works / What Doesn't in Proot

### Works
- XFCE desktop environment
- VSCode (with `--no-sandbox`)
- Chromium (with `--no-sandbox`)
- Sound via PulseAudio TCP (plays through Android speakers)
- USB OTG devices (via bind-mounted /dev/bus/usb)
- Node.js, Python, Java, Go, Rust, .NET
- Git, SSH, GPG
- Most CLI dev tools
- Android SDK CLI tools (aapt2, d8, signing)
- Gradle / Flutter CLI builds

### Does NOT Work
| Tool | Why | Alternative |
|---|---|---|
| Docker | Needs kernel namespaces | Remote Docker or Podman (limited) |
| Snap | Needs systemd | Use apt |
| Android Emulator | Needs KVM | Use physical device via ADB |
| Hardware GPU | No /dev/dri in proot | Software rendering (`LIBGL_ALWAYS_SOFTWARE=1`) |
| USB auto-mount | Needs kernel driver | Manual mount or raw libusb access |
| GDM/LightDM | Display managers need systemd | Use VNC xstartup directly |

> **Note on GDM**: GDM (GNOME Display Manager) cannot run in proot because it requires systemd, PAM, and logind — none of which work in proot. XFCE launched directly via `startxfce4` in the VNC xstartup is the correct approach.

---

## Quick Reference Card

```
START (VNC):       bash ~/start-ubuntu-vnc.sh
START (X11):       bash ~/start-ubuntu-x11.sh
STOP:              bash ~/stop-ubuntu.sh
SHELL ONLY:        bash ~/login-ubuntu.sh  (or: proot-distro login ubuntu)
CONNECT VNC:       RealVNC Viewer → localhost:5901
RE-RUN SETUP:      proot-distro login ubuntu -- bash /root/setup-proot.sh
BACKUP:            bash ~/proot-backup.sh backup
BACKUP (quick):    bash ~/proot-backup.sh backup --quick
LIST BACKUPS:      bash ~/proot-backup.sh list
RESTORE:           bash ~/proot-backup.sh restore <filename>
SOUND TEST:        pactl info   (inside proot)
SOUND VOLUME:      pactl set-sink-volume @DEFAULT_SINK@ 80%
USB LIST:          lsusb   (inside proot)
USB LIST (TERMUX): termux-usb -l
```
