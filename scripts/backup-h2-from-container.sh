#!/usr/bin/env bash
# Copia /metabase.db de um container parado e grava SHA256SUMS.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

usage() {
  cat <<'EOF'
Uso: backup-h2-from-container.sh <container> <destino>

Recusa o backup se o container estiver running.
Copia /metabase.db, exige metabase.db.mv.db com tamanho > 0 e grava SHA256SUMS.
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

require_cmd docker sha256sum
[[ $# -eq 2 ]] || { usage; die "informe o container e o destino"; }
c="$1"
dest="$2"
status="$(docker inspect -f '{{.State.Status}}' "$c")"
if [[ "$status" == "running" ]]; then
  die "container $c está running; backup do H2 recusado para não copiar um arquivo inconsistente"
fi
mkdir -p "$dest"
MSYS_NO_PATHCONV=1 docker cp "$c:/metabase.db" "$(winpath "$dest")/"
mvdb="$dest/metabase.db/metabase.db.mv.db"
[[ -f "$mvdb" ]] || die "metabase.db.mv.db não apareceu em $dest"
size="$(stat -c '%s' "$mvdb")"
[[ "$size" -gt 0 ]] || die "metabase.db.mv.db está vazio"
(
  cd "$dest"
  sha256sum metabase.db/* > SHA256SUMS
  cat SHA256SUMS
)
log "backup H2 em $dest ($size bytes)"
