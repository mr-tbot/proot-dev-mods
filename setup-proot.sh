#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════
#  setup-proot.sh — Ubuntu proot environment setup
#
#  Installs XFCE desktop, VSCode, Chromium (Debian .deb — NOT snap),
#  Blender, GIMP, LibreOffice, GParted, Python, and more.
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

printf "${BOLD}${CYAN}"
cat <<'BANNER'
  ╔═══════════════════════════════════════════════════════════╗
  ║   Proot Ubuntu Desktop — Environment Setup               ║
  ║   XFCE + VSCode + Chromium + Blender + GIMP + more       ║
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
apt-get update -y
apt-get upgrade -y
ok "System updated."


# ══════════════════════════════════════════════════════════════════════
#  SECTION 1: Install XFCE Desktop Environment + VNC
# ══════════════════════════════════════════════════════════════════════
msg "Installing XFCE desktop environment + TigerVNC..."

# NOTE: We use --no-install-recommends to prevent apt from pulling in
# elementary-xfce-icon-theme (10k+ icon files that hang dpkg in proot).
# We explicitly install the icon themes we need afterwards.

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


# ══════════════════════════════════════════════════════════════════════
#  SECTION 2: Install Icon Themes (Humanity + fallbacks)
# ══════════════════════════════════════════════════════════════════════
msg "Installing icon themes (Humanity + fallbacks)..."

# Humanity is the Ubuntu-origin theme that provides the best icon
# coverage for XFCE menu categories (Settings, Accessories, Multimedia,
# System) in proot.  We install several fallback themes plus rebuild
# all icon caches so the panel and menus render correctly.

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


# ══════════════════════════════════════════════════════════════════════
#  SECTION 3: Install Chromium (from Debian repos — NOT snap)
# ══════════════════════════════════════════════════════════════════════
msg "Installing Chromium..."

# Ubuntu's chromium-browser is a snap stub that doesn't work in proot.
# We install the real .deb Chromium from Debian repos instead.

_install_chromium_from_debian() {
    msg "Adding Debian repository for Chromium .deb..."

    # Remove snap-based chromium stub if present
    apt-get remove -y chromium-browser 2>/dev/null || true

    mkdir -p /usr/share/keyrings

    # Add Debian archive GPG keys
    if [[ ! -f /usr/share/keyrings/debian-archive-keyring.gpg ]]; then
        # Try to get from the debian-archive-keyring package first
        DEBIAN_FRONTEND=noninteractive apt-get install -y debian-archive-keyring 2>/dev/null || true

        if [[ ! -f /usr/share/keyrings/debian-archive-keyring.gpg ]]; then
            # Fallback: download keys directly
            wget -qO- https://ftp-master.debian.org/keys/archive-key-12.asc \
                | gpg --dearmor > /usr/share/keyrings/debian-archive-keyring.gpg 2>/dev/null || true
            wget -qO- https://ftp-master.debian.org/keys/archive-key-12-security.asc \
                | gpg --dearmor >> /usr/share/keyrings/debian-archive-keyring.gpg 2>/dev/null || true
            wget -qO- https://ftp-master.debian.org/keys/archive-key-11.asc \
                | gpg --dearmor >> /usr/share/keyrings/debian-archive-keyring.gpg 2>/dev/null || true
            wget -qO- https://ftp-master.debian.org/keys/archive-key-10.asc \
                | gpg --dearmor >> /usr/share/keyrings/debian-archive-keyring.gpg 2>/dev/null || true
        fi
        ok "Debian GPG keys added."
    fi

    # Add Debian Bookworm repo (try Bookworm first, fall back to Bullseye, then Buster)
    cat > /etc/apt/sources.list.d/debian-chromium.list <<DEBREPO
# Debian — used ONLY for Chromium .deb (snap doesn't work in proot)
deb [signed-by=/usr/share/keyrings/debian-archive-keyring.gpg] http://deb.debian.org/debian bookworm main
DEBREPO
    ok "Debian Bookworm repo added."

    # Pin: only allow chromium packages from Debian, block everything else
    cat > /etc/apt/preferences.d/debian-chromium.pref <<'PINNING'
# Only allow chromium packages from Debian
Package: chromium chromium-common chromium-sandbox chromium-l10n
Pin: release o=Debian
Pin-Priority: 900

# Block all other Debian packages from replacing Ubuntu packages
Package: *
Pin: release o=Debian
Pin-Priority: -1
PINNING
    ok "APT pinning configured (only chromium from Debian)."

    apt-get update -y

    # Install Debian's real chromium
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
        -o Dpkg::Options::="--force-confdef" \
        -o Dpkg::Options::="--force-confold" \
        chromium && {
        ok "Chromium installed from Debian Bookworm."
        return 0
    }

    # Fallback: try Bullseye
    warn "Bookworm chromium failed — trying Bullseye..."
    sed -i 's/bookworm/bullseye/' /etc/apt/sources.list.d/debian-chromium.list
    apt-get update -y
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
        -o Dpkg::Options::="--force-confdef" \
        -o Dpkg::Options::="--force-confold" \
        chromium && {
        ok "Chromium installed from Debian Bullseye."
        return 0
    }

    # Fallback: try Buster
    warn "Bullseye chromium failed — trying Buster..."
    sed -i 's/bullseye/buster/' /etc/apt/sources.list.d/debian-chromium.list
    apt-get update -y
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
        -o Dpkg::Options::="--force-confdef" \
        -o Dpkg::Options::="--force-confold" \
        chromium && {
        ok "Chromium installed from Debian Buster."
        return 0
    }

    err "Failed to install Chromium from any Debian release."
    return 1
}

# Check if we already have a working (non-snap) chromium binary
CHROMIUM_OK=0
if command -v chromium >/dev/null 2>&1; then
    CHROMIUM_PATH="$(command -v chromium)"
    # Check it's real: either an ELF binary, a script, or a wrapper we already created
    if file "$CHROMIUM_PATH" 2>/dev/null | grep -qi "ELF\|script"; then
        # Make sure it's not a snap stub
        if ! head -5 "$CHROMIUM_PATH" 2>/dev/null | grep -qi "snap"; then
            CHROMIUM_OK=1
            ok "Chromium already installed (real binary)."
        fi
    fi
fi

if [[ "$CHROMIUM_OK" -eq 0 ]]; then
    _install_chromium_from_debian
fi


# ── Chromium proot wrapper ────────────────────────────────────────────
msg "Creating Chromium proot wrapper..."

CHROMIUM_BIN=""
[[ -e /usr/bin/chromium ]]         && CHROMIUM_BIN="/usr/bin/chromium"
[[ -e /usr/bin/chromium-browser ]] && CHROMIUM_BIN="/usr/bin/chromium-browser"

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
                chmod +x "$CHROMIUM_REAL"
            fi
        fi

        cat > "$CHROMIUM_BIN" <<WRAPPER
#!/bin/sh
# proot Chromium wrapper — all flags needed for proot environment
exec "$CHROMIUM_REAL" \\
  --no-sandbox \\
  --disable-dev-shm-usage \\
  --disable-gpu \\
  --disable-software-rasterizer \\
  --no-zygote \\
  --password-store=basic \\
  --use-mock-keychain \\
  --disable-features=WebAuthentication,WebAuthn,SecurePaymentConfirmation \\
  "\$@"
WRAPPER
        chmod +x "$CHROMIUM_BIN"
        ok "Chromium proot wrapper created (calls $CHROMIUM_REAL)"
    fi

    # Create a debug/fallback launcher at /usr/local/bin/chromium-default
    cat > /usr/local/bin/chromium-default <<DEBUGWRAPPER
#!/bin/sh
# Chromium debug/fallback launcher for proot
# Logs to /tmp/chromium-default.log for troubleshooting
export XDG_RUNTIME_DIR="\${XDG_RUNTIME_DIR:-/tmp/runtime-\$(whoami)}"
mkdir -p "\$XDG_RUNTIME_DIR"
echo "[\$(date)] Starting chromium from chromium-default wrapper" >> /tmp/chromium-default.log
echo "  DISPLAY=\$DISPLAY" >> /tmp/chromium-default.log
exec $CHROMIUM_BIN "\$@"
DEBUGWRAPPER
    chmod +x /usr/local/bin/chromium-default
    ok "Debug wrapper created at /usr/local/bin/chromium-default"

    # Patch .desktop files
    for df in /usr/share/applications/chromium*.desktop; do
        [[ -f "$df" ]] || continue
        [[ ! -f "${df}.bak" ]] && cp "$df" "${df}.bak"
        sed -i "s|^Exec=.*|Exec=$CHROMIUM_BIN --no-sandbox --disable-dev-shm-usage %U|" "$df"
        ok "Patched: $(basename "$df")"
    done

    # Configure chromium.d default flags if available
    mkdir -p /etc/chromium.d 2>/dev/null || true
    cat > /etc/chromium.d/default-flags <<'CHROMIUMD'
# Default Chromium flags for proot environment
export CHROMIUM_FLAGS="$CHROMIUM_FLAGS --no-default-browser-check --disable-pings --enable-remote-extensions"
CHROMIUMD
    ok "Chromium default flags configured."

    # Set Chromium as the default browser via multiple methods
    # 1. XFCE helpers.rc
    mkdir -p /root/.config/xfce4
    cat > /root/.config/xfce4/helpers.rc <<HELPERSRC
WebBrowserCommand=/usr/local/bin/chromium-default "%s"
WebBrowser=chromium
HELPERSRC
    ok "XFCE helpers.rc configured (Chromium as default browser)."

    # 2. Detect .desktop name
    CHROMIUM_DESKTOP_NAME=""
    [[ -f /usr/share/applications/chromium.desktop ]] && CHROMIUM_DESKTOP_NAME="chromium.desktop"
    [[ -f /usr/share/applications/chromium-browser.desktop ]] && CHROMIUM_DESKTOP_NAME="chromium-browser.desktop"

    if [[ -n "$CHROMIUM_DESKTOP_NAME" ]]; then
        # xdg-settings / xdg-mime
        command -v xdg-settings >/dev/null 2>&1 && \
            xdg-settings set default-web-browser "$CHROMIUM_DESKTOP_NAME" 2>/dev/null || true
        if command -v xdg-mime >/dev/null 2>&1; then
            for mime in x-scheme-handler/http x-scheme-handler/https text/html; do
                xdg-mime default "$CHROMIUM_DESKTOP_NAME" "$mime" 2>/dev/null || true
            done
        fi
    fi

    # 3. update-alternatives
    update-alternatives --install /usr/bin/x-www-browser x-www-browser "$CHROMIUM_BIN" 200 2>/dev/null || true
    update-alternatives --set x-www-browser "$CHROMIUM_BIN" 2>/dev/null || true

    # 4. mimeapps.list
    mkdir -p /root/.local/share/applications
    cat > /root/.local/share/applications/mimeapps.list <<MIMEAPPS
[Default Applications]
x-scheme-handler/http=${CHROMIUM_DESKTOP_NAME:-chromium.desktop}
x-scheme-handler/https=${CHROMIUM_DESKTOP_NAME:-chromium.desktop}
text/html=${CHROMIUM_DESKTOP_NAME:-chromium.desktop}
MIMEAPPS
    ok "Chromium set as default browser (xdg + alternatives + mimeapps)."
fi


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
msg "This may take a while (Blender, GIMP, LibreOffice, GParted, Python)..."

DEBIAN_FRONTEND=noninteractive apt-get install -y \
    --no-install-recommends \
    -o Dpkg::Options::="--force-confdef" \
    -o Dpkg::Options::="--force-confold" \
    blender \
    gimp \
    libreoffice \
    gparted \
    python3 python3-pip python3-venv python3-dev \
    build-essential \
    file-roller \
    htop \
    tree \
    unzip zip \
    net-tools \
    openssh-client

ok "Additional applications installed."

# Python: make 'python' available as a command
if ! command -v python >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1; then
    update-alternatives --install /usr/bin/python python /usr/bin/python3 1 2>/dev/null || \
        ln -sf /usr/bin/python3 /usr/bin/python 2>/dev/null || true
    ok "python → python3 symlink created."
fi


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
#  SECTION 7: XFCE Desktop Customization
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

# ── 7b. XFCE panel with all application launchers ─────────────────────
msg "Configuring XFCE panel with application launchers..."

# Detect .desktop file names
CHROMIUM_DESKTOP=""
[[ -f /usr/share/applications/chromium.desktop ]]         && CHROMIUM_DESKTOP="chromium.desktop"
[[ -f /usr/share/applications/chromium-browser.desktop ]] && CHROMIUM_DESKTOP="chromium-browser.desktop"

LIBREOFFICE_DESKTOP=""
[[ -f /usr/share/applications/libreoffice-startcenter.desktop ]] && LIBREOFFICE_DESKTOP="libreoffice-startcenter.desktop"
[[ -f /usr/share/applications/libreoffice-writer.desktop ]] && LIBREOFFICE_DESKTOP="libreoffice-writer.desktop"

BLENDER_DESKTOP=""
[[ -f /usr/share/applications/blender.desktop ]] && BLENDER_DESKTOP="blender.desktop"

GIMP_DESKTOP=""
for gd in /usr/share/applications/gimp*.desktop; do
    [[ -f "$gd" ]] && GIMP_DESKTOP="$(basename "$gd")" && break
done

cat > "$XFCE_XML_DIR/xfce4-panel.xml" <<PANEL_XML
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
        <value type="string" value="${CHROMIUM_DESKTOP:-chromium.desktop}"/>
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
      <property name="digital-format" type="string" value="%R"/>
    </property>
  </property>
</channel>
PANEL_XML
ok "Panel: Menu | Terminal | Files | Chromium | VSCode | LibreOffice | GIMP | Blender | Tasklist | Systray | Volume | Clock"

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

ok "Dark theme + Humanity icons + session config applied."


# ══════════════════════════════════════════════════════════════════════
#  SECTION 8: Final Validation
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
_check "Chromium"           "command -v chromium || command -v chromium-browser" "echo 'installed'"
_check "Visual Studio Code" "test -f /usr/share/code/code"  "/usr/share/code/code --version 2>/dev/null | head -1 || echo 'installed'"
_check "Blender"            "command -v blender"       "blender --version 2>/dev/null | head -1"
_check "GIMP"               "command -v gimp"          "gimp --version 2>/dev/null | head -1"
_check "LibreOffice"        "command -v libreoffice"   "libreoffice --version 2>/dev/null | head -1"
_check "GParted"            "command -v gparted"       "echo 'installed'"
_check "Python"             "command -v python3"       "python3 --version"
_check "Git"                "command -v git"           "git --version"
echo ""

printf "  ${BOLD}Proot Mods${NC}\n"
printf "  ${DIM}──────────────────────────────────────────────${NC}\n"
_check "Environment vars"   "grep -q ELECTRON_DISABLE_SANDBOX /etc/environment"                                    "echo '/etc/environment'"
_check "VSCode argv.json"   "test -f /root/.vscode/argv.json"                                                      "echo 'configured'"
_check "VSCode wrapper"     "head -3 /usr/bin/code 2>/dev/null | grep -q no-sandbox"                               "echo '/usr/bin/code'"
_check "Chromium wrapper"   "head -5 /usr/bin/chromium 2>/dev/null | grep -q no-sandbox || head -5 /usr/bin/chromium-browser 2>/dev/null | grep -q no-sandbox" "echo 'wrapped'"
_check "Default browser"    "test -f /root/.config/xfce4/helpers.rc"                                                "echo 'Chromium'"
echo ""

printf "  ${BOLD}Audio & USB${NC}\n"
printf "  ${DIM}──────────────────────────────────────────────${NC}\n"
_check "PulseAudio client"  "command -v pactl"         "pactl --version 2>/dev/null | head -1"
_check "PULSE_SERVER env"   "grep -q PULSE_SERVER /etc/environment"   "echo '127.0.0.1 (Termux TCP)'"
_check "pavucontrol"        "command -v pavucontrol"   "echo 'installed'"
_check "lsusb"             "command -v lsusb"         "echo 'installed'"
_check "libusb"            "dpkg -s libusb-1.0-0 2>/dev/null | grep -q installed" "echo 'installed'"
echo ""

printf "  ${BOLD}Desktop Customization${NC}\n"
printf "  ${DIM}──────────────────────────────────────────────${NC}\n"
_check "Black wallpaper"    "test -f $XFCE_XML_DIR/xfce4-desktop.xml"   "echo 'configured'"
_check "Panel + launchers"  "test -f $XFCE_XML_DIR/xfce4-panel.xml"     "echo 'configured'"
_check "Humanity icons"     "test -d /usr/share/icons/Humanity"          "echo 'Humanity'"
_check "Dark theme"         "test -f $XFCE_XML_DIR/xsettings.xml"       "echo 'Adwaita-dark'"
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
       • Panel (top): Menu | Terminal | Files | Chromium | VSCode |
                      LibreOffice | GIMP | Blender | Tasklist | Volume | Clock
       • Or launch from terminal:
           code .
           chromium
           gimp
           blender
           libreoffice

    4. To stop:
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

  Expected harmless proot warnings (ignore these):
    - "Failed to move to new namespace..."
    - "SUID sandbox helper binary not found"
    - dbus / netlink / udev / inotify warnings

  If VSCode shows a keyring unlock dialog:
    → Just cancel it. password-store=basic is already configured.

DONE