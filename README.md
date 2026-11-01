# CAFEÍNA Collector

Repositório **exclusivo do coletor de dados Roblox e do gateway HTTP**. A árvore ativa foi enxugada sem alterar o contrato das APIs ou os caminhos consumidos pelo deploy.

## Arquivos ativos

| Arquivo / pasta | Função |
| --- | --- |
| `Cafeina_Universal_Game_Trace_V3_0.lua` | Coletor universal V3, com investigação adaptativa e envio por lotes. |
| `Cafeina_Universal_Game_Trace_LOCAL.lua` | Coletor local, sem envio à rede. |
| `Cafeina_Universal_Game_Trace_V2_1.lua` | Coletor legado V2.1, preservado por compatibilidade. |
| `collector-gateway.js` | Entrada pública do servidor (`npm start`). |
| `gateway-main.js` | Servidor Express e rotas V2.1. |
| `collector-v3-routes.js` | Rotas V3, perfis por jogo, batches e espelhamento. |
| `server.js`, `avatar-gateway.js` | Aliases antigos de entrada, preservados para Start Commands existentes. |
| `test/`, `.github/workflows/` | Testes de integração e validações de CI. |
| `docs/CAFEINA_TRACE_V3_README.md` | Documentação técnica do V3. |
| `inventory-traces/`, `inventory-traces-v3/` | Histórico espelhado e perfis, preservados por dependência e para futura análise. |

## Iniciar e validar

```sh
npm install
npm run check
npm test
npm start
```

A porta é definida pela variável `PORT`. A configuração de ambiente está em `.env.example`.

## Rotas de compatibilidade

- `GET /api/health`
- `GET /api/inventory-trace/health`
- `POST /api/inventory-trace`
- `GET /api/inventory-trace/:placeId/latest`
- `GET /api/inventory-trace/:placeId/status`
- `GET /api/inventory-trace-v3/health`
- `GET /api/inventory-trace-v3/profile/:gameId`
- `POST /api/inventory-trace-v3/batch`
- `GET /api/inventory-trace-v3/:gameId/:placeId/latest`

## Arquivo de segurança da limpeza

Os menus e scripts auxiliares antigos, versões especializadas e o coletor de executor foram retirados **somente da árvore de trabalho**. A versão completa anterior permanece na branch `archive/coletor-pre-limpeza-2026-11-01`.

**Atenção:** links externos `raw.githubusercontent.com/.../main/<script-antigo>.lua` podem parar de funcionar **quando esta limpeza for mesclada**. Caso algum ainda seja usado, recupere o arquivo da branch arquivada antes de mesclar.

O GitHub continua recebendo históricos por meio de `inventory-traces/` e `inventory-traces-v3/`. Remover esses diretórios sem migrar o espelhamento e a sincronização poderia quebrar recuperação de sessões, perfis e automações; eles foram preservados deliberadamente.

O serviço em produção e as configurações do Render **não foram modificados por esta limpeza**.
