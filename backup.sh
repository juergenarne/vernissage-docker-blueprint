#!/usr/bin/env bash
# Vernissage – backup of database, images (MinIO) and configuration.
#
#   ./backup.sh              backup to backups/<timestamp>/
#   KEEP_DAYS=14 ./backup.sh delete older backups automatically (default: 7)
#
# Backups contain secrets (.env.local) – protect the target directory accordingly
# and also keep a copy off the server.

source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
cd "$ROOT_DIR"

load_env
detect_docker || die "Docker is not reachable."

KEEP_DAYS="${KEEP_DAYS:-7}"
target="$ROOT_DIR/backups/$(date +%Y%m%d-%H%M%S)"
umask 077
mkdir -p "$target"

section "PostgreSQL"
compose exec -T postgres pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Fc > "$target/postgres.dump"
ok "postgres.dump ($(du -h "$target/postgres.dump" | cut -f1))"

section "MinIO data"
tar -C "$ROOT_DIR/data" -czf "$target/minio.tar.gz" minio 2>/dev/null \
    || "${DOCKER[@]}" run --rm -v "$ROOT_DIR/data:/data:ro" alpine:3.22 tar -C /data -cz minio > "$target/minio.tar.gz"
ok "minio.tar.gz ($(du -h "$target/minio.tar.gz" | cut -f1))"

section "Configuration"
cp "$ENV_FILE" "$target/env.local"
tar -C "$ROOT_DIR" -czf "$target/config.tar.gz" nginx $( [[ -f "$INSTALLATION_FILE" ]] && echo INSTALLATION.md )
ok "env.local, config.tar.gz (nginx/, INSTALLATION.md)"

find "$ROOT_DIR/backups" -mindepth 1 -maxdepth 1 -type d -mtime +"$KEEP_DAYS" -exec rm -rf {} +
ok "Backup complete: $target"

info ""
info "Restoring the database (example):"
info "  docker compose stop api jobs"
info "  docker compose exec -T postgres pg_restore -U $POSTGRES_USER -d $POSTGRES_DB --clean --if-exists < $target/postgres.dump"
info "  docker compose start api jobs"
