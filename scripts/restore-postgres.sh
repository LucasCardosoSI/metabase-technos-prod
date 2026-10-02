#!/usr/bin/env bash
# Restaura um dump pg_dump -Fc no DEV ou no PROD. Exige a palavra RESTAURAR.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

usage() {
  cat <<'EOF'
Uso: restore-postgres.sh <dev|prod> <arquivo.dump>

Confere o SHA256SUMS da mesma pasta, exige digitar RESTAURAR,
para o Metabase do ambiente, recria o banco, roda pg_restore e sobe o Metabase de novo.
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

require_cmd docker sha256sum
[[ $# -eq 2 ]] || { usage; die "informe o ambiente e o arquivo .dump"; }
env_name="$1"
dump="$2"
require_env_name "$env_name"
[[ -f "$dump" ]] || die "dump inexistente: $dump"
dir="$(cd "$(dirname "$dump")" && pwd)"
base="$(basename "$dump")"
sums="$dir/SHA256SUMS"
[[ -f "$sums" ]] || die "SHA256SUMS ausente em $dir"
expected="$(grep -E "[[:space:]]\\*?${base}$" "$sums" | awk '{print $1}' | tail -n 1)"
[[ -n "$expected" ]] || die "não achei $base em $sums"
actual="$(sha256sum "$dump" | awk '{print $1}')"
[[ "$actual" == "$expected" ]] || die "checksum divergente para $base"
log "checksum ok"

efile="$(env_file "$env_name")"
dbname="$(read_env "$efile" MB_DB_DBNAME)"
dbuser="$(read_env "$efile" MB_DB_USER)"
db_c="$(db_container "$env_name")"
app_svc="$(app_service "$env_name")"
log "Digite RESTAURAR para substituir o banco $dbname de $env_name."
read -r confirm
[[ "$confirm" == "RESTAURAR" ]] || die "confirmação recusada"

log "parando $(app_container "$env_name")"
compose_for "$env_name" stop "$app_svc" || true
psql_admin "$env_name" -v ON_ERROR_STOP=1 -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '${dbname}' AND pid <> pg_backend_pid();" || true
psql_admin "$env_name" -c "DROP DATABASE IF EXISTS \"${dbname}\";"
psql_admin "$env_name" -c "CREATE DATABASE \"${dbname}\" OWNER \"${dbuser}\";"
MSYS_NO_PATHCONV=1 docker cp "$(winpath "$dump")" "$db_c:/tmp/restore.dump"
docker exec "$db_c" sh -c 'export PGPASSWORD="$(cat /run/secrets/db_password)"; pg_restore -U "$POSTGRES_USER" -d "$POSTGRES_DB" --no-owner --exit-on-error /tmp/restore.dump'
docker exec "$db_c" rm -f /tmp/restore.dump
log "restore concluído; subindo o Metabase de $env_name"
compose_for "$env_name" up -d "$app_svc"
