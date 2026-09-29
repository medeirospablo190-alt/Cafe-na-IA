# CAFEÍNA — Laboratório interno da IA

## Regra do produto

O laboratório é parte do aplicativo Android, mas não é uma área em que o usuário opera ferramentas. A futura IA e seus especialistas farão isso. O usuário define objetivos, permissões e limites; consulta relatórios; pausa, cancela, restaura e aprova mudanças relevantes. O motor de teste deve funcionar antes de existir a IA principal.

Sem reutilizar dados, credenciais, infraestrutura ou permissões do Grupo Lua. Nenhuma modificação do cliente Roblox ou do anti-cheat de terceiros; o Mundo e os simuladores usados são próprios.

## Implementação efetiva desta primeira etapa

- LaboratoryEngine: harness determinístico JVM sem acesso a arquivos, rede ou execução de código gerado. Somente a ferramenta embutida source-fingerprint@1.0.0 roda no processo Android normal. Calcula hash SHA-256, bytes UTF-8 e linhas. Isto NÃO verifica sintaxe nem correção Luau.
- Solicitação registra seed, limite de tempo, até 16 casos e limites de texto por caso/lote. Resultados: PASS/FAIL/CANCELLED/TIMEOUT, esperado versus obtido, hashes e duração. Cancelamento tem pontos de verificação entre casos; não interrompe forçadamente código externo.
- LaboratoryRunner exige gravar relatório para devolver êxito; se o cofre estiver inacessível ou cheio, o teste não começa.
- LaboratoryReportStore registra JSON com criação única em files/laboratory/legacy/reports ou files/laboratory/project-<id>/reports. Não usa scripts, autoexec.list, runtime-fs nem projetos reais. Não guarda os textos de fonte testados. Limites: 256 relatórios por projeto e 48 KiB por relatório; não apaga históricos automaticamente.
- SISTEMA > RELATÓRIOS DO LABORATÓRIO é somente leitura. Exibe status, sucessos, falhas, hashes, seed, evidências e duração, sem operar ferramentas.
- Testes JVM e Android verificam contratos, limites, cancelamento, registros e separação entre projetos.

Esta etapa NÃO constitui o laboratório completo ou uma IA de teste. Não roda candidatos arbitrários, não faz testes 3D e não concede acesso ao dispositivo. O registro é create-only por política da classe, não inviolável contra código com o mesmo UID Android ou root.

## Ordem para concluir antes da IA principal

1. Contratos/versionamento: ID, versões, entradas/saídas, capacidades, origem e hash, limites, métricas, testes obrigatórios, compatibilidade e rollback. Novas ferramentas começam EXPERIMENTAL. Candidatos ficam separados de STABLE.
2. Sandbox executável: trabalhador Android em processo isolado, IPC mínimo e permissões explicitamente permitidas. Candidatos não podem ler projetos, scripts privados, dados da IA, credenciais nem controles do núcleo. Cópia de entradas e pasta temporária por sessão. Validar isolamento com testes negativos antes de permitir execução dinâmica.
3. Recovery Core: snapshot por hash do insumo aprovado, execução apenas na cópia, reset entre casos, watchdog, cancelamento/pausa externos ao modelo, limpeza segura, quarentena e restauração. Nem IA nem ferramenta podem modificar o mecanismo de segurança.
4. Tool Workshop: especialistas internos criam, versionam, compõem, testam e arquivam ferramentas de código, diagnóstico, modelos 3D e Mundo. Quick/Batch/Stress/Replay/AI Experiment com seeds, métricas e regressões; Test World independente do Mundo do usuário, headless quando possível.
5. Relatórios e revisão: objetivo, hipótese, ferramenta/versão, hashes, método, seed, ambiente, sucessos, falhas, riscos, métricas antes/depois e rollback. Histórico preservado mesmo após falhas. STABLE só muda após aprovação explícita do usuário.
6. IA de teste opcional: só quando testes determinísticos forem insuficientes. O agente de teste propõe casos e solicita execução ao Test Engine; não avalia sozinho sua própria qualidade, não apaga falhas nem promove candidatos. A IA principal só começa depois de laboratório e contratos validados.

## Critérios de conclusão

Código candidato isolado; limites e cancelamento efetivos; snapshots/rollback; testes automatizados e reproduzíveis do Test World; relatórios duráveis; usuário capaz de consultar/autorizar sem operar ferramentas; impossibilidade de a IA alterar controles de segurança; validação de desempenho no aparelho real. O Mundo, os projetos e os scripts antigos permanecem intactos até haver migração específica, validada e aprovada.


## Segunda entrega: execução Luau em trabalhador Android isolado

- LaboratorySandboxService: Service privado, não exportado, com isolatedProcess=true e UID distinto do aplicativo. Recebe código e orçamento por Messenger; executa apenas LuauBridge.nativeExecute, sem habilitar a capacidade fs e sem receber diretório ou descritor de arquivo do projeto.
- LaboratorySandboxClient: cliente de uso interno, uma sessão por solicitação, fonte limitada a 16 Ki caracteres, timeout nativo máximo de 3 s e watchdog independente do processo da IA. Cancelamento envia ABORT ao trabalhador, que encerra o próprio processo isolado. Dados de retorno têm limite de tamanho.
- LaboratoryCandidateRunner: liga o trabalhador a LaboratoryReportStore. Um resultado do runtime só vira PASS quando a primeira saída corresponde ao valor esperado E o relatório foi salvo; erros e timeouts ficam registrados. O texto do candidato, stdout, erros completos e valores de retorno não são gravados no relatório — somente seus hashes e o status.
- Teste Android verifica o sinalizador isolatedProcess, UID diferente do processo principal, execução Luau sem fs e persistência do relatório sem armazenar fonte do candidato.

A execução isolada é apenas a base para ferramentas candidatas. Ainda faltam limites efetivos de memória/CPU verificados no dispositivo, fornecimento opcional e seguro de arquivos temporários, snapshots e Recovery Core, suites de regressão/Stress/Replay, Test World headless, registro de ferramentas e aprovação de promoção de versões. Nenhum agente de IA foi integrado ou autorizado a executar candidatos automaticamente.
