# CAFEÍNA — BASE AUTORITATIVA + HANDOFF DO PRÓXIMO CHAT

Atualizado em 2026-09-23. Este documento é cumulativo e serve para impedir perda de contexto na troca de chat.

## NÃO PERDER AO TROCAR DE CHAT

1. Ler primeiro `docs/CAFEINA_OPERATIONAL_PROTOCOL.md` (incluindo a seção 2.1 de blocos de 25 minutos) e usar `AGENTS.md` como entrada resumida.
2. O Protocolo Definitivo consolidado em `docs/CAFEINA_OPERATIONAL_PROTOCOL.md` substitui os conjuntos operacionais antigos (141 regras e 6 regras intermediárias) e tem precedência sobre interpretações operacionais conflitantes.
3. Verificar o estado REAL do GitHub antes de qualquer afirmação ou mutação.
4. Não reconstruir trabalho já concluído.
5. Preservar regras técnicas e invariantes; elas protegem o software, mas não criam checkpoints de conversa.
6. Preservar decisões, arquitetura, fases, PRs, branches, commits, testes, falhas, correções, infraestrutura, Collector e ponto exato de continuação.
7. O Plano Mestre CAFEÍNA de 300 itens fornecido pelo usuário continua sendo a especificação funcional autoritativa. Não o substituir por um resumo quando o texto canônico estiver disponível no contexto/handoff anterior.
8. Não misturar requisitos Roblox/Grupo Lua no produto independente CAFEÍNA.

## OBJETIVO DO PRODUTO

CAFEÍNA é um aplicativo Android independente que combina:
- runtime Luau oficial;
- editor e projetos;
- CAFEÍNA AI profundamente integrada;
- Test World;
- workspace/editor/modelador 3D;
- ferramentas, skills e extensibilidade;
- pesquisa pública com proveniência;
- testes, diagnósticos, replay, métricas e profiling;
- memória/Knowledge Store persistente;
- snapshots, versionamento, recuperação e rollback;
- continuidade de trabalho interrompido;
- futura expansão desktop/notebook.

Fluxo de produto:
USER → CAFEÍNA AI → CODE + WORLD + 3D + TESTS + RESEARCH + TOOLS → FUNCTIONAL RESULT → VALIDATION → LEARNING.

Fluxo interno esperado:
entender → planejar → executar → testar → encontrar falhas → corrigir → retestar → melhorar → entregar.

O usuário mantém controle final. Tudo deve ser gratuito; recursos essenciais não devem depender de serviço pago. A direção da AI é local/offline por padrão quando aplicável.

Frase-guia literal:
“A CAFEÍNA deve fazer o máximo possível para cumprir o objetivo do usuário, aprender com cada experiência, criar as ferramentas que estiverem faltando, testar antes de confiar, preservar o que funciona, explicar mudanças importantes e nunca perder a capacidade de voltar para um estado estável.”

## ARQUITETURA BASE

Camadas/sistemas:
- APP SHELL
- CAFEÍNA AI
- LUAU RUNTIME
- EDITOR
- TEST WORLD
- 3D ENGINE
- TOOL SYSTEM
- KNOWLEDGE SYSTEM
- RESEARCH SYSTEM
- TEST ENGINE
- DIAGNOSTICS
- DEVICE PROFILE
- PROJECT SYSTEM
- VERSIONING
- SNAPSHOTS
- RECOVERY CORE

UI planejada: IA | CÓDIGO | MUNDO | 3D | SISTEMA.

AI:
- MODO CRIAÇÃO / MODO APRENDIZADO
- Goal Lock
- Learning Queue
- STABLE / CANDIDATE / EXPERIMENTAL
- Shadow/Reviewer/adversarial/self-evaluation
- autoaperfeiçoamento exige evidência, testes, métricas, rollback e controle do usuário.

Knowledge lifecycle:
- EXPERIMENTAL
- VALIDATED
- CONSOLIDATED
- OBSOLETE
Internet é candidata até validação. Camadas HOT/WARM/COLD.

Capabilities previstas:
APP_STORAGE, SELECTED_FOLDER, NETWORK, CAMERA, MICROPHONE, NOTIFICATIONS, BLUETOOTH, LOCATION, SENSORS, BACKGROUND_PROCESSING, TEST_WORLD, 3D_ENGINE, DEVICE_DIAGNOSTICS.
Princípios: least privilege, permissões honestas, fail-closed quando necessário.

## FASES CONCLUÍDAS

1. Runtime Luau independente: compile/execute, print/warn, retornos, erros, timeout, CLI, Android JNI e sandbox.
2. Android Shell: editor/console/background execution/JNI/APK.
3. Tabs.
4. Armazenamento local de scripts.
5. SAVE/LOAD.
6. Restauração de tabs + proteção de não salvo.
7. Auto Execute local explícito.
8. Runtime filesystem sandboxed: `fs.write()`, `fs.read()`, `fs.exists()`, `fs.list()`.
9–13. Fundação Test World/World Core/render/mobile preview/scene diff/picking/camera/persistência avançadas desenvolvidas por PRs sucessivos.
14. Project/World persistence e snapshot foundation já integrados; recovery em validação.

Diretórios privados históricos:
- `files/runtime-fs`
- `files/scripts`
- `files/autoexec.list`
- projetos em `files/projects/<project-id>/...`

## ROADMAP AUTORITATIVO DE FASES

9 Test World foundation
10 Scene Graph + headless World
11 render Android básico + avatar
12 Edit/Play
13 test harness + metrics + replay
14 projects + snapshots + versioning + recovery + diff + rollback
15 SQLite Knowledge Store
16 CAFEÍNA AI core interface
17 chat/context/missions
18 tool system
19 research subsystem
20 learning mode
21 auto-improvement candidates
22 3D editor foundation
23 procedural modeling
24 image-assisted modeling
25 advanced playtest agents
26 optimization/profiling
27 plugin/skill architecture

## INVARIANTES TÉCNICAS QUE CONTINUAM VÁLIDAS

- WorldService/native é fonte de verdade; renderer recebe estado derivado.
- Preservar `worldMatrix`.
- Scene Graph rejeita ciclos e pais inválidos.
- Remover pai retorna filhos à raiz.
- RenderScene determinístico.
- Scene diff estável por ObjectId.
- Picking usa `worldMatrix`.
- Camera separada do World e não muta objetos.
- Gestos: 1 dedo orbit, pinch zoom, 2 dedos pan.
- ObjectId Luau em string decimal; não perder precisão uint64.
- World IDs não são reciclados.
- Import inválido de World não pode destruir World válido anterior.
- Capability System fail-closed.
- CMake Android 3.22.1: não reintroduzir `DOWNLOAD_EXTRACT_TIMESTAMP TRUE` sem causa comprovada.
- Filament fixado em 1.75.1.
- Testes devem validar comportamento, não apenas compilação.
- Bug recorrente exige correção de causa raiz + regressão.
- Branch → testes → PR → CI → merge para mudanças relevantes; isso ocorre dentro do bloco contínuo, sem virar checkpoint de conversa.
- Antes de merge, verificar diff e preservar dados protegidos.
- Squash merge pode divergir branches empilhadas: reconstruir branch limpa sobre o novo main quando necessário.
- Não copiar arquivos inteiros cegamente entre branches.
- Não force-update sem preservar exatamente o branch/PR pretendido.
- POC-alvo: Projeto → World → Luau cria objeto → renderiza → salva → fecha → abre → restaura.

## HISTÓRICO RECENTE IMPORTANTE

- #101: `Render: propagate hierarchical world transforms`, merge em 2026-09-23. Transform local preservado, `worldMatrix` column-major, composição recursiva de ancestrais, translation → rotation Z/Y/X → scale, pais não-mesh afetam filhos, falhas fechadas.
- #107 recuperou trabalho válido do antigo #102.
- #108 recuperou camera mobile preview do antigo #103.
- #111 recuperou deterministic scene diff do antigo #104.
- #112 persistência do World integrada; squash merge `126072fe08ef836a60c98c9c8f9d20547c859f3d`.
  - arquivo: `files/projects/<project-id>/worlds/main.cafeina-world.json`
  - limite 16 MiB
  - temp + fsync + replace seguro
  - symlink fail-closed
  - JNI export/import
  - import inválido validado antes de substituir World ativo
  - IDs não reciclados
- #113 antigo POC stacked foi fechado sem merge.
- #114 POC limpo de save/load/startup restore foi integrado; merge `709d068fd41b930f8b36e20e36d8bea9f7e1f3b6`.
- #115 snapshot foundation antigo foi fechado após divergência causada por squash.
- #116 snapshot foundation reconstruído sobre main e integrado; merge `b551954f746216636a8f0c461d2263b197bb7681`.
  - `ProjectSnapshotStore`
  - snapshots imutáveis
  - limite 16 MiB
  - IDs lowercase alnum/hyphen/underscore, primeiro caractere alnum, max 64
  - escrita temp + fsync + atomic move/fallback
  - sem overwrite
  - symlink fail-closed
  - listagem determinística.

## ESTADO EXATO VERIFICADO EM 2026-09-23

### PR #117 — transactional World snapshot recovery
- Estado: OPEN
- Head: `c80030fcc430db0143da8dab6216fc8e8a90281c`
- Mergeable: true
- CI run `35915914472`: COMPLETED / SUCCESS.
- Branch: `project/snapshot-recovery-current-main`
- Diff pretendido: apenas `ProjectWorldRecovery.java` e `ProjectWorldRecoveryTest.java`.
- Comportamento: snapshot do World nativo; restore transacional; import inválido restaura estado nativo anterior e preserva arquivo principal.
- Antes do merge: verificar novamente diff/head/mergeability e ausência de dados protegidos. Depois squash merge.

### PR #118 — SQLite Knowledge Store foundation
- Estado: OPEN
- Head: `4c08a170ca861e75a34659b093254ccb443dc7a7`
- Mergeable: true
- CI run `35916012198`: COMPLETED / FAILURE.
- Falha observada: job `android-emulator`, etapa instrumentation.
- Causa do log: infraestrutura do runner ao instalar o Android Emulator: `Error on ZipFile unknown archive`; emulador não chegou a iniciar (`Connection refused` na limpeza). Não há evidência nesse run de falha do código da Knowledge Store.
- Android build/unit do fluxo anterior progrediram normalmente; não tratar o erro do emulador como defeito funcional sem nova evidência.
- Branch: `knowledge/sqlite-foundation`.
- Arquivos: `CafeinaKnowledgeDatabase.java`, `KnowledgeState.java`, `KnowledgeStateTest.java`.
- Schema inicial local: conversations, knowledge, sources, experiments, diagnostics, test_results, decisions, failures, snapshots; índices básicos.
- Estados: EXPERIMENTAL/VALIDATED/CONSOLIDATED/OBSOLETE.
- Migração desconhecida falha fechada.

## INFRAESTRUTURA / COLLECTOR — NÃO QUEBRAR

CAFEÍNA App/Runtime e CAFEÍNA Collector são blocos independentes no mesmo repositório.

Collector:
- preservar V2.1/V3;
- preservar histórico `inventory-traces/` e `inventory-traces-v3/`;
- gateway atual e mirror GitHub não devem ser quebrados por trabalho do app;
- endpoint de health V3 conhecido: `/api/inventory-trace-v3/health`;
- Collector historicamente usa JSON persistente/GitHub mirror, não o runtime Android.

Cloud API:
- `cafeina-cloud-api/`
- PostgreSQL reutilizável
- toda estrutura nova CAFEÍNA no schema `cafeina_ai`
- não executar DROP automático em tabelas legadas
- variáveis usadas: `DATABASE_URL`, `DATABASE_SSL`, `PUBLIC_BASE_URL`, `PORT`, `NODE_ENV`.
- migração de envs do Collector deve ser compatível: criar novo mesmo valor → testar → confirmar → remover antigo → remover fallback depois.
- aliases legados podem existir temporariamente; não apagar antes de provar dependências.
- considerar `rootDir` do Render.
- novo servidor/banco CAFEÍNA já foi autorizado; não pedir autorização novamente para a direção já aprovada.
- nunca reproduzir segredos desnecessariamente.

## ERROS DE PROCESSO IDENTIFICADOS E CORRIGIDOS NAS REGRAS

Falhas ocorridas:
- polling repetitivo de CI;
- micro-updates enchendo a conversa;
- parar porque CI estava pendente;
- parar ao terminar PR/etapa;
- reconsultar o mesmo job várias vezes;
- tratar regra técnica/checkpoint como gatilho de conversa;
- re-pedir autorização já concedida;
- fragmentar desenvolvimento em operações minúsculas.

Correção vigente:
- Protocolo Definitivo consolidado em `docs/CAFEINA_OPERATIONAL_PROTOCOL.md`;
- as 141 regras operacionais antigas e as 6 regras intermediárias NÃO permanecem como sistemas concorrentes;
- Plano Mestre = especificação do produto; Protocolo = como desenvolver; Handoff = estado mutável;
- execução por objetivo e em blocos substanciais;
- consultas em lote;
- erro corrigível tratado internamente;
- CI pendente não gera polling;
- mínimo de narração;
- execução contínua: não encerrar voluntariamente enquanto existir ação segura, autorizada e relevante executável autonomamente;
- parada somente por dependência real do usuário, pausa/cancelamento ou limitação real das ferramentas;
- continuidade obrigatória entre chats.

## MODELO BASE PARA O PRÓXIMO CHAT

Ao receber “continua”:
1. Ler este arquivo e o protocolo operacional.
2. Verificar GitHub real em lote.
3. Não narrar micro-etapas.
4. Consumir primeiro trabalho executável, depois independente, depois pendências externas.
5. Resolver erros corrigíveis internamente.
6. Não retornar porque um PR/merge/teste/fase terminou.
7. Continuar pelas fases do roadmap até existir dependência real do usuário ou limite inevitável da sessão.

## CONTINUE EXATAMENTE DAQUI

Estado verificado em 2026-09-23:
1. #123 integrado: repository transacional project-scoped de knowledge.
2. #128 integrado: migration v1→v2 de provenance.
3. #132 integrado: fresh installs v2 criam knowledge_links e foreign keys são habilitadas.
4. #142 integrado: gate obrigatório de saída do protocolo; se existe ação autônoma segura/relevante, resposta final é inválida e o trabalho continua.
5. #138, #139, #140 e #141 são clean rebuilds sobre bases recentes para support repositories, test evidence, decisions/failures e experiments/snapshots; último estado: CI em execução. Não parar/pollar repetidamente: consumir trabalho independente e integrar/reconstruir conforme o main avançar.
6. Falha anterior de #137 foi infraestrutura do runner: download do NDK 27.2 retornou `ZipFile unknown archive`; não foi evidência de falha do código. Re-run dos failed jobs foi solicitado.
7. Continuar Fase 15 até cobrir provenance linking transacional, lifecycle de knowledge, migrations/testes de reopen e repositórios restantes necessários.
8. Em seguida avançar Fase 16 CAFEÍNA AI core interface sem misturar/tocar o Collector.
9. Antes de qualquer resposta final, aplicar o gate do Protocolo Definitivo.

## REGRA FINAL DE HANDOFF

Este documento não substitui o Plano Mestre de 300 itens. O Plano Mestre é a especificação do produto; o Protocolo Definitivo define como desenvolver; este Handoff registra apenas o estado mutável necessário para retomada. Não é necessário duplicar integralmente o Plano Mestre neste handoff.

## ATUALIZAÇÃO 2026-09-23 — FASES 15/16
- Integrados no main: #144 support repositories, #145 test evidence, #146 decisions/failures, #147 provenance links e #149 CafeinaAiCore foundation.
- #148 lifecycle encontrou regressão real no teste antigo: a política passou a rejeitar EXPERIMENTAL→CONSOLIDATED por exceção; teste corrigido e CI reexecutando.
- #152 falhou corretamente por dependências AI ainda não integradas; substituído por integração coesa #155 sobre main atual.
- #153/#154 são rebuilds intermediários; #155 consolida capabilities fail-closed + trusted project context + provider boundary sobre CafeinaAiCore já integrado.
- Próximo fluxo: integrar lifecycle quando verde; integrar #155 quando verde; adicionar testes do DefaultCafeinaAiCore e persistência/reopen da Knowledge Store; então avançar chat/missões da Fase 17.

## ATUALIZAÇÃO DE PROCESSO — 2026-09-24

- O usuário determinou blocos de criação com **meta mínima de 25 minutos de trabalho útil contínuo por execução**, quando sessão/ferramentas permitirem; não fazer espera artificial nem prometer execução após encerrar resposta.
- A regra está incorporada à seção 2.1 do protocolo canônico. `AGENTS.md` e `docs/DEVELOPMENT_WORKFLOW.md` são resumos/procedimentos, não protocolos concorrentes; `docs/DEVELOPMENT_HANDOFF_TEMPLATE.md` preserva estado entre sessões.
- Não encerrar por CI pendente, commit, PR ou etapa; trabalhar em outra frente segura sem misturar diffs. Não usar polling repetitivo. O gate da seção 64 continua aplicável também após os 25 minutos.
- PR #165: contrato inicial de operações AI; consultar o estado atual do GitHub antes de afirmar CI/merge. PR #166: atualização do processo, incluindo este handoff. Nenhum estado de CI aqui substitui consulta ao SHA atual.
- O pedido de alterar o método não autoriza merge do código de IA do PR #165, deploy, mudanças destrutivas ou alterações do Collector. Merge de qualquer mudança exige autorização explícita e revisão/testes pertinentes.
