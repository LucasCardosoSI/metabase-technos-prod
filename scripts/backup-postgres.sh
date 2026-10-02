#!/usr/bin/env bash
# pg_dump -Fc do banco de aplicação. A última linha da saída padrão é o caminho do dump.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

usage() {
  cat <<'EOF'
Uso: backup-postgres.sh <dev|prod> [destino]

Gera metabase-<env>-<versao>-<timestamp>.dump com pg_dump -Fc.
Valida tamanho > 0, pg_restore --list contendo report_dashboard e grava SHA256SUMS.
Logs vão para a saída de erro. A última linha da saída padrão é o caminho do arquivo.
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

require_cmd docker sha256sum
[[ $# -ge 1 && $# -le 2 ]] || { usage; die "informe o ambiente e, se quiser, o destino"; }
env_name="$1"
require_env_name "$env_name"
dest="${2:-/c/Projetos/Metabase/backups}"
mkdir -p "$dest"
efile="$(env_file "$env_name")"
image="$(read_env "$efile" MB_IMAGE)"
ver="${image##*:}"
ver="${ver//\//_}"
[[ -n "$ver" ]] || ver="sem-tag"
stamp="$(ts)"
outfile="$dest/metabase-${env_name}-${ver}-${stamp}.dump"
db_c="$(db_container "$env_name")"
status="$(docker inspect -f '{{.State.Status}}' "$db_c")"
[[ "$status" == "running" ]] || die "$db_c não está running"

log "pg_dump de $env_name para $outfile"
docker exec "$db_c" sh -c 'rm -f /tmp/metabase-backup.dump; export PGPASSWORD="$(cat /run/secrets/db_password)"; pg_dump -Fc -U "$POSTGRES_USER" -d "$POSTGRES_DB" -f /tmp/metabase-backup.dump'
if ! docker exec "$db_c" sh -c 'pg_restore --list /tmp/metabase-backup.dump | grep -q report_dashboard'; then
  docker exec "$db_c" rm -f /tmp/metabase-backup.dump || true
  die "pg_restore --list não encontrou report_dashboard"
fi
MSYS_NO_PATHCONV=1 docker cp "$db_c:/tmp/metabase-backup.dump" "$(winpath "$outfile")"
docker exec "$db_c" rm -f /tmp/metabase-backup.dump
size="$(stat -c '%s' "$outfile")"
[[ "$size" -gt 0 ]] || die "dump vazio: $outfile"
(
  cd "$dest"
  sha256sum "$(basename "$outfile")" >> SHA256SUMS
)
log "dump ok: $outfile ($size bytes)"
printf '%s\n' "$outfile"
