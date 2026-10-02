# metabase-technos-prod

Repositório de **produção** do Metabase da empresa. O código-fonte, a toolbox e o ambiente DEV ficam em [metabase-technos-dev](https://github.com/LucasCardosoSI/metabase-technos-dev).

Este projeto só sobe e opera a instância. Não contém o código do Metabase. A imagem em uso no ensaio é `metabase/metabase:v0.63.5-local`. Uma imagem construída no repositório de desenvolvimento entra aqui pelo `scripts/upgrade-prod.sh`.

O container antigo `metabase` (H2, porta 3000) não é gerenciado por estes arquivos. O ensaio publica a porta 3002.

## Subir

```bash
cp .env.example .env
mkdir -p secrets
openssl rand -base64 32 | tr -d '\r\n' > secrets/db_password.txt
docker compose --env-file .env up -d
./scripts/healthcheck.sh 3002 600
```

Se o `.env` e a senha já existirem nesta máquina, não gere outro arquivo: a senha nova não abre o volume que já está no ar.

## Operação

```bash
./scripts/backup-postgres.sh prod
./scripts/healthcheck.sh 3002 600
./scripts/upgrade-prod.sh <nova-imagem>
```

Upgrade de versão só pelo `scripts/upgrade-prod.sh`. O nome do projeto Compose continua `metabase-technos-prod`, o mesmo dos containers já criados.
