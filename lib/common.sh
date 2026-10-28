#!/usr/bin/env bash
# Shared helper functions for init.sh, install.sh, backup.sh and upgrade.sh.

set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$ROOT_DIR/.env.local"
NGINX_DIR="$ROOT_DIR/nginx"
INSTALLED_MARKER="$ROOT_DIR/data/.installed"
INSTALLATION_FILE="$ROOT_DIR/INSTALLATION.md"

if [[ -t 1 ]]; then
    C_RESET=$'\e[0m'; C_BOLD=$'\e[1m'; C_RED=$'\e[31m'; C_GREEN=$'\e[32m'; C_YELLOW=$'\e[33m'; C_BLUE=$'\e[34m'
else
    C_RESET=''; C_BOLD=''; C_RED=''; C_GREEN=''; C_YELLOW=''; C_BLUE=''
fi

section() { printf '\n%s== %s ==%s\n' "$C_BOLD$C_BLUE" "$*" "$C_RESET"; }
info()    { printf '%s\n' "$*"; }
ok()      { printf '%s✔ %s%s\n' "$C_GREEN" "$*" "$C_RESET"; }
warn()    { printf '%s! %s%s\n' "$C_YELLOW" "$*" "$C_RESET" >&2; }
die()     { printf '%s✘ %s%s\n' "$C_RED" "$*" "$C_RESET" >&2; exit 1; }

trap 'die "Aborted at line $LINENO: $BASH_COMMAND"' ERR

# ask VAR "Question" [default] – reads a value (empty input => default).
ask() {
    local __var="$1" __question="$2" __default="${3-}" __answer
    if [[ -n "$__default" ]]; then
        read -r -p "$__question [$__default]: " __answer || [[ -n "$__answer" ]] || __answer=""
        __answer="${__answer:-$__default}"
    else
        while true; do
            read -r -p "$__question: " __answer || [[ -n "$__answer" ]] || die "No more input available."
            [[ -n "$__answer" ]] && break
            warn "Please enter a value."
        done
    fi
    printf -v "$__var" '%s' "$__answer"
}

# ask_optional VAR "Question" – may be left empty.
ask_optional() {
    local __var="$1" __question="$2" __answer
    read -r -p "$__question (optional): " __answer || true
    printf -v "$__var" '%s' "$__answer"
}

# ask_secret VAR "Question" min max – hidden input with confirmation.
ask_secret() {
    local __var="$1" __question="$2" __min="${3:-8}" __max="${4:-128}" __a __b
    while true; do
        read -r -s -p "$__question: " __a || [[ -n "$__a" ]] || die "No more input available."; echo
        if (( ${#__a} < __min || ${#__a} > __max )); then
            warn "Must be between $__min and $__max characters long."; continue
        fi
        read -r -s -p "Repeat: " __b || true; echo
        [[ "$__a" == "$__b" ]] && break
        warn "The entries do not match."
    done
    printf -v "$__var" '%s' "$__a"
}

# confirm "Question" [y|n] – returns 0 for yes.
confirm() {
    local question="$1" default="${2:-n}" answer hint
    [[ "$default" == y ]] && hint="Y/n" || hint="y/N"
    read -r -p "$question [$hint]: " answer || true
    answer="${answer:-$default}"
    [[ "$answer" =~ ^[Yy] ]]
}

# Random hex string (URL-safe, no escaping issues in connection strings).
gen_hex() { openssl rand -hex "${1:-32}"; }

# Unpadded base64url from stdin.
b64url() { openssl base64 -A | tr '+/' '-_' | tr -d '='; }

# Generates a VAPID key pair (P-256) for Web Push.
# Sets VAPID_PUBLIC_KEY and VAPID_PRIVATE_KEY.
gen_vapid_keys() {
    local pem
    pem="$(openssl ecparam -name prime256v1 -genkey -noout 2>/dev/null)"
    VAPID_PRIVATE_KEY="$(printf '%s\n' "$pem" | openssl ec -outform DER 2>/dev/null | tail -c +8 | head -c 32 | b64url)"
    VAPID_PUBLIC_KEY="$(printf '%s\n' "$pem" | openssl ec -pubout -outform DER 2>/dev/null | tail -c 65 | b64url)"
}

load_env() {
    [[ -f "$ENV_FILE" ]] || die ".env.local is missing – please run ./init.sh first."
    set -a
    # shellcheck disable=SC1090
    source "$ENV_FILE"
    set +a
}

# Call Docker via sudo if the user is not in the docker group.
DOCKER=(docker)
detect_docker() {
    command -v docker >/dev/null 2>&1 || return 1
    if docker info >/dev/null 2>&1; then
        DOCKER=(docker)
    elif command -v sudo >/dev/null 2>&1 && sudo docker info >/dev/null 2>&1; then
        DOCKER=(sudo docker)
    else
        return 1
    fi
    "${DOCKER[@]}" compose version >/dev/null 2>&1
}

compose() {
    (cd "$ROOT_DIR" && "${DOCKER[@]}" compose --env-file "$ENV_FILE" "$@")
}

# Like compose, but never reads from stdin (keeps answers for later prompts intact).
compose_noin() {
    compose "$@" < /dev/null
}

# Runs SQL (from stdin) against the Vernissage database.
psql_exec() {
    compose exec -T postgres psql -v ON_ERROR_STOP=1 -q -t -A \
        -U "$POSTGRES_USER" -d "$POSTGRES_DB" "$@"
}

# Quotes an SQL string literal ('' instead of ').
sql_quote() { local q="'"; printf "'%s'" "${1//$q/$q$q}"; }

# Waits until a Compose service reports "healthy".
wait_healthy() {
    local service="$1" timeout="${2:-300}" waited=0 cid status
    info "Waiting for '$service' (max. ${timeout}s)…"
    while (( waited < timeout )); do
        cid="$(compose ps -q "$service" 2>/dev/null || true)"
        if [[ -n "$cid" ]]; then
            status="$("${DOCKER[@]}" inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$cid" 2>/dev/null || true)"
            if [[ "$status" == healthy ]]; then ok "$service is ready."; return 0; fi
        fi
        sleep 3; waited=$((waited + 3))
    done
    warn "'$service' did not become ready in time. Latest logs:"
    compose logs --tail 40 "$service" >&2 || true
    return 1
}
