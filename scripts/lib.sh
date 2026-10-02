#!/usr/bin/env bash
# Funções comuns dos scripts de PROD.
# Este repositório é só produção. O código e o DEV ficam em metabase-technos.
set -euo pipefail

_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${_LIB_DIR}/.." && pwd)"

log() {
  printf '%s %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$*" >&2
}

die() {
  printf 'ERRO: %s\n' "$*" >&2
  exit 1
}

ts() {
  date '+%Y%m%d-%H%M%S'
}

require_cmd() {
  local c
  for c in "$@"; do
    command -v "$c" >/dev/null 2>&1 || die "comando ausente: $c"
  done
}

winpath() {
  cygpath -w "$1"
}

compose_prod() {
  (
    cd "$ROOT" || exit 1
    docker compose --project-directory . -f compose.yaml --env-file .env "$@"
  )
}

compose_for() {
  local env="$1"
  shift
  case "$env" in
    prod) compose_prod "$@" ;;
    dev) die "DEV não fica neste repositório. Use https://github.com/LucasCardosoSI/metabase-technos.git" ;;
    *) die "ambiente inválido: $env (neste repositório só prod)" ;;
  esac
}

env_file() {
  case "$1" in
    prod) printf '%s\n' "$ROOT/.env" ;;
    dev) die "DEV não fica neste repositório. Use https://github.com/LucasCardosoSI/metabase-technos.git" ;;
    *) die "ambiente inválido: $1 (neste repositório só prod)" ;;
  esac
}

read_env() {
  local file="$1" key="$2" line
  [[ -f "$file" ]] || die "arquivo de ambiente ausente: $file"
  line="$(grep -E "^${key}=" "$file" | tail -n 1 || true)"
  line="${line#"${key}"=}"
  line="${line%$'\r'}"
  printf '%s' "$line"
}

db_container() {
  case "$1" in
    prod) printf '%s\n' metabase-technos-prod-db ;;
    *) die "ambiente inválido: $1 (neste repositório só prod)" ;;
  esac
}

app_container() {
  case "$1" in
    prod) printf '%s\n' metabase-technos-prod ;;
    *) die "ambiente inválido: $1 (neste repositório só prod)" ;;
  esac
}

app_service() {
  case "$1" in
    prod) printf '%s\n' metabase-prod ;;
    *) die "ambiente inválido: $1 (neste repositório só prod)" ;;
  esac
}

db_service() {
  case "$1" in
    prod) printf '%s\n' postgres-prod ;;
    *) die "ambiente inválido: $1 (neste repositório só prod)" ;;
  esac
}

secret_file() {
  case "$1" in
    prod) printf '%s\n' "$ROOT/secrets/db_password.txt" ;;
    *) die "ambiente inválido: $1 (neste repositório só prod)" ;;
  esac
}

require_env_name() {
  case "$1" in
    prod) ;;
    dev) die "DEV não fica neste repositório. Use https://github.com/LucasCardosoSI/metabase-technos.git" ;;
    *) die "ambiente inválido: $1 (neste repositório só prod)" ;;
  esac
}

psql_exec() {
  local env="$1"
  shift
  local c
  c="$(db_container "$env")"
  docker exec "$c" sh -c 'export PGPASSWORD="$(cat /run/secrets/db_password)"; exec psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" "$@"' sh "$@"
}

psql_admin() {
  local env="$1"
  shift
  local c
  c="$(db_container "$env")"
  docker exec "$c" sh -c 'export PGPASSWORD="$(cat /run/secrets/db_password)"; exec psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d postgres "$@"' sh "$@"
}

wait_healthy() {
  local c="$1" i st
  for i in $(seq 1 36); do
    st="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$c" 2>/dev/null || echo missing)"
    if [[ "$st" == "healthy" ]]; then
      log "$c está healthy"
      return 0
    fi
    sleep 5
  done
  die "timeout aguardando $c ficar healthy (último status: ${st:-desconhecido})"
}

network_of() {
  local c="$1" net
  net="$(docker inspect -f '{{range $k, $v := .NetworkSettings.Networks}}{{println $k}}{{end}}' "$c" | head -n 1)"
  [[ -n "$net" ]] || die "não achei a rede do container $c"
  printf '%s\n' "$net"
}
