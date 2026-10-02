#!/usr/bin/env bash
# Copia um backup H2 para uma pasta temporária e carrega no Postgres do ambiente.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

usage() {
  cat <<'EOF'
Uso: migrate-h2-to-postgres.sh <dev|prod> <pasta-do-backup-h2> [--force-recreate]

A pasta do backup precisa conter metabase.db/metabase.db.mv.db.
O script trabalha numa cópia. O backup original não é alterado.
Recusa se a tabela report_dashboard já existir, salvo com --force-recreate.
Nesse caso é preciso digitar RECRIAR; o banco da aplicação é apagado e recriado.
O argumento do load-from-h2 é o caminho sem a extensão .mv.db.
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

require_cmd docker python
force=0
env_name=""
src=""
for arg in "$@"; do
  case "$arg" in
    --force-recreate) force=1 ;;
    -h|--help) usage; exit 0 ;;
    *)
      if [[ -z "$env_name" ]]; then
        env_name="$arg"
      elif [[ -z "$src" ]]; then
        src="$arg"
      else
        die "argumento inesperado: $arg"
      fi
      ;;
  esac
done
[[ -n "$env_name" && -n "$src" ]] || { usage; die "informe o ambiente e a pasta do backup"; }
require_env_name "$env_name"
[[ -f "$src/metabase.db/metabase.db.mv.db" ]] || die "backup sem metabase.db/metabase.db.mv.db: $src"

efile="$(env_file "$env_name")"
image="$(read_env "$efile" MB_IMAGE)"
dbname="$(read_env "$efile" MB_DB_DBNAME)"
dbuser="$(read_env "$efile" MB_DB_USER)"
passfile="$(secret_file "$env_name")"
[[ -n "$image" ]] || die "MB_IMAGE vazio em $efile"
[[ -s "$passfile" ]] || die "senha ausente: $passfile"
[[ "$image" != *:latest ]] || die "MB_IMAGE não pode ser a tag latest"

db_svc="$(db_service "$env_name")"
db_c="$(db_container "$env_name")"
app_svc="$(app_service "$env_name")"
log "subindo $db_svc"
compose_for "$env_name" up -d "$db_svc"
wait_healthy "$db_c"

exists="$(psql_exec "$env_name" -tA -c "SELECT CASE WHEN to_regclass('public.report_dashboard') IS NULL THEN 'nao' ELSE 'sim' END;")"
exists="$(printf '%s' "$exists" | tr -d '[:space:]')"
if [[ "$exists" == "sim" ]]; then
  if [[ "$force" -ne 1 ]]; then
    die "report_dashboard já existe em $env_name; recusado. Use --force-recreate e confirme com RECRIAR"
  fi
  log "report_dashboard existe. Digite RECRIAR para apagar o banco $dbname e recriar."
  read -r confirm
  [[ "$confirm" == "RECRIAR" ]] || die "confirmação recusada"
  log "parando o Metabase de $env_name antes de recriar o banco"
  compose_for "$env_name" stop "$app_svc" || true
  psql_admin "$env_name" -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '${dbname}' AND pid <> pg_backend_pid();" || true
  psql_admin "$env_name" -c "DROP DATABASE IF EXISTS \"${dbname}\";"
  psql_admin "$env_name" -c "CREATE DATABASE \"${dbname}\" OWNER \"${dbuser}\";"
  log "banco $dbname recriado"
fi

work="$(mktemp -d)"
cleanup() { rm -rf "$work"; }
trap cleanup EXIT
cp -a "$src/metabase.db" "$work/metabase.db"
chmod -R a+rX "$work" || true
size="$(stat -c '%s' "$work/metabase.db/metabase.db.mv.db")"
[[ "$size" -gt 0 ]] || die "cópia do H2 está vazia"
log "cópia de trabalho em $work ($size bytes). O backup original não foi alterado."

net="$(network_of "$db_c")"
db_host="$db_svc"
log "load-from-h2 na rede $net com imagem $image"
# O entrypoint /app/run_metabase.sh, como root, não repassa argumentos ao java
# (o "$@" quebra o -c do su). Por isso o java é chamado direto, no formato da
# documentação: caminho sem .mv.db. A senha entra por MB_DB_PASS, lida do arquivo
# dentro do container, e não aparece na linha de comando do host.
MSYS_NO_PATHCONV=1 docker run --rm \
  --network "$net" \
  --entrypoint /bin/sh \
  -v "$(winpath "$work"):/h2" \
  -v "$(winpath "$passfile"):/run/secrets/db_password:ro" \
  -e MB_DB_TYPE=postgres \
  -e MB_DB_HOST="$db_host" \
  -e MB_DB_PORT=5432 \
  -e MB_DB_DBNAME="$dbname" \
  -e MB_DB_USER="$dbuser" \
  -e MB_DB_PASS_FILE=/run/secrets/db_password \
  "$image" \
  -c 'export MB_DB_PASS="$(cat "$MB_DB_PASS_FILE")"; unset MB_DB_PASS_FILE; exec java -XX:+IgnoreUnrecognizedVMOptions -Dfile.encoding=UTF-8 -XX:+CrashOnOutOfMemoryError -server --add-opens java.base/java.nio=ALL-UNNAMED --enable-native-access=ALL-UNNAMED -jar /app/metabase.jar load-from-h2 /h2/metabase.db/metabase.db'

log "resumo $env_name"
psql_exec "$env_name" -c "SELECT 'core_user' AS tabela, count(*) FROM core_user UNION ALL SELECT 'report_dashboard', count(*) FROM report_dashboard;"
