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
#  3. Install Ubuntu 22.04 via proot-distro
# ══════════════════════════════════════════════════════════════════════
msg "Installing Ubuntu via proot-distro..."
if proot-distro list 2>/dev/null | grep -q "ubuntu.*Installed"; then
    ok "Ubuntu is already installed."
else
    proot-distro install ubuntu
    ok "Ubuntu installed."
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

UBUNTU_ROOT="$PREFIX/var/lib/proot-distro/installed-rootfs/ubuntu"

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
#  5. Create VNC launcher script
# ══════════════════════════════════════════════════════════════════════
msg "Creating VNC launcher: ~/start-ubuntu-vnc.sh"

cat > "$HOME/start-ubuntu-vnc.sh" <<'LAUNCHER'
#!/data/data/com.termux/files/usr/bin/bash
# ─────────────────────────────────────────────────────────────
#  start-ubuntu-vnc.sh — Start Ubuntu proot + TigerVNC server
# ─────────────────────────────────────────────────────────────
#  Usage:
#    bash ~/start-ubuntu-vnc.sh              # default: display :1, 1920x1080
#    bash ~/start-ubuntu-vnc.sh 1 1280x720   # custom display + resolution
#
#  Then connect with VNC viewer to localhost:5901
# ─────────────────────────────────────────────────────────────
set -euo pipefail

DISPLAY_NUM="${1:-1}"
VNC_PORT=$((5900 + DISPLAY_NUM))
RESOLUTION="${2:-1920x1080}"

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
PROOT_USB_ARGS=""
if [[ -d /dev/bus/usb ]]; then
    PROOT_USB_ARGS="--bind /dev/bus/usb:/dev/bus/usb"
fi

proot-distro login ubuntu --shared-tmp \$PROOT_USB_ARGS -- bash -c "
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
    echo ''    echo '  Sound: plays through Android speakers (PulseAudio TCP)'
    echo '  USB:   OTG devices accessible if Termux has USB permission'
    echo ''    echo '  Open RealVNC Viewer → New Connection → localhost:${VNC_PORT}'
    echo ''
    echo '  Press Ctrl+C to stop.'
    echo '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━'
    echo ''

    # Keep session alive
    sleep infinity
"
LAUNCHER
chmod +x "$HOME/start-ubuntu-vnc.sh"
ok "VNC launcher created: ~/start-ubuntu-vnc.sh"

# ══════════════════════════════════════════════════════════════════════
#  6. Create Termux:X11 launcher script
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
PROOT_USB_ARGS=""
if [[ -d /dev/bus/usb ]]; then
    PROOT_USB_ARGS="--bind /dev/bus/usb:/dev/bus/usb"
fi

proot-distro login ubuntu --shared-tmp $PROOT_USB_ARGS -- bash -c "
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
ok "Termux:X11 launcher created: ~/start-ubuntu-x11.sh"

# ══════════════════════════════════════════════════════════════════════
#  7. Create stop script
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
#  8. Create shell-only login script
# ══════════════════════════════════════════════════════════════════════
msg "Creating shell-only login: ~/login-ubuntu.sh"

cat > "$HOME/login-ubuntu.sh" <<'LOGIN'
#!/data/data/com.termux/files/usr/bin/bash
# Quick login to Ubuntu proot (no desktop, just a shell)
# Bind USB if available
PROOT_USB_ARGS=""
if [[ -d /dev/bus/usb ]]; then
    PROOT_USB_ARGS="--bind /dev/bus/usb:/dev/bus/usb"
fi
proot-distro login ubuntu $PROOT_USB_ARGS
LOGIN
chmod +x "$HOME/login-ubuntu.sh"
ok "Shell login created: ~/login-ubuntu.sh"

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
         proot-distro login ubuntu

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
