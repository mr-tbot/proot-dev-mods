#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════
#  setup-proot.sh — Ubuntu proot environment setup
#
#  Installs XFCE desktop, VSCode, Chromium v89 and/or Firefox (user choice),
#  Google Chrome, Blender, GIMP, LibreOffice, GParted, Python,
#  Android SDK/ADB, Arduino CLI, Node.js, and more development tools.
#  Customizes desktop (black bg, Humanity icons, dock bar with all apps).
#
#  Run INSIDE the Ubuntu proot:
#    proot-distro login ubuntu-oldlts   (or whichever alias)
#    bash /root/setup-proot.sh
#
#  Safe to re-run — detects existing installs and won't double-wrap.
# ═══════════════════════════════════════════════════════════════════════
set -uo pipefail

# ── Colors ────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'
msg()  { printf "\n${CYAN}[*]${NC} %s\n" "$*"; }
ok()   { printf "  ${GREEN}✔${NC} %s\n" "$*"; }
warn() { printf "  ${YELLOW}⚠${NC} %s\n" "$*"; }
err()  { printf "  ${RED}✖${NC} %s\n" "$*"; }
skip() { printf "  ${DIM}─ %s (already installed)${NC}\n" "$*"; }

# ── Install log ───────────────────────────────────────────────────────
# Everything printed to stdout/stderr is also captured in the log file.
# The log persists across re-runs (appended) for full troubleshooting.
LOG_FILE="/var/log/proot-setup.log"
mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true
exec > >(tee -a "$LOG_FILE") 2>&1
echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "  proot-setup.sh started: $(date)"
echo "═══════════════════════════════════════════════════════════════"

# ── Helper: check if a dpkg package is installed ─────────────────────
_is_installed() { dpkg -s "$1" &>/dev/null; }

# ── Helper: check if ALL named packages are installed ───────────────
_all_installed() {
    for _pkg in "$@"; do
        _is_installed "$_pkg" || return 1
    done
    return 0
}

printf "${BOLD}${CYAN}"
cat <<'BANNER'
  ╔═══════════════════════════════════════════════════════════╗
  ║   Proot Ubuntu Desktop — Environment Setup               ║
  ║   XFCE + VSCode + Chromium/Firefox + Dev Tools + more    ║
  ╚═══════════════════════════════════════════════════════════╝
BANNER
printf "${NC}\n"

# ── Architecture detection ────────────────────────────────────────────
ARCH="$(dpkg --print-architecture 2>/dev/null || uname -m)"
case "$ARCH" in
    amd64|x86_64)  DEB_ARCH="amd64" ;;
    arm64|aarch64) DEB_ARCH="arm64" ;;
    armhf|armv7*)  DEB_ARCH="armhf" ;;
    *)             DEB_ARCH="arm64"; warn "Unknown arch '$ARCH' — defaulting to arm64" ;;
esac
ok "Architecture: $ARCH (deb: $DEB_ARCH)"

# ── Detect Ubuntu version ────────────────────────────────────────────
UBUNTU_CODENAME="$(lsb_release -cs 2>/dev/null || (. /etc/os-release 2>/dev/null && echo "$VERSION_CODENAME") || echo "unknown")"
UBUNTU_VERSION="$(lsb_release -rs 2>/dev/null || (. /etc/os-release 2>/dev/null && echo "$VERSION_ID") || echo "unknown")"
ok "Ubuntu: $UBUNTU_VERSION ($UBUNTU_CODENAME)"


# ══════════════════════════════════════════════════════════════════════
#  SECTION 0: Fix apt sources.list
# ══════════════════════════════════════════════════════════════════════
msg "Fixing apt sources.list..."

SOURCES=/etc/apt/sources.list
if [[ -f "$SOURCES" ]]; then
    # Backup once
    [[ ! -f "${SOURCES}.bak" ]] && cp "$SOURCES" "${SOURCES}.bak"

    # Replace ftp mirrors with archive.ubuntu.com (more reliable in proot)
    if grep -qE 'ftp[^[:space:]]*\.ubuntu\.com' "$SOURCES"; then
        sed -i -E 's|ftp[^[:space:]]*\.ubuntu\.com|archive.ubuntu.com|g' "$SOURCES"
        ok "Replaced ftp mirror(s) with archive.ubuntu.com"
    else
        ok "No ftp mirrors found — sources.list OK."
    fi

    # Remove duplicate deb lines
    BEFORE=$(grep -cE '^[[:space:]]*deb' "$SOURCES" 2>/dev/null || true)
    TMP=$(mktemp)
    awk '
        /^[[:space:]]*$/ { print; next }
        /^[[:space:]]*#/ { print; next }
        !seen[$0]++      { print; next }
                         { print "# [dup removed] " $0 }
    ' "$SOURCES" > "$TMP" && mv "$TMP" "$SOURCES"
    AFTER=$(grep -cE '^[[:space:]]*deb' "$SOURCES" 2>/dev/null || true)
    REMOVED=$((BEFORE - AFTER))
    [[ "$REMOVED" -gt 0 ]] && ok "Removed $REMOVED duplicate line(s)"
fi

# Also handle newer deb822-format sources (Ubuntu 24.04+ uses ubuntu.sources)
if [[ -f /etc/apt/sources.list.d/ubuntu.sources ]]; then
    ok "Found deb822-format sources (ubuntu.sources) — leaving as-is."
fi

msg "Running apt update & upgrade..."
# Only run full update/upgrade if XFCE isn't installed yet (first run)
# On re-runs, skip the slow apt update/upgrade since packages are present
if ! _is_installed xfce4-session; then
    apt-get update -y
    apt-get upgrade -y
    ok "System updated."
else
    ok "Existing proot environment detected — skipping apt update/upgrade."
    ok "(Re-run mode: will check packages & refresh config.)"
fi


# ── Create /dev/shm (needed by Chromium/Electron apps in proot) ──────
msg "Creating /dev/shm..."
mkdir -p /dev/shm 2>/dev/null || true
chmod 1777 /dev/shm 2>/dev/null || true
ok "/dev/shm directory ensured."


# ══════════════════════════════════════════════════════════════════════
#  SECTION 1: Install XFCE Desktop Environment + VNC
# ══════════════════════════════════════════════════════════════════════
msg "Installing XFCE desktop environment + TigerVNC..."

# NOTE: We use --no-install-recommends to prevent apt from pulling in
# elementary-xfce-icon-theme (10k+ icon files that hang dpkg in proot).
# We explicitly install the icon themes we need afterwards.

# Check key packages from this group to decide if install is needed
if _all_installed xfce4-session xfce4-terminal tigervnc-standalone-server dbus-x11; then
    skip "XFCE desktop + TigerVNC"
else
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
        --no-install-recommends \
        -o Dpkg::Options::="--force-confdef" \
        -o Dpkg::Options::="--force-confold" \
        xfce4 xfce4-terminal \
        xfce4-whiskermenu-plugin xfce4-clipman-plugin \
        xfce4-screenshooter xfce4-taskmanager \
        xfce4-notifyd xfce4-power-manager \
        thunar-archive-plugin \
        dbus dbus-x11 \
        tigervnc-standalone-server tigervnc-common \
        xfonts-base xfonts-100dpi xfonts-75dpi \
        sudo wget curl nano git \
        at-spi2-core libglib2.0-0 \
        locales \
        pulseaudio libpulse0 alsa-utils \
        xfce4-pulseaudio-plugin pavucontrol \
        libusb-1.0-0 usbutils \
        desktop-file-utils shared-mime-info \
        xdg-utils exo-utils

    ok "XFCE desktop + TigerVNC + PulseAudio + USB tools installed."
fi


# ══════════════════════════════════════════════════════════════════════
#  SECTION 2: Install Icon Themes (Humanity + fallbacks)
# ══════════════════════════════════════════════════════════════════════
msg "Installing icon themes (Humanity + fallbacks)..."

# Humanity is the Ubuntu-origin theme that provides the best icon
# coverage for XFCE menu categories (Settings, Accessories, Multimedia,
# System) in proot.  We install several fallback themes plus rebuild
# all icon caches so the panel and menus render correctly.

if _is_installed humanity-icon-theme; then
    skip "Icon themes"
else
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
        --no-install-recommends \
        -o Dpkg::Options::="--force-confdef" \
        -o Dpkg::Options::="--force-confold" \
        humanity-icon-theme \
        adwaita-icon-theme-full \
        hicolor-icon-theme \
        tango-icon-theme \
        ubuntu-mono 2>/dev/null || \
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
        --no-install-recommends \
        humanity-icon-theme \
        adwaita-icon-theme \
        hicolor-icon-theme \
        tango-icon-theme 2>/dev/null || \
    warn "Some icon theme packages could not be installed — menus may have missing icons."

    ok "Icon theme packages installed."
fi

# Rebuild icon caches so XFCE finds all icons immediately
msg "Rebuilding icon caches..."
for theme_dir in /usr/share/icons/*/; do
    if [[ -d "$theme_dir" ]]; then
        gtk-update-icon-cache -f -t "$theme_dir" 2>/dev/null || true
    fi
done
ok "Icon caches rebuilt."

# Update desktop & MIME databases so menu categories populate
update-desktop-database /usr/share/applications 2>/dev/null || true
update-mime-database /usr/share/mime 2>/dev/null || true
ok "Desktop and MIME databases updated."


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
#!/bin/bash
export PULSE_SERVER=127.0.0.1
LANG=en_US.UTF-8
export LANG
export NO_AT_BRIDGE=1
export LIBGL_ALWAYS_SOFTWARE=1
export ELECTRON_DISABLE_SANDBOX=1
export ELECTRON_DISABLE_GPU=1
export MOZ_FAKE_NO_SANDBOX=1
dbus-launch --exit-with-session /usr/bin/startxfce4
XSTARTUP
chmod +x ~/.vnc/xstartup
ok "VNC xstartup configured (dbus-launch --exit-with-session)."

# ── Create .Xauthority (prevents "does not exist" warnings) ──────────
touch /root/.Xauthority
chmod 600 /root/.Xauthority
ok ".Xauthority created."


# ══════════════════════════════════════════════════════════════════════
#  BROWSER CHOICE
# ══════════════════════════════════════════════════════════════════════
echo ""
printf "${BOLD}${CYAN}"
cat <<'BROWSERMENU'
  ┌─────────────────────────────────────────────────────┐
  │   Which browser(s) would you like to install?       │
  │                                                     │
  │   [1] Chromium v89  (recommended — proven in proot) │
  │   [2] Firefox       (Mozilla official APT)          │
  │   [3] Both                                          │
  └─────────────────────────────────────────────────────┘
BROWSERMENU
printf "${NC}"
INSTALL_CHROMIUM=0
INSTALL_FIREFOX=0

while true; do
    read -rp "  Choose [1/2/3] (default: 1): " _browser_choice
    _browser_choice="${_browser_choice:-1}"
    case "$_browser_choice" in
        1) INSTALL_CHROMIUM=1; break ;;
        2) INSTALL_FIREFOX=1; break ;;
        3) INSTALL_CHROMIUM=1; INSTALL_FIREFOX=1; break ;;
        *) echo "  Invalid choice. Enter 1, 2, or 3." ;;
    esac
done

if [[ "$INSTALL_CHROMIUM" -eq 1 ]] && [[ "$INSTALL_FIREFOX" -eq 1 ]]; then
    ok "Installing: Chromium v89 + Firefox"
elif [[ "$INSTALL_CHROMIUM" -eq 1 ]]; then
    ok "Installing: Chromium v89"
else
    ok "Installing: Firefox"
fi


# ══════════════════════════════════════════════════════════════════════
#  SECTION 3: Snap Browser Stub Cleanup
# ══════════════════════════════════════════════════════════════════════
msg "Cleaning up snap browser stubs..."

# Ubuntu's chromium-browser and firefox packages are snap stubs — they
# redirect to snapd, which cannot run inside proot (no kernel namespaces,
# no systemd, no cgroups).  We remove these stubs and block them from
# returning, but leave snapd itself installed (it's harmless if present).

# ── Step 1: Remove snap browser stubs ─────────────────────────────────
msg "Removing snap browser stubs..."

if command -v snap >/dev/null 2>&1; then
    snap remove --purge firefox 2>/dev/null || true
    snap remove --purge chromium 2>/dev/null || true
    for _snap in $(snap list 2>/dev/null | awk 'NR>1{print $1}' | grep -v "^core" | grep -v "^snapd"); do
        snap remove --purge "$_snap" 2>/dev/null || true
    done
    for _snap in $(snap list 2>/dev/null | awk 'NR>1{print $1}'); do
        snap remove --purge "$_snap" 2>/dev/null || true
    done
fi

# Remove snap stubs for chromium (always safe — we never want these)
apt-get purge -y chromium-browser chromium-browser-l10n \
    chromium-codecs-ffmpeg chromium-codecs-ffmpeg-extra 2>/dev/null || true

# For Firefox: ONLY purge if it's a snap stub (preserve working Mozilla APT installs)
_ff_is_snap_stub=0
if dpkg -s firefox 2>/dev/null | grep -q "Status: install ok installed"; then
    if head -20 /usr/bin/firefox 2>/dev/null | grep -qi "snap"; then
        _ff_is_snap_stub=1
    elif ! [[ -f /etc/apt/sources.list.d/mozilla-firefox.list ]]; then
        # Installed but no Mozilla repo configured → Ubuntu's transitional snap package
        _ff_is_snap_stub=1
    fi
fi
if [[ "$_ff_is_snap_stub" -eq 1 ]]; then
    msg "Removing Firefox snap stub..."
    apt-get purge -y firefox 2>/dev/null || true
fi
for _bin in /usr/bin/chromium-browser /usr/bin/chromium /usr/bin/firefox; do
    if [[ -f "$_bin" ]] && head -20 "$_bin" 2>/dev/null | grep -qi "snap"; then
        rm -f "$_bin"
    fi
done
# Clean up wrapper artifacts from prior runs (not managed by dpkg)
rm -f /usr/bin/firefox.real 2>/dev/null || true
ok "Snap browser stubs removed."

# Block snapd from being installed/upgraded (useless in proot — no systemd,
# no kernel namespaces, no cgroups)
cat > /etc/apt/preferences.d/no-snapd.pref <<'NOSNAPD'
Package: snapd
Pin: release *
Pin-Priority: -10
NOSNAPD
ok "snapd blocked permanently."

# Block the Ubuntu snap-stub chromium packages
# (these are useless redirect-to-snap packages that don't work in proot)
cat > /etc/apt/preferences.d/no-snap-chromium.pref <<'NOSNAPCHROM'
Package: chromium-browser chromium-browser-l10n chromium-codecs-ffmpeg chromium-codecs-ffmpeg-extra
Pin: release o=Ubuntu
Pin-Priority: -1

Package: chromium-browser chromium-browser-l10n chromium-codecs-ffmpeg chromium-codecs-ffmpeg-extra
Pin: release *
Pin-Priority: -10
NOSNAPCHROM

# Block Ubuntu's firefox snap-stub package
# (we install the real Firefox from Mozilla's official APT repo instead)
cat > /etc/apt/preferences.d/no-snap-firefox.pref <<'NOSNAPFF'
Package: firefox
Pin: release o=Ubuntu
Pin-Priority: -1
NOSNAPFF

ok "snapd + snap browser stubs blocked permanently."

# Clean up old repo configs from prior attempts
# IMPORTANT: If a previous run added the Debian Buster repo, its packages
# contaminate apt's package database and cause dependency conflicts during
# ALL subsequent installs (blender, gimp, libreoffice, vscode, etc.).
# We must remove the repo AND refresh apt's cache.
# NOTE: Mozilla Firefox repo/key/pin are NOT stale — they are intentionally
# set up by this script and should be preserved for Firefox updates.
# Detect stale third-party repos left by previous runs
_had_stale_repo=0
[[ -f /etc/apt/sources.list.d/debian-chromium.list ]]    && _had_stale_repo=1
[[ -f /etc/apt/sources.list.d/debian-chromium.sources ]]  && _had_stale_repo=1
[[ -f /etc/apt/sources.list.d/google-chrome.list ]]       && _had_stale_repo=1

# Remove stale Buster + Chrome repos, keys, and pins
# (these actually contaminate apt — Buster conflicts with Ubuntu packages,
# Chrome repo has no arm64 packages)
rm -f /etc/apt/sources.list.d/debian-chromium.list 2>/dev/null || true
rm -f /etc/apt/sources.list.d/debian-chromium.sources 2>/dev/null || true
rm -f /etc/apt/sources.list.d/google-chrome.list 2>/dev/null || true
rm -f /etc/apt/preferences.d/debian-chromium.pref 2>/dev/null || true
rm -f /usr/share/keyrings/debian-archive-all.gpg 2>/dev/null || true
rm -f /usr/share/keyrings/google-chrome.gpg 2>/dev/null || true
rm -f /etc/apt/trusted.gpg.d/debian*.gpg 2>/dev/null || true

# If any stale third-party repo was present from a prior run, refresh
# apt cache to prevent contamination of standard Ubuntu package installs
if [[ "$_had_stale_repo" -eq 1 ]]; then
    msg "Cleaning stale third-party browser repos from apt cache..."
    apt-get update -qq 2>/dev/null || true
    ok "Apt cache refreshed (stale browser repos removed)."
fi

# Fix broken dpkg state
dpkg --configure -a 2>/dev/null || true


# ══════════════════════════════════════════════════════════════════════
#  SECTION 4: Install Visual Studio Code
# ══════════════════════════════════════════════════════════════════════
msg "Installing Visual Studio Code..."

_vscode_needs_install=1
if [[ -f /usr/share/code/code ]]; then
    _vscode_needs_install=0
    ok "VSCode binary already present at /usr/share/code/code"
fi

if [[ "$_vscode_needs_install" -eq 1 ]]; then
    # Install prerequisites
    apt-get install -y wget gpg apt-transport-https ca-certificates

    # Add Microsoft GPG key
    if [[ ! -f /usr/share/keyrings/microsoft-archive-keyring.gpg ]]; then
        wget -qO- https://packages.microsoft.com/keys/microsoft.asc \
            | gpg --dearmor > /usr/share/keyrings/microsoft-archive-keyring.gpg 2>/dev/null
        ok "Microsoft GPG key added."
    fi

    # Add VSCode apt repository
    if [[ ! -f /etc/apt/sources.list.d/vscode.list ]]; then
        echo "deb [arch=${DEB_ARCH} signed-by=/usr/share/keyrings/microsoft-archive-keyring.gpg] https://packages.microsoft.com/repos/code stable main" \
            > /etc/apt/sources.list.d/vscode.list
        ok "VSCode apt repository added."
    fi

    # Install VSCode + dependencies
    # Try with libasound2t64 first (Ubuntu 24.04+), fall back to libasound2
    apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
        -o Dpkg::Options::="--force-confdef" \
        -o Dpkg::Options::="--force-confold" \
        libsecret-1-0 libgbm1 libasound2t64 libxss1 libnss3 \
        libatk-bridge2.0-0 libgtk-3-0 gnome-keyring code 2>/dev/null || \
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
        -o Dpkg::Options::="--force-confdef" \
        -o Dpkg::Options::="--force-confold" \
        libsecret-1-0 libgbm1 libasound2 libxss1 libnss3 \
        libatk-bridge2.0-0 libgtk-3-0 gnome-keyring code

    ok "VSCode installed."
fi

# ── VSCode proot wrapper ──────────────────────────────────────────────
msg "Creating VSCode proot wrapper..."

# Find the real code binary
CODE_REAL_BIN=""
if [[ -f /usr/share/code/bin/code ]]; then
    CODE_REAL_BIN="/usr/share/code/bin/code"
elif [[ -f /usr/share/code/code ]]; then
    CODE_REAL_BIN="/usr/share/code/code"
elif [[ -L /usr/bin/code ]]; then
    CODE_REAL_BIN="$(readlink -f /usr/bin/code)"
fi

if [[ -n "$CODE_REAL_BIN" ]]; then
    already_wrapped=0
    head -n 6 /usr/bin/code 2>/dev/null | grep -q "proot VSCode wrapper\|no-sandbox.*disable-gpu" && already_wrapped=1

    if [[ "$already_wrapped" -eq 1 ]]; then
        ok "VSCode wrapper already in place."
    else
        # Remove symlink or stock launcher
        rm -f /usr/bin/code

        cat > /usr/bin/code <<WRAPPER
#!/bin/sh
# proot VSCode wrapper — all flags needed for proot
exec $CODE_REAL_BIN \\
  --no-sandbox \\
  --disable-gpu \\
  --disable-gpu-compositing \\
  --disable-dev-shm-usage \\
  --disable-software-rasterizer \\
  --password-store=basic \\
  --user-data-dir="/root/.vscode" \\
  "\$@"
WRAPPER
        chmod +x /usr/bin/code
        ok "VSCode proot wrapper created (calls $CODE_REAL_BIN)"
    fi
else
    warn "Could not locate VSCode binary — wrapper not created."
    warn "You may need to install VSCode manually."
fi

# ── VSCode argv.json ──────────────────────────────────────────────────
msg "Configuring VSCode argv.json..."

_write_argv() {
    local vscode_dir="$1"
    mkdir -p "$vscode_dir"
    cat > "$vscode_dir/argv.json" <<'JSON'
{
    "disable-hardware-acceleration": true,
    "password-store": "basic",
    "disable-chromium-sandbox": true
}
JSON
    ok "Configured: $vscode_dir/argv.json"
}

# Write to both possible locations
_write_argv "/root/.vscode"
_write_argv "/root/.config/Code"
for d in /home/*/; do
    [[ -d "$d" ]] && _write_argv "$d/.config/Code"
    [[ -d "$d" ]] && _write_argv "$d/.vscode"
done

# ── VSCode settings.json — fix "Signature verification failed" in proot ──
msg "Configuring VSCode settings.json for proot..."

_write_vscode_settings() {
    local settings_dir="$1/User"
    mkdir -p "$settings_dir"
    local settings_file="$settings_dir/settings.json"
    if [[ -f "$settings_file" ]]; then
        # Merge into existing settings — add our keys if not present
        if ! grep -q '"extensions.verifySignature"' "$settings_file" 2>/dev/null; then
            # Insert before the closing brace
            sed -i 's/}$/,\n    "extensions.verifySignature": false\n}/' "$settings_file"
        fi
        if ! grep -q '"security.workspace.trust.enabled"' "$settings_file" 2>/dev/null; then
            sed -i 's/}$/,\n    "security.workspace.trust.enabled": false\n}/' "$settings_file"
        fi
        ok "Updated: $settings_file"
    else
        cat > "$settings_file" <<'VSCODE_SETTINGS'
{
    "extensions.verifySignature": false,
    "security.workspace.trust.enabled": false
}
VSCODE_SETTINGS
        ok "Created: $settings_file"
    fi
}

_write_vscode_settings "/root/.vscode"
_write_vscode_settings "/root/.config/Code"
for d in /home/*/; do
    [[ -d "$d" ]] && _write_vscode_settings "$d/.config/Code"
    [[ -d "$d" ]] && _write_vscode_settings "$d/.vscode"
done

# ── Patch code.desktop ────────────────────────────────────────────────
msg "Patching code.desktop for proot..."

CODE_DESKTOP="/usr/share/applications/code.desktop"
if [[ -f "$CODE_DESKTOP" ]]; then
    [[ ! -f "${CODE_DESKTOP}.bak" ]] && cp "$CODE_DESKTOP" "${CODE_DESKTOP}.bak"
    # Replace ALL Exec= lines with the full proot flags
    sed -i 's|^Exec=.*|Exec=/usr/share/code/code --disable-gpu --disable-gpu-compositing --no-sandbox --user-data-dir="/root/.vscode" %F|' "$CODE_DESKTOP"
    ok "code.desktop Exec= lines patched with proot flags."
fi

# Also patch code-url-handler.desktop if present
CODE_URL_DESKTOP="/usr/share/applications/code-url-handler.desktop"
if [[ -f "$CODE_URL_DESKTOP" ]]; then
    [[ ! -f "${CODE_URL_DESKTOP}.bak" ]] && cp "$CODE_URL_DESKTOP" "${CODE_URL_DESKTOP}.bak"
    sed -i 's|^Exec=.*|Exec=/usr/share/code/code --disable-gpu --disable-gpu-compositing --no-sandbox --user-data-dir="/root/.vscode" --open-url %U|' "$CODE_URL_DESKTOP"
    ok "code-url-handler.desktop patched."
fi


# ══════════════════════════════════════════════════════════════════════
#  SECTION 5: Install Additional Applications
# ══════════════════════════════════════════════════════════════════════
msg "Installing additional applications..."
msg "This may take a while (Blender, GIMP, LibreOffice, GParted, Kdenlive, Shotcut, Thunderbird, OBS, Python)..."

if _all_installed blender gimp libreoffice-common gparted python3 kdenlive shotcut thunderbird obs-studio; then
    skip "Additional applications (Blender, GIMP, LibreOffice, GParted, Kdenlive, Shotcut, Thunderbird, OBS, Python)"
else
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
        --no-install-recommends \
        -o Dpkg::Options::="--force-confdef" \
        -o Dpkg::Options::="--force-confold" \
        blender \
        gimp \
        libreoffice \
        gparted \
        kdenlive \
        shotcut \
        thunderbird \
        obs-studio \
        python3 python3-pip python3-venv python3-dev \
        build-essential \
        file-roller \
        htop \
        tree \
        unzip zip \
        net-tools \
        openssh-client

    ok "Additional applications installed."
fi

# Python: make 'python' available as a command
if ! command -v python >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1; then
    update-alternatives --install /usr/bin/python python /usr/bin/python3 1 2>/dev/null || \
        ln -sf /usr/bin/python3 /usr/bin/python 2>/dev/null || true
    ok "python → python3 symlink created."
fi


# ══════════════════════════════════════════════════════════════════════
#  SECTION 5b: Install Development Tools
# ══════════════════════════════════════════════════════════════════════
msg "Installing development tools..."

# ── Android SDK platform-tools (adb, fastboot) ──────────────────────
if command -v adb >/dev/null 2>&1; then
    skip "Android platform-tools (adb)"
else
    msg "Installing Android SDK platform-tools..."
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        adb fastboot 2>/dev/null || \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        android-tools-adb android-tools-fastboot 2>/dev/null || \
    warn "Android platform-tools not in repos. Download from: https://developer.android.com/tools/releases/platform-tools"
fi

# ── Node.js + npm ─────────────────────────────────────────────────────
if command -v node >/dev/null 2>&1; then
    skip "Node.js + npm"
else
    msg "Installing Node.js + npm..."
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        nodejs npm 2>/dev/null || \
    warn "Node.js not available from repos. Install via nvm: curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash"
fi

# ── Arduino CLI ───────────────────────────────────────────────────────
if command -v arduino-cli >/dev/null 2>&1; then
    skip "Arduino CLI"
else
    msg "Installing Arduino CLI..."
    curl -fsSL https://raw.githubusercontent.com/arduino/arduino-cli/master/install.sh 2>/dev/null \
        | BINDIR=/usr/local/bin sh 2>/dev/null && \
    ok "Arduino CLI installed." || \
    warn "Arduino CLI install failed. Get it from: https://arduino.github.io/arduino-cli/"
fi

# ── Additional dev tools (compilers, debuggers, utilities) ─────────
msg "Installing additional development tools..."
if _all_installed cmake gdb tmux; then
    skip "Additional dev tools (cmake, gdb, tmux, jq, etc.)"
else
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        -o Dpkg::Options::="--force-confdef" \
        -o Dpkg::Options::="--force-confold" \
        cmake \
        gdb \
        clang \
        make \
        pkg-config \
        autoconf automake libtool \
        strace ltrace \
        tmux screen \
        jq \
        sqlite3 libsqlite3-dev \
        libssl-dev libffi-dev \
        default-jdk-headless \
        ruby \
        2>/dev/null || warn "Some dev tools could not be installed (non-fatal)."
    ok "Additional development tools installed."
fi

ok "Development tools section complete."


# ══════════════════════════════════════════════════════════════════════
#  SECTION 5c: Network Tools + Wine / Notepad++
# ══════════════════════════════════════════════════════════════════════

# ── Network scanning tools (nmap + Angry IP Scanner) ───────────────
msg "Installing network scanning tools..."

if command -v nmap >/dev/null 2>&1; then
    skip "nmap"
else
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        nmap traceroute whois dnsutils iputils-ping 2>/dev/null || \
    warn "Some network tools could not be installed."
    ok "Network tools installed (nmap, traceroute, whois, dig)."
fi

# Angry IP Scanner — Java-based GUI network scanner (arch-independent .deb)
if command -v ipscan >/dev/null 2>&1; then
    skip "Angry IP Scanner"
else
    msg "Installing Angry IP Scanner..."
    # Requires Java (installed in dev tools section above)
    # Fetch latest release .deb from GitHub
    _ipscan_installed=0
    IPSCAN_DEB="/tmp/ipscan.deb"

    # Try to get the latest release URL from GitHub API
    IPSCAN_URL=$(curl -fsSL https://api.github.com/repos/angryip/ipscan/releases/latest 2>/dev/null \
        | grep -oP '"browser_download_url":\s*"\K[^"]+_all\.deb' | head -1) || true

    if [[ -n "$IPSCAN_URL" ]]; then
        wget -qO "$IPSCAN_DEB" "$IPSCAN_URL" 2>/dev/null && \
            dpkg -i "$IPSCAN_DEB" 2>/dev/null && _ipscan_installed=1
        apt-get install -f -y 2>/dev/null || true  # fix any missing deps
        [[ $_ipscan_installed -eq 1 ]] && ok "Angry IP Scanner installed from GitHub release."
    fi

    if [[ $_ipscan_installed -eq 0 ]]; then
        # Fallback: try a known recent version
        wget -qO "$IPSCAN_DEB" "https://github.com/angryip/ipscan/releases/download/3.9.1/ipscan_3.9.1_all.deb" 2>/dev/null && \
            dpkg -i "$IPSCAN_DEB" 2>/dev/null && _ipscan_installed=1
        apt-get install -f -y 2>/dev/null || true
        [[ $_ipscan_installed -eq 1 ]] && ok "Angry IP Scanner 3.9.1 installed."
    fi

    [[ $_ipscan_installed -eq 0 ]] && warn "Angry IP Scanner install failed. Get it from: https://angryip.org/download/"
    rm -f "$IPSCAN_DEB" 2>/dev/null
fi

# ── Wine + Notepad++ ───────────────────────────────────────────────
# Wine allows running Windows .exe apps inside the proot.
# On arm64 this needs box64/box86 to translate x86 calls.
# We try to install Wine and set up Notepad++ if it works.
msg "Installing Wine (for Windows app support)..."

WINE_OK=0
if command -v wine >/dev/null 2>&1 || command -v wine64 >/dev/null 2>&1; then
    WINE_OK=1
    skip "Wine"
else
    # Enable 32-bit arch on amd64 (needed for wine32)
    if [[ "$DEB_ARCH" == "amd64" ]]; then
        dpkg --add-architecture i386 2>/dev/null || true
        apt-get update -qq 2>/dev/null
    fi

    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        wine wine64 2>/dev/null && WINE_OK=1 || true

    # Fallback: try wine-stable or wine-development
    if [[ $WINE_OK -eq 0 ]]; then
        DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
            wine-stable 2>/dev/null && WINE_OK=1 || true
    fi
    if [[ $WINE_OK -eq 0 ]]; then
        DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
            wine-development 2>/dev/null && WINE_OK=1 || true
    fi

    # arm64: try box64 + wine-i386-to-arm64 approach
    if [[ $WINE_OK -eq 0 && "$DEB_ARCH" == "arm64" ]]; then
        warn "Native Wine not available for arm64."
        msg "Trying box64 + Wine (x86-on-arm64 translation)..."

        # Install box64 from its PPA / repo if available
        if ! command -v box64 >/dev/null 2>&1; then
            # Try Ubuntu PPA
            if ! apt-get install -y box64 2>/dev/null; then
                # Try from Ryanfortner's repo (popular for arm64 proot)
                wget -qO- https://ryanfortner.github.io/box64-debs/box64.list 2>/dev/null \
                    > /etc/apt/sources.list.d/box64.list && \
                wget -qO- https://ryanfortner.github.io/box64-debs/KEY.gpg 2>/dev/null \
                    | gpg --dearmor > /usr/share/keyrings/box64-archive-keyring.gpg 2>/dev/null && \
                sed -i 's|^deb |deb [signed-by=/usr/share/keyrings/box64-archive-keyring.gpg] |' \
                    /etc/apt/sources.list.d/box64.list 2>/dev/null && \
                apt-get update -qq 2>/dev/null && \
                apt-get install -y box64-generic-arm 2>/dev/null || \
                apt-get install -y box64 2>/dev/null || true
            fi
        fi

        # With box64 available, install x86_64 Wine
        if command -v box64 >/dev/null 2>&1; then
            ok "box64 available — x86_64 emulation enabled."
            # Try installing wine through box64
            apt-get install -y wine64 2>/dev/null && WINE_OK=1 || true
        fi

        [[ $WINE_OK -eq 0 ]] && warn "Wine on arm64 requires box64. Install manually: https://box86.org"
    fi

    [[ $WINE_OK -eq 1 ]] && ok "Wine installed." || warn "Wine could not be installed — Notepad++ will be skipped."
fi

# ── Notepad++ via Wine ───────────────────────────────────────────
NPP_INSTALLED=0
if [[ $WINE_OK -eq 1 ]]; then
    NPP_DIR="$HOME/.wine/drive_c/Program Files/Notepad++"
    if [[ -f "$NPP_DIR/notepad++.exe" ]]; then
        NPP_INSTALLED=1
        skip "Notepad++ (Wine)"
    else
        msg "Installing Notepad++ via Wine..."
        # Initialize Wine prefix (suppress first-run dialogs)
        WINEDEBUG=-all DISPLAY=:1 wineboot --init 2>/dev/null || \
            WINEDEBUG=-all wineboot --init 2>/dev/null || true

        NPP_EXE="/tmp/npp-installer.exe"
        # Download Notepad++ installer (portable/silent)
        NPP_DL_URL=$(curl -fsSL https://api.github.com/repos/notepad-plus-plus/notepad-plus-plus/releases/latest 2>/dev/null \
            | grep -oP '"browser_download_url":\s*"\K[^"]+Installer\.x64\.exe' | head -1) || true

        if [[ -n "$NPP_DL_URL" ]]; then
            wget -qO "$NPP_EXE" "$NPP_DL_URL" 2>/dev/null
        else
            # Fallback to a known version
            wget -qO "$NPP_EXE" "https://github.com/notepad-plus-plus/notepad-plus-plus/releases/download/v8.6.9/npp.8.6.9.Installer.x64.exe" 2>/dev/null || true
        fi

        if [[ -f "$NPP_EXE" && -s "$NPP_EXE" ]]; then
            # Silent install via Wine
            WINEDEBUG=-all wine "$NPP_EXE" /S 2>/dev/null && NPP_INSTALLED=1 || true
            sleep 3
            # Check if it installed
            if [[ -f "$NPP_DIR/notepad++.exe" ]]; then
                NPP_INSTALLED=1
                ok "Notepad++ installed via Wine."
            else
                warn "Notepad++ silent install may not have completed."
                warn "Try running manually:  wine '$NPP_EXE'"
            fi
        else
            warn "Could not download Notepad++ installer."
        fi
        rm -f "$NPP_EXE" 2>/dev/null
    fi

    # Create a .desktop shortcut for Notepad++ if installed
    if [[ $NPP_INSTALLED -eq 1 ]]; then
        cat > /usr/share/applications/notepadpp.desktop <<'NPPDESK'
[Desktop Entry]
Type=Application
Name=Notepad++
Comment=Source code editor (Windows, via Wine)
Exec=wine "C:\\Program Files\\Notepad++\\notepad++.exe" %F
Icon=notepad
Terminal=false
Categories=Development;TextEditor;
MimeType=text/plain;text/x-csrc;text/x-c++src;text/x-python;
NPPDESK
        update-desktop-database /usr/share/applications 2>/dev/null || true
        ok "Notepad++ .desktop shortcut created."
    fi
else
    warn "Wine not available — skipping Notepad++ installation."
    warn "To install later: apt install wine && wine npp-installer.exe /S"
fi

ok "Network tools + Wine section complete."


# ══════════════════════════════════════════════════════════════════════
#  SECTION 5d: Spotify
# ══════════════════════════════════════════════════════════════════════
msg "Installing Spotify..."

if command -v spotify >/dev/null 2>&1 || test -f /usr/share/spotify/spotify; then
    skip "Spotify"
else
    # Spotify ships an official Debian repo for amd64.
    # For arm64 (most Android devices), we use spotifyd + spotify-tui or
    # the snap-less .deb repack from GitHub, or the official repo if amd64.
    _spotify_installed=0

    if [[ "$DEB_ARCH" == "amd64" ]]; then
        # Official Spotify repo (amd64 only)
        msg "Adding official Spotify apt repository (amd64)..."
        curl -fsSL https://download.spotify.com/debian/pubkey_C85668DF69375001.gpg 2>/dev/null \
            | gpg --dearmor -o /usr/share/keyrings/spotify-archive-keyring.gpg 2>/dev/null || true
        echo "deb [signed-by=/usr/share/keyrings/spotify-archive-keyring.gpg] http://repository.spotify.com stable non-free" \
            > /etc/apt/sources.list.d/spotify.list
        apt-get update -y 2>/dev/null || true
        if DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends spotify-client 2>/dev/null; then
            _spotify_installed=1
            ok "Spotify installed from official repo (amd64)."
        fi
    fi

    if [[ $_spotify_installed -eq 0 ]]; then
        # On arm64: install spotifyd (background daemon) + spotify-tui (ncurses client)
        # Or try the snap-less approach via spotify-launcher (Flatpak alt)
        msg "Trying arm64/alternative Spotify install..."

        # Method 1: spotify-launcher from GitHub (Rust-based official-ish launcher)
        # This downloads the official client and patches it to run
        if command -v cargo >/dev/null 2>&1 || apt-get install -y --no-install-recommends cargo 2>/dev/null; then
            if cargo install spotify-launcher 2>/dev/null; then
                _spotify_installed=1
                ok "spotify-launcher installed via cargo."
            fi
        fi
    fi

    if [[ $_spotify_installed -eq 0 ]]; then
        # Method 2: spotifyd + spotify-tui (lightweight TUI client)
        msg "Installing spotifyd + spotify-tui (terminal client)..."

        # spotifyd - Spotify daemon (plays music)
        _spotifyd_url=""
        case "$DEB_ARCH" in
            arm64) _spotifyd_url="https://github.com/Spotifyd/spotifyd/releases/latest/download/spotifyd-linux-aarch64-slim.tar.gz" ;;
            amd64) _spotifyd_url="https://github.com/Spotifyd/spotifyd/releases/latest/download/spotifyd-linux-x86_64-slim.tar.gz" ;;
            armhf) _spotifyd_url="https://github.com/Spotifyd/spotifyd/releases/latest/download/spotifyd-linux-armhf-slim.tar.gz" ;;
        esac

        if [[ -n "$_spotifyd_url" ]]; then
            if curl -fsSL "$_spotifyd_url" 2>/dev/null | tar xz -C /usr/local/bin/ 2>/dev/null; then
                chmod +x /usr/local/bin/spotifyd 2>/dev/null || true
                ok "spotifyd installed."
            else
                warn "Could not download spotifyd."
            fi
        fi

        # spotify-tui (spt) - TUI interface
        _spt_url=""
        case "$DEB_ARCH" in
            arm64) _spt_url="https://github.com/Rigellute/spotify-tui/releases/latest/download/spotify-tui-linux-aarch64.tar.gz" ;;
            amd64) _spt_url="https://github.com/Rigellute/spotify-tui/releases/latest/download/spotify-tui-linux.tar.gz" ;;
            armhf) _spt_url="https://github.com/Rigellute/spotify-tui/releases/latest/download/spotify-tui-linux-armv7.tar.gz" ;;
        esac

        if [[ -n "$_spt_url" ]]; then
            if curl -fsSL "$_spt_url" 2>/dev/null | tar xz -C /usr/local/bin/ 2>/dev/null; then
                chmod +x /usr/local/bin/spt 2>/dev/null || true
                _spotify_installed=1
                ok "spotify-tui (spt) installed."
            else
                warn "Could not download spotify-tui."
            fi
        fi
    fi

    # Create a wrapper script called 'spotify' that launches the best available option
    if [[ $_spotify_installed -eq 1 ]]; then
        if ! command -v spotify >/dev/null 2>&1; then
            cat > /usr/local/bin/spotify <<'SPOTIFY_WRAPPER'
#!/usr/bin/env bash
# Spotify launcher — uses best available client
if command -v spotify-launcher &>/dev/null; then
    exec spotify-launcher "$@"
elif [[ -f /usr/share/spotify/spotify ]]; then
    exec /usr/share/spotify/spotify --no-sandbox --disable-gpu "$@"
elif command -v spt &>/dev/null; then
    # Start spotifyd if not running
    if command -v spotifyd &>/dev/null && ! pgrep -x spotifyd &>/dev/null; then
        echo "Starting spotifyd daemon..."
        spotifyd --no-daemon &
        sleep 1
    fi
    exec spt
else
    echo "No Spotify client found. Install with: apt install spotify-client (amd64)"
    echo "Or use the web player: https://open.spotify.com"
    exit 1
fi
SPOTIFY_WRAPPER
            chmod +x /usr/local/bin/spotify
            ok "Created 'spotify' launcher wrapper."
        fi

        # .desktop shortcut
        cat > /usr/share/applications/spotify.desktop <<'SPOTIFY_DESKTOP'
[Desktop Entry]
Type=Application
Name=Spotify
GenericName=Music Player
Comment=Stream music with Spotify
Exec=spotify %U
Icon=spotify-client
Terminal=false
Categories=Audio;Music;Player;
MimeType=x-scheme-handler/spotify;
SPOTIFY_DESKTOP
        # Try to find a suitable icon
        if [[ ! -f /usr/share/icons/hicolor/256x256/apps/spotify-client.png ]]; then
            mkdir -p /usr/share/icons/hicolor/256x256/apps
            curl -fsSL -o /usr/share/icons/hicolor/256x256/apps/spotify-client.png \
                "https://upload.wikimedia.org/wikipedia/commons/thumb/8/84/Spotify_icon.svg/256px-Spotify_icon.svg.png" 2>/dev/null || true
        fi
        update-desktop-database /usr/share/applications 2>/dev/null || true
        ok "Spotify .desktop shortcut created."
    else
        warn "Spotify could not be installed automatically."
        warn "Options:"
        warn "  - Web player: https://open.spotify.com (via Chromium)"
        warn "  - Manual install: https://www.spotify.com/download/linux/"
    fi
fi

ok "Spotify section complete."


# ══════════════════════════════════════════════════════════════════════
#  SECTION 5e: App Store, WireGuard, Android SDK, Arduino IDE, Conky
# ══════════════════════════════════════════════════════════════════════

# ── App Store (GNOME Software / gnome-packagekit) ────────────────────
msg "Installing app store..."

if _is_installed gnome-software || _is_installed gnome-packagekit; then
    skip "App store (GNOME Software / PackageKit)"
else
    # Try gnome-software first (full-featured app store), fall back to gnome-packagekit
    if DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        gnome-software gnome-software-plugin-flatpak 2>/dev/null; then
        ok "GNOME Software (app store) installed."
    elif DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        gnome-packagekit 2>/dev/null; then
        ok "GNOME PackageKit (app store) installed."
    else
        warn "Could not install app store. Install manually:"
        warn "  apt install gnome-software   OR   apt install gnome-packagekit"
    fi
fi

# ── WireGuard VPN ────────────────────────────────────────────────────
msg "Installing WireGuard..."

if command -v wg >/dev/null 2>&1; then
    skip "WireGuard"
else
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        wireguard-tools 2>/dev/null && \
    ok "WireGuard tools installed." || \
    warn "WireGuard install failed. Install manually: apt install wireguard-tools"
fi

# ── Android SDK (command-line tools + extras) ────────────────────────
msg "Installing Android SDK components..."

ANDROID_SDK_ROOT="/opt/android-sdk"

if [[ -d "$ANDROID_SDK_ROOT/cmdline-tools" ]] || command -v sdkmanager >/dev/null 2>&1; then
    skip "Android SDK command-line tools"
else
    msg "Downloading Android SDK command-line tools..."
    mkdir -p "$ANDROID_SDK_ROOT"

    # Download commandlinetools (works on both amd64 and arm64 since it's Java-based)
    _cmdtools_zip="/tmp/commandlinetools.zip"
    _cmdtools_url="https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip"
    if curl -fsSL -o "$_cmdtools_zip" "$_cmdtools_url" 2>/dev/null; then
        mkdir -p "$ANDROID_SDK_ROOT/cmdline-tools"
        unzip -qo "$_cmdtools_zip" -d "$ANDROID_SDK_ROOT/cmdline-tools/" 2>/dev/null
        # Google's zip extracts to 'cmdline-tools/' — rename to 'latest'
        if [[ -d "$ANDROID_SDK_ROOT/cmdline-tools/cmdline-tools" ]]; then
            mv "$ANDROID_SDK_ROOT/cmdline-tools/cmdline-tools" "$ANDROID_SDK_ROOT/cmdline-tools/latest"
        fi
        rm -f "$_cmdtools_zip"
        ok "Android SDK command-line tools installed."

        # Add to PATH and set ANDROID_SDK_ROOT
        _sdk_profile="/etc/profile.d/android-sdk.sh"
        cat > "$_sdk_profile" <<SDKENV
export ANDROID_SDK_ROOT=$ANDROID_SDK_ROOT
export ANDROID_HOME=$ANDROID_SDK_ROOT
export PATH="\$PATH:$ANDROID_SDK_ROOT/cmdline-tools/latest/bin:$ANDROID_SDK_ROOT/platform-tools"
SDKENV
        chmod +x "$_sdk_profile"
        export ANDROID_SDK_ROOT ANDROID_HOME="$ANDROID_SDK_ROOT"
        export PATH="$PATH:$ANDROID_SDK_ROOT/cmdline-tools/latest/bin:$ANDROID_SDK_ROOT/platform-tools"

        # Accept licenses non-interactively
        if command -v sdkmanager >/dev/null 2>&1; then
            yes 2>/dev/null | sdkmanager --licenses 2>/dev/null || true
            # Install essential SDK packages
            msg "Installing SDK platform-tools and build-tools..."
            sdkmanager "platform-tools" 2>/dev/null && ok "platform-tools installed." || true
            sdkmanager "build-tools;34.0.0" 2>/dev/null && ok "build-tools;34.0.0 installed." || true
            sdkmanager "platforms;android-34" 2>/dev/null && ok "platforms;android-34 installed." || true
        fi
    else
        warn "Could not download Android SDK command-line tools."
        warn "Download manually from: https://developer.android.com/studio#command-tools"
    fi
fi

# Also ensure adb/fastboot is available (lightweight platform-tools)
if ! command -v adb >/dev/null 2>&1; then
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        adb fastboot 2>/dev/null || \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        android-tools-adb android-tools-fastboot 2>/dev/null || true
fi

# ── Arduino IDE ──────────────────────────────────────────────────────
msg "Installing Arduino IDE..."

if _is_installed arduino || test -f /usr/local/bin/arduino-ide; then
    skip "Arduino IDE"
else
    # Try the apt package first (Arduino IDE 1.x — lighter, still very functional)
    if DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        arduino 2>/dev/null; then
        ok "Arduino IDE installed via apt."
    else
        # Arduino IDE 2.x is an Electron app — download AppImage or .deb
        msg "Arduino IDE not in repos. Trying Arduino IDE 2.x download..."
        _arduino_installed=0

        # Try to get latest Arduino IDE 2.x release info
        _ard_api="https://api.github.com/repos/arduino/arduino-ide/releases/latest"
        _ard_json=$(curl -fsSL "$_ard_api" 2>/dev/null || echo "")

        if [[ -n "$_ard_json" ]]; then
            # Look for Linux arm64 or amd64 zip
            _ard_suffix=""
            case "$DEB_ARCH" in
                amd64) _ard_suffix="Linux_64bit.zip" ;;
                arm64) _ard_suffix="Linux_ARM64.zip" ;;
            esac

            if [[ -n "$_ard_suffix" ]]; then
                _ard_url=$(echo "$_ard_json" | grep -o "https://[^\"]*${_ard_suffix}" | head -1)
                if [[ -n "$_ard_url" ]]; then
                    msg "Downloading Arduino IDE 2.x..."
                    _ard_zip="/tmp/arduino-ide.zip"
                    if curl -fsSL -o "$_ard_zip" "$_ard_url" 2>/dev/null; then
                        mkdir -p /opt/arduino-ide
                        unzip -qo "$_ard_zip" -d /opt/arduino-ide/ 2>/dev/null
                        # Find the binary
                        _ard_bin=$(find /opt/arduino-ide -name "arduino-ide" -type f 2>/dev/null | head -1)
                        if [[ -n "$_ard_bin" ]]; then
                            ln -sf "$_ard_bin" /usr/local/bin/arduino-ide
                            chmod +x "$_ard_bin"
                            _arduino_installed=1
                            ok "Arduino IDE 2.x installed to /opt/arduino-ide/"
                        fi
                        rm -f "$_ard_zip"
                    fi
                fi
            fi
        fi

        if [[ $_arduino_installed -eq 0 ]]; then
            warn "Arduino IDE could not be installed automatically."
            warn "Arduino CLI is still available (arduino-cli)."
            warn "For the IDE: https://www.arduino.cc/en/software"
        fi
    fi
fi

# Ensure Arduino CLI is also available
if ! command -v arduino-cli >/dev/null 2>&1; then
    msg "Installing Arduino CLI..."
    curl -fsSL https://raw.githubusercontent.com/arduino/arduino-cli/master/install.sh 2>/dev/null \
        | BINDIR=/usr/local/bin sh 2>/dev/null && \
    ok "Arduino CLI installed." || \
    warn "Arduino CLI install failed. Get it from: https://arduino.github.io/arduino-cli/"
fi

# ── Desktop Performance Widgets (Conky) ──────────────────────────────
msg "Installing desktop performance widgets (Conky)..."

if command -v conky >/dev/null 2>&1; then
    skip "Conky system monitor"
else
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        conky-all 2>/dev/null || \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        conky 2>/dev/null || \
    warn "Conky install failed. Install manually: apt install conky-all"
fi

# Create a nice default conky config
CONKY_DIR="/root/.config/conky"
CONKY_CONF="$CONKY_DIR/conky.conf"
mkdir -p "$CONKY_DIR"

cat > "$CONKY_CONF" <<'CONKY_CFG'
conky.config = {
    alignment = 'top_right',
    background = true,
    border_width = 0,
    cpu_avg_samples = 2,
    default_color = 'white',
    default_outline_color = 'white',
    default_shade_color = 'black',
    double_buffer = true,
    draw_borders = false,
    draw_graph_borders = true,
    draw_outline = false,
    draw_shades = true,
    extra_newline = false,
    font = 'DejaVu Sans Mono:size=10',
    gap_x = 20,
    gap_y = 50,
    minimum_height = 300,
    minimum_width = 250,
    net_avg_samples = 2,
    no_buffers = true,
    out_to_console = false,
    out_to_ncurses = false,
    out_to_stderr = false,
    out_to_x = true,
    own_window = true,
    own_window_class = 'Conky',
    own_window_type = 'desktop',
    own_window_transparent = true,
    own_window_argb_visual = true,
    own_window_argb_value = 0,
    own_window_hints = 'undecorated,below,sticky,skip_taskbar,skip_pager',
    show_graph_range = false,
    show_graph_scale = false,
    stippled_borders = 0,
    update_interval = 2.0,
    uppercase = false,
    use_spacer = 'none',
    use_xft = true,
};

conky.text = [[
${color #88aaff}SYSTEM ${hr 2}${color}
Host:  ${nodename}
OS:    ${sysname} ${machine}
Uptime:${uptime_short}

${color #88aaff}CPU ${hr 2}${color}
Usage: ${cpu}% ${cpubar 8}
${cpugraph 30,250 444444 88aaff}
Core 1: ${cpu cpu1}%  Core 2: ${cpu cpu2}%
Core 3: ${cpu cpu3}%  Core 4: ${cpu cpu4}%

${color #88aaff}MEMORY ${hr 2}${color}
RAM:  ${mem}/${memmax} ${membar 8}
Swap: ${swap}/${swapmax} ${swapbar 8}
${memgraph 30,250 444444 88aaff}

${color #88aaff}STORAGE ${hr 2}${color}
Root: ${fs_used /}/${fs_size /} ${fs_bar 8 /}
Home: ${fs_used /root}/${fs_size /root} ${fs_bar 8 /root}

${color #88aaff}NETWORK ${hr 2}${color}
${if_existing /sys/class/net/eth0}eth0: ${addr eth0}
  Up: ${upspeed eth0}  Down: ${downspeed eth0}${endif}
${if_existing /sys/class/net/wlan0}wlan0: ${addr wlan0}
  Up: ${upspeed wlan0}  Down: ${downspeed wlan0}${endif}

${color #88aaff}TOP PROCESSES ${hr 2}${color}
${color #ffaa88}Name               CPU%  MEM%${color}
${top name 1} ${top cpu 1} ${top mem 1}
${top name 2} ${top cpu 2} ${top mem 2}
${top name 3} ${top cpu 3} ${top mem 3}
${top name 4} ${top cpu 4} ${top mem 4}
${top name 5} ${top cpu 5} ${top mem 5}
]];
CONKY_CFG

ok "Conky config created at $CONKY_CONF"

# Create autostart entry so conky launches with the desktop
AUTOSTART_DIR="/root/.config/autostart"
mkdir -p "$AUTOSTART_DIR"

cat > "$AUTOSTART_DIR/conky.desktop" <<'CONKY_AUTO'
[Desktop Entry]
Type=Application
Name=Conky System Monitor
Comment=Desktop performance widgets
Exec=bash -c 'sleep 5 && conky -d'
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
CONKY_AUTO
ok "Conky set to autostart with desktop (5s delay)."

# Create a .desktop entry for manually launching conky
cat > /usr/share/applications/conky.desktop <<'CONKY_DESK'
[Desktop Entry]
Type=Application
Name=System Monitor (Conky)
Comment=Desktop performance and system monitoring widgets
Exec=conky -d
Icon=utilities-system-monitor
Terminal=false
Categories=System;Monitor;
CONKY_DESK
update-desktop-database /usr/share/applications 2>/dev/null || true
ok "Conky .desktop shortcut created."

ok "App store + WireGuard + Android SDK + Arduino IDE + Conky section complete."


# ══════════════════════════════════════════════════════════════════════
#  SECTION 6: Proot Environment Tweaks
# ══════════════════════════════════════════════════════════════════════
msg "Applying proot environment tweaks..."

# Helper: add/update a variable in /etc/environment
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
_add_env "PULSE_SERVER"                            "127.0.0.1"
_add_env "MOZ_FAKE_NO_SANDBOX"                     "1"
ok "/etc/environment updated with proot-safe variables."

# Helper: add export to ~/.bashrc if not present
_add_bashrc() {
    grep -qF "export $1=" ~/.bashrc 2>/dev/null || echo "export $1=\"$2\"" >> ~/.bashrc
}

_add_bashrc "ELECTRON_DISABLE_SANDBOX" "1"
_add_bashrc "VSCODE_KEYRING"           "basic"
_add_bashrc "PULSE_SERVER"             "127.0.0.1"
_add_bashrc "MOZ_FAKE_NO_SANDBOX"      "1"

# Add code alias to .bashrc for terminal usage
if ! grep -qF 'alias code=' ~/.bashrc 2>/dev/null; then
    cat >> ~/.bashrc <<'ALIAS'
alias code='code --disable-gpu --disable-gpu-compositing --no-sandbox --user-data-dir="$HOME/.vscode"'
ALIAS
fi
ok "~/.bashrc exports and aliases added."



# ══════════════════════════════════════════════════════════════════════
#  SECTION 7: Install Browsers (LAST — after all standard app installs)
# ══════════════════════════════════════════════════════════════════════
# IMPORTANT: Browser installation is intentionally the LAST package
# install step. Browsers may add third-party apt sources (Mozilla APT
# for Firefox) or install via dpkg (Chromium v89, Google Chrome).
# Running these AFTER all standard Ubuntu repo installs ensures that
# no third-party source contamination can break regular apt packages.
msg "Installing selected browser(s) (last install step)..."

# ── Chromium v89 (Debian Buster .deb) ─────────────────────────────────
if [[ "$INSTALL_CHROMIUM" -eq 1 ]]; then

msg "Installing Chromium v89 (Debian Buster .deb)..."

# NOTE: Chromium v89 .debs are downloaded directly from archive.debian.org
# via wget. We intentionally do NOT add a Debian Buster apt repo because
# it would contaminate apt's package database and cause dependency
# conflicts with Ubuntu packages for ALL subsequent installs
# (blender, gimp, libreoffice, vscode, chrome, dev tools, etc.).

# ── Step 3: Download Chromium v89 + compat libs from Debian Buster ────
CHROMIUM_INSTALLED=0

# Check if Chromium is already installed (real Debian package, not snap stub)
if [[ -f /usr/lib/chromium/chromium ]]; then
    if dpkg -s chromium 2>/dev/null | grep -q "Status: install ok installed"; then
        # Verify no missing libraries
        _missing="$(ldd /usr/lib/chromium/chromium 2>&1 | grep 'not found' || true)"
        if [[ -z "$_missing" ]]; then
            CHROMIUM_INSTALLED=1
            ok "Chromium already installed (Debian .deb, no missing libs)."
        else
            warn "Chromium installed but has missing libs — reinstalling compat libraries."
        fi
    fi
fi

if [[ "$CHROMIUM_INSTALLED" -eq 0 ]]; then
    # Ensure Ubuntu's libxml2 is installed (Chromium links libxml2.so.2,
    # which is the same soname Ubuntu provides — just needs to be present)
    apt-get install -y libxml2 2>/dev/null || true

    msg "Downloading Chromium v89 + Buster compat libraries..."

    # Ubuntu has newer library sonames than Debian Buster.  We download
    # the specific Buster compat libraries — they coexist safely alongside
    # Ubuntu's own libs because they have different soname versions.

    _DEB_DIR="/tmp/chromium-debs"
    rm -rf "$_DEB_DIR" && mkdir -p "$_DEB_DIR"
    _BASE="http://archive.debian.org/debian/pool/main"

    # Chromium itself (v89, Debian Buster build)
    msg "Downloading Chromium v89 .debs..."
    wget -q "${_BASE}/c/chromium/chromium_89.0.4389.114-1~deb10u1_${DEB_ARCH}.deb"             -O "$_DEB_DIR/chromium.deb"
    wget -q "${_BASE}/c/chromium/chromium-common_89.0.4389.114-1~deb10u1_${DEB_ARCH}.deb"      -O "$_DEB_DIR/common.deb"

    # Compat libraries from Debian Buster (different sonames from Ubuntu)
    msg "Downloading Buster compat libraries..."
    wget -q "${_BASE}/libe/libevent/libevent-2.1-6_2.1.8-stable-4_${DEB_ARCH}.deb"             -O "$_DEB_DIR/libevent-2.1-6.deb"
    wget -q "${_BASE}/i/icu/libicu63_63.1-6+deb10u3_${DEB_ARCH}.deb"                           -O "$_DEB_DIR/libicu63.deb"
    wget -q "${_BASE}/libj/libjsoncpp/libjsoncpp1_1.7.4-3_${DEB_ARCH}.deb"                     -O "$_DEB_DIR/libjsoncpp1.deb"
    wget -q "${_BASE}/r/re2/libre2-5_20190101+dfsg-2_${DEB_ARCH}.deb"                          -O "$_DEB_DIR/libre2-5.deb"
    wget -q "${_BASE}/libv/libvpx/libvpx5_1.7.0-3+deb10u1_${DEB_ARCH}.deb"                     -O "$_DEB_DIR/libvpx5.deb"
    wget -q "${_BASE}/f/ffmpeg/libavcodec58_4.1.9-0+deb10u1_${DEB_ARCH}.deb"                   -O "$_DEB_DIR/libavcodec58.deb"
    wget -q "${_BASE}/f/ffmpeg/libavformat58_4.1.9-0+deb10u1_${DEB_ARCH}.deb"                  -O "$_DEB_DIR/libavformat58.deb"
    wget -q "${_BASE}/f/ffmpeg/libavutil56_4.1.9-0+deb10u1_${DEB_ARCH}.deb"                    -O "$_DEB_DIR/libavutil56.deb"
    wget -q "${_BASE}/f/ffmpeg/libswresample3_4.1.9-0+deb10u1_${DEB_ARCH}.deb"                 -O "$_DEB_DIR/libswresample3.deb"
    wget -q "${_BASE}/a/aom/libaom0_1.0.0-3_${DEB_ARCH}.deb"                                   -O "$_DEB_DIR/libaom0.deb"
    wget -q "${_BASE}/c/codec2/libcodec2-0.8.1_0.8.1-2_${DEB_ARCH}.deb"                        -O "$_DEB_DIR/libcodec2-0.8.1.deb"
    wget -q "${_BASE}/x/x264/libx264-155_0.155.2917+git0a84d98-2_${DEB_ARCH}.deb"              -O "$_DEB_DIR/libx264-155.deb"
    wget -q "${_BASE}/x/x265/libx265-165_2.9-4_${DEB_ARCH}.deb"                                -O "$_DEB_DIR/libx265-165.deb"
    wget -q "${_BASE}/libs/libssh/libssh-gcrypt-4_0.8.7-1+deb10u1_${DEB_ARCH}.deb"             -O "$_DEB_DIR/libssh-gcrypt-4.deb"

    # Additional compat libraries — Chromium v89 links these sonames which
    # differ between Buster and Ubuntu (without these, Chromium crashes
    # with "cannot open shared object file")
    wget -q "${_BASE}/libw/libwebp/libwebp6_0.6.1-2+deb10u1_${DEB_ARCH}.deb"                  -O "$_DEB_DIR/libwebp6.deb" \
        || wget -q "${_BASE}/libw/libwebp/libwebp6_0.6.1-2_${DEB_ARCH}.deb"                    -O "$_DEB_DIR/libwebp6.deb"
    wget -q "${_BASE}/libj/libjpeg-turbo/libjpeg62-turbo_1.5.2-2+deb10u1_${DEB_ARCH}.deb"      -O "$_DEB_DIR/libjpeg62-turbo.deb" \
        || wget -q "${_BASE}/libj/libjpeg-turbo/libjpeg62-turbo_1.5.2-2+b1_${DEB_ARCH}.deb"    -O "$_DEB_DIR/libjpeg62-turbo.deb" \
        || wget -q "${_BASE}/libj/libjpeg-turbo/libjpeg62-turbo_1.5.2-2_${DEB_ARCH}.deb"       -O "$_DEB_DIR/libjpeg62-turbo.deb"
    wget -q "${_BASE}/f/flac/libflac8_1.3.2-3+deb10u1_${DEB_ARCH}.deb"                         -O "$_DEB_DIR/libflac8.deb" \
        || wget -q "${_BASE}/f/flac/libflac8_1.3.2-3_${DEB_ARCH}.deb"                          -O "$_DEB_DIR/libflac8.deb"

    # Verify all downloads succeeded (wget -q hides errors silently)
    _DOWNLOAD_OK=1
    for _f in "$_DEB_DIR"/*.deb; do
        if [[ ! -s "$_f" ]]; then
            err "Download failed or empty: $(basename "$_f")"
            _DOWNLOAD_OK=0
        fi
    done
    if [[ "$_DOWNLOAD_OK" -eq 1 ]]; then
        ok "All .deb files downloaded ($(ls "$_DEB_DIR"/*.deb 2>/dev/null | wc -l) files)."
    else
        err "Some .deb downloads failed — check network. Chromium may not install correctly."
    fi

    # ── Step 4: Install compat libraries ──────────────────────────────
    msg "Installing Buster compat libraries..."
    dpkg --force-depends -i \
        "$_DEB_DIR/libevent-2.1-6.deb" \
        "$_DEB_DIR/libicu63.deb" \
        "$_DEB_DIR/libjsoncpp1.deb" \
        "$_DEB_DIR/libre2-5.deb" \
        "$_DEB_DIR/libvpx5.deb" \
        "$_DEB_DIR/libavutil56.deb" \
        "$_DEB_DIR/libswresample3.deb" \
        "$_DEB_DIR/libaom0.deb" \
        "$_DEB_DIR/libcodec2-0.8.1.deb" \
        "$_DEB_DIR/libx264-155.deb" \
        "$_DEB_DIR/libx265-165.deb" \
        "$_DEB_DIR/libavcodec58.deb" \
        "$_DEB_DIR/libavformat58.deb" \
        "$_DEB_DIR/libssh-gcrypt-4.deb" \
        "$_DEB_DIR/libwebp6.deb" \
        "$_DEB_DIR/libjpeg62-turbo.deb" \
        "$_DEB_DIR/libflac8.deb" 2>&1
    ok "Buster compat libraries installed."

    # ── Step 5: Install Chromium ──────────────────────────────────────
    msg "Installing Chromium v89..."
    dpkg --force-depends -i "$_DEB_DIR/common.deb" "$_DEB_DIR/chromium.deb" 2>&1
    # Note: dpkg warns about libgdk-pixbuf2.0-0 — this is a package name
    # difference only (Ubuntu has libgdk-pixbuf-2.0-0 with the library
    # already installed).  --force-depends handles it.

    if ! dpkg -s chromium 2>/dev/null | grep -q "Status: install ok installed"; then
        err "Chromium installation failed!"
        err "Check output above for errors."
    else
        ok "Chromium v89 installed."
        CHROMIUM_INSTALLED=1
    fi

    # ── Step 6: Fix gdk-pixbuf symlink ────────────────────────────────
    msg "Fixing gdk-pixbuf symlink..."
    _LIBDIR="/usr/lib/aarch64-linux-gnu"
    [[ "$DEB_ARCH" == "amd64" ]]  && _LIBDIR="/usr/lib/x86_64-linux-gnu"
    [[ "$DEB_ARCH" == "armhf" ]]  && _LIBDIR="/usr/lib/arm-linux-gnueabihf"
    _GDK_REAL="$(ls "${_LIBDIR}"/libgdk_pixbuf-2.0.so.0.* 2>/dev/null | head -1)"
    if [[ -n "$_GDK_REAL" ]]; then
        ln -sf "$_GDK_REAL" "${_LIBDIR}/libgdk_pixbuf-2.0.so.0"
        ldconfig
        ok "gdk-pixbuf symlink fixed → $(basename "$_GDK_REAL")"
    else
        warn "Could not find libgdk_pixbuf .so — symlink not created."
    fi

    # ── Step 7: Verify no missing libraries ───────────────────────────
    msg "Checking for missing libraries..."
    _missing="$(ldd /usr/lib/chromium/chromium 2>&1 | grep 'not found' || true)"
    if [[ -z "$_missing" ]]; then
        ok "No missing libraries — Chromium is ready."
    else
        warn "Missing libraries detected:"
        echo "$_missing"
    fi

    # Clean up downloaded .debs
    rm -rf "$_DEB_DIR"
fi

# ── Step 8: Ensure stock Chromium launcher is intact ──────────────────
# The Debian package installs a shell launcher at /usr/bin/chromium which
# sources /etc/chromium.d/* for flags, then exec's the ELF binary.
# All proot flags are injected via /etc/chromium.d/proot-flags — no
# wrapper is needed.  The stock launcher handles everything.
if [[ "$CHROMIUM_INSTALLED" -eq 1 ]]; then
    msg "Ensuring stock Chromium launcher is intact..."

    # Undo previous wrapper installs: if chromium.real exists, restore
    # the stock launcher (a prior run may have renamed it).
    if [[ -f /usr/bin/chromium.real ]]; then
        mv -f /usr/bin/chromium.real /usr/bin/chromium
        chmod +x /usr/bin/chromium
        ok "Restored stock launcher from chromium.real (removed old wrapper)"
    fi

    # Verify /usr/bin/chromium is the stock Debian launcher
    if [[ -f /usr/bin/chromium ]]; then
        if head -30 /usr/bin/chromium 2>/dev/null | grep -qE "chromium\.d|CHROMIUM_FLAGS|/usr/lib/chromium"; then
            ok "Stock Debian launcher verified at /usr/bin/chromium"
        else
            warn "/usr/bin/chromium may not be the stock Debian launcher — check manually"
        fi
    else
        warn "/usr/bin/chromium not found — Chromium may not have installed correctly"
    fi

    # Create debug/XFCE helper wrapper at /usr/local/bin/chromium-default
    # This logs launch info for troubleshooting, then exec's the stock launcher.
    # All flags come from /etc/chromium.d/proot-flags (sourced by the launcher).
    mkdir -p /usr/local/bin
    cat > /usr/local/bin/chromium-default <<'CHROMDEFAULT'
#!/bin/sh
exec >>/tmp/chromium-default.log 2>&1
echo "----- $(date) -----"
echo "UID=$(id -u) USER=$USER"
echo "ARGS: $*"
echo "DISPLAY=$DISPLAY"
echo "XAUTHORITY=$XAUTHORITY"
echo "XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR"
echo "DBUS_SESSION_BUS_ADDRESS=$DBUS_SESSION_BUS_ADDRESS"
echo "PATH=$PATH"
echo "PWD=$(pwd)"
echo "which chromium: $(command -v chromium)"
ls -l /usr/bin/chromium

# Make runtime dir exist (Chromium and some desktop bits expect it)
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp/runtime-root}"
mkdir -p "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR" 2>/dev/null || true

exec /usr/bin/chromium "$@"
CHROMDEFAULT
    chmod +x /usr/local/bin/chromium-default
    ok "Debug wrapper created at /usr/local/bin/chromium-default"

    # ── Step 9: Configure proot flags (chromium.d) ────────────────────
    # The stock Debian launcher sources /etc/chromium.d/* as shell scripts.
    # All proot flags go here — this is the SOLE place for Chromium flags.
    msg "Configuring Chromium proot flags..."

    mkdir -p /etc/chromium.d
    cat > /etc/chromium.d/proot-flags <<'PROOTFLAGS'
# Proot environment flags — required for Chromium to run inside proot-distro
# Core sandbox disabling (proot can't create namespaces)
export CHROMIUM_FLAGS="$CHROMIUM_FLAGS --no-sandbox"
export CHROMIUM_FLAGS="$CHROMIUM_FLAGS --no-zygote"
export CHROMIUM_FLAGS="$CHROMIUM_FLAGS --disable-setuid-sandbox"
export CHROMIUM_FLAGS="$CHROMIUM_FLAGS --disable-seccomp-filter-sandbox"

# Renderer stability
export CHROMIUM_FLAGS="$CHROMIUM_FLAGS --disable-dev-shm-usage"
export CHROMIUM_FLAGS="$CHROMIUM_FLAGS --in-process-gpu"
export CHROMIUM_FLAGS="$CHROMIUM_FLAGS --renderer-process-limit=2"
export CHROMIUM_FLAGS="$CHROMIUM_FLAGS --disable-site-isolation-trials"

# GPU disabled (no real GPU in proot)
export CHROMIUM_FLAGS="$CHROMIUM_FLAGS --disable-gpu"
export CHROMIUM_FLAGS="$CHROMIUM_FLAGS --disable-gpu-compositing"
export CHROMIUM_FLAGS="$CHROMIUM_FLAGS --disable-software-rasterizer"

# Disable problematic features in ONE flag (Chromium uses only the LAST --disable-features)
export CHROMIUM_FLAGS="$CHROMIUM_FLAGS --disable-features=VizDisplayCompositor,WebAuthentication,WebAuthn,WebAuthenticationConditionalUI,SecurePaymentConfirmation,AudioServiceOutOfProcess,IsolateOrigins,WebOTP,DigitalCredentials"

# Kill breakpad crash reporter (useless in proot)
export CHROMIUM_FLAGS="$CHROMIUM_FLAGS --disable-breakpad"

# Keychain/auth workarounds
export CHROMIUM_FLAGS="$CHROMIUM_FLAGS --password-store=basic"
export CHROMIUM_FLAGS="$CHROMIUM_FLAGS --use-mock-keychain"

# Skip first run
export CHROMIUM_FLAGS="$CHROMIUM_FLAGS --no-first-run"
export CHROMIUM_FLAGS="$CHROMIUM_FLAGS --no-default-browser-check"
PROOTFLAGS
    ok "Proot flags written to /etc/chromium.d/proot-flags"

    # ── Step 10: Ensure runtime directories ────────────────────────────
    mkdir -p /dev/shm && chmod 1777 /dev/shm
    mkdir -p /tmp/runtime-root && chmod 700 /tmp/runtime-root
    ok "Runtime directories ensured (/dev/shm, /tmp/runtime-root)."

    # ── Step 11: Hold ALL Buster packages to prevent accidental upgrades ──
    # CRITICAL: apt-get install -f (e.g. after Chrome's dpkg) will try to
    # "fix" the force-installed Buster compat libs by REMOVING them if they
    # aren't held.  Hold every Buster package to protect them.
    apt-mark hold \
        chromium chromium-common \
        libevent-2.1-6 libicu63 libjsoncpp1 libre2-5 libvpx5 \
        libavcodec58 libavformat58 libavutil56 libswresample3 \
        libaom0 libcodec2-0.8.1 libx264-155 libx265-165 \
        libssh-gcrypt-4 \
        libwebp6 libjpeg62-turbo libflac8 2>/dev/null || true
    ok "Chromium + 17 Buster compat packages held (protected from apt-get install -f)."

    # Create dummy transitional package for libgdk-pixbuf2.0-0
    # (Debian Buster package name — Ubuntu uses libgdk-pixbuf-2.0-0 instead).
    # This satisfies dpkg's dependency tracking so apt can install other packages.
    if ! dpkg -s libgdk-pixbuf2.0-0 >/dev/null 2>&1; then
        _DUMMY_DIR="/tmp/libgdk-pixbuf2.0-0-dummy"
        mkdir -p "$_DUMMY_DIR/DEBIAN"
        cat > "$_DUMMY_DIR/DEBIAN/control" <<GDKCTRL
Package: libgdk-pixbuf2.0-0
Version: 99.0~proot-dummy
Architecture: $DEB_ARCH
Description: Transitional dummy — satisfies Buster chromium dep
Maintainer: proot-setup
GDKCTRL
        dpkg-deb --build "$_DUMMY_DIR" /tmp/libgdk-pixbuf2.0-0-dummy.deb 2>/dev/null
        dpkg -i /tmp/libgdk-pixbuf2.0-0-dummy.deb 2>/dev/null || true
        apt-mark hold libgdk-pixbuf2.0-0 2>/dev/null || true
        rm -rf "$_DUMMY_DIR" /tmp/libgdk-pixbuf2.0-0-dummy.deb
        ok "Dummy libgdk-pixbuf2.0-0 package created (satisfies chromium dep)."
    fi

    # Clear any broken dpkg state so subsequent apt-get install (e.g. Firefox) works
    dpkg --configure -a 2>/dev/null || true

    # ── Step 12: Chromium smoke test ──────────────────────────────────
    # Actually launch Chromium headless to prove the binary + flags + launcher
    # all work end-to-end.  If this fails, something is fundamentally broken.
    msg "Running Chromium headless smoke test..."
    _smoke_ok=0
    _smoke_out=""
    _smoke_out="$(timeout 30 chromium \
        --headless --disable-gpu --no-sandbox --no-zygote \
        --disable-software-rasterizer --disable-dev-shm-usage \
        --dump-dom about:blank 2>&1)" && _smoke_ok=1 || true

    if [[ "$_smoke_ok" -eq 1 ]] && echo "$_smoke_out" | grep -qi "<html"; then
        ok "Chromium smoke test PASSED (headless --dump-dom returned HTML)."
    else
        warn "Chromium smoke test: headless --dump-dom did not return expected HTML."
        warn "This may be normal in proot (missing /dev nodes, no display)."
        warn "Smoke test output (last 5 lines):"
        echo "$_smoke_out" | tail -5

        # Fallback: verify the binary at least starts and prints version
        _ver_out=""
        _ver_out="$(timeout 10 /usr/lib/chromium/chromium --version 2>&1)" || true
        if echo "$_ver_out" | grep -qi "chromium"; then
            ok "Chromium binary responds to --version: $_ver_out"
        else
            err "Chromium binary did not respond to --version."
            err "Output: $_ver_out"
            err "Chromium may not work. Check log: $LOG_FILE"
        fi
    fi

    # ── Chromium .desktop file ────────────────────────────────────────
    # The stock Debian launcher sources /etc/chromium.d/proot-flags
    # automatically, so no extra flags are needed in the Exec line.
    cat > /usr/share/applications/chromium.desktop <<'CHROMDESK'
[Desktop Entry]
Type=Application
Name=Chromium Web Browser
Comment=Access the Internet
GenericName=Web Browser
Exec=chromium %U
Icon=chromium
Terminal=false
Categories=Network;WebBrowser;
MimeType=text/html;text/xml;application/xhtml+xml;x-scheme-handler/http;x-scheme-handler/https;
StartupNotify=true
StartupWMClass=Chromium-browser
Actions=new-window;new-private-window;

[Desktop Action new-window]
Name=New Window
Exec=chromium --new-window

[Desktop Action new-private-window]
Name=New Private Window
Exec=chromium --incognito
CHROMDESK
    ok "Chromium .desktop file written."
    fi  # end CHROMIUM_INSTALLED
fi  # end INSTALL_CHROMIUM

# Safety: ensure Debian Buster repo is never left behind
# (prevents contaminating apt for Chrome, VSCode, apps, dev tools, etc.)
rm -f /etc/apt/sources.list.d/debian-chromium.sources /etc/apt/sources.list.d/debian-chromium.list 2>/dev/null || true


# ── Firefox Install (Mozilla APT) ─────────────────────────────────────
if [[ "$INSTALL_FIREFOX" -eq 1 ]]; then
    msg "Installing Firefox (Mozilla APT)..."

    FIREFOX_INSTALLED=0
    # Check using dpkg status (not command -v, which can find leftover wrappers)
    if dpkg -s firefox 2>/dev/null | grep -q "Status: install ok installed"; then
        if ! head -20 /usr/bin/firefox 2>/dev/null | grep -qi "snap"; then
            FIREFOX_INSTALLED=1
            ok "Firefox already installed (dpkg verified, not snap stub)."
        else
            warn "Firefox is a snap stub — will reinstall from Mozilla APT."
        fi
    else
        # Package not installed — clean up any leftover wrapper artifacts
        rm -f /usr/bin/firefox /usr/bin/firefox.real 2>/dev/null || true
    fi

    if [[ "$FIREFOX_INSTALLED" -eq 0 ]]; then
        # Add Mozilla GPG key
        msg "Adding Mozilla APT signing key..."
        _moz_key_ok=0
        wget -q -O /tmp/mozilla-signing-key.gpg \
            https://packages.mozilla.org/apt/repo-signing-key.gpg 2>&1 && \
            [[ -s /tmp/mozilla-signing-key.gpg ]] && \
            gpg --dearmor < /tmp/mozilla-signing-key.gpg \
                > /usr/share/keyrings/packages.mozilla.org.gpg 2>&1 && \
            [[ -s /usr/share/keyrings/packages.mozilla.org.gpg ]] && \
            _moz_key_ok=1
        rm -f /tmp/mozilla-signing-key.gpg 2>/dev/null || true
        if [[ "$_moz_key_ok" -eq 1 ]]; then
            ok "Mozilla GPG key added."
        else
            err "Failed to download/dearmor Mozilla GPG key — Firefox install may fail."
        fi

        # Add Mozilla APT repository
        echo "deb [signed-by=/usr/share/keyrings/packages.mozilla.org.gpg] https://packages.mozilla.org/apt mozilla main" \
            > /etc/apt/sources.list.d/mozilla-firefox.list

        # Pin Mozilla's Firefox higher than Ubuntu's snap stub
        cat > /etc/apt/preferences.d/mozilla-firefox.pref <<'MOZPIN'
Package: firefox*
Pin: origin packages.mozilla.org
Pin-Priority: 1001
MOZPIN

        apt-get update -qq 2>&1 | tail -3

        # Clear any lingering broken dpkg state from Chromium compat packages
        # before attempting Firefox install (apt refuses to install anything
        # while the system has packages with unresolved dependencies).
        dpkg --configure -a 2>/dev/null || true

        DEBIAN_FRONTEND=noninteractive apt-get install -y \
            -o Dpkg::Options::="--force-confdef" \
            -o Dpkg::Options::="--force-confold" \
            firefox 2>&1

        if dpkg -s firefox 2>/dev/null | grep -q "Status: install ok installed"; then
            FIREFOX_INSTALLED=1
            ok "Firefox installed from Mozilla APT."
        else
            err "Firefox installation failed!"
        fi
    fi

    if [[ "$FIREFOX_INSTALLED" -eq 1 ]]; then
        # Create proot wrapper for Firefox
        msg "Creating Firefox proot wrapper..."

        FIREFOX_BIN="/usr/bin/firefox"
        already_wrapped=0
        head -n 5 "$FIREFOX_BIN" 2>/dev/null | grep -q "proot.*wrapper\|MOZ_FAKE_NO_SANDBOX" && already_wrapped=1

        if [[ "$already_wrapped" -eq 0 ]]; then
            FIREFOX_REAL=""
            if [[ -f "${FIREFOX_BIN}.real" ]]; then
                FIREFOX_REAL="${FIREFOX_BIN}.real"
            else
                cp "$FIREFOX_BIN" "${FIREFOX_BIN}.real"
                chmod +x "${FIREFOX_BIN}.real"
                FIREFOX_REAL="${FIREFOX_BIN}.real"
            fi

            cat > "$FIREFOX_BIN" <<FFWRAPPER
#!/bin/sh
# proot Firefox wrapper — disables sandbox (proot can't create namespaces)
export MOZ_FAKE_NO_SANDBOX=1
export MOZ_DISABLE_CONTENT_SANDBOX=1
export MOZ_DISABLE_GMP_SANDBOX=1
export MOZ_DISABLE_GPU_SANDBOX=1
export MOZ_DISABLE_RDD_SANDBOX=1
export MOZ_DISABLE_SOCKET_PROCESS_SANDBOX=1
export TMPDIR=/tmp
export XDG_RUNTIME_DIR=\${XDG_RUNTIME_DIR:-/tmp/runtime-\$(whoami)}
mkdir -p "\$XDG_RUNTIME_DIR" 2>/dev/null
exec "$FIREFOX_REAL" --no-remote "\$@"
FFWRAPPER
            chmod +x "$FIREFOX_BIN"
            ok "Firefox proot wrapper created (calls $FIREFOX_REAL)"
        else
            ok "Firefox wrapper already in place."
        fi

        # Firefox .desktop file
        cat > /usr/share/applications/firefox.desktop <<'FFDESK'
[Desktop Entry]
Type=Application
Name=Firefox Web Browser
Comment=Browse the World Wide Web
GenericName=Web Browser
Exec=firefox %u
Icon=firefox
Terminal=false
Categories=Network;WebBrowser;
MimeType=text/html;text/xml;application/xhtml+xml;x-scheme-handler/http;x-scheme-handler/https;
StartupNotify=true
StartupWMClass=firefox
Actions=new-window;new-private-window;

[Desktop Action new-window]
Name=New Window
Exec=firefox --new-window

[Desktop Action new-private-window]
Name=New Private Window
Exec=firefox --private-window
FFDESK
        ok "Firefox .desktop file written."
    fi
fi


# ── Set default browser based on selection ─────────────────────────────
_DEFAULT_BROWSER=""
_DEFAULT_DESKTOP=""
if [[ "$INSTALL_CHROMIUM" -eq 1 ]]; then
    _DEFAULT_BROWSER="chromium"
    _DEFAULT_DESKTOP="chromium.desktop"
elif [[ "$INSTALL_FIREFOX" -eq 1 ]]; then
    _DEFAULT_BROWSER="firefox"
    _DEFAULT_DESKTOP="firefox.desktop"
fi

if [[ -n "$_DEFAULT_BROWSER" ]]; then
    msg "Setting $_DEFAULT_BROWSER as default browser..."

    mkdir -p /root/.config/xfce4
    if [[ "$_DEFAULT_BROWSER" == "chromium" ]]; then
        _WEB_CMD="/usr/local/bin/chromium-default \"%s\""
    else
        _WEB_CMD="/usr/bin/firefox \"%s\""
    fi
    cat > /root/.config/xfce4/helpers.rc <<HELPERSRC
WebBrowser=$_DEFAULT_BROWSER
WebBrowserCommand=$_WEB_CMD
HELPERSRC
    ok "XFCE helpers.rc: $_DEFAULT_BROWSER as default browser."

    command -v xdg-settings >/dev/null 2>&1 && \
        xdg-settings set default-web-browser "$_DEFAULT_DESKTOP" 2>/dev/null || true
    if command -v xdg-mime >/dev/null 2>&1; then
        for mime in x-scheme-handler/http x-scheme-handler/https text/html; do
            xdg-mime default "$_DEFAULT_DESKTOP" "$mime" 2>/dev/null || true
        done
    fi
    update-alternatives --install /usr/bin/x-www-browser x-www-browser "/usr/bin/$_DEFAULT_BROWSER" 200 2>/dev/null || true
    update-alternatives --set x-www-browser "/usr/bin/$_DEFAULT_BROWSER" 2>/dev/null || true

    mkdir -p /root/.local/share/applications
    cat > /root/.local/share/applications/mimeapps.list <<MIMEAPPS
[Default Applications]
x-scheme-handler/http=$_DEFAULT_DESKTOP
x-scheme-handler/https=$_DEFAULT_DESKTOP
text/html=$_DEFAULT_DESKTOP
MIMEAPPS
    ok "$_DEFAULT_BROWSER set as default browser (xdg + alternatives + mimeapps)."
fi

# Update desktop database so start menu picks up all .desktop files
update-desktop-database /usr/share/applications 2>/dev/null || true



# ── Google Chrome (direct .deb — NO apt source/key) ─────────────────

msg "Checking Google Chrome availability..."

# Google Chrome for Linux — only available as amd64 .deb.
# On non-amd64 architectures (like arm64/Android) this is skipped.

CHROME_INSTALLED=0
if [[ -f /opt/google/chrome/google-chrome ]] || command -v google-chrome-stable >/dev/null 2>&1; then
    CHROME_INSTALLED=1
    ok "Google Chrome already installed."
fi

if [[ "$CHROME_INSTALLED" -eq 0 ]]; then
    # NOTE: We do NOT add Google's apt repository or signing key.
    # Adding third-party apt sources can break standard package installs
    # on architectures where the repo has no packages (e.g. arm64).
    # Instead, we download the .deb directly and install via dpkg.

    if [[ "$DEB_ARCH" == "amd64" ]]; then
        _chrome_deb="/tmp/google-chrome-stable_current_amd64.deb"
        msg "Downloading Google Chrome .deb (amd64 only)..."
        wget -q -O "$_chrome_deb" \
            "https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb" 2>/dev/null && \
        [[ -s "$_chrome_deb" ]] && {
            msg "Installing Google Chrome .deb..."
            dpkg -i "$_chrome_deb" 2>/dev/null || true
            apt-get install -f -y 2>/dev/null || true
            if command -v google-chrome-stable >/dev/null 2>&1 || [[ -f /opt/google/chrome/google-chrome ]]; then
                CHROME_INSTALLED=1
                ok "Google Chrome installed via direct .deb download."
            else
                warn "Google Chrome .deb install did not succeed."
            fi
        } || {
            warn "Google Chrome download failed — skipping."
        }
        rm -f "$_chrome_deb" 2>/dev/null || true
    else
        warn "Google Chrome is not available for $DEB_ARCH — skipping."
    fi

    # Safety: remove any Google Chrome apt sources from prior runs
    # (prevents contaminating apt for standard package installs)
    rm -f /etc/apt/sources.list.d/google-chrome.list 2>/dev/null || true
    rm -f /usr/share/keyrings/google-chrome.gpg 2>/dev/null || true
fi

# ── Google Chrome proot wrapper ───────────────────────────────────────
if [[ "$CHROME_INSTALLED" -eq 1 ]]; then
    msg "Creating Google Chrome proot wrapper..."

    CHROME_BIN=""
    [[ -f /usr/bin/google-chrome-stable ]] && CHROME_BIN="/usr/bin/google-chrome-stable"
    [[ -f /usr/bin/google-chrome ]]        && CHROME_BIN="/usr/bin/google-chrome"

    if [[ -n "$CHROME_BIN" ]]; then
        already_wrapped=0
        head -n 5 "$CHROME_BIN" 2>/dev/null | grep -q "proot.*wrapper\|no-sandbox.*disable-gpu" && already_wrapped=1

        if [[ "$already_wrapped" -eq 0 ]]; then
            # Find the real Chrome binary
            CHROME_REAL=""
            if [[ -f /opt/google/chrome/google-chrome ]]; then
                CHROME_REAL="/opt/google/chrome/google-chrome"
            elif [[ -f "${CHROME_BIN}.real" ]]; then
                CHROME_REAL="${CHROME_BIN}.real"
            else
                cp "$CHROME_BIN" "${CHROME_BIN}.real"
                chmod +x "${CHROME_BIN}.real"
                CHROME_REAL="${CHROME_BIN}.real"
            fi

            cat > "$CHROME_BIN" <<CHRWRAPPER
#!/bin/sh
# proot Google Chrome wrapper
export TMPDIR=/tmp
export XDG_RUNTIME_DIR=\${XDG_RUNTIME_DIR:-/tmp/runtime-\$(whoami)}
mkdir -p \$XDG_RUNTIME_DIR 2>/dev/null
exec "$CHROME_REAL" \\
  --no-sandbox \\
  --disable-dev-shm-usage \\
  --disable-gpu \\
  --disable-software-rasterizer \\
  --no-zygote \\
  --disable-setuid-sandbox \\
  --password-store=basic \\
  --use-mock-keychain \\
  --no-first-run \\
  --no-default-browser-check \\
  --disable-breakpad \\
  --disable-features=WebAuthentication,WebAuthn,SecurePaymentConfirmation \\
  "\$@"
CHRWRAPPER
            chmod +x "$CHROME_BIN"
            ok "Google Chrome proot wrapper created (calls $CHROME_REAL)"
        else
            ok "Google Chrome wrapper already in place."
        fi

        # Patch .desktop files
        for df in /usr/share/applications/google-chrome*.desktop; do
            [[ -f "$df" ]] || continue
            [[ ! -f "${df}.bak" ]] && cp "$df" "${df}.bak"
            sed -i "s|^Exec=.*|Exec=$CHROME_BIN --no-sandbox --disable-dev-shm-usage %U|" "$df"
            ok "Patched: $(basename "$df")"
        done

        # Ensure at least one .desktop file for Chrome in start menu
        if [[ ! -f /usr/share/applications/google-chrome.desktop ]] && [[ ! -f /usr/share/applications/google-chrome-stable.desktop ]]; then
            cat > /usr/share/applications/google-chrome-stable.desktop <<CHRDESK
[Desktop Entry]
Type=Application
Name=Google Chrome
Comment=Access the Internet
GenericName=Web Browser
Exec=$CHROME_BIN --no-sandbox --disable-dev-shm-usage %U
Icon=google-chrome
Terminal=false
Categories=Network;WebBrowser;
MimeType=text/html;text/xml;application/xhtml+xml;x-scheme-handler/http;x-scheme-handler/https;
StartupNotify=true
CHRDESK
            ok "Created google-chrome-stable.desktop"
        fi

        update-desktop-database /usr/share/applications 2>/dev/null || true
    fi

    ok "Google Chrome configuration complete."
fi

# Detect Chrome .desktop name for panel launcher (used in Section 8)
CHROME_DESKTOP=""
[[ -f /usr/share/applications/google-chrome-stable.desktop ]] && CHROME_DESKTOP="google-chrome-stable.desktop"
[[ -f /usr/share/applications/google-chrome.desktop ]]        && CHROME_DESKTOP="google-chrome.desktop"


# ══════════════════════════════════════════════════════════════════════
#  SECTION 8: XFCE Desktop Customization
# ══════════════════════════════════════════════════════════════════════
msg "Customizing XFCE desktop..."

XFCE_XML_DIR="/root/.config/xfce4/xfconf/xfce-perchannel-xml"
mkdir -p "$XFCE_XML_DIR"

# ── 7a. Set desktop background to solid black ─────────────────────────
msg "Setting desktop wallpaper to solid black..."

cat > "$XFCE_XML_DIR/xfce4-desktop.xml" <<'DESKTOP_XML'
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

# ── 7b. XFCE bottom dock with all application launchers ───────────────
msg "Configuring XFCE bottom dock with application launchers..."

# Detect .desktop file names
CHROMIUM_DESKTOP=""
[[ -f /usr/share/applications/chromium.desktop ]] && CHROMIUM_DESKTOP="chromium.desktop"

LIBREOFFICE_DESKTOP=""
[[ -f /usr/share/applications/libreoffice-startcenter.desktop ]] && LIBREOFFICE_DESKTOP="libreoffice-startcenter.desktop"
[[ -f /usr/share/applications/libreoffice-writer.desktop ]] && LIBREOFFICE_DESKTOP="libreoffice-writer.desktop"

BLENDER_DESKTOP=""
[[ -f /usr/share/applications/blender.desktop ]] && BLENDER_DESKTOP="blender.desktop"

GIMP_DESKTOP=""
for gd in /usr/share/applications/gimp*.desktop; do
    [[ -f "$gd" ]] && GIMP_DESKTOP="$(basename "$gd")" && break
done

# CHROME_DESKTOP was set in Section 7 (empty string if Chrome not installed)
CHROME_DESKTOP="${CHROME_DESKTOP:-}"

FIREFOX_DESKTOP=""
[[ -f /usr/share/applications/firefox.desktop ]] && FIREFOX_DESKTOP="firefox.desktop"

# Primary browser for panel slot (Chromium if installed, else Firefox)
_PRIMARY_BROWSER_DESKTOP=""
if [[ "$INSTALL_CHROMIUM" -eq 1 ]]; then
    _PRIMARY_BROWSER_DESKTOP="${CHROMIUM_DESKTOP:-chromium.desktop}"
elif [[ "$INSTALL_FIREFOX" -eq 1 ]]; then
    _PRIMARY_BROWSER_DESKTOP="${FIREFOX_DESKTOP:-firefox.desktop}"
fi

# Firefox secondary panel slot (only when BOTH browsers installed)
_FF_PLUGIN_ID=""
_FF_PLUGIN_DEF=""
if [[ "$INSTALL_CHROMIUM" -eq 1 ]] && [[ "$INSTALL_FIREFOX" -eq 1 ]]; then
    _FF_PLUGIN_ID='        <value type="int" value="18"/>'
    _FF_PLUGIN_DEF='    <property name="plugin-18" type="string" value="launcher">
      <property name="items" type="array">
        <value type="string" value="'"${FIREFOX_DESKTOP:-firefox.desktop}"'"/>
      </property>
    </property>'
fi

cat > "$XFCE_XML_DIR/xfce4-panel.xml" <<PANEL_XML
<?xml version="1.0" encoding="UTF-8"?>

<channel name="xfce4-panel" version="1.0">
  <property name="configver" type="int" value="2"/>
  <property name="panels" type="array">
    <value type="int" value="1"/>
    <property name="dark-mode" type="bool" value="true"/>
    <property name="panel-1" type="empty">
      <property name="position" type="string" value="p=10;x=0;y=0"/>
      <property name="length" type="uint" value="100"/>
      <property name="position-locked" type="bool" value="true"/>
      <property name="icon-size" type="uint" value="0"/>
      <property name="size" type="uint" value="40"/>
      <property name="mode" type="uint" value="0"/>
      <property name="autohide-behavior" type="uint" value="0"/>
      <property name="plugin-ids" type="array">
        <value type="int" value="1"/>
        <value type="int" value="16"/>
        <value type="int" value="2"/>
        <value type="int" value="3"/>
        <value type="int" value="4"/>
${_FF_PLUGIN_ID}
        <value type="int" value="14"/>
        <value type="int" value="17"/>
        <value type="int" value="5"/>
        <value type="int" value="6"/>
        <value type="int" value="7"/>
        <value type="int" value="8"/>
        <value type="int" value="15"/>
        <value type="int" value="9"/>
        <value type="int" value="10"/>
        <value type="int" value="11"/>
        <value type="int" value="12"/>
        <value type="int" value="13"/>
      </property>
    </property>
  </property>
  <property name="plugins" type="empty">
    <property name="plugin-1" type="string" value="applicationsmenu">
      <property name="show-tooltips" type="bool" value="true"/>
      <property name="show-button-title" type="bool" value="true"/>
    </property>
    <property name="plugin-16" type="string" value="launcher">
      <property name="items" type="array">
        <value type="string" value="xfce4-settings-manager.desktop"/>
      </property>
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
        <value type="string" value="${_PRIMARY_BROWSER_DESKTOP}"/>
      </property>
    </property>
${_FF_PLUGIN_DEF}
    <property name="plugin-14" type="string" value="launcher">
      <property name="items" type="array">
        <value type="string" value="${CHROME_DESKTOP:-google-chrome-stable.desktop}"/>
      </property>
    </property>
    <property name="plugin-17" type="string" value="launcher">
      <property name="items" type="array">
        <value type="string" value="thunderbird.desktop"/>
      </property>
    </property>
    <property name="plugin-5" type="string" value="launcher">
      <property name="items" type="array">
        <value type="string" value="code.desktop"/>
      </property>
    </property>
    <property name="plugin-6" type="string" value="launcher">
      <property name="items" type="array">
        <value type="string" value="${LIBREOFFICE_DESKTOP:-libreoffice-startcenter.desktop}"/>
      </property>
    </property>
    <property name="plugin-7" type="string" value="launcher">
      <property name="items" type="array">
        <value type="string" value="${GIMP_DESKTOP:-gimp.desktop}"/>
      </property>
    </property>
    <property name="plugin-8" type="string" value="launcher">
      <property name="items" type="array">
        <value type="string" value="${BLENDER_DESKTOP:-blender.desktop}"/>
      </property>
    </property>
    <property name="plugin-15" type="string" value="launcher">
      <property name="items" type="array">
        <value type="string" value="spotify.desktop"/>
      </property>
    </property>
    <property name="plugin-9" type="string" value="tasklist">
      <property name="flat-buttons" type="bool" value="true"/>
      <property name="show-handle" type="bool" value="false"/>
      <property name="show-labels" type="bool" value="true"/>
    </property>
    <property name="plugin-10" type="string" value="separator">
      <property name="expand" type="bool" value="true"/>
      <property name="style" type="uint" value="0"/>
    </property>
    <property name="plugin-11" type="string" value="systray">
      <property name="known-legacy-items" type="array">
        <value type="string" value="task manager"/>
      </property>
    </property>
    <property name="plugin-12" type="string" value="pulseaudio">
      <property name="enable-keyboard-shortcuts" type="bool" value="true"/>
      <property name="show-notifications" type="bool" value="false"/>
    </property>
    <property name="plugin-13" type="string" value="clock">
      <property name="mode" type="uint" value="2"/>
      <property name="digital-format" type="string" value="%R"/>
    </property>
  </property>
</channel>
PANEL_XML

# Build dynamic panel description
_PANEL_BROWSERS=""
if [[ "$INSTALL_CHROMIUM" -eq 1 ]] && [[ "$INSTALL_FIREFOX" -eq 1 ]]; then
    _PANEL_BROWSERS="Chromium | Firefox | Chrome"
elif [[ "$INSTALL_CHROMIUM" -eq 1 ]]; then
    _PANEL_BROWSERS="Chromium | Chrome"
elif [[ "$INSTALL_FIREFOX" -eq 1 ]]; then
    _PANEL_BROWSERS="Firefox | Chrome"
fi
ok "Bottom dock: Applications | Settings | Terminal | Thunar | ${_PANEL_BROWSERS} | Thunderbird | VSCode | LibreOffice | GIMP | Blender | Spotify | Tasklist | Systray | Volume | Clock (LCD)"

# ── 7b2. Create panel launcher directories ────────────────────────────
# Some XFCE versions need .desktop files in ~/.config/xfce4/panel/launcher-N/
msg "Creating panel launcher directories..."

PANEL_DIR="/root/.config/xfce4/panel"
mkdir -p "$PANEL_DIR"

_link_launcher() {
    local plugin_id=$1 desktop_name=$2
    local launcher_dir="$PANEL_DIR/launcher-$plugin_id"
    mkdir -p "$launcher_dir"
    local src="/usr/share/applications/$desktop_name"
    if [[ -f "$src" ]]; then
        cp "$src" "$launcher_dir/"
        ok "Launcher $plugin_id: $desktop_name"
    fi
}

_link_launcher 16 "xfce4-settings-manager.desktop"
_link_launcher 2  "xfce4-terminal.desktop"
_link_launcher 3  "thunar.desktop"
_link_launcher 4  "${_PRIMARY_BROWSER_DESKTOP:-chromium.desktop}"
[[ -n "$_FF_PLUGIN_DEF" ]] && _link_launcher 18 "${FIREFOX_DESKTOP:-firefox.desktop}"
_link_launcher 14 "${CHROME_DESKTOP:-google-chrome-stable.desktop}"
_link_launcher 17 "thunderbird.desktop"
_link_launcher 5  "code.desktop"
_link_launcher 6  "${LIBREOFFICE_DESKTOP:-libreoffice-startcenter.desktop}"
_link_launcher 7  "${GIMP_DESKTOP:-gimp.desktop}"
_link_launcher 8  "${BLENDER_DESKTOP:-blender.desktop}"
_link_launcher 15 "spotify.desktop"
ok "Panel launcher directories created."

# ── 7c. Apply dark theme with Humanity icons ──────────────────────────
msg "Setting dark theme with Humanity icons..."

cat > "$XFCE_XML_DIR/xsettings.xml" <<'XSETTINGS_XML'
<?xml version="1.0" encoding="UTF-8"?>

<channel name="xsettings" version="1.0">
  <property name="Net" type="empty">
    <property name="ThemeName" type="string" value="Adwaita-dark"/>
    <property name="IconThemeName" type="string" value="Humanity"/>
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

cat > "$XFCE_XML_DIR/xfwm4.xml" <<'XFWM4_XML'
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

# ── 7d. XFCE session config ─────────────────────────────────────────
cat > "$XFCE_XML_DIR/xfce4-session.xml" <<'SESSION_XML'
<?xml version="1.0" encoding="UTF-8"?>

<channel name="xfce4-session" version="1.0">
  <property name="general" type="empty">
    <property name="FailsafeSessionName" type="string" value="Failsafe"/>
    <property name="LockCommand" type="string" value=""/>
    <property name="SaveOnExit" type="bool" value="false"/>
  </property>
  <property name="sessions" type="empty">
    <property name="Failsafe" type="empty">
      <property name="IsFailsafe" type="bool" value="true"/>
      <property name="Count" type="int" value="5"/>
      <property name="Client0_Command" type="array">
        <value type="string" value="xfwm4"/>
      </property>
      <property name="Client0_PerScreen" type="bool" value="false"/>
      <property name="Client1_Command" type="array">
        <value type="string" value="xfsettingsd"/>
      </property>
      <property name="Client1_PerScreen" type="bool" value="false"/>
      <property name="Client2_Command" type="array">
        <value type="string" value="xfce4-panel"/>
      </property>
      <property name="Client2_PerScreen" type="bool" value="false"/>
      <property name="Client3_Command" type="array">
        <value type="string" value="Thunar"/>
        <value type="string" value="--daemon"/>
      </property>
      <property name="Client3_PerScreen" type="bool" value="false"/>
      <property name="Client4_Command" type="array">
        <value type="string" value="xfdesktop"/>
      </property>
      <property name="Client4_PerScreen" type="bool" value="false"/>
    </property>
  </property>
</channel>
SESSION_XML

# ── 7e. Disable display power management (DPMS / screensaver) ────────
msg "Disabling display power management..."

cat > "$XFCE_XML_DIR/xfce4-power-manager.xml" <<'POWER_XML'
<?xml version="1.0" encoding="UTF-8"?>

<channel name="xfce4-power-manager" version="1.0">
  <property name="xfce4-power-manager" type="empty">
    <property name="dpms-enabled" type="bool" value="false"/>
    <property name="blank-on-ac" type="int" value="0"/>
    <property name="dpms-on-ac-sleep" type="uint" value="0"/>
    <property name="dpms-on-ac-off" type="uint" value="0"/>
    <property name="blank-on-battery" type="int" value="0"/>
    <property name="dpms-on-battery-sleep" type="uint" value="0"/>
    <property name="dpms-on-battery-off" type="uint" value="0"/>
    <property name="lock-screen-suspend-hibernate" type="bool" value="false"/>
    <property name="logind-handle-lid-switch" type="bool" value="false"/>
  </property>
</channel>
POWER_XML

# Also disable xfce4-screensaver if present
if command -v xfce4-screensaver-command >/dev/null 2>&1; then
    xfce4-screensaver-command --deactivate 2>/dev/null || true
fi

# xset dpms off for good measure (applied at session start via xstartup)
if grep -qF 'xset' /root/.vnc/xstartup 2>/dev/null; then
    if ! grep -qF 'dpms' /root/.vnc/xstartup 2>/dev/null; then
        sed -i '/startxfce4/i xset s off -dpms 2>/dev/null || true' /root/.vnc/xstartup
        ok "Added 'xset s off -dpms' to VNC xstartup."
    fi
else
    ok "xset dpms will be handled by power manager config."
fi

ok "Display power management disabled."
ok "Dark theme + Humanity icons + session config applied."


# ══════════════════════════════════════════════════════════════════════
#  SECTION 9: Final Validation
# ══════════════════════════════════════════════════════════════════════
msg "Validating installation..."
echo ""

_check() {
    local name="$1" cmd="$2" ver_cmd="$3"
    if eval "$cmd" >/dev/null 2>&1; then
        local ver
        ver=$(eval "$ver_cmd" 2>/dev/null || echo "ok")
        printf "  ${GREEN}✔${NC} %-30s %s\n" "$name" "$ver"
    else
        printf "  ${RED}✖${NC} %-30s ${DIM}not found${NC}\n" "$name"
    fi
}

printf "  ${BOLD}Desktop & Display${NC}\n"
printf "  ${DIM}──────────────────────────────────────────────${NC}\n"
_check "XFCE Desktop"       "command -v startxfce4"   "echo 'installed'"
_check "TigerVNC Server"    "command -v vncserver"     "vncserver -version 2>&1 | head -1"
echo ""

printf "  ${BOLD}Applications${NC}\n"
printf "  ${DIM}──────────────────────────────────────────────${NC}\n"
if [[ "$INSTALL_CHROMIUM" -eq 1 ]]; then
_check "Chromium"           "test -f /usr/lib/chromium/chromium"                                                    "dpkg -s chromium 2>/dev/null | grep Version || echo 'installed'"
_check "Chromium (not snap)" "! head -20 /usr/bin/chromium 2>/dev/null | grep -qi snap"                              "echo 'Debian .deb'"
_check "Chromium no missing" "test -z \"\$(ldd /usr/lib/chromium/chromium 2>&1 | grep 'not found')\" 2>/dev/null"    "echo 'all libs present'"
_check "Chromium proot flags" "test -f /etc/chromium.d/proot-flags"                                                  "echo '/etc/chromium.d/proot-flags'"
_check "Stock launcher"      "head -20 /usr/bin/chromium 2>/dev/null | grep -q 'chromium.d\\|CHROMIUM_FLAGS'"        "echo '/usr/bin/chromium (sources chromium.d)'"
fi
if [[ "$INSTALL_FIREFOX" -eq 1 ]]; then
_check "Firefox"            "command -v firefox"                                                                    "firefox --version 2>/dev/null | head -1 || echo 'installed'"
_check "Firefox (not snap)" "! head -20 /usr/bin/firefox 2>/dev/null | grep -qi snap"                               "echo 'Mozilla APT'"
_check "Firefox wrapper"    "head -5 /usr/bin/firefox 2>/dev/null | grep -q MOZ_FAKE_NO_SANDBOX"                    "echo 'proot wrapper'"
fi
_check "snap stubs blocked"  "test -f /etc/apt/preferences.d/no-snap-chromium.pref"                                  "echo 'chromium stubs pinned'"
_check "Firefox snap block" "test -f /etc/apt/preferences.d/no-snap-firefox.pref"                                   "echo 'firefox stub pinned'"
_check "snapd blocked"       "test -f /etc/apt/preferences.d/no-snapd.pref"                                          "echo 'snapd pinned'"
_check "Google Chrome"      "command -v google-chrome-stable || command -v google-chrome" "echo 'installed'"
_check "Visual Studio Code" "test -f /usr/share/code/code"  "/usr/share/code/code --version 2>/dev/null | head -1 || echo 'installed'"
_check "Blender"            "command -v blender"       "blender --version 2>/dev/null | head -1"
_check "GIMP"               "command -v gimp"          "gimp --version 2>/dev/null | head -1"
_check "LibreOffice"        "command -v libreoffice"   "libreoffice --version 2>/dev/null | head -1"
_check "GParted"            "command -v gparted"       "echo 'installed'"
_check "Kdenlive"           "command -v kdenlive"      "echo 'installed'"
_check "Shotcut"            "command -v shotcut"       "echo 'installed'"
_check "OBS Studio"         "command -v obs"           "obs --version 2>/dev/null || echo 'installed'"
_check "Thunderbird"        "command -v thunderbird"   "thunderbird --version 2>/dev/null | head -1"
_check "Spotify"            "command -v spotify || command -v spt || test -f /usr/share/spotify/spotify" "echo 'installed'"
_check "App store"          "command -v gnome-software || command -v gpk-application"  "echo 'installed'"
_check "Python"             "command -v python3"       "python3 --version"
_check "Git"                "command -v git"           "git --version"
echo ""

printf "  ${BOLD}Proot Dev Mods${NC}\n"
printf "  ${DIM}──────────────────────────────────────────────${NC}\n"
_check "Environment vars"   "grep -q ELECTRON_DISABLE_SANDBOX /etc/environment"                                    "echo '/etc/environment'"
_check "VSCode argv.json"   "test -f /root/.vscode/argv.json"                                                      "echo 'configured'"
_check "VSCode settings"    "test -f /root/.vscode/User/settings.json"                                              "echo 'signature fix applied'"
_check "VSCode wrapper"     "grep -q 'proot VSCode wrapper' /usr/bin/code 2>/dev/null"                            "echo '/usr/bin/code'"
if [[ "$INSTALL_CHROMIUM" -eq 1 ]]; then
_check "Chromium held"     "apt-mark showhold 2>/dev/null | grep -q chromium"                                    "echo 'no upgrades'"
fi
_check "Chrome wrapper"     "grep -q 'proot.*[Cc]hrome.*wrapper' /usr/bin/google-chrome-stable 2>/dev/null || grep -q 'proot.*wrapper' /usr/bin/google-chrome 2>/dev/null" "echo 'wrapped'"
_check "/dev/shm"           "test -d /dev/shm"                                                                  "echo 'exists'"
_check ".Xauthority"        "test -f /root/.Xauthority"                                                         "echo 'exists'"
_check "Default browser"    "test -f /root/.config/xfce4/helpers.rc"                                                "cat /root/.config/xfce4/helpers.rc 2>/dev/null | grep -oP '(?<=WebBrowser=).*' || echo 'set'"
echo ""

printf "  ${BOLD}Audio & USB${NC}\n"
printf "  ${DIM}──────────────────────────────────────────────${NC}\n"
_check "PulseAudio client"  "command -v pactl"         "pactl --version 2>/dev/null | head -1"
_check "PULSE_SERVER env"   "grep -q PULSE_SERVER /etc/environment"   "echo '127.0.0.1 (Termux TCP)'"
_check "pavucontrol"        "command -v pavucontrol"   "echo 'installed'"
_check "lsusb"             "command -v lsusb"         "echo 'installed'"
_check "libusb"            "dpkg -s libusb-1.0-0 2>/dev/null | grep -q installed" "echo 'installed'"
echo ""

printf "  ${BOLD}Development Tools${NC}\n"
printf "  ${DIM}──────────────────────────────────────────────${NC}\n"
_check "Android adb"        "command -v adb"            "adb --version 2>/dev/null | head -1"
_check "Node.js"            "command -v node"           "node --version 2>/dev/null"
_check "npm"                "command -v npm"            "npm --version 2>/dev/null"
_check "Arduino CLI"        "command -v arduino-cli"    "arduino-cli version 2>/dev/null | head -1"
_check "Java JDK"           "command -v javac || command -v java"  "java -version 2>&1 | head -1"
_check "CMake"              "command -v cmake"          "cmake --version 2>/dev/null | head -1"
_check "GDB"                "command -v gdb"            "gdb --version 2>/dev/null | head -1"
_check "Clang"              "command -v clang"          "clang --version 2>/dev/null | head -1"
_check "tmux"               "command -v tmux"           "tmux -V 2>/dev/null"
_check "Ruby"               "command -v ruby"           "ruby --version 2>/dev/null"
echo ""

printf "  ${BOLD}Network & Windows Apps${NC}\n"
printf "  ${DIM}──────────────────────────────────────────────${NC}\n"
_check "nmap"               "command -v nmap"           "nmap --version 2>/dev/null | head -1"
_check "Angry IP Scanner"   "command -v ipscan"         "echo 'installed'"
_check "Wine"               "command -v wine || command -v wine64"  "wine --version 2>/dev/null || wine64 --version 2>/dev/null"
_check "box64 (arm64)"      "command -v box64"          "box64 --version 2>/dev/null | head -1 || echo 'installed'"
_check "Notepad++ (Wine)"   "test -f \"$HOME/.wine/drive_c/Program Files/Notepad++/notepad++.exe\"" "echo 'installed'"
_check "WireGuard"          "command -v wg"             "wg --version 2>/dev/null || echo 'installed'"
echo ""

printf "  ${BOLD}Android SDK & Arduino${NC}\n"
printf "  ${DIM}──────────────────────────────────────────────${NC}\n"
_check "Android SDK"        "test -d /opt/android-sdk/cmdline-tools || command -v sdkmanager" "echo '/opt/android-sdk'"
_check "sdkmanager"         "command -v sdkmanager"     "echo 'installed'"
_check "Android adb"        "command -v adb"            "adb --version 2>/dev/null | head -1"
_check "Arduino IDE"        "command -v arduino || test -f /usr/local/bin/arduino-ide" "echo 'installed'"
_check "Arduino CLI"        "command -v arduino-cli"    "arduino-cli version 2>/dev/null | head -1"
echo ""

printf "  ${BOLD}Desktop Customization${NC}\n"
printf "  ${DIM}──────────────────────────────────────────────${NC}\n"
_check "Black wallpaper"    "test -f $XFCE_XML_DIR/xfce4-desktop.xml"   "echo 'configured'"
_check "Panel + launchers"  "test -f $XFCE_XML_DIR/xfce4-panel.xml"     "echo 'bottom dock'"
_check "Launcher dirs"      "test -d /root/.config/xfce4/panel/launcher-2" "echo 'configured'"
_check "Humanity icons"     "test -d /usr/share/icons/Humanity"          "echo 'Humanity'"
_check "Dark theme"         "test -f $XFCE_XML_DIR/xsettings.xml"       "echo 'Adwaita-dark'"
_check "DPMS disabled"      "test -f $XFCE_XML_DIR/xfce4-power-manager.xml" "echo 'power mgmt off'"
_check "Conky widgets"      "command -v conky"          "echo 'installed'"
_check "Conky config"       "test -f /root/.config/conky/conky.conf"     "echo 'configured'"
_check "VNC xstartup"       "test -f /root/.vnc/xstartup"               "echo 'configured'"
echo ""


# ══════════════════════════════════════════════════════════════════════
#  Done
# ══════════════════════════════════════════════════════════════════════
printf "${GREEN}${BOLD}"
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
DONE

# Dynamic dock + launch list based on browser choice
if [[ "$INSTALL_CHROMIUM" -eq 1 ]] && [[ "$INSTALL_FIREFOX" -eq 1 ]]; then
cat <<'DONE'
       • Bottom dock: Applications | Settings | Terminal | Thunar | Chromium |
                     Firefox | Chrome | Thunderbird | VSCode | LibreOffice |
                     GIMP | Blender | Spotify | Tasklist | Volume |
                     Clock (LCD)
       • Or launch from terminal:
           chromium
           firefox
           code .
           google-chrome-stable
DONE
elif [[ "$INSTALL_CHROMIUM" -eq 1 ]]; then
cat <<'DONE'
       • Bottom dock: Applications | Settings | Terminal | Thunar | Chromium |
                     Chrome | Thunderbird | VSCode | LibreOffice |
                     GIMP | Blender | Spotify | Tasklist | Volume |
                     Clock (LCD)
       • Or launch from terminal:
           chromium
           code .
           google-chrome-stable
DONE
else
cat <<'DONE'
       • Bottom dock: Applications | Settings | Terminal | Thunar | Firefox |
                     Chrome | Thunderbird | VSCode | LibreOffice |
                     GIMP | Blender | Spotify | Tasklist | Volume |
                     Clock (LCD)
       • Or launch from terminal:
           firefox
           code .
           google-chrome-stable
DONE
fi

cat <<'DONE'
           gimp
           blender
           libreoffice
           kdenlive
           shotcut
           obs
           spotify

    4. Development tools available:
         adb              — Android Debug Bridge
         sdkmanager       — Android SDK manager
         arduino-cli      — Arduino board programming
         arduino          — Arduino IDE (if installed)
         node / npm       — JavaScript runtime
         python3 / pip    — Python development
         cmake / make     — Build systems
         gdb              — GNU debugger
         clang / gcc      — C/C++ compilers
         javac            — Java compiler
         ruby             — Ruby interpreter
         tmux             — Terminal multiplexer
         git              — Version control
         wg               — WireGuard VPN
         conky            — Desktop system monitor

    5. To stop:
         bash ~/stop-ubuntu.sh

  Sound:
    Audio plays through Android device speakers via PulseAudio TCP.
    • Termux starts PulseAudio server; proot connects at 127.0.0.1
    • Works with both VNC and Termux:X11 display methods
    • Volume control is in the panel (speaker icon)
    • For advanced mixing: run  pavucontrol

  USB:
    USB OTG devices are accessible if Termux has USB permission.
    • The launcher scripts bind-mount /dev/bus/usb into proot
    • Run  lsusb  inside proot to list connected devices
    • For USB permission: plug in device → Android will prompt
      → Grant access to Termux
    • Also try:  termux-usb -l  in Termux to list USB devices

DONE

if [[ "$INSTALL_CHROMIUM" -eq 1 ]]; then
cat <<'DONE'
  Chromium troubleshooting:
    Chromium v89 (Debian Buster) is installed with proot flags
    via /etc/chromium.d/proot-flags.  All flags are sourced
    automatically by /usr/bin/chromium (the stock Debian launcher).

    If Chromium crashes immediately:
    → Check: ldd /usr/lib/chromium/chromium | grep 'not found'
    → Re-run setup-proot.sh to reinstall compat libraries

    Chromium launch chain (for debugging):
    → exo-open / panel click / .desktop
    → /usr/local/bin/chromium-default  (debug wrapper, logs to /tmp/chromium-default.log)
    → /usr/bin/chromium                (stock Debian launcher, sources /etc/chromium.d/*)
    → /etc/chromium.d/proot-flags      (sets CHROMIUM_FLAGS with all proot flags)
    → /usr/lib/chromium/chromium       (actual ELF binary)

    Harmless Chromium proot warnings (ignore these):
    → "Could not bind NETLINK socket: Permission denied"
    → "Failed to connect to the bus: /run/dbus/system_bus_socket"
    → "Failed to initialize a udev monitor"
    → "Floss manager not present"

DONE
fi

if [[ "$INSTALL_FIREFOX" -eq 1 ]]; then
cat <<'DONE'
  Firefox troubleshooting:
    Firefox is installed from Mozilla's official APT repo with a
    proot wrapper that sets MOZ_FAKE_NO_SANDBOX=1 and other sandbox
    disable vars.  The wrapper is at /usr/bin/firefox and calls
    /usr/bin/firefox.real.

    If Firefox crashes immediately:
    → Check:  head -5 /usr/bin/firefox  (should show MOZ_FAKE_NO_SANDBOX)
    → Re-run setup-proot.sh to recreate the wrapper

DONE
fi

cat <<'DONE'
  Expected harmless proot warnings (ignore these):
    - "Failed to move to new namespace..."
    - "SUID sandbox helper binary not found"
    - dbus / netlink / udev / inotify warnings

  If VSCode shows a keyring unlock dialog:
    → Just cancel it. password-store=basic is already configured.

  VNC won't connect on second launch?
    → Run:  bash ~/stop-ubuntu.sh  first, then start again.
    → The stop script cleans up stale VNC locks and PID files.

  Termux keeps getting killed (error 9)?
    → Disable battery optimization for Termux in Android Settings:
      Settings → Apps → Termux → Battery → Unrestricted
    → Also ensure Termux has a persistent notification (wake lock).

  Google Chrome not available?
    → Chrome for Linux may not support your CPU architecture.
    → Chromium or Firefox are available as alternatives.

DONE