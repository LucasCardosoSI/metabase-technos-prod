# Decisões

## Produção neste repositório, desenvolvimento no outro

[Confirmado] O código e o DEV ficam em [metabase-technos-dev](https://github.com/LucasCardosoSI/metabase-technos-dev), branch `technos/main`. Este repositório, [metabase-technos-prod](https://github.com/LucasCardosoSI/metabase-technos-prod), guarda só o Compose, os scripts de backup, restore, migração e upgrade, e o exemplo de ambiente.

Motivo: desenvolvimento e produção não compartilham o mesmo Git. Um commit de código não altera o que está no ar, e o repositório de produção não carrega a árvore inteira do Metabase.

O projeto Compose continua se chamando `metabase-technos-prod`, para reutilizar os containers e o volume já criados no ensaio da porta 3002.
