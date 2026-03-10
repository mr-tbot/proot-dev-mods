#!/bin/bash
# ╔════════════════════════════════════════════════════════════════════╗
# ║  Browser Repair Script — Proot Ubuntu                           ║
# ║  Reinstalls Chromium v89 (Debian Buster) and/or Firefox         ║
# ║  (Mozilla APT) with proot wrappers and compat libraries.        ║
# ║  Uses the exact same approach as setup-proot.sh Section 3.      ║
# ║                                                                  ║
# ║  Run INSIDE the proot environment:                               ║
# ║    bash /root/chromium-repair.sh                                 ║
# ╚════════════════════════════════════════════════════════════════════╝
set -euo pipefail

# ── Colors ────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; CYAN='\033[0;36m'
BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'

msg()  { printf "  ${CYAN}▸${NC} %s\n" "$*"; }
ok()   { printf "  ${GREEN}✔${NC} %s\n" "$*"; }
warn() { printf "  ${YELLOW}⚠${NC} %s\n" "$*"; }
err()  { printf "  ${RED}✘${NC} %s\n" "$*"; }
die()  { err "$*"; exit 1; }

# ── Repair log ────────────────────────────────────────────────────────
# Everything printed to stdout/stderr is also captured in the log file.
LOG_FILE="/var/log/proot-browser-repair.log"
mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true
exec > >(tee -a "$LOG_FILE") 2>&1
echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "  chromium-repair.sh started: $(date)"
echo "═══════════════════════════════════════════════════════════════"

printf "\n${BOLD}╔════════════════════════════════════════════════════════════╗${NC}\n"
printf "${BOLD}║   Browser Repair — Proot Ubuntu                           ║${NC}\n"
printf "${BOLD}║   Chromium v89 / Firefox / Both                           ║${NC}\n"
printf "${BOLD}╚════════════════════════════════════════════════════════════╝${NC}\n\n"

# ── Must run as root inside proot ─────────────────────────────────────
[[ "$(id -u)" -eq 0 ]] || die "Must run as root. Try: sudo bash $0"

# ── Architecture detection ────────────────────────────────────────────
ARCH="$(dpkg --print-architecture 2>/dev/null || uname -m)"
case "$ARCH" in
    amd64|x86_64)  DEB_ARCH="amd64" ;;
    arm64|aarch64) DEB_ARCH="arm64" ;;
    armhf|armv7*)  DEB_ARCH="armhf" ;;
    *)             DEB_ARCH="arm64"; warn "Unknown arch '$ARCH' — defaulting to arm64" ;;
esac
ok "Architecture: $ARCH (deb: $DEB_ARCH)"

# ── Browser choice ────────────────────────────────────────────────────
printf "\n${BOLD}${CYAN}"
cat <<'BROWSERMENU'
  ┌─────────────────────────────────────────────────────┐
  │   Which browser(s) to repair/reinstall?             │
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
    ok "Repairing: Chromium v89 + Firefox"
elif [[ "$INSTALL_CHROMIUM" -eq 1 ]]; then
    ok "Repairing: Chromium v89"
else
    ok "Repairing: Firefox"
fi


# ══════════════════════════════════════════════════════════════════════
#  PHASE 1: Cleanup — snap browser stubs + old browser remnants
# ══════════════════════════════════════════════════════════════════════
printf "\n${BOLD}Phase 1: Cleanup — snap browser stubs + old browser remnants...${NC}\n\n"

# Remove snap-installed browsers (snap stubs that don't work in proot)
if command -v snap >/dev/null 2>&1; then
    msg "Removing snap browser packages..."
    snap remove --purge firefox 2>/dev/null || true
    snap remove --purge chromium 2>/dev/null || true
    ok "Snap browser packages removed"
fi

# Remove snap stubs for chromium (always safe — we never want these)
msg "Removing chromium snap stubs..."
apt-get purge -y chromium-browser chromium-browser-l10n \
    chromium-codecs-ffmpeg chromium-codecs-ffmpeg-extra 2>/dev/null || true

# For Firefox: ONLY purge if it's a snap stub (preserve working Mozilla APT installs)
_ff_is_snap_stub=0
if dpkg -s firefox 2>/dev/null | grep -q "Status: install ok installed"; then
    if head -20 /usr/bin/firefox 2>/dev/null | grep -qi "snap"; then
        _ff_is_snap_stub=1
    elif ! [[ -f /etc/apt/sources.list.d/mozilla-firefox.list ]]; then
        # Installed but no Mozilla repo configured → Ubuntu's snap stub
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
ok "Snap browser stubs removed"

# Remove any existing Chromium (to do a clean reinstall)
msg "Removing existing Chromium packages..."
apt-mark unhold chromium chromium-common 2>/dev/null || true
dpkg --purge --force-depends chromium chromium-common 2>/dev/null || true
# Clean up old wrapper artifacts from previous runs
rm -f /usr/bin/chromium.real 2>/dev/null || true
ok "Old Chromium removed"

# Clean up old repo configs
# NOTE: Only delete Buster + Chrome repos (these contaminate apt).
# Mozilla Firefox repo/key/pin are NOT stale — they are set up by this
# script and needed for Firefox updates. Do NOT delete them.
rm -f /etc/apt/sources.list.d/debian-chromium.list 2>/dev/null || true
rm -f /etc/apt/sources.list.d/google-chrome.list 2>/dev/null || true
rm -f /etc/apt/preferences.d/debian-chromium.pref 2>/dev/null || true
rm -f /usr/share/keyrings/debian-archive-all.gpg 2>/dev/null || true
rm -f /usr/share/keyrings/google-chrome.gpg 2>/dev/null || true
rm -f /etc/apt/trusted.gpg.d/debian*.gpg 2>/dev/null || true

apt-get autoremove -y 2>/dev/null || true
ok "All old configs cleaned"


# ══════════════════════════════════════════════════════════════════════
#  PHASE 2: Block snap-stub chromium packages permanently
# ══════════════════════════════════════════════════════════════════════
printf "\n${BOLD}Phase 2: Blocking snap-stub chromium packages permanently...${NC}\n\n"

# Block snapd from being installed/upgraded (useless in proot)
cat > /etc/apt/preferences.d/no-snapd.pref <<'NOSNAPD'
Package: snapd
Pin: release *
Pin-Priority: -10
NOSNAPD
ok "snapd blocked permanently"

cat > /etc/apt/preferences.d/no-snap-chromium.pref <<'NOSNAPCHROM'
Package: chromium-browser chromium-browser-l10n chromium-codecs-ffmpeg chromium-codecs-ffmpeg-extra
Pin: release o=Ubuntu
Pin-Priority: -1

Package: chromium-browser chromium-browser-l10n chromium-codecs-ffmpeg chromium-codecs-ffmpeg-extra
Pin: release *
Pin-Priority: -10
NOSNAPCHROM

ok "snapd + snap browser stubs blocked permanently"

# Block Ubuntu's firefox snap-stub package
# (we install the real Firefox from Mozilla's official APT repo instead)
cat > /etc/apt/preferences.d/no-snap-firefox.pref <<'NOSNAPFF'
Package: firefox
Pin: release o=Ubuntu
Pin-Priority: -1
NOSNAPFF
ok "Ubuntu firefox snap stub blocked permanently"

# Fix broken dpkg state
dpkg --configure -a 2>/dev/null || true
apt-get clean 2>/dev/null || true


# ── Chromium v89 Repair ──────────────────────────────────────────────
if [[ "$INSTALL_CHROMIUM" -eq 1 ]]; then

# ══════════════════════════════════════════════════════════════════════
#  PHASE 3: Prepare for Chromium download
# ══════════════════════════════════════════════════════════════════════
printf "\n${BOLD}Phase 3: Preparing Chromium v89 download...${NC}\n\n"

# NOTE: We download .debs directly from archive.debian.org via wget.
# No Debian Buster apt repo is added — doing so would contaminate apt's
# package database with thousands of old Buster packages and cause
# dependency conflicts with Ubuntu packages.
# Clean up any leftover Buster repo from previous runs.
rm -f /etc/apt/sources.list.d/debian-chromium.sources /etc/apt/sources.list.d/debian-chromium.list 2>/dev/null || true
ok "Buster repo cleanup complete"

# Ensure Ubuntu's libxml2 is installed (Chromium links libxml2.so.2,
# which is the same soname Ubuntu provides — just needs to be present)
apt-get install -y libxml2 2>/dev/null || true


# ══════════════════════════════════════════════════════════════════════
#  PHASE 4: Download Chromium v89 + compat libraries
# ══════════════════════════════════════════════════════════════════════
printf "\n${BOLD}Phase 4: Downloading Chromium v89 + Buster compat libraries...${NC}\n\n"

# Ubuntu has newer library sonames than Debian Buster.  We download the
# specific Buster compat libraries — they coexist safely alongside
# Ubuntu's own libs because they have different soname versions.

_DEB_DIR="/tmp/chromium-debs"
rm -rf "$_DEB_DIR" && mkdir -p "$_DEB_DIR"
_BASE="http://archive.debian.org/debian/pool/main"

# Chromium itself (v89, Debian Buster build)
msg "Downloading Chromium v89 .debs..."
wget -q "${_BASE}/c/chromium/chromium_89.0.4389.114-1~deb10u1_${DEB_ARCH}.deb"             -O "$_DEB_DIR/chromium.deb" && ok "chromium.deb" || die "Failed to download chromium.deb"
wget -q "${_BASE}/c/chromium/chromium-common_89.0.4389.114-1~deb10u1_${DEB_ARCH}.deb"      -O "$_DEB_DIR/common.deb"   && ok "common.deb"   || die "Failed to download common.deb"

# Compat libraries from Debian Buster (different sonames from Ubuntu)
msg "Downloading Buster compat libraries..."
wget -q "${_BASE}/libe/libevent/libevent-2.1-6_2.1.8-stable-4_${DEB_ARCH}.deb"             -O "$_DEB_DIR/libevent-2.1-6.deb"   && ok "libevent-2.1-6"
wget -q "${_BASE}/i/icu/libicu63_63.1-6+deb10u3_${DEB_ARCH}.deb"                           -O "$_DEB_DIR/libicu63.deb"          && ok "libicu63"
wget -q "${_BASE}/libj/libjsoncpp/libjsoncpp1_1.7.4-3_${DEB_ARCH}.deb"                     -O "$_DEB_DIR/libjsoncpp1.deb"       && ok "libjsoncpp1"
wget -q "${_BASE}/r/re2/libre2-5_20190101+dfsg-2_${DEB_ARCH}.deb"                          -O "$_DEB_DIR/libre2-5.deb"          && ok "libre2-5"
wget -q "${_BASE}/libv/libvpx/libvpx5_1.7.0-3+deb10u1_${DEB_ARCH}.deb"                     -O "$_DEB_DIR/libvpx5.deb"           && ok "libvpx5"
wget -q "${_BASE}/f/ffmpeg/libavcodec58_4.1.9-0+deb10u1_${DEB_ARCH}.deb"                   -O "$_DEB_DIR/libavcodec58.deb"      && ok "libavcodec58"
wget -q "${_BASE}/f/ffmpeg/libavformat58_4.1.9-0+deb10u1_${DEB_ARCH}.deb"                  -O "$_DEB_DIR/libavformat58.deb"     && ok "libavformat58"
wget -q "${_BASE}/f/ffmpeg/libavutil56_4.1.9-0+deb10u1_${DEB_ARCH}.deb"                    -O "$_DEB_DIR/libavutil56.deb"       && ok "libavutil56"
wget -q "${_BASE}/f/ffmpeg/libswresample3_4.1.9-0+deb10u1_${DEB_ARCH}.deb"                 -O "$_DEB_DIR/libswresample3.deb"    && ok "libswresample3"
wget -q "${_BASE}/a/aom/libaom0_1.0.0-3_${DEB_ARCH}.deb"                                   -O "$_DEB_DIR/libaom0.deb"           && ok "libaom0"
wget -q "${_BASE}/c/codec2/libcodec2-0.8.1_0.8.1-2_${DEB_ARCH}.deb"                        -O "$_DEB_DIR/libcodec2-0.8.1.deb"   && ok "libcodec2-0.8.1"
wget -q "${_BASE}/x/x264/libx264-155_0.155.2917+git0a84d98-2_${DEB_ARCH}.deb"              -O "$_DEB_DIR/libx264-155.deb"       && ok "libx264-155"
wget -q "${_BASE}/x/x265/libx265-165_2.9-4_${DEB_ARCH}.deb"                                -O "$_DEB_DIR/libx265-165.deb"       && ok "libx265-165"
wget -q "${_BASE}/libs/libssh/libssh-gcrypt-4_0.8.7-1+deb10u1_${DEB_ARCH}.deb"             -O "$_DEB_DIR/libssh-gcrypt-4.deb"   && ok "libssh-gcrypt-4"

# Additional compat libraries — Chromium v89 links these sonames which
# differ between Buster and Ubuntu (without these, Chromium crashes
# with "cannot open shared object file")
wget -q "${_BASE}/libw/libwebp/libwebp6_0.6.1-2+deb10u1_${DEB_ARCH}.deb"                  -O "$_DEB_DIR/libwebp6.deb" \
    || wget -q "${_BASE}/libw/libwebp/libwebp6_0.6.1-2_${DEB_ARCH}.deb"                    -O "$_DEB_DIR/libwebp6.deb"
[[ -s "$_DEB_DIR/libwebp6.deb" ]] && ok "libwebp6" || err "libwebp6 download failed"
wget -q "${_BASE}/libj/libjpeg-turbo/libjpeg62-turbo_1.5.2-2+deb10u1_${DEB_ARCH}.deb"      -O "$_DEB_DIR/libjpeg62-turbo.deb" \
    || wget -q "${_BASE}/libj/libjpeg-turbo/libjpeg62-turbo_1.5.2-2+b1_${DEB_ARCH}.deb"    -O "$_DEB_DIR/libjpeg62-turbo.deb" \
    || wget -q "${_BASE}/libj/libjpeg-turbo/libjpeg62-turbo_1.5.2-2_${DEB_ARCH}.deb"       -O "$_DEB_DIR/libjpeg62-turbo.deb"
[[ -s "$_DEB_DIR/libjpeg62-turbo.deb" ]] && ok "libjpeg62-turbo" || err "libjpeg62-turbo download failed"
wget -q "${_BASE}/f/flac/libflac8_1.3.2-3+deb10u1_${DEB_ARCH}.deb"                         -O "$_DEB_DIR/libflac8.deb" \
    || wget -q "${_BASE}/f/flac/libflac8_1.3.2-3_${DEB_ARCH}.deb"                          -O "$_DEB_DIR/libflac8.deb"
[[ -s "$_DEB_DIR/libflac8.deb" ]] && ok "libflac8" || err "libflac8 download failed"

# Verify all downloads (wget -q hides failures silently)
_DOWNLOAD_OK=1
for _f in "$_DEB_DIR"/*.deb; do
    if [[ ! -s "$_f" ]]; then
        err "Download failed or empty: $(basename "$_f")"
        _DOWNLOAD_OK=0
    fi
done
if [[ "$_DOWNLOAD_OK" -eq 1 ]]; then
    ok "All .deb files downloaded ($(ls "$_DEB_DIR"/*.deb 2>/dev/null | wc -l) files)"
else
    die "Some .deb downloads failed — check network and retry."
fi


# ══════════════════════════════════════════════════════════════════════
#  PHASE 5: Install compat libraries
# ══════════════════════════════════════════════════════════════════════
printf "\n${BOLD}Phase 5: Installing Buster compat libraries...${NC}\n\n"

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
ok "Buster compat libraries installed"


# ══════════════════════════════════════════════════════════════════════
#  PHASE 6: Install Chromium v89
# ══════════════════════════════════════════════════════════════════════
printf "\n${BOLD}Phase 6: Installing Chromium v89...${NC}\n\n"

dpkg --force-depends -i "$_DEB_DIR/common.deb" "$_DEB_DIR/chromium.deb" 2>&1

if ! dpkg -s chromium 2>/dev/null | grep -q "Status: install ok installed"; then
    die "Chromium installation failed!"
fi
ok "Chromium v89 installed: $(dpkg -s chromium 2>/dev/null | grep ^Version | head -1)"


# ══════════════════════════════════════════════════════════════════════
#  PHASE 7: Fix gdk-pixbuf symlink
# ══════════════════════════════════════════════════════════════════════
printf "\n${BOLD}Phase 7: Fixing gdk-pixbuf symlink...${NC}\n\n"

_LIBDIR="/usr/lib/aarch64-linux-gnu"
[[ "$DEB_ARCH" == "amd64" ]]  && _LIBDIR="/usr/lib/x86_64-linux-gnu"
[[ "$DEB_ARCH" == "armhf" ]]  && _LIBDIR="/usr/lib/arm-linux-gnueabihf"
_GDK_REAL="$(ls "${_LIBDIR}"/libgdk_pixbuf-2.0.so.0.* 2>/dev/null | head -1)"
if [[ -n "$_GDK_REAL" ]]; then
    ln -sf "$_GDK_REAL" "${_LIBDIR}/libgdk_pixbuf-2.0.so.0"
    ldconfig
    ok "gdk-pixbuf symlink fixed → $(basename "$_GDK_REAL")"
else
    warn "Could not find libgdk_pixbuf .so — symlink not created"
fi


# ══════════════════════════════════════════════════════════════════════
#  PHASE 8: Verify no missing libraries
# ══════════════════════════════════════════════════════════════════════
printf "\n${BOLD}Phase 8: Verifying no missing libraries...${NC}\n\n"

_missing="$(ldd /usr/lib/chromium/chromium 2>&1 | grep 'not found' || true)"
if [[ -z "$_missing" ]]; then
    ok "No missing libraries — Chromium binary is ready"
else
    warn "Missing libraries detected:"
    echo "$_missing"
fi


# ══════════════════════════════════════════════════════════════════════
#  PHASE 9: Configure proot flags
# ══════════════════════════════════════════════════════════════════════
printf "\n${BOLD}Phase 9: Configuring proot flags...${NC}\n\n"

# The Debian Chromium launcher (/usr/bin/chromium) sources all files in
# /etc/chromium.d/ as shell scripts.  We add a proot-specific config.
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


# ══════════════════════════════════════════════════════════════════════
#  PHASE 10: Ensure stock Chromium launcher is intact
# ══════════════════════════════════════════════════════════════════════
printf "\n${BOLD}Phase 10: Ensuring stock launcher is intact...${NC}\n\n"

# The stock Debian launcher (/usr/bin/chromium) sources /etc/chromium.d/*
# and then exec's the ELF binary.  All proot flags are injected via
# /etc/chromium.d/proot-flags — no wrapper is needed.

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


# ══════════════════════════════════════════════════════════════════════
#  PHASE 11: Ensure runtime directories + hold packages
# ══════════════════════════════════════════════════════════════════════
printf "\n${BOLD}Phase 11: Runtime dirs + package hold...${NC}\n\n"

mkdir -p /dev/shm && chmod 1777 /dev/shm
mkdir -p /tmp/runtime-root && chmod 700 /tmp/runtime-root
ok "Runtime directories ensured (/dev/shm, /tmp/runtime-root)"

# CRITICAL: Hold ALL Buster packages to prevent apt-get install -f from
# removing the force-installed compat libs (which it treats as "broken").
apt-mark hold \
    chromium chromium-common \
    libevent-2.1-6 libicu63 libjsoncpp1 libre2-5 libvpx5 \
    libavcodec58 libavformat58 libavutil56 libswresample3 \
    libaom0 libcodec2-0.8.1 libx264-155 libx265-165 \
    libssh-gcrypt-4 \
    libwebp6 libjpeg62-turbo libflac8 2>/dev/null || true
ok "Chromium + 17 Buster compat packages held (protected from apt-get install -f)"

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

# ── Chromium smoke test ───────────────────────────────────────────────
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

# .desktop file — stock launcher sources proot-flags automatically
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
ok "Chromium .desktop file written"

update-desktop-database /usr/share/applications 2>/dev/null || true

# Clean up downloaded .debs
rm -rf "$_DEB_DIR"

fi  # end INSTALL_CHROMIUM

# Safety: ensure Debian Buster repo is never left behind
rm -f /etc/apt/sources.list.d/debian-chromium.sources /etc/apt/sources.list.d/debian-chromium.list 2>/dev/null || true


# ── Firefox Repair (Mozilla APT) ─────────────────────────────────────
if [[ "$INSTALL_FIREFOX" -eq 1 ]]; then

printf "\n${BOLD}Firefox Repair: Installing from Mozilla APT...${NC}\n\n"

# Remove old Firefox ONLY if it's a snap stub or the user explicitly
# chose to repair Firefox (this section only runs when INSTALL_FIREFOX=1).
# Because this is a repair script, we do a clean reinstall of Firefox.
msg "Removing old Firefox for clean reinstall..."
# Only purge the dpkg package if it's actually installed
if dpkg -s firefox 2>/dev/null | grep -q "Status: install ok installed"; then
    apt-get purge -y firefox 2>/dev/null || true
fi
for _bin in /usr/bin/firefox; do
    if [[ -f "$_bin" ]] && head -20 "$_bin" 2>/dev/null | grep -qi "snap"; then
        rm -f "$_bin"
    fi
done
rm -f /usr/bin/firefox.real 2>/dev/null || true
ok "Old Firefox removed"

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
    ok "Mozilla GPG key added"
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

msg "Updating apt..."
apt-get update 2>&1 | tail -5
ok "apt updated"

msg "Installing Firefox..."
DEBIAN_FRONTEND=noninteractive apt-get install -y \
    -o Dpkg::Options::="--force-confdef" \
    -o Dpkg::Options::="--force-confold" \
    firefox 2>&1

if ! dpkg -s firefox 2>/dev/null | grep -q "Status: install ok installed"; then
    die "Firefox installation failed!"
fi
ok "Firefox installed: $(firefox --version 2>/dev/null || echo 'ok')"

# Create proot wrapper
msg "Creating Firefox proot wrapper..."
FIREFOX_BIN="/usr/bin/firefox"
FIREFOX_REAL="${FIREFOX_BIN}.real"
if [[ ! -f "$FIREFOX_REAL" ]]; then
    cp "$FIREFOX_BIN" "$FIREFOX_REAL"
    chmod +x "$FIREFOX_REAL"
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
ok "Firefox proot wrapper created"

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
ok "Firefox .desktop file written"

update-desktop-database /usr/share/applications 2>/dev/null || true

fi  # end INSTALL_FIREFOX


# ══════════════════════════════════════════════════════════════════════
#  Final verification
# ══════════════════════════════════════════════════════════════════════
printf "\n${BOLD}Final verification...${NC}\n\n"

PASS=0; FAIL=0
_verify() {
    local label="$1" cmd="$2"
    if eval "$cmd" >/dev/null 2>&1; then
        ok "$label"; PASS=$((PASS + 1))
    else
        err "$label"; FAIL=$((FAIL + 1))
    fi
}

_verify "snap stubs blocked"           "test -f /etc/apt/preferences.d/no-snap-chromium.pref"
_verify "Firefox snap blocked"         "test -f /etc/apt/preferences.d/no-snap-firefox.pref"
_verify "snapd blocked"               "test -f /etc/apt/preferences.d/no-snapd.pref"
_verify "/dev/shm exists"             "test -d /dev/shm"

if [[ "$INSTALL_CHROMIUM" -eq 1 ]]; then
_verify "chromium binary exists"       "test -f /usr/lib/chromium/chromium"
_verify "chromium NOT snap stub"       "! head -20 /usr/bin/chromium 2>/dev/null | grep -qi snap"
_verify "chromium no missing libs"     "test -z \"\$(ldd /usr/lib/chromium/chromium 2>&1 | grep 'not found')\""
_verify "proot-flags config exists"    "test -f /etc/chromium.d/proot-flags"
_verify "proot-flags has --no-sandbox" "grep -q 'no-sandbox' /etc/chromium.d/proot-flags"
_verify "stock launcher intact"        "head -20 /usr/bin/chromium 2>/dev/null | grep -q 'chromium.d\|CHROMIUM_FLAGS'"
_verify "no old wrapper artifact"      "test ! -f /usr/bin/chromium.real"
_verify "chromium-default exists"      "test -f /usr/local/bin/chromium-default"
_verify "chromium .desktop exists"     "test -f /usr/share/applications/chromium.desktop"
_verify "chromium packages held"       "apt-mark showhold 2>/dev/null | grep -q chromium"
_verify "Buster repo removed"          "test ! -f /etc/apt/sources.list.d/debian-chromium.sources"
fi

if [[ "$INSTALL_FIREFOX" -eq 1 ]]; then
_verify "firefox binary exists"        "command -v firefox"
_verify "firefox NOT snap stub"        "! head -20 /usr/bin/firefox 2>/dev/null | grep -qi snap"
_verify "firefox wrapper active"       "head -5 /usr/bin/firefox 2>/dev/null | grep -q MOZ_FAKE_NO_SANDBOX"
_verify "firefox .desktop exists"      "test -f /usr/share/applications/firefox.desktop"
_verify "Mozilla APT repo configured"  "test -f /etc/apt/sources.list.d/mozilla-firefox.list"
fi

printf "\n  ─────────────────────────────────────────────\n"
if [[ "$FAIL" -eq 0 ]]; then
    printf "  ${GREEN}${BOLD}ALL ${PASS} CHECKS PASSED${NC}\n"
else
    printf "  ${GREEN}${PASS} passed${NC}, ${RED}${FAIL} failed${NC}\n"
fi

printf "\n${BOLD}  Launch:${NC}\n"
if [[ "$INSTALL_CHROMIUM" -eq 1 ]]; then
    printf "    chromium\n"
fi
if [[ "$INSTALL_FIREFOX" -eq 1 ]]; then
    printf "    firefox\n"
fi
printf "\n"

printf "${DIM}  Harmless proot warnings (ignore these):${NC}\n"
printf "${DIM}    - Could not bind NETLINK socket: Permission denied${NC}\n"
printf "${DIM}    - Failed to connect to the bus: /run/dbus/system_bus_socket${NC}\n"
printf "${DIM}    - Failed to initialize a udev monitor${NC}\n"
printf "${DIM}    - Floss manager not present${NC}\n"
printf "${DIM}    - Fontconfig error: out of memory${NC}\n"
printf "${DIM}    - getcwd() failed${NC}\n\n"
