#!/data/data/com.termux/files/usr/bin/bash
# ═══════════════════════════════════════════════════════════════════════
#  proot-backup.sh — Backup & Restore Ubuntu proot environment
#  Run in Termux (NOT inside proot)
#
#  Usage:
#    bash proot-backup.sh backup              # full backup
#    bash proot-backup.sh backup --quick      # skip caches/tmp
#    bash proot-backup.sh restore <file>      # restore from archive
#    bash proot-backup.sh list                # list available backups
#    bash proot-backup.sh info <file>         # show backup details
# ═══════════════════════════════════════════════════════════════════════
set -euo pipefail

# ── Config ────────────────────────────────────────────────────────────
DISTRO="${PROOT_DISTRO:-ubuntu}"
ROOTFS="$PREFIX/var/lib/proot-distro/installed-rootfs/${DISTRO}"
BACKUP_DIR="${PROOT_BACKUP_DIR:-$HOME/storage/shared/proot-backups}"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_NAME="proot-${DISTRO}-${TIMESTAMP}.tar.gz"

# ── Colors ────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'
msg()  { printf "\n${CYAN}[*]${NC} %s\n" "$*"; }
ok()   { printf "  ${GREEN}✔${NC} %s\n" "$*"; }
warn() { printf "  ${YELLOW}⚠${NC} %s\n" "$*"; }
err()  { printf "  ${RED}✖${NC} %s\n" "$*"; }
info() { printf "  ${DIM}ℹ${NC} %s\n" "$*"; }

# ── Helpers ───────────────────────────────────────────────────────────
human_size() {
    local bytes=$1
    if   (( bytes >= 1073741824 )); then printf "%.1f GB" "$(echo "scale=1; $bytes/1073741824" | bc)"
    elif (( bytes >= 1048576 ));    then printf "%.1f MB" "$(echo "scale=1; $bytes/1048576" | bc)"
    elif (( bytes >= 1024 ));       then printf "%.1f KB" "$(echo "scale=1; $bytes/1024" | bc)"
    else printf "%d B" "$bytes"; fi
}

confirm() {
    printf "  ${BOLD}%s${NC} [y/N] " "$1"
    read -r ans
    [[ "${ans,,}" == "y" || "${ans,,}" == "yes" ]]
}

check_rootfs() {
    if [[ ! -d "$ROOTFS" ]]; then
        err "Proot rootfs not found at: $ROOTFS"
        err "Is '${DISTRO}' installed? Check with: proot-distro list"
        exit 1
    fi
}

ensure_backup_dir() {
    if [[ ! -d "$BACKUP_DIR" ]]; then
        # Try to create it — if storage permission isn't granted, fall back
        mkdir -p "$BACKUP_DIR" 2>/dev/null || {
            warn "Cannot create $BACKUP_DIR (run 'termux-setup-storage' first?)"
            BACKUP_DIR="$HOME/proot-backups"
            mkdir -p "$BACKUP_DIR"
            warn "Falling back to: $BACKUP_DIR"
        }
    fi
}

# ── Stop running proot sessions ───────────────────────────────────────
stop_proot_sessions() {
    msg "Checking for running proot sessions..."
    if pgrep -f "proot.*${DISTRO}" >/dev/null 2>&1; then
        warn "Active proot session detected."
        if confirm "Stop it before backup? (recommended)"; then
            # Kill VNC servers inside proot
            proot-distro login "$DISTRO" -- bash -c "vncserver -kill :1 2>/dev/null; true" 2>/dev/null || true
            # Kill proot processes
            pkill -f "proot.*${DISTRO}" 2>/dev/null || true
            sleep 2
            ok "Proot sessions stopped."
        else
            warn "Backing up with an active session may produce an inconsistent snapshot."
            warn "Continuing anyway..."
        fi
    else
        ok "No active proot sessions."
    fi
}

# ══════════════════════════════════════════════════════════════════════
#  BACKUP
# ══════════════════════════════════════════════════════════════════════
do_backup() {
    local quick=0
    [[ "${1:-}" == "--quick" ]] && quick=1

    check_rootfs
    ensure_backup_dir
    stop_proot_sessions

    local backup_path="${BACKUP_DIR}/${BACKUP_NAME}"

    # Calculate source size
    msg "Calculating rootfs size..."
    local rootfs_size
    rootfs_size=$(du -sb "$ROOTFS" 2>/dev/null | awk '{print $1}')
    ok "Rootfs size: $(human_size "$rootfs_size")"

    # Check available space (compressed is usually 30-50% of original)
    local avail_bytes
    avail_bytes=$(df --output=avail -B1 "$(dirname "$backup_path")" 2>/dev/null | tail -1 | tr -d ' ')
    if [[ -n "$avail_bytes" ]] && (( avail_bytes > 0 )); then
        local estimate=$(( rootfs_size / 3 ))  # rough compressed estimate
        ok "Estimated archive size: ~$(human_size "$estimate")"
        ok "Available space: $(human_size "$avail_bytes")"
        if (( estimate > avail_bytes )); then
            err "Not enough free space! Need ~$(human_size "$estimate"), have $(human_size "$avail_bytes")"
            exit 1
        fi
    fi

    echo ""
    info "Distro:      ${DISTRO}"
    info "Source:      ${ROOTFS}"
    info "Destination: ${backup_path}"
    [[ "$quick" -eq 1 ]] && info "Mode:        Quick (skipping caches/tmp)"
    [[ "$quick" -eq 0 ]] && info "Mode:        Full"
    echo ""

    if ! confirm "Start backup?"; then
        echo "Aborted."
        exit 0
    fi

    msg "Creating backup (this may take several minutes)..."

    # Build exclude list
    local excludes=()
    if [[ "$quick" -eq 1 ]]; then
        excludes=(
            --exclude="./tmp/*"
            --exclude="./var/tmp/*"
            --exclude="./var/cache/apt/archives/*.deb"
            --exclude="./var/cache/apt/pkgcache.bin"
            --exclude="./var/cache/apt/srcpkgcache.bin"
            --exclude="./root/.cache/*"
            --exclude="./home/*/.cache/*"
            --exclude="./root/.local/share/Trash/*"
            --exclude="./home/*/.local/share/Trash/*"
            --exclude="./root/.config/Code/Cache*"
            --exclude="./root/.config/Code/CachedData/*"
            --exclude="./root/.config/Code/CachedExtensions/*"
            --exclude="./root/.config/Code/logs/*"
            --exclude="./root/.config/chromium/Default/Cache/*"
            --exclude="./root/.config/chromium/Default/Code Cache/*"
            --exclude="./root/.nvm/.cache/*"
            --exclude="./root/.cargo/registry/cache/*"
            --exclude="./.Trash*"
        )
    fi

    # Always exclude these (meaningless / problematic in backup)
    excludes+=(
        --exclude="./proc/*"
        --exclude="./sys/*"
        --exclude="./dev/*"
    )

    local start_time=$SECONDS

    # Use tar with gzip, preserving permissions and ownership numbers
    cd "$ROOTFS"
    tar -czf "$backup_path" \
        --numeric-owner \
        --preserve-permissions \
        "${excludes[@]}" \
        . 2>&1 | grep -v "Removing leading" || true

    local elapsed=$(( SECONDS - start_time ))
    local archive_size
    archive_size=$(stat -c%s "$backup_path" 2>/dev/null || wc -c < "$backup_path")

    echo ""
    ok "Backup complete!"
    ok "Archive:  ${backup_path}"
    ok "Size:     $(human_size "$archive_size")"
    ok "Time:     ${elapsed}s"

    # Also save a metadata sidecar
    local meta_path="${backup_path%.tar.gz}.meta.txt"
    cat > "$meta_path" <<META
Proot Backup Metadata
═════════════════════
Date:        $(date '+%Y-%m-%d %H:%M:%S %Z')
Distro:      ${DISTRO}
Arch:        $(uname -m)
Mode:        $([ "$quick" -eq 1 ] && echo "quick" || echo "full")
Rootfs size: $(human_size "$rootfs_size")
Archive:     $(human_size "$archive_size")
Duration:    ${elapsed}s
Device:      $(getprop ro.product.model 2>/dev/null || echo "unknown")
Android:     $(getprop ro.build.version.release 2>/dev/null || echo "unknown")
Termux ver:  $(pkg show termux-tools 2>/dev/null | grep Version | head -1 || echo "unknown")
Packages:    $(proot-distro login "$DISTRO" -- dpkg --get-selections 2>/dev/null | wc -l || echo "unknown") installed
META
    ok "Metadata saved: ${meta_path}"

    echo ""
    printf "${BOLD}${CYAN}"
    printf '─%.0s' {1..60}
    printf "\n  How to get the backup off your device:\n"
    printf '─%.0s' {1..60}
    printf "${NC}\n\n"

    _print_extraction_instructions "$backup_path"
}

_print_extraction_instructions() {
    local backup_path="$1"
    local rel_path="${backup_path#$HOME/storage/shared/}"

    echo "  The backup is saved at:"
    echo "    ${backup_path}"
    echo ""

    if [[ "$backup_path" == *"/storage/shared/"* ]]; then
        echo "  Since it's in shared storage, you have several options:"
        echo ""
        echo "  ${BOLD}1. Android File Manager${NC}"
        echo "     Open your file manager app → Internal Storage → proot-backups/"
        echo "     Share/copy the .tar.gz file wherever you need it."
        echo ""
        echo "  ${BOLD}2. USB Transfer${NC}"
        echo "     Connect phone to PC via USB (file transfer mode)."
        echo "     Browse to: Internal Storage/proot-backups/"
        echo "     Copy the .tar.gz file to your computer."
        echo ""
        echo "  ${BOLD}3. ADB Pull (from computer)${NC}"
        echo "     adb pull /sdcard/proot-backups/${BACKUP_NAME} ."
        echo ""
        echo "  ${BOLD}4. Cloud Upload (from Termux)${NC}"
        echo "     # Google Drive via rclone:"
        echo "     pkg install rclone && rclone config"
        echo "     rclone copy \"${backup_path}\" gdrive:proot-backups/"
        echo ""
        echo "     # Or just use a simple HTTP upload:"
        echo "     curl -T \"${backup_path}\" https://your-server.com/upload/"
        echo ""
        echo "  ${BOLD}5. SCP/SFTP (to another machine)${NC}"
        echo "     pkg install openssh"
        echo "     scp \"${backup_path}\" user@yourpc:/path/to/backups/"
        echo ""
        echo "  ${BOLD}6. Share via Android${NC}"
        echo "     termux-share \"${backup_path}\""
        echo "     (Requires termux-api package and Termux:API app)"
        echo ""
    else
        echo "  The backup is in Termux private storage."
        echo "  To make it accessible to other apps or transfer off-device:"
        echo ""
        echo "  ${BOLD}Copy to shared storage:${NC}"
        echo "     termux-setup-storage  # if not done already"
        echo "     cp \"${backup_path}\" ~/storage/shared/proot-backups/"
        echo ""
        echo "  ${BOLD}SCP to another machine:${NC}"
        echo "     pkg install openssh"
        echo "     scp \"${backup_path}\" user@yourpc:/path/to/backups/"
        echo ""
        echo "  ${BOLD}ADB pull:${NC}"
        echo "     # From your computer (requires adb + Termux path):"
        echo "     adb shell \"run-as com.termux cat '${backup_path}'\" > ${BACKUP_NAME}"
        echo ""
    fi
}

# ══════════════════════════════════════════════════════════════════════
#  RESTORE
# ══════════════════════════════════════════════════════════════════════
do_restore() {
    local archive="$1"

    # Resolve path
    if [[ ! -f "$archive" ]]; then
        # Check backup dir
        if [[ -f "${BACKUP_DIR}/${archive}" ]]; then
            archive="${BACKUP_DIR}/${archive}"
        else
            err "File not found: $archive"
            err "Try: bash proot-backup.sh list"
            exit 1
        fi
    fi

    # Validate it's a tar.gz
    if ! file "$archive" 2>/dev/null | grep -qiE 'gzip|tar'; then
        err "File does not appear to be a .tar.gz archive: $archive"
        exit 1
    fi

    local archive_size
    archive_size=$(stat -c%s "$archive" 2>/dev/null || wc -c < "$archive")

    echo ""
    info "Archive:     ${archive}"
    info "Size:        $(human_size "$archive_size")"

    # Show metadata if available
    local meta="${archive%.tar.gz}.meta.txt"
    if [[ -f "$meta" ]]; then
        echo ""
        info "Backup metadata:"
        while IFS= read -r line; do
            info "  $line"
        done < "$meta"
    fi
    echo ""

    # Check if distro already exists
    local existing=0
    if [[ -d "$ROOTFS" ]]; then
        existing=1
        local existing_size
        existing_size=$(du -sb "$ROOTFS" 2>/dev/null | awk '{print $1}')
        warn "An existing '${DISTRO}' rootfs was found ($(human_size "$existing_size"))."
        echo ""
        printf "  ${BOLD}How do you want to restore?${NC}\n"
        printf "    ${CYAN}1)${NC} Wipe and replace (clean restore)\n"
        printf "    ${CYAN}2)${NC} Overwrite on top (merge — keeps files not in backup)\n"
        printf "    ${CYAN}3)${NC} Cancel\n"
        printf "  Choice [1-3]: "
        read -r restore_mode

        case "$restore_mode" in
            1)
                stop_proot_sessions
                msg "Removing existing rootfs..."
                # Use proot-distro reset to cleanly remove
                proot-distro reset "$DISTRO" 2>/dev/null || {
                    warn "proot-distro reset failed — removing manually..."
                    rm -rf "$ROOTFS"
                    mkdir -p "$ROOTFS"
                }
                # proot-distro reset reinstalls a fresh copy; we need to wipe that too
                if [[ -d "$ROOTFS" ]] && [[ "$(ls -A "$ROOTFS" 2>/dev/null)" ]]; then
                    rm -rf "${ROOTFS:?}/"*
                fi
                ok "Existing rootfs removed."
                ;;
            2)
                stop_proot_sessions
                warn "Merging backup on top of existing rootfs."
                warn "Existing files will be overwritten if they exist in the backup."
                if ! confirm "Continue?"; then
                    echo "Aborted."
                    exit 0
                fi
                ;;
            3)
                echo "Aborted."
                exit 0
                ;;
            *)
                err "Invalid choice."
                exit 1
                ;;
        esac
    else
        # Distro not installed — install minimal then overwrite, or just create the dir
        msg "Distro '${DISTRO}' not installed. Creating rootfs directory..."
        mkdir -p "$ROOTFS"
    fi

    msg "Restoring backup (this may take several minutes)..."
    local start_time=$SECONDS

    tar -xzf "$archive" \
        --numeric-owner \
        --preserve-permissions \
        -C "$ROOTFS" 2>&1 | grep -v "Removing leading" || true

    local elapsed=$(( SECONDS - start_time ))

    echo ""
    ok "Restore complete!"
    ok "Time:    ${elapsed}s"
    ok "Rootfs:  ${ROOTFS}"

    # Verify
    msg "Quick verification..."
    if [[ -f "${ROOTFS}/etc/os-release" ]]; then
        ok "OS: $(grep PRETTY_NAME "${ROOTFS}/etc/os-release" | cut -d'"' -f2)"
    fi
    if [[ -x "${ROOTFS}/usr/bin/code" || -L "${ROOTFS}/usr/bin/code" ]]; then
        ok "VSCode: found"
    fi
    if [[ -x "${ROOTFS}/usr/bin/chromium-browser" || -x "${ROOTFS}/usr/bin/chromium" ]]; then
        ok "Chromium: found"
    fi
    if [[ -f "${ROOTFS}/root/.vnc/xstartup" ]]; then
        ok "VNC xstartup: found"
    fi

    echo ""
    info "You can now start the environment:"
    info "  bash ~/start-ubuntu-vnc.sh"
    info "  bash ~/start-ubuntu-x11.sh"
    info ""
    info "Or login to the shell:"
    info "  proot-distro login ${DISTRO}"
}

# ══════════════════════════════════════════════════════════════════════
#  LIST
# ══════════════════════════════════════════════════════════════════════
do_list() {
    ensure_backup_dir

    # Also check Termux-private fallback location
    local dirs=("$BACKUP_DIR")
    [[ "$BACKUP_DIR" != "$HOME/proot-backups" && -d "$HOME/proot-backups" ]] && dirs+=("$HOME/proot-backups")

    local count=0

    for dir in "${dirs[@]}"; do
        if compgen -G "${dir}/proot-*.tar.gz" >/dev/null 2>&1; then
            printf "\n  ${BOLD}Backups in: ${dir}${NC}\n"
            printf "  %-45s %10s  %s\n" "FILENAME" "SIZE" "DATE"
            printf "  ${DIM}"
            printf '─%.0s' {1..70}
            printf "${NC}\n"

            for f in "${dir}"/proot-*.tar.gz; do
                [[ -f "$f" ]] || continue
                local fname=$(basename "$f")
                local fsize=$(stat -c%s "$f" 2>/dev/null || echo 0)
                local fdate=$(stat -c%y "$f" 2>/dev/null | cut -d. -f1 || echo "unknown")
                printf "  %-45s %10s  %s\n" "$fname" "$(human_size "$fsize")" "$fdate"
                count=$((count + 1))
            done
        fi
    done

    if [[ "$count" -eq 0 ]]; then
        warn "No backups found."
        info "Create one with: bash proot-backup.sh backup"
    else
        echo ""
        ok "$count backup(s) found."
        info "Restore with:  bash proot-backup.sh restore <filename>"
        info "Details with:  bash proot-backup.sh info <filename>"
    fi
}

# ══════════════════════════════════════════════════════════════════════
#  INFO
# ══════════════════════════════════════════════════════════════════════
do_info() {
    local archive="$1"

    # Resolve path
    if [[ ! -f "$archive" ]]; then
        [[ -f "${BACKUP_DIR}/${archive}" ]] && archive="${BACKUP_DIR}/${archive}"
        [[ -f "$HOME/proot-backups/${archive}" ]] && archive="$HOME/proot-backups/${archive}"
    fi

    if [[ ! -f "$archive" ]]; then
        err "File not found: $archive"
        exit 1
    fi

    local archive_size
    archive_size=$(stat -c%s "$archive" 2>/dev/null || wc -c < "$archive")
    local archive_date
    archive_date=$(stat -c%y "$archive" 2>/dev/null | cut -d. -f1)

    echo ""
    printf "  ${BOLD}Backup Info${NC}\n"
    printf "  ${DIM}"
    printf '─%.0s' {1..50}
    printf "${NC}\n"
    info "File:     $(basename "$archive")"
    info "Path:     ${archive}"
    info "Size:     $(human_size "$archive_size")"
    info "Modified: ${archive_date}"

    # Show metadata sidecar if available
    local meta="${archive%.tar.gz}.meta.txt"
    if [[ -f "$meta" ]]; then
        echo ""
        printf "  ${BOLD}Saved Metadata${NC}\n"
        printf "  ${DIM}"
        printf '─%.0s' {1..50}
        printf "${NC}\n"
        while IFS= read -r line; do
            [[ "$line" == "═"* || "$line" == "Proot Backup"* ]] && continue
            [[ -n "$line" ]] && info "$line"
        done < "$meta"
    fi

    # Peek inside the archive for key files
    echo ""
    printf "  ${BOLD}Contents Check${NC}\n"
    printf "  ${DIM}"
    printf '─%.0s' {1..50}
    printf "${NC}\n"

    local contents
    contents=$(tar -tzf "$archive" 2>/dev/null | head -500)

    _check_in_archive() {
        local label="$1" pattern="$2"
        if echo "$contents" | grep -q "$pattern"; then
            printf "  ${GREEN}✔${NC} %s\n" "$label"
        else
            printf "  ${DIM}✖ %s${NC}\n" "$label"
        fi
    }

    _check_in_archive "Ubuntu OS"           "etc/os-release"
    _check_in_archive "XFCE desktop"        "usr/bin/startxfce4"
    _check_in_archive "VSCode"              "usr/bin/code"
    _check_in_archive "Chromium"            "usr/bin/chromium"
    _check_in_archive "VNC xstartup"        "root/.vnc/xstartup"
    _check_in_archive "VSCode config"       "root/.config/Code"
    _check_in_archive "XFCE panel config"   "xfce4-panel.xml"
    _check_in_archive "Bash config"         "root/.bashrc"
    _check_in_archive "apt sources"         "etc/apt/sources.list"
    echo ""
}

# ══════════════════════════════════════════════════════════════════════
#  MAIN
# ══════════════════════════════════════════════════════════════════════
usage() {
    cat <<'USAGE'

  Proot Backup & Restore Tool
  ════════════════════════════

  Usage:
    bash proot-backup.sh <command> [options]

  Commands:
    backup              Create a full backup of the proot rootfs
    backup --quick      Backup but skip caches, logs, and temp files
    restore <file>      Restore a backup (file path or name from list)
    list                List all available backups
    info <file>         Show details about a backup archive

  Options:
    PROOT_DISTRO=name   Backup a different distro (default: ubuntu)
    PROOT_BACKUP_DIR=p  Custom backup directory

  Examples:
    bash proot-backup.sh backup
    bash proot-backup.sh backup --quick
    bash proot-backup.sh list
    bash proot-backup.sh restore proot-ubuntu-20260302-143000.tar.gz
    bash proot-backup.sh info proot-ubuntu-20260302-143000.tar.gz
    PROOT_DISTRO=debian bash proot-backup.sh backup

USAGE
}

case "${1:-}" in
    backup)   do_backup "${2:-}" ;;
    restore)
        if [[ -z "${2:-}" ]]; then
            err "Please specify a backup file to restore."
            info "Run 'bash proot-backup.sh list' to see available backups."
            exit 1
        fi
        do_restore "$2"
        ;;
    list)     do_list ;;
    info)
        if [[ -z "${2:-}" ]]; then
            err "Please specify a backup file."
            exit 1
        fi
        do_info "$2"
        ;;
    -h|--help|help) usage ;;
    *)
        usage
        exit 1
        ;;
esac
