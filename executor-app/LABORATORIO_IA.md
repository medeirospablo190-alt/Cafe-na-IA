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


## Terceira entrega — Recovery Core, cópias verificáveis de candidatos

- `LaboratorySnapshotStore` recebe **somente** os bytes de um insumo de teste aprovado e passado explicitamente pelo chamador interno; não examina, copia nem migra arquivos do editor, scripts antigos, projetos ou Mundo. Antes da execução isolada, `LaboratoryCandidateRunner` cria a cópia da fonte candidata em `files/laboratory/<escopo>/snapshots/`.
- Cada snapshot é único, tem formato e versão, ID UUID, rótulo validado, data, tamanho e SHA-256 do conteúdo. A gravação utiliza arquivo temporário, fsync e move atômico quando disponível. A leitura valida versão, identidade, tamanho e hash antes de devolver **uma nova cópia na memória**, sem sobrescrever nenhum arquivo original.
- Limites iniciais: 128 KiB por snapshot, 64 snapshots por escopo de projeto, orçamento de entradas para evitar resíduos de falhas ocupando armazenamento ilimitado. Ao atingir o limite, o laboratório recusa novas cópias e não apaga as antigas. Rascunhos temporários resultantes de interrupção exigem manutenção controlada futura; não são apagados automaticamente.
- O relatório de teste registra o UUID e a integridade do snapshot sem incluir o texto da fonte. Se a cópia falhar na verificação após a execução, o caso é marcado FAIL, mesmo que o runtime tenha devolvido o valor esperado. A tela de relatório exibe o identificador e o resultado da verificação, nunca o conteúdo da cópia.
- Os snapshots guardam o **código candidato fornecido internamente**, que poderá conter informações sensíveis se uma futura IA for autorizada a usá-las. Permanecem no diretório privado do aplicativo, não são exportados automaticamente e não são enviados a servidores; acesso root ou código com o mesmo UID ainda pode lê-los. Uma futura política de retenção e autorização deve tratar essa limitação antes de usar dados pessoais.
- Testes JVM exercitam cópias imutáveis, restauração sem sobrescrita, separação por projeto, hash inválido, symlinks, caminho malicioso, quotas e preservação de dados; o teste Android liga o snapshot ao resultado da execução isolada.

**Escopo real:** esta etapa implementa baseline e leitura verificada, não uma restauração automática dos arquivos do usuário, snapshot de Mundo 3D, armazenamento resistente a adulteração ou rollback de uma versão estável. Recuperar/reaplicar mudanças no núcleo requer aprovação do usuário e controles independentes que ainda serão implementados.


## Quarta entrega — bancada geométrica do Test World (headless)

- `LaboratoryTestWorld` mantém uma fixture imutável de 11 caixas, em milímetros inteiros, com volumes sólidos e zonas. Essa é uma **cópia congelada** da geometria inicial da cena para testes; não carrega, modifica nem executa o Mundo em que o usuário joga.
- A ferramenta interna `world-contact@0.1.0` é allowlisted no `LaboratoryEngine`; aceita apenas seis inteiros dentro dos limites para uma consulta AABB (centro e semiextensões), sem código arbitrário, rede ou arquivos. Registra contatos geométricos e zonas em ordem fixa e reprova resultados divergentes dos valores esperados.
- O relatório inclui versão da ferramenta e SHA-256 da fixture, além do hash dos casos e da seed. Isso permite distinguir resultados de ambientes geométricos diferentes em execuções futuras.
- Testes JVM cobrem contato sólido, zona, fronteira sem sobreposição, parser malicioso, limites, fixture imutável e divergência de resultados. Um teste Android verifica que a ferramenta pode rodar sem abrir a Activity do Godot, e que o resultado fica persistido no cofre de relatórios.

**Limite técnico:** a bancada usa interseção geométrica AABB, não simula gravidade, colisão de cápsulas, rigid bodies, materiais, animações ou renderização do Godot. O Test World completo e a suíte de física/3D ainda precisam de um worker Godot próprio, testado e separado, antes de fornecerem garantias sobre o Mundo real.


## Quinta entrega — versionamento seguro de ferramentas

- `LaboratoryToolRegistry` registra cada ferramenta por `toolId`, versão semântica, SHA-256 do artefato, origem, capacidades, testes obrigatórios, compatibilidade e limites de execução/entrada. Cada versão é criada uma única vez e nunca é sobrescrita.
- O ciclo de vida é separado em `EXPERIMENTAL → CANDIDATE → STABLE`. Uma versão só chega a CANDIDATE quando há relatórios PASS que comprovem o mesmo SHA-256 do artefato registrado.
- A seleção de STABLE não usa um ponteiro mutável que apague rastros. Promoções e rollbacks são eventos create-only; a versão estável ativa é reconstruída pelo histórico completo.
- Promoção para STABLE e rollback exigem um `ApprovalGate` fornecido pelo host e um identificador de aprovação explícita. Não existe implementação permissiva/default no registro. O identificador bruto não é persistido: apenas seu SHA-256 entra no histórico.
- Rollback só pode apontar para uma versão que já tenha sido aprovada como STABLE anteriormente. Versões antigas e seus metadados continuam preservados.
- O registro fica separado por projeto em `files/laboratory/<escopo>/tool-registry/`, com validação de IDs, versões, hashes, limites, caminhos e symlinks. Ao atingir quotas, novas gravações são recusadas sem apagar histórico.
- Testes JVM cobrem imutabilidade, rejeição de path traversal, evidência vinculada ao hash exato do artefato, bloqueio sem aprovação, promoção de duas versões e rollback para a estável anterior.

**Limite técnico:** o gate de aprovação já é obrigatório no núcleo do registro, mas a tela Android que emitirá/aprovará esse gate ainda não foi ligada. Portanto esta entrega não dá à IA autorização para promover ferramentas sozinha e não muda nenhuma versão STABLE do aplicativo atual.


## Sexta entrega — métricas e detecção determinística de regressões

- `LaboratoryRegressionEngine` compara uma execução baseline já registrada com uma execução candidata sem executar código novo. A comparação exige identidade do mesmo harness, seed reproduzível, conjunto de casos compatível e, quando configurado, o mesmo hash de ambiente.
- Cada caso preserva esperado/obtido, PASS/FAIL e hash da entrada. Mudança de casos, mudança do resultado esperado, falha de um caso, baseline inválida, seed diferente ou ambiente diferente tornam a comparação FAIL.
- A política de performance define percentual máximo de lentidão e uma tolerância absoluta em milissegundos. O cálculo é determinístico, limitado e protegido contra overflow; o relatório registra duração baseline, duração candidata, limite permitido e delta.
- `LaboratoryRegressionStore` lê apenas relatórios já persistidos pelo laboratório e grava comparações create-only em `files/laboratory/<escopo>/regressions/`. O registro contém IDs dos runs, hashes, métricas, política, testes cobertos e motivos do veredito; não grava fonte de ferramenta.
- O cofre de regressões é separado por projeto, recusa sobrescrita, valida caminhos/symlinks e possui quota inicial de 256 comparações de até 32 KiB cada.
- Testes JVM validam equivalência funcional, regressão de duração, diferenças de seed/ambiente/harness, mudança de casos e limites da política. Testes Android validam persistência real de comparações PASS/FAIL e impedem usar o mesmo run como sua própria baseline.

**Limite técnico:** esta entrega cria a evidência objetiva de regressão, mas ainda não a torna requisito automático para promover uma nova versão a STABLE. A ligação entre o registro de versões e essas comparações será feita como gate separado, para não permitir que uma ferramenta se autopromova apenas por produzir seu próprio relatório.
