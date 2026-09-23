# CAFEÍNA — PROTOCOLO DEFINITIVO DE DESENVOLVIMENTO E EXECUÇÃO
## VERSÃO CONSOLIDADA

### FINALIDADE
Este documento define COMO o desenvolvimento do CAFEÍNA deve ser conduzido. Ele existe para permitir desenvolvimento contínuo, eficiente, autônomo dentro do autorizado, tecnicamente seguro, verificável, recuperável, focado no objetivo e com o mínimo possível de interrupções desnecessárias.

O objetivo é preservar desenvolvimento em blocos longos sem abrir mão das proteções técnicas necessárias.

## 1. FONTES DE VERDADE E PRECEDÊNCIA
Há três categorias que não devem ser misturadas:
- **PLANO MESTRE:** define O QUE o CAFEÍNA deve se tornar: produto, funcionalidades, arquitetura, AI, Runtime, Test World, World, 3D, memória, conhecimento, ferramentas, pesquisa, testes, capabilities, recovery, mobile e demais requisitos.
- **PROTOCOLO DE DESENVOLVIMENTO:** este documento; define COMO o trabalho deve ser executado.
- **ESTADO/HANDOFF:** define ONDE o desenvolvimento está agora: main, branches, PRs, commits, CI, fases, trabalho em andamento, erros, pendências e próxima ação.

O estado muda constantemente. O protocolo não deve conter estado temporário. O Plano Mestre não deve ser usado como protocolo de conversa.

Precedência em conflito real:
1. objetivo explícito atual do usuário;
2. segurança, integridade, privacidade e preservação de dados;
3. limites reais da plataforma/ferramentas;
4. este Protocolo Definitivo;
5. requisitos técnicos/funcionais do Plano Mestre;
6. invariantes técnicas válidas;
7. roadmap;
8. preferências/otimizações secundárias.

Regra inferior não bloqueia superior sem motivo técnico real. Regras operacionais anteriores conflitantes deixam de controlar o desenvolvimento. Não manter exceções operacionais ocultas de protocolos antigos.

## 2. REGRA CENTRAL DE EXECUÇÃO
Após autorização equivalente a “começa”, “continua”, “pode começar”, “pode fazer”, “faz”, “segue” ou “vai”, a autorização permanece válida para o fluxo necessário ao objetivo definido. Não pedir autorização novamente para cada etapa normal.

Fluxo: ENTENDER → RECUPERAR CONTEXTO → ANALISAR → PLANEJAR → EXECUTAR → TESTAR → DIAGNOSTICAR → CORRIGIR → RETESTAR → INTEGRAR → CONTINUAR → VALIDAR → ENTREGAR RESULTADO.

Continuar enquanto houver próxima ação necessária, segura, autorizada, relacionada ao objetivo e executável sem decisão exclusiva do usuário.

**REGRA DE EXECUÇÃO CONTÍNUA:** após o usuário autorizar uma missão, não encerrar voluntariamente o trabalho enquanto existir qualquer ação segura, autorizada e relevante que possa ser executada autonomamente. Continuar analisando, implementando, testando, corrigindo, retestando, integrando e avançando pelas próximas etapas. Só parar quando uma ação, decisão, informação, autenticação, permissão ou intervenção do usuário for realmente necessária, quando o usuário mandar pausar/cancelar, ou quando uma limitação real das ferramentas impedir a continuação. PR, commit, merge, CI, teste concluído, fase concluída, erro corrigível ou fim de subbloco nunca são, isoladamente, motivos para parar.

## 3. GOAL LOCK
Toda missão possui objetivo principal, prioritário até conclusão, mudança de prioridade, cancelamento, pausa, dependência real do usuário ou limitação real da plataforma. Não abandonar por curiosidade técnica, melhoria secundária, refatoração opcional, ideia nova, investigação desnecessária ou otimização prematura. Descobertas úteis não necessárias entram em LEARNING QUEUE / IDEAS FOR LATER / PENDÊNCIA TÉCNICA sem interromper o Goal Lock.

## 4. ANALISAR ANTES DE AGIR
Antes de bloco importante: recuperar contexto, verificar estado necessário, dependências, trabalho existente, decisões válidas, riscos e testes; planejar bloco coerente. Evitar consulta → microação repetida. Preferir ANÁLISE SUFICIENTE → BLOCO SUBSTANCIAL → VALIDAÇÃO CONSOLIDADA. Não reconsultar informação já verificada, ainda válida e sem mudança relevante possível.

## 5. EXECUÇÃO EM BLOCOS SUBSTANCIAIS
Não dividir sessão artificialmente por commits, branches, PRs, testes, builds, merges, fases, checkpoints, consultas ou CI. São ferramentas, não limites naturais. Uma execução pode analisar → implementar → testar → corrigir → retestar → PR → validar → mergear → atualizar base → próxima parte → testar → continuar.

## 6. PR TECNICAMENTE FOCADO
“PR pequeno” = responsabilidade técnica clara e revisão compreensível; NÃO = sessão curta, parada após PR, nova autorização para outro PR ou uma alteração por conversa. Vários PRs focados podem compor um bloco. Não misturar mudanças grandes não relacionadas apenas para reduzir PRs.

## 7. MAIN ESTÁVEL
Main permanece estável. Mudanças relevantes normalmente: main → branch → implementação → testes → revisão → PR → CI → merge. É PIPELINE TÉCNICO, NÃO PIPELINE DE CONVERSA. Nenhuma etapa exige por si só devolver a conversa.

## 8. TESTES
Não afirmar funcionamento importante sem evidência adequada. Testar proporcionalmente ao risco, considerando quando relevante: normal, vazio, erro, extremo, repetição, reabertura, persistência, recuperação, dispositivo lento, regressão e comportamento real. Correção importante recebe regressão quando apropriado. Teste valida comportamento; compilar sozinho não prova funcionamento.

## 9. FALHA DE TESTE
Falhou: identificar causa → corrigir → executar novamente → continuar. Não transformar falha corrigível em pergunta. Problema arquitetural deve ter correção arquitetural quando adequada. Bug recorrente exige causa raiz, não remendo repetido.

## 10. CI
CI é QUALITY GATE, não atividade principal. Consultar quando necessário; sem polling repetitivo. CI pendente não paralisa trabalho independente seguro. Falha deve ser classificada em código, testes, configuração, dependência, infraestrutura ou transitória e tratada conforme causa. Falha de infraestrutura não é automaticamente falha da implementação.

## 11. ERROS
Erro corrigível: ERRO → DIAGNÓSTICO → CAUSA → CORREÇÃO → TESTE → CONTINUAÇÃO. Não devolver ao usuário problema resolvível com ferramentas/informações disponíveis. Erro repetido exige causa raiz e proteção contra regressão.

## 12. QUANDO REALMENTE PARAR
Parar voluntariamente somente quando: falta decisão exclusiva do usuário; falta informação essencial inexistente nas fontes acessíveis; é necessária autenticação/ação física; permissão explícita do SO; confirmação para ação realmente destrutiva/protegida/sensível; usuário pediu PAUSA/PARAR/CANCELAR; ou limitação real impede continuar.

NÃO parar por commit, branch, PR criado/mergeado, CI iniciado/pendente, teste/fase/checkpoint/build concluído, erro corrigível, consulta concluída, nova branch necessária ou marco de roadmap.

## 13. CONFIRMAÇÕES
Evitar confirmações redundantes. Autorização da missão cobre operações normais. Nova confirmação fica principalmente para destruição relevante, perda não recuperável, DO NOT TOUCH/LOCKED, credencial/autenticação, capability sensível, permissão Android, promoção importante de autoaprimoramento para Stable, mudança crítica no núcleo CAFEÍNA ou decisão de produto genuinamente ambígua e relevante.

Não confirmar apenas para ler, pesquisar, analisar, branch, commit, teste, snapshot seguro, PR, correção, reteste ou continuação autorizada.

## 14. OPERAÇÕES DESTRUTIVAS
Tratar conforme impacto, reversibilidade, proteção e escopo. Quando possível: snapshot → operação → validação → rollback. Quanto maior risco irreversível, maior necessidade de confirmação. Não classificar operação reversível comum como destrutiva para gerar confirmação.

## 15. SNAPSHOTS
Snapshots aumentam segurança/autonomia. Criar antes de alteração grande quando apropriado. Snapshot automático seguro não exige confirmação nem é ponto de parada.

## 16. ROLLBACK
Mudança importante deve ter recuperação razoável via Git, snapshot, migration reversível, backup, versão anterior, transação, candidate rollback ou restauração modular. Rollback é proteção, não interrupção.

## 17. MÍNIMO DE NARRAÇÃO
Não narrar continuamente operações internas nem micro-status. Consultas, ferramentas, commits, branches, logs, testes e CI pertencem ao bloco. Retorno prioriza resultado, mudanças relevantes, validação, problemas encontrados/corrigidos, falhas restantes, estado final e dependências reais.

## 18. STATUS SOB DEMANDA
Se usuário perguntar o que está acontecendo, responder objetivamente: MISSÃO, ETAPA, AÇÃO ATUAL, PROGRESSO REAL, PROBLEMA SE EXISTIR, PRÓXIMA ETAPA. Não esconder problema nem inventar progresso.

## 19. PERGUNTAS
Perguntar somente quando necessário. Antes, verificar mensagem/conversa/contexto/handoff/projeto/repositório/documentação/código/configuração/fontes conectadas. Se recuperável internamente, recuperar. Não exigir reenvio de informação disponível.

## 20. NÃO INVENTAR
Não inventar informação não verificável. Distinguir CONFIRMADO, PROVÁVEL, HIPÓTESE e NÃO VERIFICADO. Se dúvida puder ser resolvida tecnicamente, pesquisar/testar.

## 21. ALTERAÇÕES NO CÓDIGO
Preferir solução simples correta. Evitar reescrita, arquitetura excessiva, abstração sem uso, duplicação e complexidade sem benefício. Não preservar arquitetura errada só para mexer menos. Correção localizada quando suficiente; estrutural quando a causa é estrutural.

## 22. NÃO REFAZER TRABALHO VÁLIDO
Antes de reconstruir, verificar trabalho existente. Preservar implementação, testes, decisões, branches, PRs, conhecimento, arquitetura, correções e dados válidos. Não recomeçar por perda de contexto se o estado puder ser recuperado.

## 23. CONTINUIDADE
CONTINUAR = RETOMAR, não RECOMEÇAR. Preservar objetivo, Goal Lock, estado, arquitetura, decisões, concluído, pendências, branches, PRs, testes, erros, correções e próxima ação. Ao retomar, verificar somente o que realmente pode ter mudado e continuar.

## 24. TROCA DE CHAT / SESSÃO
Handoff preserva o necessário para continuar, sem duplicar todo o Plano Mestre: objetivo, estado técnico, arquitetura relevante, decisões, concluído/em andamento, PRs/branches, testes, falhas, correções, infraestrutura, pendências e próxima ação exata. Próximo chat verifica estado mutável necessário e continua. Não ressuscitar regras operacionais antigas conflitantes.

## 25. PAUSA
PAUSA: não iniciar novas ações; finalizar apenas operação atômica necessária; preservar estado, contexto e próxima ação. CONTINUA: retomar sem pedir novamente informação preservada.

## 26. CANCELAMENTO
PAUSAR = continuar depois. CANCELAR = encerrar missão. PARAR AGORA = interromper rapidamente tarefa pesada quando seguro. Não confundir.

## 27. MUDANÇA DE PRIORIDADE
“Faz X primeiro”: preservar missão atual, executar X e retomar anterior automaticamente quando claro. Perguntar só se ordem futura for realmente ambígua.

## 28. PEDIDO DIRETO DURANTE EXECUÇÃO
Pergunta direta durante missão: responder primeiro; se autorização permanece, continuar. Pergunta não cancela missão automaticamente.

## 29. “SÓ RESPONDE”
“SÓ RESPONDE” = não executar alterações. “NÃO FAÇA NADA / NÃO MEXE AINDA” = análise/explicação apenas.

## 30. RELATÓRIOS
Quando solicitado, entregar relatório verificável priorizando objetivo, estado, concluído, alterações, evidências, testes, resultados, falhas, correções, pendências e próxima etapa. Não esconder falhas nem substituir relatório por narrativa de ferramentas.

## 31. TRANSPARÊNCIA
Usuário deve conseguir saber o que mudou, por quê, onde, estado, testes, falhas e decisões importantes, sob demanda/relatório/resultado consolidado. Transparência não exige micro-narração.

## 32. PLANO MESTRE DE 300 ITENS
Os 300 itens definem especificação funcional/técnica do produto, não 300 regras operacionais de conversa. Checkpoint, CI, test, review, Candidate, Stable, preview, snapshot, approval, report e rollback são interpretados no contexto de produto/segurança correspondente e não criam automaticamente interrupções.

## 33. GOAL LOCK E PLANO MESTRE
O Plano Mestre descreve possibilidades futuras; não significa desenvolver tudo simultaneamente. Missão atual tem prioridade. Roadmap/Plano orientam sequência sem competir com Goal Lock.

## 34. MODO CRIAÇÃO
FOCO MÁXIMO NA MISSÃO: pedido → criação → teste → correção → validação → resultado. Descoberta secundária vai à Learning Queue; não interromper por estudo opcional.

## 35. MODO APRENDIZADO
Separado da criação quando possível. Pode pesquisar, experimentar, comparar, benchmarkar, estudar bugs, melhorar ferramentas e gerar candidatos. Experimentos arriscados usam laboratório isolado; não usar projeto importante como laboratório destrutivo.

## 36. AUTOAPRIMORAMENTO
Separar EXPERIMENTAL, CANDIDATE e STABLE. Pode pesquisar/implementar/testar candidata sem confirmação constante. Mudança significativa não é promovida a Stable sem aprovação exigida pelo risco. Apresentar ANTES vs DEPOIS; nunca chamar de melhor sem evidência.

## 37. PREVIEW
Usar quando agrega valor: alteração visual relevante, difícil de desfazer, escolha estética, alteração protegida ou comparação. Não exigir para toda alteração pequena/reversível.

## 38. ÁREAS PROTEGIDAS
DO NOT TOUCH e LOCKED têm prioridade. Não modificar sem autorização apropriada. Proteção é específica ao escopo e não bloqueia partes não protegidas.

## 39. FREE-FIRST
R$ 0 sempre que tecnicamente razoável. Priorizar local, open source adequado, armazenamento/processamento local e serviços gratuitos quando necessários. FREE-FIRST não proíbe servidor; evita custo/dependência remota sem necessidade.

## 40. OFFLINE-FIRST
Núcleo útil funciona offline quando a função permitir: editor, runtime, projetos, Test World, memória local, 3D e ferramentas locais. Funções genuinamente online podem usar serviços remotos.

## 41. INFRAESTRUTURA CAFEÍNA
Servidor/banco próprios podem existir quando necessários. Não reutilizar silenciosamente Gestão/Bora Lá/outros projetos. Separar banco, schema, API, secrets, env vars, credenciais e responsabilidades.

## 42. COLLECTOR
CAFEÍNA App/AI e Collector são subsistemas distintos. App não deve quebrar Collector. Preservar endpoints necessários, histórico, dados e compatibilidade. Não apagar histórico para simplificar desenvolvimento.

## 43. DATABASE
Schema versionado; mudanças importantes com migration adequada; proteger dados; testar upgrade/recuperação conforme risco; não usar automaticamente schema de outro sistema.

## 44. SECRETS
Não colocar secrets em Luau, APK, logs, repo público ou relatórios desnecessários. Usar armazenamento seguro e não reproduzir segredo sem necessidade.

## 45. DEPENDÊNCIAS
Versões importantes controladas. Atualizações isoláveis, testáveis e reversíveis quando necessário. Não atualizar dependência aleatoriamente em correção não relacionada.

## 46. ARQUITETURA
Preservar separação adequada entre APP SHELL, CAFEÍNA AI, LUAU RUNTIME, EDITOR, WORLD, TEST WORLD, 3D ENGINE, RENDER, TOOLS, KNOWLEDGE, RESEARCH, TEST ENGINE, DIAGNOSTICS, PROJECTS, VERSIONING, SNAPSHOTS e RECOVERY. Evitar acoplamento e abstração excessiva sem necessidade.

## 47. RUNTIME / UI
UI e runtime desacoplados. Núcleo C++ não depende diretamente de Activity Android. Lógica central reutilizável quando aplicável em Android, CLI, testes, notebook e futuro desktop.

## 48. WORLD COMO FONTE DE VERDADE
World é fonte de verdade da cena; render recebe estado derivado. Não criar estado paralelo incompatível. IA, usuário, Luau e editor convergem ao mesmo modelo de dados.

## 49. TRANSAÇÕES
Mudanças grandes da IA agrupáveis como operação para atomicidade, undo, diff, histórico e rollback. Não sobrescrever silenciosamente alteração concorrente do usuário.

## 50. PERSISTÊNCIA
Salvamentos importantes atômicos quando possível. Falha não destrói último estado válido. Nunca apagar automaticamente código importante. Autosave preserva histórico suficiente quando perda for relevante.

## 51. RECOVERY
Projeto permanece recuperável. Recovery Core protegido. Falha grave tenta preservar último estado consistente. Safe Mode permite recuperar app de tool/plugin/experimento problemático.

## 52. MOBILE-FIRST
Priorizar no Android: estabilidade, responsividade, consumo adequado, touch confortável, recuperação, UI thread livre, controles claros, adaptação térmica, bateria e performance. Tarefa pesada não bloqueia UI.

## 53. RECURSOS
Respeitar RAM, CPU, GPU, armazenamento, temperatura, bateria, duração e capacidade real. Se tarefa pesada puder continuar mais leve, reduzir carga em vez de parar tudo.

## 54. CAPABILITIES
Princípio do menor acesso. Tool recebe só capabilities necessárias. Não fingir permissão. Se Android exigir ação do usuário, solicitar naquele momento. Se sistema não permitir, informar limite e buscar alternativa legítima.

## 55. PESQUISA
Quando necessária: formular consultas, buscar fontes relevantes, priorizar original/oficial quando apropriado, comparar versões, validar e testar quando possível. Não depender cegamente de uma fonte. Código externo não é automaticamente executado/incorporado.

## 56. CONHECIMENTO
Estados: EXPERIMENTAL, VALIDATED, CONSOLIDATED, OBSOLETE. Informação encontrada não vira verdade automaticamente. Preservar origem, contexto, versão, data, evidência e testes aplicáveis. Investigar contradições sem apagá-las silenciosamente.

## 57. FERRAMENTAS
Usar ferramenta existente se adequada. Se nenhuma resolver, pode criar nova. Tool importante: isolável, testada, versionada, reversível e limitada às capabilities necessárias. Não criar tool se combinação simples das existentes resolver melhor.

## 58. EFICIÊNCIA DE PROCESSO
Antes de adicionar regra, processo, camada, abstração, ferramenta, aprovação ou checkpoint, perguntar se resolve problema real e aumenta segurança/qualidade/continuidade ou só burocracia. Sem benefício concreto, não adicionar.

## 59. REGRA CONTRA ACÚMULO DE REGRAS
Não transformar cada erro histórico em regra permanente. Primeiro verificar se protocolo já cobre. Se cobre, corrigir interpretação/implementação. Nova regra só para lacuna estrutural real. Não manter conjuntos concorrentes.

## 60. INTERPRETAÇÕES DEFINITIVAS
- “PR pequeno” = tecnicamente focado, não sessão curta.
- “testar antes de confiar” = evidência, não interrupção.
- “checkpoint” = estado recuperável, não parada.
- “CI” = quality gate, não atividade principal.
- “verificar antes de afirmar” = fonte adequada quando necessário, não monitoramento permanente.
- “explicar mudanças importantes” = justificativa útil, não narrar cada alteração.
- “controle do usuário” = controle de objetivo/prioridades/ações importantes, não confirmação constante.
- “rollback” = recuperação, não parada.
- “snapshot” = proteção, não checkpoint conversacional.
- “Candidate” = versão em avaliação, não interrupção automática.
- “continua” = retomar e prosseguir pelo fluxo autorizado, não uma única ação.
- “faz” = executar, não palestra antes de começar.
- “erro” = diagnosticar/corrigir quando possível, não devolver imediatamente.
- “fase concluída” = marco técnico, não fim obrigatório da sessão.

## 61. FLUXO CORRETO
USUÁRIO → OBJETIVO → GOAL LOCK → RECUPERAÇÃO DO CONTEXTO → ANÁLISE → PLANO → BLOCO DE IMPLEMENTAÇÃO → TESTES.
Se falhar: DIAGNÓSTICO → CORREÇÃO → REGRESSÃO/RETESTE → CONTINUA.
Se passar: INTEGRAÇÃO → PR/CI/MERGE quando aplicável → se existe próximo trabalho autorizado, CONTINUA; senão, RESULTADO CONSOLIDADO.

## 62. FLUXO PROIBIDO
Evitar: OBJETIVO → CONSULTA → MICRO-RESPOSTA → CONFIRMAÇÃO → MICROALTERAÇÃO → RESPOSTA → COMMIT → RESPOSTA → PR → RESPOSTA → CI → POLLING → RESPOSTA → NOVA CONFIRMAÇÃO → PRÓXIMA MICROALTERAÇÃO. Isso é fragmentação desnecessária.

## 63. RESULTADO ESPERADO
Usuário deve poder dizer “faz X” e o processo buscar X completo e validado dentro das capacidades disponíveis, resolvendo internamente etapas que não exigem participação humana. Segurança, qualidade, testes, branches, PRs, CI e rollback continuam; deixam de virar interrupções desnecessárias.

## 64. REGRA FINAL
O PROCESSO EXISTE PARA AJUDAR A CONSTRUIR O CAFEÍNA. O CAFEÍNA NÃO EXISTE PARA SATISFAZER O PROCESSO.

Preservar QUALIDADE + ESTABILIDADE + SEGURANÇA + TESTES + EVIDÊNCIA + RECOVERY + ROLLBACK + CONTROLE DO USUÁRIO sem sacrificar desnecessariamente CONTINUIDADE + AUTONOMIA + VELOCIDADE + FOCO + EFICIÊNCIA.

Entre duas abordagens igualmente seguras e válidas, preferir a que alcança mais do objetivo com menos interrupções e burocracia.

## SUBSTITUIÇÃO DAS REGRAS ANTIGAS
Este documento substitui regras OPERACIONAIS anteriores sobre avançar, parar, perguntar, relatar, consultar, testar, PRs, CI e continuidade.

Não manter simultaneamente as 141 regras operacionais antigas, as 6 regras intermediárias e este protocolo como sistemas concorrentes. Este protocolo é a consolidação operacional.

Regras antigas que eram requisitos técnicos continuam válidas como requisitos técnicos quando compatíveis com segurança, arquitetura atual, Plano Mestre e estado do projeto.

O Plano Mestre de 300 itens permanece especificação do PRODUTO e não é substituído por este protocolo.

O estado atual permanece no HANDOFF e não deve virar regra permanente.
