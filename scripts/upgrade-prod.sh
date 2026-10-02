#!/usr/bin/env bash
# Troca a imagem de PROD só depois de um backup validado. Qualquer falha antes disso não mexe no .env.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

usage() {
  cat <<'EOF'
Uso: upgrade-prod.sh <nova-imagem>

Recusa imagem inexistente, tag latest e a mesma imagem já configurada.
Exige postgres-prod healthy e espaço livre de pelo menos 2x o tamanho do banco.
Faz backup-postgres.sh prod e valida de novo o dump. Se isso falhar, o .env não muda.
Se o healthcheck da nova imagem falhar, devolve o .env anterior e imprime o comando
de restore. Não restaura o banco sozinho.
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

require_cmd docker sha256sum df
[[ $# -eq 1 ]] || { usage; die "informe a nova imagem"; }
new_image="$1"
efile="$(env_file prod)"
current="$(read_env "$efile" MB_IMAGE)"
history="$ROOT/upgrade-history.log"

docker image inspect "$new_image" >/dev/null 2>&1 || die "imagem inexistente: $new_image"
if [[ "$new_image" == *:latest || "$new_image" != *:* ]]; then
  die "recusa tag latest (explícita ou implícita): $new_image"
fi
[[ "$new_image" != "$current" ]] || die "a imagem nova é a mesma já configurada: $current"

db_c="$(db_container prod)"
st="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$db_c" 2>/dev/null || echo missing)"
[[ "$st" == "healthy" ]] || die "postgres-prod não está healthy (status=$st)"

db_kb="$(docker exec "$db_c" du -sk /var/lib/postgresql/data | awk '{print $1}')"
free_kb="$(docker exec "$db_c" df -Pk /var/lib/postgresql/data | awk 'NR==2 {print $4}')"
need_kb=$((db_kb * 2))
[[ "$free_kb" -ge "$need_kb" ]] || die "espaço livre ${free_kb} KiB é menor que 2x o banco (${need_kb} KiB)"

log "backup obrigatório antes de trocar $current por $new_image"
dump="$("$ROOT/scripts/backup-postgres.sh" prod)"
dump="$(printf '%s\n' "$dump" | tail -n 1)"
[[ -f "$dump" ]] || die "backup não gerou arquivo: $dump"
size="$(stat -c '%s' "$dump")"
[[ "$size" -gt 0 ]] || die "dump vazio; .env não foi alterado"
dir="$(cd "$(dirname "$dump")" && pwd)"
base="$(basename "$dump")"
expected="$(grep -E "[[:space:]]\\*?${base}$" "$dir/SHA256SUMS" | awk '{print $1}' | tail -n 1)"
actual="$(sha256sum "$dump" | awk '{print $1}')"
[[ -n "$expected" && "$actual" == "$expected" ]] || die "checksum do dump falhou; .env não foi alterado"
MSYS_NO_PATHCONV=1 docker cp "$(winpath "$dump")" "$db_c:/tmp/upgrade-check.dump"
if ! docker exec "$db_c" sh -c 'pg_restore --list /tmp/upgrade-check.dump | grep -q report_dashboard'; then
  docker exec "$db_c" rm -f /tmp/upgrade-check.dump || true
  die "validação extra do dump falhou; .env não foi alterado"
fi
docker exec "$db_c" rm -f /tmp/upgrade-check.dump

cp "$efile" "$ROOT/.env.previous"
tmp="$(mktemp)"
replaced=0
while IFS= read -r line || [[ -n "$line" ]]; do
  line="${line%$'\r'}"
  if [[ "$line" == MB_IMAGE=* ]]; then
    printf 'MB_IMAGE=%s\n' "$new_image" >> "$tmp"
    replaced=1
  else
    printf '%s\n' "$line" >> "$tmp"
  fi
done < "$efile"
[[ "$replaced" -eq 1 ]] || { rm -f "$tmp"; die "MB_IMAGE não encontrado no .env; cópia anterior mantida em .env.previous"; }
mv "$tmp" "$efile"

record() {
  printf '%s | %s | %s | %s | %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$current" "$new_image" "$dump" "$1" >> "$history"
}

log "subindo metabase-prod com $new_image"
if ! compose_for prod up -d metabase-prod; then
  compose_for prod stop metabase-prod || true
  cp "$ROOT/.env.previous" "$efile"
  record FALHA
  die "compose up falhou. .env restaurado. Para voltar o banco: $ROOT/scripts/restore-postgres.sh prod $dump"
fi

port="$(read_env "$efile" MB_HOST_PORT)"
[[ -n "$port" ]] || port=3002
if ! "$ROOT/scripts/healthcheck.sh" "$port" 900; then
  compose_for prod stop metabase-prod || true
  cp "$ROOT/.env.previous" "$efile"
  record FALHA
  printf 'Healthcheck falhou. .env restaurado para %s.\n' "$current" >&2
  printf 'O banco NÃO foi restaurado automaticamente. Comando:\n' >&2
  printf '%s prod %s\n' "$ROOT/scripts/restore-postgres.sh" "$dump" >&2
  exit 1
fi
record OK
log "upgrade ok: $current -> $new_image (dump $dump)"
