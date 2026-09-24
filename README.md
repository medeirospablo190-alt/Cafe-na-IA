# CAFEÍNA

Este repositório agora mantém dois blocos independentes:

1. **CAFEÍNA App/Runtime** — editor Luau, World Core, Render Core e Android.
2. **CAFEÍNA Collector** — gateway de coleta V2.1/V3 e histórico de traces.

O produto legado anterior foi removido da árvore ativa. A CAFEÍNA mantém somente sua infraestrutura atual, o coletor e a base neutra de backend.

## Coletor

Entrypoint canônico:

```bash
npm start
```

Rotas preservadas:

- `GET /api/health`
- `GET /api/inventory-trace/health`
- `POST /api/inventory-trace`
- `GET /api/inventory-trace/:placeId/latest`
- `GET /api/inventory-trace/:placeId/status`
- `GET /api/inventory-trace-v3/health`
- `GET /api/inventory-trace-v3/profile/:gameId`
- `POST /api/inventory-trace-v3/batch`
- `GET /api/inventory-trace-v3/:gameId/:placeId/latest`

Os arquivos `avatar-gateway.js` e `server.js` permanecem somente como aliases temporários para não quebrar Start Commands antigos do Render. Eles não expõem Avatar Dump nem portal de downloads.

Dados históricos e espelho GitHub continuam em `inventory-traces/` e `inventory-traces-v3/`.

## Cloud API

A base PostgreSQL reutilizável foi preservada em `cafeina-cloud-api/`.

Ela usa o mesmo `DATABASE_URL` que pode apontar para o banco existente, porém toda estrutura nova da CAFEÍNA fica no schema PostgreSQL `cafeina_ai`.

**Importante:** tabelas legadas do banco não são apagadas automaticamente. Isso evita perda acidental de dados; a remoção física do legado deve ocorrer somente após auditoria do banco em produção.

## Desenvolvimento do app

- `executor-runtime/` — runtime Luau e bridge nativa.
- `executor-app/` — app Android/editor.
- `world-core/` — estado/hierarquia/componentes/persistência do mundo.
- `render-core/` — snapshots/render/picking e infraestrutura gráfica.

## Validação do coletor

```bash
npm install
npm run check
npm test
```

## Método de desenvolvimento

O trabalho de agentes segue [AGENTS.md](AGENTS.md) e o [fluxo de blocos longos](docs/DEVELOPMENT_WORKFLOW.md): meta de 25 minutos de trabalho útil por execução quando possível, implementação por fase, CI em checkpoints, continuidade durante esperas e aprovação explícita antes de merge na `main`. Essas regras não flexibilizam segurança, testes nem isolamento do Collector.
