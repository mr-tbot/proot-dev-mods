#!/data/data/com.termux/files/usr/bin/bash
# ═══════════════════════════════════════════════════════════════════════
#  setup-termux.sh — Termux-side setup for Ubuntu proot desktop
#
#  Installs proot-distro + Ubuntu, TigerVNC, Termux:X11 support,
#  and creates launcher/stop scripts.
#
#  Run in TERMUX (not inside proot):
#    bash setup-termux.sh
# ═══════════════════════════════════════════════════════════════════════
set -euo pipefail

# ── Colors ────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
msg()  { printf "\n${CYAN}[*]${NC} %s\n" "$*"; }
ok()   { printf "  ${GREEN}✔${NC} %s\n" "$*"; }
warn() { printf "  ${YELLOW}⚠${NC} %s\n" "$*"; }
err()  { printf "  ${RED}✖${NC} %s\n" "$*"; exit 1; }

printf "${BOLD}${CYAN}"
cat <<'BANNER'
  ╔═══════════════════════════════════════════════════════════╗
  ║   Proot Ubuntu Desktop — Termux Setup                    ║
  ║   Installs Ubuntu + VNC/X11 display support              ║
  ╚═══════════════════════════════════════════════════════════╝
BANNER
printf "${NC}\n"

# ══════════════════════════════════════════════════════════════════════
#  1. Update Termux
# ══════════════════════════════════════════════════════════════════════
msg "Updating Termux packages..."
pkg update -y && pkg upgrade -y
ok "Termux updated."

# ══════════════════════════════════════════════════════════════════════
#  2. Install core packages
# ══════════════════════════════════════════════════════════════════════
msg "Installing required Termux packages..."
pkg install -y proot-distro pulseaudio wget

# VNC support
pkg install -y x11-repo
pkg install -y tigervnc

# Termux:X11 support (optional — both are installed so user can choose)
pkg install -y termux-x11-nightly 2>/dev/null || \
    warn "termux-x11-nightly not available — Termux:X11 method will not work. VNC still works."

# Wake-lock support
pkg install -y termux-api 2>/dev/null || \
    warn "termux-api not installed — wake-lock unavailable."

ok "Termux packages installed."

# ══════════════════════════════════════════════════════════════════════
#  3. Choose Ubuntu version + install via proot-distro
# ══════════════════════════════════════════════════════════════════════
msg "Detecting available Ubuntu versions..."

# Discover Ubuntu-related aliases from proot-distro
mapfile -t UBUNTU_ALIASES < <(proot-distro list 2>/dev/null \
    | grep -i 'ubuntu' \
    | awk '{print $1}' \
    | sort)

# Guarantee at least the well-known aliases are offered
for _alias in ubuntu-oldlts ubuntu; do
    if ! printf '%s\n' "${UBUNTU_ALIASES[@]}" | grep -qx "$_alias"; then
        UBUNTU_ALIASES+=("$_alias")
    fi
done

printf "\n  ${BOLD}Available Ubuntu versions:${NC}\n"
for i in "${!UBUNTU_ALIASES[@]}"; do
    _a="${UBUNTU_ALIASES[$i]}"
    _tag=""
    case "$_a" in
        ubuntu-oldlts) _tag=" (22.04 LTS)" ;;
        ubuntu)        _tag=" (latest — rolling)" ;;
    esac
    # Mark default
    if [[ "$_a" == "ubuntu-oldlts" ]]; then
        printf "  ${GREEN}[%d] %s%s  ← recommended${NC}\n" "$((i+1))" "$_a" "$_tag"
    else
        printf "  [%d] %s%s\n" "$((i+1))" "$_a" "$_tag"
    fi
done

printf "\n  Enter number [default: ubuntu-oldlts (22.04 LTS)]: "
read -r _choice

# Resolve the selection
UBUNTU_ALIAS=""
if [[ -z "$_choice" ]]; then
    UBUNTU_ALIAS="ubuntu-oldlts"
else
    idx=$((_choice - 1))
    if [[ "$idx" -ge 0 && "$idx" -lt "${#UBUNTU_ALIASES[@]}" ]]; then
        UBUNTU_ALIAS="${UBUNTU_ALIASES[$idx]}"
    else
        warn "Invalid choice '$_choice' — defaulting to ubuntu-oldlts"
        UBUNTU_ALIAS="ubuntu-oldlts"
    fi
fi

ok "Selected: $UBUNTU_ALIAS"

msg "Installing $UBUNTU_ALIAS via proot-distro..."
if proot-distro list 2>/dev/null | grep -q "${UBUNTU_ALIAS}.*Installed"; then
    ok "$UBUNTU_ALIAS is already installed."
else
    proot-distro install "$UBUNTU_ALIAS"
    ok "$UBUNTU_ALIAS installed."
fi

# ══════════════════════════════════════════════════════════════════════
#  4. Copy setup-proot.sh into Ubuntu's filesystem
# ══════════════════════════════════════════════════════════════════════
msg "Checking for setup-proot.sh..."

# Look for setup-proot.sh alongside this script, or in Termux $HOME
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROOT_SCRIPT=""

for candidate in "$SCRIPT_DIR/setup-proot.sh" "$HOME/setup-proot.sh"; do
    if [[ -f "$candidate" ]]; then
        PROOT_SCRIPT="$candidate"
        break
    fi
done

UBUNTU_ROOT="$PREFIX/var/lib/proot-distro/installed-rootfs/$UBUNTU_ALIAS"

if [[ -n "$PROOT_SCRIPT" ]]; then
    cp "$PROOT_SCRIPT" "$UBUNTU_ROOT/root/setup-proot.sh"
    chmod +x "$UBUNTU_ROOT/root/setup-proot.sh"
    ok "setup-proot.sh copied into Ubuntu proot at /root/setup-proot.sh"
else
    warn "setup-proot.sh not found next to this script or in $HOME"
    warn "Place it at $HOME/setup-proot.sh and re-run, or copy it manually:"
    warn "  cp setup-proot.sh $UBUNTU_ROOT/root/setup-proot.sh"
fi

# Also copy backup script if present
for candidate in "$SCRIPT_DIR/proot-backup.sh" "$HOME/proot-backup.sh"; do
    if [[ -f "$candidate" ]]; then
        cp "$candidate" "$HOME/proot-backup.sh"
        chmod +x "$HOME/proot-backup.sh"
        ok "proot-backup.sh placed at ~/proot-backup.sh"
        break
    fi
done

# ══════════════════════════════════════════════════════════════════════
#  5. Configure display resolution presets
# ══════════════════════════════════════════════════════════════════════
msg "Configuring display resolution presets..."

RESOLUTION_CONF="$HOME/.proot-resolutions.conf"

printf "\n  ${BOLD}Set up your resolution presets${NC}\n"
printf "  ${DIM}These will be offered as choices each time you start the desktop.${NC}\n"
printf "  ${DIM}You can add as many as you like (phone, tablet, folding, remote, etc).${NC}\n\n"

# Offer common defaults
printf "  ${BOLD}Common resolutions:${NC}\n"
printf "  ${DIM}  Phone portrait:    1080x2400${NC}\n"
printf "  ${DIM}  Phone landscape:   2400x1080${NC}\n"
printf "  ${DIM}  Fold inner:        1812x2176${NC}\n"
printf "  ${DIM}  Fold outer:        904x2316${NC}\n"
printf "  ${DIM}  Tablet:            1600x2560${NC}\n"
printf "  ${DIM}  Small desktop:     1280x720${NC}\n"
printf "  ${DIM}  Full HD:           1920x1080${NC}\n"
printf "  ${DIM}  QHD:               2560x1440${NC}\n\n"

PRESETS=()
DEFAULT_PRESET=""
_preset_idx=0

while true; do
    _preset_idx=$((_preset_idx + 1))
    if [[ $_preset_idx -eq 1 ]]; then
        printf "  Enter resolution #%d (e.g. 1920x1080) [default: 1920x1080]: " "$_preset_idx"
    else
        printf "  Enter resolution #%d (or press Enter to finish): " "$_preset_idx"
    fi
    read -r _res

    # First entry defaults to 1920x1080
    if [[ -z "$_res" && $_preset_idx -eq 1 ]]; then
        _res="1920x1080"
    elif [[ -z "$_res" ]]; then
        break
    fi

    # Validate format
    if ! echo "$_res" | grep -qE '^[0-9]+x[0-9]+$'; then
        warn "Invalid format '$_res' — use WIDTHxHEIGHT (e.g. 1920x1080)"
        _preset_idx=$((_preset_idx - 1))
        continue
    fi

    # Ask for a label
    printf "  Give it a name (e.g. 'Phone', 'Desktop') [default: Preset %d]: " "$_preset_idx"
    read -r _label
    [[ -z "$_label" ]] && _label="Preset $_preset_idx"

    PRESETS+=("${_label}|${_res}")

    # First preset is the default
    [[ -z "$DEFAULT_PRESET" ]] && DEFAULT_PRESET="$_res"

    ok "Added: $_label → $_res"
done

# If user added nothing, use a sensible default
if [[ ${#PRESETS[@]} -eq 0 ]]; then
    PRESETS=("Full HD|1920x1080")
    DEFAULT_PRESET="1920x1080"
    ok "Using default: Full HD → 1920x1080"
fi

# Write the config file
printf "# Proot Desktop — Resolution Presets\n" > "$RESOLUTION_CONF"
printf "# Format: LABEL|WIDTHxHEIGHT\n" >> "$RESOLUTION_CONF"
printf "# First entry is the default. Edit anytime.\n" >> "$RESOLUTION_CONF"
for p in "${PRESETS[@]}"; do
    echo "$p" >> "$RESOLUTION_CONF"
done
ok "Resolution presets saved to ~/.proot-resolutions.conf"
printf "  ${DIM}(Edit ~/.proot-resolutions.conf anytime to change presets)${NC}\n"

# ══════════════════════════════════════════════════════════════════════
#  6. Create VNC launcher script
# ══════════════════════════════════════════════════════════════════════
msg "Creating VNC launcher: ~/start-ubuntu-vnc.sh"

cat > "$HOME/start-ubuntu-vnc.sh" <<'LAUNCHER'
#!/data/data/com.termux/files/usr/bin/bash
# ─────────────────────────────────────────────────────────────
#  start-ubuntu-vnc.sh — Start Ubuntu proot + TigerVNC server
# ─────────────────────────────────────────────────────────────
#  Usage:
#    bash ~/start-ubuntu-vnc.sh              # interactive resolution picker
#    bash ~/start-ubuntu-vnc.sh 1920x1080    # skip picker, use this resolution
#    bash ~/start-ubuntu-vnc.sh 1920x1080 2  # custom resolution + display number
#
#  Then connect with VNC viewer to localhost:5901
# ─────────────────────────────────────────────────────────────
set -euo pipefail

CONF="$HOME/.proot-resolutions.conf"

pick_resolution() {
    if [[ ! -f "$CONF" ]]; then
        echo "1920x1080"
        return
    fi

    # Read presets (skip comments/blanks)
    local presets=()
    while IFS= read -r line; do
        [[ "$line" =~ ^#.*$ || -z "$line" ]] && continue
        presets+=("$line")
    done < "$CONF"

    if [[ ${#presets[@]} -eq 0 ]]; then
        echo "1920x1080"
        return
    fi

    if [[ ${#presets[@]} -eq 1 ]]; then
        echo "${presets[0]##*|}"
        return
    fi

    echo "" >&2
    echo "  Select resolution:" >&2
    echo "" >&2
    for i in "${!presets[@]}"; do
        local label="${presets[$i]%%|*}"
        local res="${presets[$i]##*|}"
        if [[ $i -eq 0 ]]; then
            printf "  [%d] %-20s %s  ← default\n" "$((i+1))" "$label" "$res" >&2
        else
            printf "  [%d] %-20s %s\n" "$((i+1))" "$label" "$res" >&2
        fi
    done
    echo "" >&2
    printf "  Choice [1]: " >&2
    read -r choice

    if [[ -z "$choice" ]]; then
        echo "${presets[0]##*|}"
    else
        local idx=$((choice - 1))
        if [[ $idx -ge 0 && $idx -lt ${#presets[@]} ]]; then
            echo "${presets[$idx]##*|}"
        else
            echo "${presets[0]##*|}"
        fi
    fi
}

# Allow resolution as first arg, display as second
if [[ -n "${1:-}" && "${1:-}" =~ ^[0-9]+x[0-9]+$ ]]; then
    RESOLUTION="$1"
    DISPLAY_NUM="${2:-1}"
else
    RESOLUTION="$(pick_resolution)"
    DISPLAY_NUM="${1:-1}"
fi

VNC_PORT=$((5900 + DISPLAY_NUM))

echo ""
echo "  Starting Ubuntu Desktop (VNC)..."
echo "  Display:    :${DISPLAY_NUM}"
echo "  Port:       ${VNC_PORT}"
echo "  Resolution: ${RESOLUTION}"
echo ""

# Acquire wake-lock so Android doesn't kill the session
command -v termux-wake-lock &>/dev/null && termux-wake-lock

# Kill any existing VNC server on this display
vncserver -kill ":${DISPLAY_NUM}" 2>/dev/null || true

# Start PulseAudio (for sound forwarding)
pulseaudio --start \
    --load="module-native-protocol-tcp auth-ip-acl=127.0.0.1 auth-anonymous=1" \
    --exit-idle-time=-1 2>/dev/null || true

# Launch proot-distro with Ubuntu and start VNC inside it
# Build proot args: bind USB if the host device path exists
PROOT_ARGS="--shared-tmp"
if [[ -d /dev/bus/usb ]]; then
    PROOT_ARGS="$PROOT_ARGS --bind /dev/bus/usb:/dev/bus/usb"
fi

proot-distro login ubuntu $PROOT_ARGS -- bash -c "
    export DISPLAY=:${DISPLAY_NUM}
    export PULSE_SERVER=127.0.0.1

    # Start dbus if available
    export DBUS_SESSION_BUS_ADDRESS=unix:path=/tmp/dbus-session-bus
    dbus-daemon --session --address=\$DBUS_SESSION_BUS_ADDRESS --nofork --nopidfile 2>/dev/null &

    # Clean stale locks
    rm -f /tmp/.X${DISPLAY_NUM}-lock /tmp/.X11-unix/X${DISPLAY_NUM} 2>/dev/null

    # Start TigerVNC (try no-auth first for local use, fallback to standard)
    vncserver :${DISPLAY_NUM} \
        -geometry ${RESOLUTION} \
        -depth 24 \
        -name 'Ubuntu Desktop' \
        -localhost no \
        -SecurityTypes None \
        --I-KNOW-THIS-IS-INSECURE 2>/dev/null || \
    vncserver :${DISPLAY_NUM} \
        -geometry ${RESOLUTION} \
        -depth 24 \
        -name 'Ubuntu Desktop' \
        -localhost no 2>/dev/null

    echo ''
    echo '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━'
    echo '  ✔ VNC server started!'
    echo \"  Connect to: localhost:${VNC_PORT}\"
    echo \"  Resolution: ${RESOLUTION}\"
    echo ''
    echo '  Sound: plays through Android speakers (PulseAudio TCP)'
    echo '  USB:   OTG devices accessible if Termux has USB permission'
    echo ''
    echo '  Open RealVNC Viewer → New Connection → localhost:${VNC_PORT}'
    echo ''
    echo '  Press Ctrl+C to stop.'
    echo '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━'
    echo ''

    # Keep session alive
    sleep infinity
"
LAUNCHER
chmod +x "$HOME/start-ubuntu-vnc.sh"
sed -i "s|proot-distro login ubuntu|proot-distro login $UBUNTU_ALIAS|g" "$HOME/start-ubuntu-vnc.sh"
ok "VNC launcher created: ~/start-ubuntu-vnc.sh (distro: $UBUNTU_ALIAS)"

# ══════════════════════════════════════════════════════════════════════
#  7. Create Termux:X11 launcher script
# ══════════════════════════════════════════════════════════════════════
msg "Creating Termux:X11 launcher: ~/start-ubuntu-x11.sh"

cat > "$HOME/start-ubuntu-x11.sh" <<'LAUNCHER'
#!/data/data/com.termux/files/usr/bin/bash
# ─────────────────────────────────────────────────────────────
#  start-ubuntu-x11.sh — Start Ubuntu proot + Termux:X11
# ─────────────────────────────────────────────────────────────
#  Usage: bash ~/start-ubuntu-x11.sh
#   Then open the Termux:X11 app on Android
# ─────────────────────────────────────────────────────────────
set -euo pipefail

echo ""
echo "  Starting Ubuntu Desktop (Termux:X11)..."
echo ""

# Acquire wake-lock
command -v termux-wake-lock &>/dev/null && termux-wake-lock

# Kill existing X11 processes
pkill -f "termux.x11" 2>/dev/null || true

# Start PulseAudio
pulseaudio --start \
    --load="module-native-protocol-tcp auth-ip-acl=127.0.0.1 auth-anonymous=1" \
    --exit-idle-time=-1 2>/dev/null || true

# Start Termux:X11 server
termux-x11 :0 &
sleep 2

# Launch the Termux:X11 Android app
am start --user 0 -n com.termux.x11/com.termux.x11.MainActivity 2>/dev/null || \
    echo "  ⚠ Could not auto-launch Termux:X11 app. Open it manually."

# Enter proot and start XFCE
# Build proot args: bind USB if the host device path exists
PROOT_ARGS="--shared-tmp"
if [[ -d /dev/bus/usb ]]; then
    PROOT_ARGS="$PROOT_ARGS --bind /dev/bus/usb:/dev/bus/usb"
fi

proot-distro login ubuntu $PROOT_ARGS -- bash -c "
    export DISPLAY=:0
    export PULSE_SERVER=127.0.0.1

    # Start dbus
    export DBUS_SESSION_BUS_ADDRESS=unix:path=/tmp/dbus-session-bus
    dbus-daemon --session --address=\$DBUS_SESSION_BUS_ADDRESS --nofork --nopidfile 2>/dev/null &

    echo '  Starting XFCE desktop...'
    startxfce4 2>/dev/null
"
LAUNCHER
chmod +x "$HOME/start-ubuntu-x11.sh"
sed -i "s|proot-distro login ubuntu|proot-distro login $UBUNTU_ALIAS|g" "$HOME/start-ubuntu-x11.sh"
ok "Termux:X11 launcher created: ~/start-ubuntu-x11.sh (distro: $UBUNTU_ALIAS)"

# ══════════════════════════════════════════════════════════════════════
#  8. Create stop script
# ══════════════════════════════════════════════════════════════════════
msg "Creating stop script: ~/stop-ubuntu.sh"

cat > "$HOME/stop-ubuntu.sh" <<'STOPPER'
#!/data/data/com.termux/files/usr/bin/bash
# ─────────────────────────────────────────────────────────────
#  stop-ubuntu.sh — Stop Ubuntu proot desktop environment
# ─────────────────────────────────────────────────────────────
echo "  Stopping Ubuntu desktop..."

# Stop VNC
vncserver -kill :1 2>/dev/null && echo "  ✔ VNC server stopped." || true

# Stop Termux:X11
pkill -f "termux.x11" 2>/dev/null && echo "  ✔ Termux:X11 stopped." || true

# Stop PulseAudio
pulseaudio --kill 2>/dev/null && echo "  ✔ PulseAudio stopped." || true

# Release wake-lock
command -v termux-wake-unlock &>/dev/null && termux-wake-unlock && echo "  ✔ Wake-lock released."

echo ""
echo "  ✔ Ubuntu desktop environment stopped."
STOPPER
chmod +x "$HOME/stop-ubuntu.sh"
ok "Stop script created: ~/stop-ubuntu.sh"

# ══════════════════════════════════════════════════════════════════════
#  9. Create shell-only login script
# ══════════════════════════════════════════════════════════════════════
msg "Creating shell-only login: ~/login-ubuntu.sh"

cat > "$HOME/login-ubuntu.sh" <<'LOGIN'
#!/data/data/com.termux/files/usr/bin/bash
# Quick login to Ubuntu proot (no desktop, just a shell)
# Bind USB if available
PROOT_ARGS=""
if [[ -d /dev/bus/usb ]]; then
    PROOT_ARGS="--bind /dev/bus/usb:/dev/bus/usb"
fi
proot-distro login ubuntu $PROOT_ARGS
LOGIN
chmod +x "$HOME/login-ubuntu.sh"
sed -i "s|proot-distro login ubuntu|proot-distro login $UBUNTU_ALIAS|g" "$HOME/login-ubuntu.sh"
ok "Shell login created: ~/login-ubuntu.sh (distro: $UBUNTU_ALIAS)"

# ══════════════════════════════════════════════════════════════════════
#  Done
# ══════════════════════════════════════════════════════════════════════
printf "\n${GREEN}${BOLD}"
printf '═%.0s' {1..60}
printf "\n  Termux setup complete!\n"
printf '═%.0s' {1..60}
printf "${NC}\n\n"

cat <<EOF
  Scripts created:
    ~/start-ubuntu-vnc.sh   — Start desktop via VNC
    ~/start-ubuntu-x11.sh   — Start desktop via Termux:X11
    ~/stop-ubuntu.sh        — Stop the desktop
    ~/login-ubuntu.sh       — Shell-only proot login

  Sound:
    PulseAudio runs in Termux and streams to Android speakers.
    Inside proot, PULSE_SERVER=127.0.0.1 connects to it.
    Works with both VNC and Termux:X11 display methods.
    Use the volume icon in the panel or 'pavucontrol' for mixing.

  USB:
    USB OTG devices are bind-mounted into proot automatically.
    Run 'lsusb' inside proot to see connected USB devices.
    Android may prompt you to grant USB permission to Termux
    when you plug in a device — tap Allow.
    In Termux: 'termux-usb -l' lists USB devices.

  Next steps:

    1. Enter Ubuntu proot:
         proot-distro login $UBUNTU_ALIAS

    2. Run the proot setup script inside Ubuntu:
         bash /root/setup-proot.sh

    3. Exit proot (type 'exit'), then start the desktop:

       VNC (recommended):
         bash ~/start-ubuntu-vnc.sh
         → Connect RealVNC Viewer to localhost:5901

       Termux:X11 (alternative):
         bash ~/start-ubuntu-x11.sh
         → Open the Termux:X11 app

    4. To stop:
         bash ~/stop-ubuntu.sh

EOF
