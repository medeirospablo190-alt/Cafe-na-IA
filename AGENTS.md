# Regras de trabalho — CAFEÍNA

Estas instruções orientam agentes e colaboradores que desenvolvem a CAFEÍNA neste repositório. O objetivo é entregar blocos grandes, coerentes e testáveis, como no fluxo de desenvolvimento do Grupo Lua/Gestão, sem transformar cada commit, PR ou consulta de CI em uma pausa para o usuário.

## 1. Ritmo e autonomia

- **Meta de sessão: pelo menos 25 minutos de trabalho útil contínuo, quando a ferramenta e a sessão permitirem.** Não inventar duração, não atrasar artificialmente a resposta e não prometer execução em segundo plano. Se houver limite real de execução, informar o progresso efetivo e o próximo passo exato.
- Começar com um diagnóstico curto do estado atual e executar o maior bloco seguro e autorizado. Não parar depois de uma consulta, commit, PR, checkpoint de CI ou fase se houver trabalho independente relevante.
- Encadear análise, implementação, testes, revisão, documentação e correção no mesmo bloco. Agrupar leituras e operações de GitHub; evitar polling repetitivo e mensagens de progresso sem entrega.
- Enquanto o CI roda, avançar revisão, testes, documentação ou outro trabalho independente que não altere o commit em validação. Não empilhar commits triviais que cancelem CI; agrupar mudanças relacionadas antes de disparar o checkpoint.
- Erro corrigível é trabalho interno: diagnosticar, corrigir, testar e continuar. Não pedir ao usuário que escolha entre alternativas técnicas equivalentes.
- Manter registro de decisões, commits, PRs, resultados de testes, pendências e próximo passo para continuidade em outro chat ou agente. Não recomeçar uma análise já validada.

## 2. Organização de implementação

- Trabalhar por dependência: contrato/capabilities → orquestração determinística/especialistas → laboratório/testes/evidência → persistência/recuperação de missões → modelo local e melhorias. Ajustar a ordem somente com justificativa técnica documentada.
- Preferir **uma branch de integração por fase** e commits coerentes. Abrir PRs quando houver um bloco revisável, não um PR por microtarefa. Separar branches/PRs quando houver risco real, migração independente ou necessidade de rollback isolado.
- `main` deve permanecer estável. Antes de merge: diff revisado, testes relevantes e CI aplicável aprovados. Não forçar merge nem interpretar CI cancelado/pendente como aprovado.
- Após squash-merge, atualizar branches dependentes sobre a `main` real e conferir diffs para não reintroduzir commits antigos.
- CI é um gate de qualidade, não a atividade principal. Se estiver pendente, continuar trabalho independente; se falhar, ler o erro, corrigir a causa e revalidar.
- Não alterar workflows para pular testes, reduzir cobertura ou ignorar falhas em nome da velocidade.

## 3. Autorização e interrupções

- A autorização para implementar a fase inclui criar branches, commits, testes, documentação e PRs pertinentes. Não pedir aprovação a cada ação interna.
- Solicitar intervenção apenas para credencial/acesso indispensável, escolha de produto sem resposta documentada, decisão com impacto irreversível ou autorização de alteração crítica. Se um bloqueio afetar só uma frente, continuar outra frente segura.
- **Merge em `main` exige autorização explícita do usuário neste projeto**, além do CI/revisão. Não presumir que a meta de 25 minutos autoriza merge, deploy, exclusão ou migração destrutiva.
- Não inventar confirmação, aprovação, resultado de teste, duração de trabalho ou execução futura.

## 4. Limites técnicos que a velocidade não altera

- Preservar Collector V2.1/V3, rotas `/api/inventory-trace` e `/api/inventory-trace-v3`, traces históricos e espelho GitHub. Não interromper coletas para desenvolver o app.
- Manter app/runtime, Collector, cloud e legado isolados em processos, permissões, dados e dependências. Novas tabelas da IA pertencem ao schema `cafeina_ai`; nunca executar `DROP` legado sem inventário, backup e autorização.
- Preservar compatibilidade Render/`rootDir` e aliases em uso até migração validada. Não expor tokens, chaves ou código privado em commits, logs ou cliente.
- Capabilities são concedidas pelo host e verificadas antes dos efeitos; operações desconhecidas falham fechadas. `WorldService` permanece a autoridade sobre o World; usar snapshot, rollback e testes de regressão para alterações de estado.
- Não apagar automaticamente scripts, projetos, dados ou histórico. Operações destrutivas, mudanças em produção, credenciais, banco e segurança exigem aprovação específica.

## 5. Entrega de cada bloco

Relatar apenas resultados verificáveis: arquivos/commits/PRs, testes efetivamente executados e seus resultados, riscos remanescentes e o próximo passo. Evitar repetir o mesmo status do CI. Se uma etapa depender do usuário, apresentar a decisão exata e continuar qualquer trabalho independente possível.

Documentação complementar: `docs/DEVELOPMENT_WORKFLOW.md`. Regras específicas de componentes podem ser mais restritivas; nenhuma regra de ritmo revoga controles de segurança.
