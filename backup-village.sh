#!/usr/bin/env bash
set -euo pipefail

# Daily backup of the village droplet's group-b instance to this machine.
#
# Wraps this repo's backup-and-fetch.sh (run backup.sh on the droplet, rsync
# the tarballs down to ~/village-backups), then prunes both the droplet and
# the local copy to the last KEEP backups. Self-contained: clone this repo and
# run './backup-village.sh setup' to install the systemd user timer.
#
# Usage:
#   ./backup-village.sh now     — run a backup + prune immediately
#   ./backup-village.sh setup   — install + enable the systemd user timer
#
# Retention: keep the last KEEP group-b tarballs (both sides).

SSH_HOST="village-droplet"          # ~/.ssh/config alias -> al@206.189.197.32
INSTANCE="group-b"
KEEP=10

FETCH_SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/backup-and-fetch.sh"
LOCAL_DIR="$HOME/village-backups"
REMOTE_BACKUPS_DIR="/opt/village/instances/${INSTANCE}/backups"
GLOB="village-${INSTANCE}-data-*.tar.gz"

TIMER_NAME="village-backup"

notify() {
    local urgency="$1" summary="$2" body="${3:-}"
    command -v notify-send &>/dev/null && \
        notify-send -u "$urgency" "$summary" "$body" 2>/dev/null || true
}

# Wait for the droplet to be reachable. The timer is Persistent=true, so a
# missed nightly run fires on login -- often before NetworkManager has the
# link up, giving "Network is unreachable". Retry rather than fail hard.
wait_for_server() {
    local max_attempts=10
    local delay=30
    for (( i=1; i<=max_attempts; i++ )); do
        if ssh -o BatchMode=yes -o ConnectTimeout=5 "$SSH_HOST" true &>/dev/null; then
            return 0
        fi
        echo "    attempt $i/$max_attempts -- $SSH_HOST not reachable, retrying in ${delay}s..."
        sleep "$delay"
    done
    return 1
}

# Delete all but the newest $KEEP files matching $GLOB in a local directory.
prune_local() {
    local files
    mapfile -t files < <(ls -1 "$LOCAL_DIR"/$GLOB 2>/dev/null | sort)
    local n=${#files[@]}
    (( n > KEEP )) || { echo "    local: $n backup(s), nothing to prune"; return; }
    local remove=$(( n - KEEP ))
    echo "    local: $n backup(s), removing oldest $remove"
    for f in "${files[@]:0:remove}"; do
        echo "      rm $(basename "$f")"
        rm -f "$f"
    done
}

# Same, on the droplet (files owned by the village user -> sudo).
prune_remote() {
    echo "    remote: pruning to last $KEEP on $SSH_HOST"
    ssh "$SSH_HOST" "sudo bash -s" <<EOF
set -euo pipefail
cd "$REMOTE_BACKUPS_DIR" 2>/dev/null || exit 0
mapfile -t files < <(ls -1 $GLOB 2>/dev/null | sort)
n=\${#files[@]}
if (( n > $KEEP )); then
    remove=\$(( n - $KEEP ))
    echo "      removing oldest \$remove of \$n"
    for f in "\${files[@]:0:remove}"; do
        echo "        rm \$f"
        rm -f "\$f"
    done
else
    echo "      \$n backup(s), nothing to prune"
fi
EOF
}

cmd_now() {
    echo "==> Village backup — $(date -Iseconds)"

    if [[ ! -x "$FETCH_SCRIPT" ]]; then
        echo "ERROR: $FETCH_SCRIPT not found or not executable."
        notify critical "Village backup failed" "Missing $FETCH_SCRIPT"
        exit 1
    fi

    echo "--> Waiting for server connectivity..."
    if ! wait_for_server; then
        echo "ERROR: Could not reach $SSH_HOST after retries. Giving up."
        notify critical "Village backup failed" "Could not reach $SSH_HOST"
        exit 1
    fi

    echo "--> Running backup-and-fetch..."
    "$FETCH_SCRIPT" "$SSH_HOST" "$INSTANCE"

    echo "--> Pruning old backups (keep $KEEP)..."
    prune_remote
    prune_local

    notify normal "Village backup complete" "$(ls -1 "$LOCAL_DIR"/$GLOB 2>/dev/null | wc -l) local archives kept"
    echo "==> Backup complete!"
}

cmd_setup() {
    echo "==> Installing village backup timer"

    local script_path
    script_path="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
    local unit_dir="$HOME/.config/systemd/user"
    mkdir -p "$unit_dir"

    cat > "$unit_dir/${TIMER_NAME}.service" <<EOF
[Unit]
Description=Village droplet backup

[Service]
Type=oneshot
ExecStart=${script_path} now
# don't let a slow/stuck backup run forever
TimeoutStartSec=30m
EOF

    cat > "$unit_dir/${TIMER_NAME}-notify-failure.service" <<EOF
[Unit]
Description=Notify on village backup failure

[Service]
Type=oneshot
ExecStart=notify-send -u critical "Village backup failed" "Check: journalctl --user -u ${TIMER_NAME}"
EOF

    mkdir -p "$unit_dir/${TIMER_NAME}.service.d"
    cat > "$unit_dir/${TIMER_NAME}.service.d/on-failure.conf" <<EOF
[Unit]
OnFailure=${TIMER_NAME}-notify-failure.service
EOF

    cat > "$unit_dir/${TIMER_NAME}.timer" <<EOF
[Unit]
Description=Daily village droplet backup

[Timer]
OnCalendar=*-*-* 03:30:00
RandomizedDelaySec=1h
Persistent=true

[Install]
WantedBy=timers.target
EOF

    systemctl --user daemon-reload
    systemctl --user enable --now "${TIMER_NAME}.timer"

    echo ""
    echo "==> Setup complete!"
    echo "    Timer:   systemctl --user status ${TIMER_NAME}.timer"
    echo "    Run now: $0 now"
}

case "${1:-}" in
    now)   cmd_now ;;
    setup) cmd_setup ;;
    *)     echo "Usage: $(basename "$0") {now|setup}"; exit 1 ;;
esac
