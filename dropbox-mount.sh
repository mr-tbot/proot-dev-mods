#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════
#  dropbox-mount.sh — Dropbox access via rclone WebDAV (proot)
#
#  Installs rclone (if needed), guides Dropbox OAuth setup, runs a
#  local WebDAV server so Dropbox appears as a browsable location
#  in Thunar — no files are synced or stored locally.
#
#  FUSE mount is NOT available inside proot (no kernel module), so
#  this script uses rclone's built-in WebDAV server to expose
#  Dropbox over localhost. Thunar connects via gvfs-webdav.
#
#  Run INSIDE the Ubuntu proot:
#    bash /root/dropbox-mount.sh
#
#  Safe to re-run — detects existing config and skips accordingly.
# ═══════════════════════════════════════════════════════════════════════
set -uo pipefail

# ── Colors ────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'
msg()  { printf "\n${CYAN}[*]${NC} %s\n" "$*"; }
ok()   { printf "  ${GREEN}✔${NC} %s\n" "$*"; }
warn() { printf "  ${YELLOW}⚠${NC} %s\n" "$*"; }
err()  { printf "  ${RED}✖${NC} %s\n" "$*"; }
skip() { printf "  ${DIM}─ %s (already done)${NC}\n" "$*"; }

REMOTE_NAME="dropbox"
RCLONE_CONF="$HOME/.config/rclone/rclone.conf"
SCRIPTS_DIR="$HOME/.local/bin"
WEBDAV_PORT=8881
WEBDAV_ADDR="localhost:${WEBDAV_PORT}"
PIDFILE="/tmp/dropbox-webdav.pid"

printf "${BOLD}${CYAN}"
cat <<'BANNER'
  ╔═══════════════════════════════════════════════════════════╗
  ║   Dropbox — rclone WebDAV Mount                           ║
  ║   Browse Dropbox as a network location                    ║
  ╚═══════════════════════════════════════════════════════════╝
BANNER
printf "${NC}\n"

printf "  ${DIM}FUSE mount is not available inside proot (no kernel module).${NC}\n"
printf "  ${DIM}Instead, rclone serves Dropbox as a local WebDAV server.${NC}\n"
printf "  ${DIM}Thunar and CLI tools browse files on-demand — nothing is synced.${NC}\n\n"

# ══════════════════════════════════════════════════════════════════════
#  1. Install rclone
# ══════════════════════════════════════════════════════════════════════
msg "Installing rclone..."

if command -v rclone &>/dev/null; then
    skip "rclone $(rclone --version 2>/dev/null | head -1 | awk '{print $2}')"
else
    if apt-get install -y rclone 2>/dev/null; then
        ok "rclone installed via apt."
    else
        msg "apt package not found — installing via official rclone script..."
        apt-get install -y curl unzip 2>/dev/null || true
        curl -fsSL https://rclone.org/install.sh | bash
        ok "rclone installed via official installer."
    fi
fi

rclone --version 2>/dev/null | head -1 && true

# ══════════════════════════════════════════════════════════════════════
#  2. Install gvfs-backends (WebDAV support for Thunar)
# ══════════════════════════════════════════════════════════════════════
msg "Installing gvfs WebDAV support..."

if dpkg -s gvfs-backends &>/dev/null 2>&1; then
    skip "gvfs-backends"
else
    apt-get install -y gvfs-backends 2>/dev/null && ok "gvfs-backends installed" \
        || warn "gvfs-backends install failed — Thunar WebDAV may not work (CLI still works)"
fi

# ══════════════════════════════════════════════════════════════════════
#  3. Configure rclone Dropbox remote
# ══════════════════════════════════════════════════════════════════════
msg "Configuring Dropbox remote..."

_remote_exists() {
    rclone listremotes 2>/dev/null | grep -q "^${REMOTE_NAME}:$"
}

if _remote_exists; then
    skip "rclone remote '$REMOTE_NAME' already configured"
    printf "\n"
    printf "  ${BOLD}Current remotes:${NC}\n"
    rclone listremotes 2>/dev/null | sed 's/^/    /'
    printf "\n"

    printf "  ${BOLD}Reconfigure?${NC}\n"
    printf "    1) Keep existing config (default)\n"
    printf "    2) Delete and reconfigure\n"
    printf "  ${BOLD}Choice [1]:${NC} "
    read -r _reconfig_choice
    if [[ "${_reconfig_choice:-1}" == "2" ]]; then
        rclone config delete "$REMOTE_NAME"
        ok "Removed old '$REMOTE_NAME' remote."
    fi
fi

if ! _remote_exists; then
    printf "\n"
    printf "  ${BOLD}═══ Dropbox OAuth Setup ═══${NC}\n\n"
    printf "  ${YELLOW}IMPORTANT — READ BEFORE CONTINUING:${NC}\n\n"
    printf "  Since we're in a proot environment, the OAuth browser flow\n"
    printf "  may or may not work directly. Two approaches:\n\n"
    printf "  ${BOLD}Option A — Auto (if Chromium/Chrome works):${NC}\n"
    printf "    rclone config will try to open a browser inside proot.\n"
    printf "    If the VNC desktop is running and Chromium works, this\n"
    printf "    should open the Dropbox sign-in page automatically.\n\n"
    printf "  ${BOLD}Option B — Manual / Remote auth:${NC}\n"
    printf "    During rclone config, when asked about auto config, say ${BOLD}N${NC}.\n"
    printf "    rclone will print a URL — open it in any browser (phone,\n"
    printf "    laptop, etc), sign into Dropbox, paste the token back.\n\n"
    printf "  ${BOLD}How would you like to configure?${NC}\n"
    printf "    1) Interactive (rclone config wizard) — recommended\n"
    printf "    2) Quick auto-config (minimal prompts)\n"
    printf "  ${BOLD}Choice [1]:${NC} "
    read -r _config_choice

    case "${_config_choice:-1}" in
        2)
            msg "Running quick auto-config..."
            printf "\n"
            printf "  ${DIM}This creates a Dropbox remote named '${REMOTE_NAME}'.${NC}\n"
            printf "  ${DIM}You'll be asked to sign into your Dropbox account.${NC}\n"
            printf "  ${DIM}When asked 'Use auto config?', answer based on your setup:${NC}\n"
            printf "  ${DIM}  - Y if VNC desktop + Chromium is running${NC}\n"
            printf "  ${DIM}  - N if running headless (paste token manually)${NC}\n\n"

            rclone config create "$REMOTE_NAME" dropbox \
                --non-interactive 2>/dev/null || true

            if ! rclone lsd "${REMOTE_NAME}:" &>/dev/null 2>&1; then
                warn "Auto-config created the remote but it needs authorization."
                warn "Running 'rclone config reconnect ${REMOTE_NAME}:' ..."
                printf "\n"
                rclone config reconnect "${REMOTE_NAME}:" || {
                    err "Authorization failed. Try option 1 (interactive wizard) instead."
                    rclone config delete "$REMOTE_NAME" 2>/dev/null || true
                }
            fi
            ;;
        *)
            msg "Launching rclone config wizard..."
            printf "\n"
            printf "  ${BOLD}Follow these steps in the wizard:${NC}\n"
            printf "  ${DIM}  1. n  (New remote)${NC}\n"
            printf "  ${DIM}  2. Name: ${REMOTE_NAME}${NC}\n"
            printf "  ${DIM}  3. Storage type: dropbox  (or enter the number for Dropbox)${NC}\n"
            printf "  ${DIM}  4. client_id: (leave blank — press Enter)${NC}\n"
            printf "  ${DIM}  5. client_secret: (leave blank — press Enter)${NC}\n"
            printf "  ${DIM}  6. Edit advanced config? n${NC}\n"
            printf "  ${DIM}  7. Use auto config?${NC}\n"
            printf "  ${DIM}     - Y if desktop+browser available${NC}\n"
            printf "  ${DIM}     - N to get a URL for manual auth${NC}\n"
            printf "  ${DIM}  8. y  (confirm)${NC}\n"
            printf "  ${DIM}  9. q  (quit config)${NC}\n\n"

            rclone config
            ;;
    esac

    if _remote_exists; then
        ok "Dropbox remote '$REMOTE_NAME' configured successfully!"
    else
        warn "Remote '$REMOTE_NAME' was not created."
        warn "You can re-run this script or run 'rclone config' manually."
    fi
fi

# ══════════════════════════════════════════════════════════════════════
#  4. Test connection
# ══════════════════════════════════════════════════════════════════════
if _remote_exists; then
    msg "Testing Dropbox connection..."
    if rclone lsd "${REMOTE_NAME}:" --max-depth 1 2>/dev/null | head -5; then
        ok "Dropbox is accessible! (showing up to 5 top-level folders)"
    else
        warn "Could not list Dropbox contents."
        warn "Check your internet connection or re-run rclone config."
    fi
fi

# ══════════════════════════════════════════════════════════════════════
#  5. Create WebDAV server and CLI wrapper scripts
# ══════════════════════════════════════════════════════════════════════
msg "Creating helper scripts in ~/.local/bin/ ..."

mkdir -p "$SCRIPTS_DIR"

# ── dropbox-start: Launch WebDAV server ──────────────────────────────
cat > "$SCRIPTS_DIR/dropbox-start" <<'STARTSCRIPT'
#!/usr/bin/env bash
# dropbox-start — Start Dropbox WebDAV server
set -uo pipefail
REMOTE="dropbox"
PORT=8881
PIDFILE="/tmp/dropbox-webdav.pid"

if [[ -f "$PIDFILE" ]] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
    echo "✔ Dropbox WebDAV is already running (PID $(cat "$PIDFILE"))"
    echo "  Browse: dav://localhost:${PORT}/"
    exit 0
fi

if ! rclone listremotes 2>/dev/null | grep -q "^${REMOTE}:\$"; then
    echo "✖ rclone remote '${REMOTE}' not configured."
    echo "  Run: bash /root/dropbox-mount.sh"
    exit 1
fi

echo "Starting Dropbox WebDAV server on port ${PORT}..."
nohup rclone serve webdav "${REMOTE}:" \
    --addr "localhost:${PORT}" \
    --read-only=false \
    --vfs-cache-mode writes \
    --vfs-write-back 5s \
    --dir-cache-time 30s \
    --poll-interval 15s \
    --buffer-size 16M \
    --log-file /tmp/dropbox-webdav.log \
    --log-level NOTICE \
    > /dev/null 2>&1 &

echo "$!" > "$PIDFILE"
sleep 2

if kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
    echo "✔ Dropbox is available at: dav://localhost:${PORT}/"
    echo "  Open Thunar → type dav://localhost:${PORT}/ in the address bar"
    echo "  Or use: dbx ls / get / put / rm commands"
    echo "  Stop with: dropbox-stop"
else
    echo "✖ WebDAV server failed to start. Check /tmp/dropbox-webdav.log"
    rm -f "$PIDFILE"
    exit 1
fi
STARTSCRIPT
chmod +x "$SCRIPTS_DIR/dropbox-start"
ok "Created dropbox-start"

# ── dropbox-stop: Stop WebDAV server ────────────────────────────────
cat > "$SCRIPTS_DIR/dropbox-stop" <<'STOPSCRIPT'
#!/usr/bin/env bash
# dropbox-stop — Stop Dropbox WebDAV server
PIDFILE="/tmp/dropbox-webdav.pid"
if [[ -f "$PIDFILE" ]]; then
    PID=$(cat "$PIDFILE")
    if kill -0 "$PID" 2>/dev/null; then
        kill "$PID" 2>/dev/null
        sleep 1
        kill -0 "$PID" 2>/dev/null && kill -9 "$PID" 2>/dev/null
        echo "✔ Dropbox WebDAV stopped."
    else
        echo "WebDAV server was not running."
    fi
    rm -f "$PIDFILE"
else
    pkill -f "rclone serve webdav dropbox:" 2>/dev/null && echo "✔ Stopped." \
        || echo "WebDAV server was not running."
fi
STOPSCRIPT
chmod +x "$SCRIPTS_DIR/dropbox-stop"
ok "Created dropbox-stop"

# ── dbx: CLI wrapper for on-the-fly file operations ─────────────────
cat > "$SCRIPTS_DIR/dbx" <<'DBXCLI'
#!/usr/bin/env bash
# dbx — Dropbox CLI (on-demand, no local sync)
#
# Usage:
#   dbx ls [path]              List files/folders
#   dbx tree [path]            Tree view (2 levels deep)
#   dbx get <remote> [local]   Download file or folder
#   dbx put <local> <remote>   Upload file or folder
#   dbx mkdir <path>           Create a folder on Dropbox
#   dbx rm <path>              Delete a file/folder on Dropbox
#   dbx mv <from> <to>         Move/rename on Dropbox
#   dbx cp <from> <to>         Copy on Dropbox
#   dbx cat <file>             Print file contents to stdout
#   dbx info                   Show Dropbox usage / quota
#   dbx search <name>          Search for files by name
#   dbx open [path]            Open in Thunar via WebDAV
#   dbx start                  Start WebDAV server
#   dbx stop                   Stop WebDAV server
#   dbx status                 Show WebDAV server status
set -uo pipefail
REMOTE="dropbox"
PORT=8881
PIDFILE="/tmp/dropbox-webdav.pid"

_ensure_remote() {
    if ! rclone listremotes 2>/dev/null | grep -q "^${REMOTE}:\$"; then
        echo "✖ rclone remote '${REMOTE}' not configured. Run: bash /root/dropbox-mount.sh"
        exit 1
    fi
}

_webdav_running() {
    [[ -f "$PIDFILE" ]] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null
}

CMD="${1:-help}"
shift 2>/dev/null || true

case "$CMD" in
    ls|list)
        _ensure_remote
        rclone lsf "${REMOTE}:${1:-}" --format "tsp" 2>/dev/null | \
            awk -F';' '{printf "%-12s %-20s %s\n", $1, $2, $3}'
        ;;
    tree)
        _ensure_remote
        rclone tree "${REMOTE}:${1:-}" --max-depth "${2:-2}" 2>/dev/null
        ;;
    get|download)
        _ensure_remote
        SRC="${1:?Usage: dbx get <remote-path> [local-path]}"
        DST="${2:-.}"
        echo "⬇ Downloading ${REMOTE}:${SRC} → ${DST}"
        rclone copy "${REMOTE}:${SRC}" "${DST}" --progress --transfers 4
        echo "✔ Download complete."
        ;;
    put|upload)
        _ensure_remote
        SRC="${1:?Usage: dbx put <local-path> <remote-path>}"
        DST="${2:?Usage: dbx put <local-path> <remote-path>}"
        echo "⬆ Uploading ${SRC} → ${REMOTE}:${DST}"
        rclone copy "${SRC}" "${REMOTE}:${DST}" --progress --transfers 4
        echo "✔ Upload complete."
        ;;
    mkdir)
        _ensure_remote
        DIR="${1:?Usage: dbx mkdir <path>}"
        rclone mkdir "${REMOTE}:${DIR}" && echo "✔ Created ${DIR}"
        ;;
    rm|delete)
        _ensure_remote
        TARGET="${1:?Usage: dbx rm <path>}"
        echo "⚠ Delete ${REMOTE}:${TARGET}?"
        read -p "  Confirm [y/N]: " confirm
        if [[ "${confirm,,}" == "y" ]]; then
            rclone purge "${REMOTE}:${TARGET}" 2>/dev/null \
                || rclone deletefile "${REMOTE}:${TARGET}" 2>/dev/null
            echo "✔ Deleted."
        else
            echo "Cancelled."
        fi
        ;;
    mv|move)
        _ensure_remote
        FROM="${1:?Usage: dbx mv <from> <to>}"
        TO="${2:?Usage: dbx mv <from> <to>}"
        rclone moveto "${REMOTE}:${FROM}" "${REMOTE}:${TO}" && echo "✔ Moved."
        ;;
    cp|copy)
        _ensure_remote
        FROM="${1:?Usage: dbx cp <from> <to>}"
        TO="${2:?Usage: dbx cp <from> <to>}"
        rclone copyto "${REMOTE}:${FROM}" "${REMOTE}:${TO}" --progress && echo "✔ Copied."
        ;;
    cat|view)
        _ensure_remote
        FILE="${1:?Usage: dbx cat <file>}"
        rclone cat "${REMOTE}:${FILE}"
        ;;
    info|about)
        _ensure_remote
        rclone about "${REMOTE}:"
        ;;
    search|find)
        _ensure_remote
        PATTERN="${1:?Usage: dbx search <name-pattern>}"
        echo "Searching for '${PATTERN}'..."
        rclone lsf "${REMOTE}:" --recursive --format "tsp" --include "*${PATTERN}*" 2>/dev/null | \
            awk -F';' '{printf "%-12s %-20s %s\n", $1, $2, $3}' | head -50
        ;;
    open)
        if ! _webdav_running; then
            dropbox-start
        fi
        SUBPATH="${1:-}"
        thunar "dav://localhost:${PORT}/${SUBPATH}" 2>/dev/null &
        ;;
    start)
        dropbox-start "$@"
        ;;
    stop)
        dropbox-stop "$@"
        ;;
    status)
        _ensure_remote
        if _webdav_running; then
            echo "✔ WebDAV server running (PID $(cat "$PIDFILE"))"
            echo "  URL: dav://localhost:${PORT}/"
        else
            echo "○ WebDAV server not running. Start with: dbx start"
        fi
        echo ""
        echo "═══ Dropbox Info ═══"
        rclone about "${REMOTE}:" 2>/dev/null || echo "  (could not connect)"
        echo ""
        echo "Top-level folders:"
        rclone lsd "${REMOTE}:" --max-depth 1 2>/dev/null | awk '{print "  " $NF}' | head -20
        ;;
    help|--help|-h|"")
        echo "dbx — Dropbox CLI (on-demand, no local sync)"
        echo ""
        echo "File operations:"
        echo "  dbx ls [path]              List files/folders"
        echo "  dbx tree [path]            Tree view"
        echo "  dbx get <remote> [local]   Download file or folder"
        echo "  dbx put <local> <remote>   Upload file or folder"
        echo "  dbx mkdir <path>           Create folder on Dropbox"
        echo "  dbx rm <path>              Delete file/folder"
        echo "  dbx mv <from> <to>         Move/rename on Dropbox"
        echo "  dbx cp <from> <to>         Copy on Dropbox"
        echo "  dbx cat <file>             Print file to stdout"
        echo "  dbx search <name>          Search by name"
        echo ""
        echo "Server & GUI:"
        echo "  dbx start                  Start WebDAV server"
        echo "  dbx stop                   Stop WebDAV server"
        echo "  dbx open [path]            Open in Thunar via WebDAV"
        echo "  dbx status                 Show status & quota"
        echo "  dbx info                   Show Dropbox usage/quota"
        ;;
    *)
        echo "Unknown command: $CMD"
        echo "Run 'dbx help' for usage."
        exit 1
        ;;
esac
DBXCLI
chmod +x "$SCRIPTS_DIR/dbx"
ok "Created dbx CLI"

# Ensure ~/.local/bin is in PATH
if ! echo "$PATH" | grep -q "$HOME/.local/bin"; then
    for _rc in "$HOME/.bashrc" "$HOME/.profile"; do
        if [[ -f "$_rc" ]] && ! grep -q '\.local/bin' "$_rc"; then
            printf '\n# Added by dropbox-mount.sh\nexport PATH="$HOME/.local/bin:$PATH"\n' >> "$_rc"
            ok "Added ~/.local/bin to PATH in $(basename "$_rc")"
            break
        fi
    done
    export PATH="$HOME/.local/bin:$PATH"
fi

# ══════════════════════════════════════════════════════════════════════
#  6. Desktop shortcut
# ══════════════════════════════════════════════════════════════════════
msg "Creating desktop shortcut..."

DESKTOP_DIR="$HOME/Desktop"
mkdir -p "$DESKTOP_DIR"

cat > "$DESKTOP_DIR/dropbox.desktop" <<DESKTOP
[Desktop Entry]
Version=1.0
Type=Application
Name=Dropbox
Comment=Open Dropbox via WebDAV (rclone)
Icon=folder-remote
Terminal=false
Exec=bash -c 'dbx open'
Categories=Network;FileTransfer;
StartupNotify=false
DESKTOP
chmod +x "$DESKTOP_DIR/dropbox.desktop"
ok "Created Dropbox desktop shortcut"

# ══════════════════════════════════════════════════════════════════════
#  7. Auto-start WebDAV server on login (optional)
# ══════════════════════════════════════════════════════════════════════
msg "Auto-start setup..."

printf "\n"
printf "  ${BOLD}Start Dropbox WebDAV automatically on login?${NC}\n"
printf "  ${DIM}This starts the rclone WebDAV server in the background${NC}\n"
printf "  ${DIM}so Dropbox is always browsable in Thunar.${NC}\n"
printf "    1) No auto-start (default) — use 'dbx start' manually\n"
printf "    2) Yes — auto-start on login\n"
printf "  ${BOLD}Choice [1]:${NC} "
read -r _autostart_choice

AUTOSTART_MARKER="# dropbox-mount.sh auto-start"
if [[ "${_autostart_choice:-1}" == "2" ]]; then
    if grep -q "$AUTOSTART_MARKER" "$HOME/.bashrc" 2>/dev/null; then
        skip "Auto-start already in .bashrc"
    else
        cat >> "$HOME/.bashrc" <<'AUTOSTART'

# dropbox-mount.sh auto-start
if command -v dropbox-start &>/dev/null && ! [[ -f /tmp/dropbox-webdav.pid ]] || ! kill -0 "$(cat /tmp/dropbox-webdav.pid 2>/dev/null)" 2>/dev/null; then
    dropbox-start >/dev/null 2>&1
fi
AUTOSTART
        ok "Auto-start on login enabled"
    fi
else
    ok "No auto-start. Use 'dbx start' when needed."
fi

# ══════════════════════════════════════════════════════════════════════
#  8. Summary
# ══════════════════════════════════════════════════════════════════════

printf "\n"
printf "${BOLD}${GREEN}"
cat <<'DONE'
  ╔═══════════════════════════════════════════════════════════╗
  ║   Dropbox Setup Complete!                                 ║
  ╚═══════════════════════════════════════════════════════════╝
DONE
printf "${NC}\n"

printf "  ${BOLD}Commands:${NC}\n"
printf "    ${CYAN}dbx start${NC}              Start WebDAV server\n"
printf "    ${CYAN}dbx stop${NC}               Stop WebDAV server\n"
printf "    ${CYAN}dbx open${NC}               Open in Thunar (starts server if needed)\n"
printf "    ${CYAN}dbx status${NC}             Show status & quota\n"
printf "\n"
printf "  ${BOLD}File operations (direct, no sync needed):${NC}\n"
printf "    ${CYAN}dbx ls [path]${NC}          List files/folders\n"
printf "    ${CYAN}dbx get <r> [l]${NC}        Download file or folder\n"
printf "    ${CYAN}dbx put <l> <r>${NC}        Upload file or folder\n"
printf "    ${CYAN}dbx rm <path>${NC}          Delete from Dropbox\n"
printf "    ${CYAN}dbx cat <file>${NC}         Print file to stdout\n"
printf "    ${CYAN}dbx search <name>${NC}      Search by name\n"
printf "    ${CYAN}dbx help${NC}               Full command list\n"
printf "\n"
printf "  ${BOLD}Thunar access:${NC}\n"
printf "    ${DIM}Start server, then type ${CYAN}dav://localhost:${WEBDAV_PORT}/${DIM} in address bar${NC}\n"
printf "    ${DIM}Or click the Dropbox desktop shortcut${NC}\n"
printf "\n"
printf "  ${BOLD}No files are stored locally${NC} — all access is on-demand via WebDAV.\n"
printf "\n"

if _remote_exists; then
    printf "  ${GREEN}✔ Remote '${REMOTE_NAME}' is configured and ready.${NC}\n"
    printf "  ${DIM}Run 'dbx start' then 'dbx open' to browse your Dropbox.${NC}\n"
else
    printf "  ${YELLOW}⚠ Remote not configured yet.${NC}\n"
    printf "  ${DIM}Run 'rclone config' to set up Dropbox access,${NC}\n"
    printf "  ${DIM}then 'dbx start' to begin browsing.${NC}\n"
fi
printf "\n"
