# Handoff de execução — modelo obrigatório

Preencher ao transferir trabalho para outro chat/agente ou ao atingir um limite de sessão. Não substituir fatos por estimativas. Atualizar apenas após consultar o estado real do repositório.

## Identificação
- Objetivo da fase:
- Branch de integração:
- SHA HEAD:
- Base em `main`:
- PRs abertos e dependências:
- Escopo explicitamente fora da fase:

## Trabalho efetivamente concluído
- Arquivos/áreas alterados:
- Commits e motivos:
- Testes executados e resultado (incluindo SHA):
- CI (run ID, SHA, status e jobs):
- Revisão do diff e riscos encontrados:

## Segurança e compatibilidade
- Efeitos sobre Collector/rotas/Render:
- Efeitos sobre dados/schema `cafeina_ai`/legado:
- Capabilities, WorldService e rollback:
- Secrets ou ações de produção: confirmar ausência ou registrar aprovação específica.

## Continuação sem perguntas repetidas
- Próxima ação segura e executável:
- Trabalhos independentes enquanto o CI aguarda:
- Bloqueios reais:
- Decisão exata que exige o usuário, se houver:
- Merge: **não autorizado** até aprovação explícita e CI do SHA atual.

Não registrar como concluído um teste pendente ou cancelado. Não solicitar ao usuário que repita decisões já documentadas. Este modelo complementa `AGENTS.md` e `docs/DEVELOPMENT_WORKFLOW.md`.
