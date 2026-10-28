#!/usr/bin/env bash
# Vernissage – bring an installed instance up to date.
#
#   ./upgrade.sh                 interactive
#   ./upgrade.sh --yes           no questions (e.g. for cron)
#   ./upgrade.sh --skip-backup   skip the backup before upgrading (not recommended)
#   ./upgrade.sh --no-git        do not update this repository via git
#
# Steps: update this repository (git pull), take a backup, pull new images,
# rebuild local images, recreate changed containers, wait for health checks,
# remove dangling images.
#
# PostgreSQL and Redis are pinned to a major version in docker-compose.yml on
# purpose – a PostgreSQL major upgrade needs a dump/restore and is not done here.

source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
cd "$ROOT_DIR"

ASSUME_YES=false
SKIP_BACKUP=false
SKIP_GIT=false
for arg in "$@"; do
    case "$arg" in
        --yes|-y) ASSUME_YES=true ;;
        --skip-backup) SKIP_BACKUP=true ;;
        --no-git) SKIP_GIT=true ;;
        -h|--help) sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) die "Unknown option: $arg (see --help)" ;;
    esac
done

# confirm, but answers the default automatically with --yes.
proceed() { [[ "$ASSUME_YES" == true ]] && return 0; confirm "$1" "${2:-y}"; }

load_env
detect_docker || die "Docker is not reachable."
[[ -f "$INSTALLED_MARKER" ]] || warn "data/.installed is missing – has ./install.sh been run?"

instance_version() {
    curl -fsS --max-time 10 -H 'Accept: application/json' "http://127.0.0.1:${PROXY_PORT}/api/v1/instance" 2>/dev/null \
        | sed -n -E 's/.*"version" *: *"([^"]+)".*/\1/p'
}

printf '%s\n' "${C_BOLD}Vernissage – upgrade${C_RESET} ($VERNISSAGE_BASEADDRESS)"
old_version="$(instance_version || true)"
info "Running version: ${old_version:-unknown}"

# ---------------------------------------------------------------------------
section "Repository"

if [[ "$SKIP_GIT" == true || "${VI_UPGRADE_REEXEC:-}" == 1 ]]; then
    info "Skipped."
elif ! git -C "$ROOT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    info "Not a git checkout – skipped."
elif ! git -C "$ROOT_DIR" rev-parse --abbrev-ref '@{upstream}' >/dev/null 2>&1; then
    info "No upstream branch configured – skipped."
elif [[ -n "$(git -C "$ROOT_DIR" status --porcelain --untracked-files=no)" ]]; then
    warn "Local changes to tracked files – git pull skipped. Check with: git status"
else
    git -C "$ROOT_DIR" fetch --quiet
    if [[ "$(git -C "$ROOT_DIR" rev-parse HEAD)" == "$(git -C "$ROOT_DIR" rev-parse '@{upstream}')" ]]; then
        ok "Repository is up to date."
    elif proceed "Repository updates are available. Pull them now?" y; then
        git -C "$ROOT_DIR" pull --ff-only
        ok "Repository updated."
        # Continue with the (possibly changed) new version of this script.
        VI_UPGRADE_REEXEC=1 exec "$ROOT_DIR/upgrade.sh" "$@"
    fi
fi

# ---------------------------------------------------------------------------
section "Backup"

if [[ "$SKIP_BACKUP" == true ]]; then
    warn "Backup skipped (--skip-backup)."
else
    "$ROOT_DIR/backup.sh"
fi

# ---------------------------------------------------------------------------
section "Fetching new images"

compose_noin pull --ignore-buildable
compose_noin build --pull

# ---------------------------------------------------------------------------
section "Restarting changed containers"

proceed "Recreate the containers now? (the instance is briefly unavailable)" y || die "Aborted – nothing has been changed apart from the downloaded images."
compose_noin up -d --build --remove-orphans

wait_healthy postgres 120
wait_healthy redis 60
wait_healthy minio 120
wait_healthy api 600
wait_healthy jobs 300
wait_healthy web 180
wait_healthy push 120

# ---------------------------------------------------------------------------
section "Tidying up"

"${DOCKER[@]}" image prune -f >/dev/null
ok "Dangling images removed."

# ---------------------------------------------------------------------------
section "Done"

new_version="$(instance_version || true)"
if [[ -n "$new_version" && "$new_version" == "$old_version" ]]; then
    ok "Vernissage is up to date: $new_version"
else
    ok "Vernissage: ${old_version:-unknown} → ${new_version:-unknown}"
fi
compose_noin ps
