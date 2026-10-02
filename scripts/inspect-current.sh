#!/usr/bin/env bash
# Inspeciona um container Metabase. Só leitura: não para, não inicia, não apaga.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

usage() {
  cat <<'EOF'
Uso: inspect-current.sh [container]

Padrão do container: metabase
Imprime imagem, ID, versão vista nos logs, portas, mounts, redes, restart
e variáveis de ambiente. Valores de chaves com PASS, SECRET, KEY ou TOKEN
saem mascarados.
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

require_cmd docker
c="${1:-metabase}"
docker inspect "$c" >/dev/null

echo "container: $c"
docker inspect -f 'status: {{.State.Status}}' "$c"
docker inspect -f 'imagem: {{.Config.Image}}' "$c"
docker inspect -f 'id_imagem: {{.Image}}' "$c"
docker inspect -f 'id_container: {{.Id}}' "$c"
docker inspect -f 'restart: {{.HostConfig.RestartPolicy.Name}}' "$c"
docker inspect -f 'portas: {{json .HostConfig.PortBindings}}' "$c"
docker inspect -f 'mounts: {{json .Mounts}}' "$c"
docker inspect -f 'redes: {{json .NetworkSettings.Networks}}' "$c"
echo "versao_nos_logs:"
docker logs "$c" 2>&1 | grep -E 'Metabase v' | tail -n 5 || true
echo "ambiente:"
docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$c" | while IFS= read -r line; do
  [[ -n "$line" ]] || continue
  key="${line%%=*}"
  if printf '%s' "$key" | grep -Eq 'PASS|SECRET|KEY|TOKEN'; then
    printf '%s=***\n' "$key"
  else
    printf '%s\n' "$line"
  fi
done
