# CAFEÍNA Collector

Repositório do coletor de dados dos jogos Roblox, dos scripts Lua relacionados e do histórico de traces. O coletor V2.1/V3 continua independente.

## Gateway

O serviço principal usa `collector-gateway.js` (entrada `npm start`). Os aliases `server.js` e `avatar-gateway.js` permanecem para compatibilidade com Start Commands existentes.

Rotas mantidas:

- `GET /api/health`
- `GET /api/inventory-trace/health`
- `POST /api/inventory-trace`
- `GET /api/inventory-trace/:placeId/latest`
- `GET /api/inventory-trace/:placeId/status`
- `GET /api/inventory-trace-v3/health`
- `GET /api/inventory-trace-v3/profile/:gameId`
- `POST /api/inventory-trace-v3/batch`
- `GET /api/inventory-trace-v3/:gameId/:placeId/latest`

O histórico e o espelho do GitHub permanecem em `inventory-traces/` e `inventory-traces-v3/`. Consulte `docs/CAFEINA_TRACE_V3_README.md` para detalhes do coletor V3.

## Verificação

```bash
npm install
npm run check
npm test
```
