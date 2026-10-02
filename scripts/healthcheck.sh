#!/usr/bin/env bash
# Espera /api/health responder status ok e imprime a versão publicada.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

usage() {
  cat <<'EOF'
Uso: healthcheck.sh <porta> [timeout_s]

Faz polling de http://localhost:<porta>/api/health até {"status":"ok"}.
Depois imprime version.tag de /api/session/properties.
Termina com código diferente de zero se estourar o tempo.
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

require_cmd curl python
[[ $# -ge 1 && $# -le 2 ]] || { usage; die "informe a porta e, se quiser, o timeout em segundos"; }
port="$1"
timeout_s="${2:-180}"
deadline=$((SECONDS + timeout_s))
health_url="http://localhost:${port}/api/health"
ok=0
while (( SECONDS < deadline )); do
  if curl -fsS --max-time 5 "$health_url" 2>/dev/null | grep -q '"status":"ok"'; then
    ok=1
    break
  fi
  sleep 5
done
[[ "$ok" -eq 1 ]] || die "healthcheck da porta $port não ficou ok em ${timeout_s}s"
log "health ok em $health_url"
curl -fsS --max-time 15 "http://localhost:${port}/api/session/properties" \
  | python -c 'import json,sys; d=json.load(sys.stdin); v=d.get("version"); print(v.get("tag") if isinstance(v, dict) else (v if v is not None else ""))'
