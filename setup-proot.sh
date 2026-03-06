#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════
#  setup-proot.sh — Ubuntu proot environment setup
#
#  Installs XFCE desktop, VSCode, Chromium with all proot mods,
#  and customizes the desktop (black background, dock bar).
#
#  Run INSIDE the Ubuntu proot:
#    proot-distro login ubuntu
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
  ║   XFCE + VSCode + Chromium (all proot-modded)            ║
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

msg "Running apt update & upgrade..."
apt-get update -y
apt-get upgrade -y
ok "System updated."


# ══════════════════════════════════════════════════════════════════════
#  SECTION 1: Install XFCE Desktop Environment + VNC
# ══════════════════════════════════════════════════════════════════════
msg "Installing XFCE desktop environment + TigerVNC..."

DEBIAN_FRONTEND=noninteractive apt-get install -y \
    xfce4 xfce4-goodies xfce4-terminal \
    dbus dbus-x11 \
    tigervnc-standalone-server tigervnc-common \
    xfonts-base xfonts-100dpi xfonts-75dpi \
    hicolor-icon-theme adwaita-icon-theme-full \
    sudo wget curl nano git \
    at-spi2-core libglib2.0-0 \
    locales \
    pulseaudio libpulse0 alsa-utils \
    xfce4-pulseaudio-plugin pavucontrol \
    libusb-1.0-0 usbutils

ok "XFCE desktop + TigerVNC + PulseAudio + USB tools installed."

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

# PulseAudio — connect to Termux's PA server over TCP
# Sound plays through Android device speakers (works for both VNC and X11)
export PULSE_SERVER=127.0.0.1

# Start XFCE
exec startxfce4
XSTARTUP
chmod +x ~/.vnc/xstartup
ok "VNC xstartup configured."


# ══════════════════════════════════════════════════════════════════════
#  SECTION 2: Install Visual Studio Code
# ══════════════════════════════════════════════════════════════════════
msg "Installing Visual Studio Code..."

if command -v code >/dev/null 2>&1; then
    ok "VSCode already installed: $(code --version 2>/dev/null | head -1)"
else
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
    apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
        libsecret-1-0 libgbm1 libasound2 libxss1 libnss3 \
        libatk-bridge2.0-0 libgtk-3-0 gnome-keyring code
    ok "VSCode installed."
fi

# ── VSCode proot wrapper ──────────────────────────────────────────────
#
# VSCode's Electron shell cannot run without --no-sandbox in proot
# because kernel namespaces (user, PID, net) are unavailable.
# We wrap /usr/bin/code so EVERY launch method (terminal, .desktop,
# XFCE menu) automatically gets the required flags.
#
msg "Creating VSCode proot wrapper..."
CODE_BIN="/usr/bin/code"

if [[ -e "$CODE_BIN" ]]; then
    already_wrapped=0
    head -n 6 "$CODE_BIN" 2>/dev/null | grep -q "code\.real\|proot VSCode wrapper" && already_wrapped=1

    if [[ "$already_wrapped" -eq 1 ]]; then
        ok "VSCode wrapper already in place."
    else
        # Resolve the real binary (usually a symlink → /usr/share/code/bin/code)
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
#
# This tells VSCode to use a plaintext credential store instead of
# trying to talk to gnome-keyring / libsecret (which fails in proot).
#
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

# ── Patch code.desktop so XFCE menu/panel use the wrapper ─────────────
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
    DEBIAN_FRONTEND=noninteractive apt-get install -y chromium-browser || \
    DEBIAN_FRONTEND=noninteractive apt-get install -y chromium || {
        err "Failed to install Chromium. Try manually: apt install chromium-browser"
    }
    ok "Chromium installed."
fi

# ── Chromium proot wrapper ────────────────────────────────────────────
#
# Same story as VSCode — Chromium needs --no-sandbox in proot.
# We also disable GPU and the zygote process (unnecessary overhead in proot).
#
msg "Creating Chromium proot wrapper..."

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

    # Patch .desktop files so XFCE menu launches through the wrapper
    for df in /usr/share/applications/chromium*.desktop; do
        [[ -f "$df" ]] || continue
        [[ ! -f "${df}.bak" ]] && cp "$df" "${df}.bak"
        sed -i "s|^Exec=.*|Exec=$CHROMIUM_BIN %U|" "$df"
        ok "Patched: $(basename "$df")"
    done

    # Set Chromium as the default browser
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
ok "/etc/environment updated with proot-safe variables."

# Helper: add export to ~/.bashrc if not present
_add_bashrc() {
    grep -qF "export $1=" ~/.bashrc 2>/dev/null || echo "export $1=\"$2\"" >> ~/.bashrc
}

_add_bashrc "ELECTRON_DISABLE_SANDBOX" "1"
_add_bashrc "VSCODE_KEYRING"           "basic"
_add_bashrc "PULSE_SERVER"             "127.0.0.1"
ok "~/.bashrc exports added."


# ══════════════════════════════════════════════════════════════════════
#  SECTION 5: XFCE Desktop Customization
# ══════════════════════════════════════════════════════════════════════
msg "Customizing XFCE desktop..."

XFCE_XML_DIR="/root/.config/xfce4/xfconf/xfce-perchannel-xml"
mkdir -p "$XFCE_XML_DIR"

# ── 5a. Set desktop background to solid black ─────────────────────────
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

# ── 5b. Add VSCode and Chromium to the XFCE panel (dock/taskbar) ─────
msg "Configuring XFCE panel with VSCode + Chromium launchers..."

# Detect the Chromium .desktop file name
CHROMIUM_DESKTOP=""
[[ -f /usr/share/applications/chromium-browser.desktop ]] && CHROMIUM_DESKTOP="chromium-browser.desktop"
[[ -f /usr/share/applications/chromium.desktop ]]         && CHROMIUM_DESKTOP="chromium.desktop"

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
    <property name="plugin-8" type="string" value="pulseaudio">
      <property name="enable-keyboard-shortcuts" type="bool" value="true"/>
      <property name="show-notifications" type="bool" value="false"/>
    </property>
    <property name="plugin-9" type="string" value="clock">
      <property name="digital-format" type="string" value="%R"/>
    </property>
  </property>
</channel>
PANEL_XML
ok "Panel: App Menu | Terminal | Files | Chromium | VSCode | Tasklist | Systray | Volume | Clock"

# ── 5c. Apply dark theme ──────────────────────────────────────────────
msg "Setting dark theme (Adwaita-dark)..."

cat > "$XFCE_XML_DIR/xsettings.xml" <<'XSETTINGS_XML'
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
ok "Dark theme applied."


# ══════════════════════════════════════════════════════════════════════
#  SECTION 6: Final Validation
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

printf "  ${BOLD}Software${NC}\n"
printf "  ${DIM}──────────────────────────────────────────────${NC}\n"
_check "XFCE Desktop"       "command -v startxfce4"   "echo 'installed'"
_check "TigerVNC Server"    "command -v vncserver"     "vncserver -version 2>&1 | head -1"
_check "Visual Studio Code" "command -v code"          "code --version 2>/dev/null | head -1"
_check "Chromium"           "command -v chromium-browser || command -v chromium" "echo 'installed'"
_check "Git"                "command -v git"           "git --version"
_check "wget"               "command -v wget"          "echo 'installed'"
_check "curl"               "command -v curl"          "echo 'installed'"
echo ""

printf "  ${BOLD}Proot Mods${NC}\n"
printf "  ${DIM}──────────────────────────────────────────────${NC}\n"
_check "Environment vars"   "grep -q ELECTRON_DISABLE_SANDBOX /etc/environment"                                    "echo '/etc/environment'"
_check "VSCode argv.json"   "test -f /root/.config/Code/argv.json"                                                 "echo 'configured'"
_check "VSCode wrapper"     "head -3 /usr/bin/code 2>/dev/null | grep -q no-sandbox"                               "echo '/usr/bin/code'"
_check "Chromium wrapper"   "head -5 /usr/bin/chromium-browser 2>/dev/null | grep -q no-sandbox || head -5 /usr/bin/chromium 2>/dev/null | grep -q no-sandbox" "echo 'wrapped'"
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
       • VSCode and Chromium are in the top panel (dock bar)
       • Or launch from terminal:  code .  /  chromium-browser

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
