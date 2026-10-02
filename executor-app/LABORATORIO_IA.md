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


## Sétima entrega — gate de regressão para promoção STABLE

- A primeira versão STABLE de uma ferramenta ainda pode ser aprovada sem baseline anterior. A partir da segunda versão, `LaboratoryToolRegistry` exige comparações de regressão PASS antes de aceitar a promoção.
- Cada comparação usada no gate precisa ligar o hash de entrada da baseline ao SHA-256 da versão STABLE atual e o hash candidato ao SHA-256 da versão que está sendo promovida. Comparações genéricas sem um único hash de entrada não servem como prova de promoção.
- O run candidato da comparação precisa estar entre os próprios runs de evidência da promoção, e o conjunto de comparações precisa cobrir todos os `requiredTests` declarados pela ferramenta.
- Um PASS criado com política frouxa é recusado. A política inicial de promoção exige o mesmo ambiente, no máximo **25% de slowdown** e **50 ms de tolerância absoluta**. Esses limites são controlados pelo núcleo do registro, não pela ferramenta candidata.
- Os IDs das comparações aprovadas são gravados no evento append-only de `ACTIVATE_STABLE`, junto com os runs de teste e o hash da aprovação. Assim o motivo exato de uma promoção pode ser reconstruído posteriormente.
- Rollback continua permitido apenas para uma versão que já foi STABLE e continua exigindo aprovação explícita do usuário; não é necessário retestar uma versão previamente aprovada só para voltar a ela.
- Testes Android verificam que upgrade sem regressão é recusado, política permissiva é recusada, comparação estrita é aceita, hashes são vinculados e o histórico preserva a referência da regressão.

**Limite técnico:** os limites de 25%/50 ms são a política inicial fixa do núcleo. Se futuramente eles forem configuráveis, essa configuração deverá pertencer ao usuário/host confiável e nunca ser alterável pelo código candidato ou pela IA isolada.


## Oitava entrega — vínculo imutável da versão ao artefato executável

- `LaboratoryToolArtifactStore` liga uma versão registrada ao snapshot exato que contém seu artefato executável. A primeira modalidade suportada é `LUAU_SOURCE_V1`.
- O vínculo só pode ser criado enquanto a versão ainda está `EXPERIMENTAL`. Depois que vira `CANDIDATE`, a fonte executável fica congelada e não pode ser trocada.
- Antes de gravar o vínculo, o store relê o snapshot pelo Recovery Core e exige que o SHA-256 seja exatamente o `artifactSha256` imutável do registro da ferramenta.
- O arquivo de vínculo guarda somente identidade, tipo, snapshot, hash e data. O código Luau não é duplicado nesse registro.
- Toda leitura futura revalida descriptor + vínculo + snapshot + SHA-256. Snapshot ausente, adulterado, symlink, hash divergente, UTF-8 inválido ou fonte acima do limite do sandbox falham de forma fechada.
- `readActiveStableVerified(toolId)` é o caminho estreito preparado para o futuro executor: o chamador informa apenas o ID da ferramenta; a versão STABLE ativa e o snapshot correto são resolvidos internamente.
- Testes Android verificam vínculo válido, rejeição de hash incorreto, impossibilidade de vincular depois de CANDIDATE, resolução da STABLE ativa e detecção de adulteração física do snapshot.

**Limite técnico:** esta etapa ainda não executa ferramentas STABLE. Ela elimina a ambiguidade entre “versão aprovada” e “bytes que serão executados”. O próximo gate poderá executar somente o artefato retornado por `readActiveStableVerified`, sem aceitar fonte ou versão fornecidas pela futura IA.


## Nona entrega — entrada de dados separada do código da ferramenta

- O runtime ganhou `ExecutionContext.inputText`. No Luau, a entrada aparece somente como a string global `tool_input`; fornecer dados não concede filesystem, rede ou qualquer outra capacidade do host.
- O runtime nativo recusa entradas acima de 16 KiB em bytes. O worker Android aplica um limite ainda mais restrito de 4096 caracteres antes do IPC.
- A JNI ganhou `nativeExecuteWithInput(source, inputText, timeoutMs)`, sem `filesRoot`. O caminho antigo `nativeExecute` continua compatível e equivale a entrada vazia.
- `LaboratorySandboxClient` envia fonte e entrada separadamente e calcula SHA-256 independente para cada uma. O worker continua em `isolatedProcess=true`.
- `LaboratoryCandidateRunner` pode testar exatamente a mesma fonte/snapshot com entradas diferentes, sem concatenar dados ao código e sem mudar o hash da versão.
- Relatórios persistem apenas `toolInputSha256`; o texto bruto da entrada não é salvo. A tela de relatórios mostra somente esse hash.
- A comparação de regressão também exige o mesmo `toolInputSha256` por caso. Se baseline e candidato receberam entradas diferentes, o caso não pode ser usado como evidência de equivalência.
- Testes nativos e Android verificam exposição de `tool_input`, ausência de `fs`, limite de tamanho, hash independente, privacidade do relatório e rejeição de regressões com entradas diferentes.

**Fronteira preparada para a IA:** o próximo executor STABLE poderá receber apenas `toolId + tool_input`. O código executável continuará vindo exclusivamente do vínculo verificado da etapa anterior; a IA não precisará e não poderá reconstruir a fonte para passar parâmetros.


## Décima entrega — gate de execução STABLE verificado

- `LaboratoryStableToolExecutor` é o caminho estreito preparado para a futura IA: o chamador informa somente `toolId + tool_input`. Não existe parâmetro para fonte, versão ou snapshot.
- O executor resolve internamente a versão STABLE ativa, o evento de ativação/rollback aprovado e o artefato ligado ao snapshot verificado. Ferramentas EXPERIMENTAL/CANDIDATE não passam por esse gate.
- Apenas versões que declaram a capacidade explícita `luau-isolated-no-files` podem executar. O gate respeita o menor limite entre o orçamento registrado da ferramenta e o limite rígido do worker isolado.
- A entrada é validada por caracteres e bytes UTF-8 contra o contrato da versão. A fonte nunca é reconstruída ou concatenada com a entrada.
- Depois que o worker termina, o gate relê registro + evento STABLE + vínculo + snapshot. Se a versão ativa, evento, snapshot ou hashes mudaram durante a execução, o resultado é invalidado.
- Um resultado só é devolvido como utilizável após três condições: worker `EXECUTED`, seleção STABLE revalidada e recibo de auditoria persistido.
- `LaboratoryStableUseStore` mantém recibos create-only em `files/laboratory/<escopo>/stable-tool-uses/`. O recibo registra versão, evento STABLE, snapshot, UID do worker, duração e hashes esperados/realmente executados da fonte e da entrada.
- Fonte, `tool_input`, stdout, retorno e erro do runtime não são persistidos no recibo; apenas seus SHA-256. Falhas também são auditadas.
- `SISTEMA > RELATÓRIOS DO LABORATÓRIO` ganhou uma seção somente leitura para a auditoria de uso STABLE.
- Testes Android cobrem execução STABLE válida, privacidade de entrada/saída/erro, falha Luau auditada, bloqueio de ferramenta não-STABLE e bloqueio sem a capacidade explícita de execução isolada.

**Limites atuais:** este gate ainda não é chamado por uma IA e não substitui a futura interface real de aprovação humana. O registro exige um `ApprovalGate`, mas a emissão dessa aprovação pela UI/credencial do dispositivo ainda precisa ser integrada à sequência atual antes de permitir autonomia da IA.


## Décima primeira entrega — aprovação humana autenticada e de uso único

- `LaboratoryApprovalActivity` é privada (`exported=false`) e acessível pela área de relatórios. Ela não executa ferramentas e não é uma interface da futura IA.
- A tela mostra promoções CANDIDATE → STABLE e rollbacks possíveis com versão de origem/destino, SHA-256 do descriptor, SHA-256 do artefato, snapshot, quantidade de evidências e comparações de regressão.
- A primeira decisão exige confirmação explícita e a credencial segura do próprio Android. Sem PIN/senha/bloqueio seguro configurado, nenhuma autorização é registrada.
- `LaboratoryHumanApprovalStore` cria um recibo único e create-only preso à ação, ferramenta, versões origem/destino, descriptor completo por hash, artefato, snapshot verificado, IDs exatos dos testes e IDs exatos das regressões revisadas.
- Uma autorização não muda o estado da ferramenta. Após autenticar, o usuário vê `AUTORIZADA • AINDA NÃO APLICADA` e precisa executar uma segunda ação explícita para promover ou fazer rollback.
- Ao aplicar, o registro relê descriptor, snapshot e estado atual. Qualquer alteração desde a revisão invalida a decisão. O próprio `LaboratoryToolRegistry` revalida os testes/regressões antes de consultar o gate de aprovação.
- O recibo é de uso único. O gate cria um marcador create-only antes de permitir o evento STABLE. Se a gravação final falhar depois disso, a autorização permanece consumida por segurança e uma nova decisão humana é necessária.
- O evento do registro não persiste o ID bruto do recibo; mantém apenas o SHA-256 já previsto pelo histórico de lifecycle.
- Aprovações pendentes idênticas são recusadas para evitar múltiplos recibos equivalentes.
- Testes Android verificam Activity não exportada, autenticação fresca, separação entre autorizar/aplicar, promoção real para STABLE, consumo único, bloqueio de recibo duplicado e invalidação se o snapshot executável for adulterado.

**Limite de segurança:** a confirmação de credencial do Android é uma barreira de interface e o recibo é uma política local do aplicativo. Isto não é uma prova criptográfica contra root ou código arbitrário já executando com o mesmo UID. A IA principal continua não integrada; antes dela, o controlador de permissões deverá manter esse caminho humano fora das APIs disponíveis ao modelo.


## Décima segunda entrega — controlador de permissões da IA (deny-by-default)

- Tornar uma ferramenta `STABLE` não a libera automaticamente para a IA. O estado padrão é **BLOQUEADO**.
- `LaboratoryAiPermissionStore` mantém um histórico append-only de `GRANT_AI_USE` e `REVOKE_AI_USE`, separado do registro de versões e das aprovações STABLE.
- Uma liberação é presa à versão STABLE ativa, fingerprint completo do descriptor, SHA-256 do artefato e snapshot executável exato. Se houver promoção ou rollback, a permissão antiga deixa de ser válida automaticamente.
- Conceder acesso exige novamente a credencial segura do Android. Revogar é uma ação explícita e imediata, sem exigir nova autenticação.
- `LaboratoryAiPermissionsActivity` é privada (`exported=false`) e não executa ferramentas. Ela mostra somente STABLEs ativas elegíveis, com estado `BLOQUEADA PARA IA` ou `LIBERADA PARA IA`.
- `LaboratoryAiToolController` é a superfície estreita planejada para o futuro orquestrador da IA. Ele expõe apenas duas operações: listar ferramentas liberadas e executar uma delas com `tool_input`.
- O controlador não expõe APIs de registro, criação de versões, promoção, rollback, aprovação humana, alteração de permissões, snapshots ou seleção de fonte.
- A execução passa obrigatoriamente pelo `LaboratoryStableToolExecutor`, portanto continua vinculada à STABLE ativa, snapshot verificado, worker isolado e auditoria de uso.
- A permissão é revalidada depois da execução. Se o usuário revogar o acesso ou a seleção autorizada mudar enquanto a ferramenta roda, o resultado é descartado e não é entregue à IA.
- Testes Android verificam padrão negado, Activity privada, autenticação fresca, liberação da STABLE exata, visibilidade controlada no catálogo da IA, execução permitida somente após grant e bloqueio novamente após revoke.

**Limite atual:** isto ainda não é a IA principal nem um scheduler de autonomia. É somente a fronteira de capacidades que o futuro orquestrador poderá receber. Controles de sessão, orçamento de chamadas, pausa/cancelamento global e políticas por tarefa ainda serão adicionados antes de conectar um modelo.


## Décima terceira entrega — sessões limitadas da IA com controle do host

- `LaboratoryAiSessionController` separa a mesma sessão em dois handles distintos: `AiHandle` e `HostHandle`.
- O `AiHandle` só consegue listar ferramentas liberadas para aquela tarefa e executar uma delas com `tool_input`. Ele não recebe métodos para pausar, continuar, cancelar, alterar orçamento, conceder permissões, aprovar versões ou tocar no registro STABLE.
- O `HostHandle` controla `pause()`, `resume()`, `cancel()` e consulta um snapshot do estado, mas não executa ferramentas em nome da IA.
- Cada sessão nasce com uma policy imutável: allowlist de até 32 ferramentas, máximo de 64 invocações, orçamento total de até 256 KiB de entrada e duração total de até 1 hora.
- A sessão só pode ser criada se todas as ferramentas da allowlist já estiverem liberadas pelo controlador deny-by-default. Uma revogação posterior continua valendo imediatamente.
- Apenas uma invocação pode ficar ativa por sessão. Tentativas concorrentes são recusadas.
- O orçamento é reservado antes de chamar a ferramenta. Tentativas que falham também consomem a chamada/bytes correspondentes para evitar retry ilimitado sem custo.
- `pause` bloqueia novos trabalhos e cancela a invocação isolada atualmente ativa; `resume` permite novos trabalhos apenas se ainda houver orçamento. Não existe tentativa de congelar uma VM nativa arbitrária no meio da instrução.
- `cancel` é terminal e também cancela o worker ativo. Uma sessão expirada ou com orçamento de invocações consumido entra em `FINISHED`.
- O relógio total da sessão continua contando durante pausa. Ao expirar, o host cancela a invocação ativa e nenhuma nova chamada é aceita.
- Foi fechado também o race de conclusão ultrarrápida: um callback que termine antes de o host salvar o handle do worker não pode deixar um falso estado de “invocação ativa”.
- Testes Android cobrem pausa/resume, orçamento de invocações, fim automático, catálogo vazio após término e cancelamento host de uma execução Luau em loop.

**Limite atual:** as sessões ainda são estruturas de controle em memória; os usos individuais continuam auditados pelo gate STABLE, mas eventos de sessão (START/PAUSE/RESUME/CANCEL/FINISH) ainda não possuem um histórico persistente próprio. Esse ledger de sessão deverá ser adicionado antes da IA principal para recuperação após encerramento do processo.


## Décima quarta entrega — auditoria persistente e recuperável das sessões da IA

- `LaboratoryAiSessionStore` mantém um histórico append-only separado por projeto e por sessão em `files/laboratory/<escopo>/ai-sessions/<sessionId>/`.
- Cada sessão possui manifesto create-only com ID, início, allowlist congelada, limite de invocações, orçamento total de entrada e duração máxima. O manifesto possui SHA-256 calculado sobre representação canônica dos campos.
- Eventos persistidos: `START`, `INVOKE_REQUEST`, `INVOKE_RESULT`, `PAUSE`, `RESUME`, `CANCEL` e `FINISH`. Cada registro possui sequência monotônica, estado, ferramenta, hash da entrada, quantidade de bytes, runId quando existe, resultado e orçamento consumido.
- O texto de `tool_input`, stdout, retorno e erro da ferramenta não entra no ledger de sessão. A entrada é representada somente por SHA-256 e tamanho.
- Cada evento possui hash canônico independente da ordem interna do JSON. Leituras verificam tipo, estado, sequência, tamanhos, caminhos e symlinks antes de aceitar o histórico.
- Limites iniciais: até 64 sessões por projeto e até 256 eventos por sessão. Ao atingir quota, o laboratório recusa novas gravações e preserva o histórico existente.
- O controlador de sessão passa a ser fail-closed para auditoria: a sessão não nasce sem conseguir persistir `START`; uma invocação não começa sem `INVOKE_REQUEST`; se o resultado não puder ser auditado, ele é descartado e a sessão é cancelada.
- `pause`, `resume`, término por orçamento/tempo e cancelamento do host também são registrados. O cancelamento de segurança continua sendo executado mesmo se a gravação do evento falhar.
- `SISTEMA > RELATÓRIOS DO LABORATÓRIO` mostra uma seção somente leitura com sessões, estado final, orçamento usado, ferramentas permitidas, quantidade de eventos e horários.
- Testes Android validam histórico START/PAUSE/RESUME/INVOKE/FINISH/CANCEL, recuperação do resumo após a execução e privacidade: valores privados usados como `tool_input` não aparecem nos arquivos de auditoria.

**Limite atual:** o ledger permite diagnosticar e reconstruir o que aconteceu em uma sessão encerrada, mas ainda não tenta restaurar automaticamente uma sessão ACTIVE/PAUSED depois que o processo do aplicativo morre. Antes de uma IA principal autônoma, sessões interrompidas no processo anterior deverão ser classificadas como interrompidas e exigir uma decisão explícita de retomar uma nova sessão ou encerrar o trabalho.


## Décima quinta entrega — recuperação explícita de sessões interrompidas

- `LaboratoryAiSessionController` mantém um registro em memória das sessões realmente vivas no processo atual. Uma sessão `ACTIVE` ou `PAUSED` persistida só é considerada órfã quando não existe mais nesse registro.
- O registro de sessão ganhou os eventos `INTERRUPT`, `RECOVERY_REQUEST` e `RECOVERY_CLOSE`, além dos estados `INTERRUPTED` e `RECOVERY_PENDING`. O histórico continua append-only; nenhum evento antigo é reescrito.
- `LaboratoryAiSessionRecovery.markInterruptedOrphans()` pode rodar no startup. Sessões antigas `ACTIVE/PAUSED` sem controlador vivo recebem `INTERRUPTED` e ficam proibidas de continuar automaticamente.
- Uma corrida no nascimento da sessão foi fechada: o ID entra no conjunto de sessões vivas antes de persistir `START`; se a criação do ledger falhar, o ID é removido novamente. Assim uma varredura concorrente não marca uma sessão recém-criada como órfã.
- A recuperação oferece duas decisões humanas: **encerrar** a sessão antiga ou **preparar retomada em nova sessão**. Preparar retomada grava `RECOVERY_PENDING`, mas não cria worker, não chama ferramenta e não inicia IA.
- A policy de retomada preserva somente a allowlist original e o orçamento restante: chamadas restantes, bytes de entrada restantes e tempo restante. Se qualquer um desses recursos acabar, a retomada não pode ser preparada.
- O tempo restante é calculado contra o relógio total da sessão original; fechar o aplicativo não congela o orçamento temporal.
- `LaboratoryAiSessionRecoveryActivity` é privada e mostra estado, ferramentas, orçamento restante e as ações de recuperação. `SISTEMA > RELATÓRIOS DO LABORATÓRIO` também ganhou acesso direto a essa tela.
- `MainActivity` faz a varredura em I/O no startup. Se houver sessão interrompida ou retomada pendente, mostra um aviso; o editor continua abrindo normalmente e nenhuma execução é iniciada.
- Varredura, preparação de retomada e encerramento usam um lock único no processo, evitando decisões duplicadas quando o aviso de startup e a tela de recuperação são usados ao mesmo tempo.
- Testes Android verificam Activity privada, marcação de sessão órfã, preservação do orçamento restante, `RECOVERY_PENDING`, encerramento explícito, histórico dos eventos e proteção contra falso positivo em uma sessão ACTIVE/PAUSED que ainda está viva no processo.

**Limite atual:** `RECOVERY_PENDING` registra a decisão de continuar, mas a nova sessão ainda não é criada porque o orquestrador principal da IA não está conectado. Quando ele existir, poderá consumir essa policy restante para criar uma sessão nova, com novo ID e nova auditoria, sem reaproveitar a sessão interrompida.


## Décima sexta entrega — painel host-only de sessões vivas

- `LaboratoryAiLiveSessionRegistry` mantém somente em memória os `HostHandle` das sessões vivas do processo atual. Ele não é persistente e não substitui a recuperação após morte do processo.
- Toda sessão criada pelo `LaboratoryAiSessionController` é registrada automaticamente para controle do host. Se o registro falhar, a sessão é cancelada por segurança.
- O registro é escopado por projeto. Uma tela ou componente de outro projeto não consegue pausar, continuar ou cancelar uma sessão que não lhe pertence.
- `LaboratoryAiLiveSessionActivity` é privada (`exported=false`) e mostra, em atualização periódica feita fora da UI thread: estado, ferramentas permitidas, chamadas usadas/restantes, bytes usados/restantes, tempo decorrido/restante e existência de worker ativo.
- A tela oferece `PAUSAR`, `CONTINUAR` e `CANCELAR`. As ações passam exclusivamente pelo `HostHandle`; a Activity não recebe `AiHandle` e nunca executa uma ferramenta diretamente.
- O painel também oferece `PAUSAR TODAS`, `CONTINUAR TODAS` e `CANCELAR TODAS` para o projeto atual. Operações globais são best-effort por sessão: uma falha isolada é relatada, mas não impede o host de controlar as demais.
- Pausar uma sessão ACTIVE cancela o worker isolado atualmente ativo e mantém a sessão em `PAUSED`. Continuar só é aceito se o controlador realmente voltar para `ACTIVE`.
- Se uma falha de auditoria impedir a transição de estado, o painel não informa sucesso incorretamente: o registro valida o estado resultante e falha fechado.
- Cancelar remove a sessão do painel imediatamente; sessões que terminam por orçamento/tempo são podadas automaticamente na próxima leitura do registro.
- `SISTEMA > RELATÓRIOS DO LABORATÓRIO` ganhou acesso separado para `CONTROLAR SESSÕES AO VIVO`, distinto da recuperação de sessões antigas.
- Testes Android verificam Activity privada, isolamento por projeto, pausa/resume/cancel pelo host registry, remoção de sessões terminadas, cancelamento do worker ativo ao pausar e a superfície do `AiHandle`: ele continua sem `pause`, `resume`, `cancel` ou `snapshot`.

**Fronteira para a IA:** o modelo futuro poderá receber apenas o `AiHandle`. O `HostHandle`, o registro ao vivo e as telas de controle ficam fora da superfície entregue ao modelo.


## Décima sétima entrega — Goal Lock e contrato imutável de tarefa

- `LaboratoryAiTaskContractStore` cria contratos de tarefa create-only, separados do ledger de sessão. Cada contrato possui ID UUID, modo (`CREATION` ou `LEARNING`), objetivo exato, SHA-256 do objetivo, allowlist de ferramentas e orçamento imutável.
- O texto do objetivo é preservado literalmente no armazenamento privado local do app, inclusive espaços e quebras de linha. A validação só impede objetivo vazio ou maior que 4096 caracteres.
- O contrato recebe SHA-256 canônico sobre identidade, modo, hash do objetivo, ferramentas e orçamento. Leitura revalida o objetivo e a integridade do contrato.
- Um contrato só pode incluir ferramentas que já estejam explicitamente liberadas ao controlador da IA no momento da criação. A admissão revalida as permissões novamente.
- `LaboratoryAiTaskAdmission` é a fronteira host-side: primeiro grava um `claim.json` de uso único; somente depois tenta criar a sessão.
- Se a sessão não puder nascer, o contrato permanece reivindicado e recebe `SESSION_FAILED`. Ele não pode ser reaproveitado silenciosamente; o host precisa criar um novo contrato.
- Se a sessão nascer mas o resultado de admissão não puder ser persistido, a sessão é cancelada por segurança.
- Em sucesso, `result.json` liga o contrato ao novo `sessionId` com `SESSION_CREATED`.
- A futura IA recebe `AiTaskHandle`: objetivo travado, modo, contractId, hash do objetivo e a superfície estreita de ferramentas da sessão. `HostHandle` continua separado.
- `AiTaskHandle` não expõe `pause`, `resume`, `cancel`, `snapshot`, alteração do objetivo ou alteração do orçamento.
- O ledger de sessão não recebe o texto do objetivo. O objetivo bruto vive somente no cofre privado do contrato; a sessão continua registrando orçamento/estado e hashes.
- `LaboratoryAiTaskContractsActivity` é privada e somente leitura. Mostra modo, estado de consumo, hash do objetivo, ferramentas e orçamento; o usuário pode abrir o objetivo exato e o resultado da admissão.
- `SISTEMA > RELATÓRIOS DO LABORATÓRIO` ganhou acesso a `CONTRATOS GOAL LOCK`.
- Testes Android verificam preservação literal do objetivo, hash, Activity privada, contrato de uso único, criação da sessão, execução pelo `AiTaskHandle`, impossibilidade de replay, falha após revogação de permissão, rejeição de objetivo adulterado e ausência do objetivo bruto no manifesto da sessão.

**Fronteira preparada:** quando o orquestrador principal for conectado, ele não deverá criar sessões a partir de `Policy` livre. O caminho previsto passa por contrato Goal Lock → claim único → sessão → `AiTaskHandle`.


## Décima oitava entrega — IA de teste determinística do laboratório

- `LaboratoryAiTestAgent` é a primeira IA de teste do laboratório, mas propositalmente **não é um LLM**. Ela funciona como um agente determinístico para validar ferramentas pelo mesmo caminho que a futura IA principal usará.
- O fluxo obrigatório é `Goal Lock → claim único → AiTaskHandle → ferramenta STABLE autorizada → worker isolado → auditoria da sessão → relatório da IA de teste`.
- Cada execução recebe um `Plan` imutável com até 16 passos. Cada passo define nome, `toolId`, `tool_input` e retorno esperado. Nomes precisam ser únicos e o plano pode usar `stopOnFailure`.
- O plano é validado **antes de consumir o Goal Lock**: número de passos não pode ultrapassar o orçamento de chamadas, toda ferramenta precisa estar na allowlist do contrato e o total UTF-8 das entradas precisa caber no orçamento de bytes.
- A execução usa exclusivamente o `AiTaskHandle`. O agente de teste não recebe acesso a aprovação humana, promoção/rollback, permissões, snapshots, fonte executável, `HostHandle` ou controles do painel.
- Cada passo compara deterministicamente o primeiro retorno esperado. Evidências persistidas contêm somente hashes SHA-256 da entrada, retorno esperado, retorno obtido e saída, além de versão da ferramenta, runId e duração.
- `tool_input`, stdout, retorno, erro bruto da ferramenta e texto do Goal Lock não são persistidos no relatório da IA de teste.
- `LaboratoryAiTestAgentReportStore` é create-only, possui limites próprios e revalida rigorosamente cada evidência ao ler o relatório: contadores, IDs, hashes, nomes, motivos, versões e duração.
- Falha de admissão gera `ADMISSION_FAILED` antes de qualquer passo. O contrato continua de uso único, conforme o Goal Lock, e o relatório registra apenas um código de motivo limitado, como `SecurityException`.
- Timeout interno aguardando callback cancela o worker/sessão por segurança. Pausa ou cancelamento do host também interrompem o plano sem transformar a sessão em sucesso.
- Foi adicionado `HostHandle.complete()`: uma tarefa concluída normalmente pode terminar como `FINISHED` com evento auditado `HOST_COMPLETED`, sem reutilizar `CANCELLED` como falso sucesso.
- `FINALIZAR` também foi adicionado ao painel host-only de sessões vivas. Esse método continua ausente do `AiHandle` e do `AiTaskHandle`.
- `LaboratoryAiTestAgentReportsActivity` é privada e somente leitura. Exibe status, Goal SHA-256, contrato, sessão e evidências por hash. `SISTEMA > RELATÓRIOS DO LABORATÓRIO` ganhou acesso a `RELATÓRIOS IA DE TESTE`.
- Testes Android cobrem: PASS determinístico com dois passos, mismatch com `stopOnFailure`, plano inválido sem consumir o Goal Lock, falha de admissão após revogar permissão, privacidade dos dados brutos, Activity privada, encerramento normal `HOST_COMPLETED` e ausência de controles host na superfície entregue à IA.

**Limite atual:** a IA de teste ainda não inventa planos nem decide quais experimentos executar. Isso é intencional nesta etapa: primeiro ela prova que o caminho de execução, isolamento, Goal Lock, orçamento, auditoria e relatório são confiáveis. Planejamento inteligente pode ser conectado depois sobre essa base sem ganhar acesso aos controles protegidos do host.


## Décima nona entrega — catálogo imutável de cenários da IA de teste

- `LaboratoryAiTestScenarioStore` mantém cenários determinísticos create-only no armazenamento privado do laboratório. Um cenário contém nome, ID, data, `stopOnFailure` e o plano completo de até 16 passos.
- Cada passo preserva `toolId`, fixture de entrada e primeiro retorno esperado. Esses valores brutos ficam apenas no arquivo privado do cenário; os relatórios executados continuam persistindo somente hashes.
- O cenário recebe SHA-256 canônico calculado sobre identidade, metadados e conteúdo exato de todos os passos. Qualquer alteração posterior em entrada, retorno esperado, ferramenta ou nome invalida a leitura.
- `LaboratoryAiTestScenarioRunner` recebe somente `scenarioId + contractId`: relê e verifica o cenário imutável e então delega para `LaboratoryAiTestAgent`.
- A validação autoritativa do Goal Lock continua no agente antes do claim. Portanto um cenário que usa ferramenta fora da allowlist, mais chamadas ou mais bytes do que o contrato permite é rejeitado antes de consumir o contrato.
- Cenários podem ser reutilizados com contratos diferentes, mas cada execução continua exigindo um Goal Lock novo/de uso único. O cenário não concede permissão nem cria sessão por conta própria.
- `LaboratoryAiTestScenariosActivity` é privada e somente leitura. Mostra nome, ID, hash, quantidade de passos e `stopOnFailure`; a inspeção dos fixtures permanece dentro do app.
- `SISTEMA > RELATÓRIOS DO LABORATÓRIO` ganhou acesso a `CENÁRIOS IA DE TESTE`.
- Testes Android verificam execução de cenário pelo agente, privacidade do relatório, fixture presente somente no cofre privado do cenário, adulteração detectada antes do claim, orçamento incompatível sem consumir Goal Lock e Activity não exportada.

**Uso futuro:** o Tool Workshop poderá criar/versionar uma ferramenta e gerar cenários imutáveis para a IA de teste. O cenário não contém código executável da ferramenta; ele referencia apenas uma ferramenta STABLE autorizada e fornece dados/expectativas de teste.


## Diagnóstico automático das IAs

O controlador comum de sessões agora dispara um diagnóstico determinístico para
toda IA que use o caminho oficial do laboratório. A análise ocorre após
resultados de ferramentas e nos estados terminais da sessão, portanto a mesma
camada serve para a IA de teste atual e para futuras IAs da equipe.

O diagnóstico é deliberadamente somente leitura:

- não recebe `HostHandle` nem `AiHandle`;
- não pausa, retoma, cancela ou executa ferramentas;
- lê apenas a auditoria limitada da sessão;
- persiste contadores, estados, códigos de motivo e sinais de melhoria;
- não persiste prompt, objetivo, `tool_input`, retorno, stdout ou erro bruto;
- nunca aplica correção automaticamente.

Sinais iniciais incluem falhas de ferramenta, cancelamentos, pausas frequentes,
aproximação dos orçamentos de chamadas/bytes, estouro de tempo e necessidade de
reduzir ou dividir um plano. O painel privado **DIAGNÓSTICO DAS IAS** mostra o
último diagnóstico de cada sessão e mantém a decisão de correção no lado do
host/usuário.


## Diagnóstico contínuo por membro da equipe de IAs

- `LaboratoryAiTeamRegistry` adiciona identidades imutáveis para membros da equipe. Cada membro possui `agentId`, nome visível, papel e hash de integridade. Papéis iniciais: `TESTER`, `DIAGNOSTIC`, `CREATOR`, `REVIEWER`, `RESEARCHER`, `ORCHESTRATOR` e `SPECIALIST`.
- Identidade não é sessão. O vínculo `sessão → IA` fica em um registro create-only separado. Uma sessão já atribuída não pode ser transferida silenciosamente para outra IA.
- O vínculo não armazena prompt, objetivo, entrada, retorno ou transcript. Mantém somente `sessionId`, `agentId`, `contractId` opcional, data e SHA-256.
- A IA de Teste agora se registra automaticamente como `test-agent / TESTER` e toda sessão dela é atribuída a essa identidade. Se a atribuição falhar, a sessão é cancelada por segurança.
- A própria IA de Diagnóstico aparece na equipe como `diagnostic-agent / DIAGNOSTIC`, mas não recebe `AiHandle`, `HostHandle` nem sessão para realizar a análise.
- `LaboratoryAiTeamDiagnostics` consome somente diagnósticos de sessão já sanitizados e os vínculos imutáveis da equipe.
- Por membro, ele agrega: quantidade de sessões, sessões saudáveis/atenção/falha, falhas de ferramentas, cancelamentos, pausas, média de uso dos orçamentos e última severidade.
- Sinais repetidos são identificados como recorrentes quando aparecem em pelo menos duas sessões e em pelo menos metade das sessões diagnosticadas daquele membro.
- Com pelo menos quatro sessões, o diagnóstico compara as duas mais antigas do bloco recente com as duas mais novas e classifica tendência como `IMPROVING`, `STABLE` ou `DEGRADING`. Com menos dados usa `INSUFFICIENT_DATA`.
- Recomendações agregadas incluem revisão de falhas repetidas, cancelamentos repetidos, interrupções frequentes, adequação de orçamento, regressões e sinais recorrentes. Nenhuma recomendação é aplicada automaticamente.
- Sempre que um diagnóstico individual é atualizado, o diagnóstico agregado da equipe é agendado depois dele e roda fora do caminho de controle da sessão.
- `LaboratoryAiTeamDiagnosticsActivity` é privada e somente leitura. Mostra cada IA, papel, sessões, falhas, tendência e recomendações sem oferecer botões de alteração.
- `SISTEMA > RELATÓRIOS DO LABORATÓRIO` ganhou acesso separado a `DIAGNÓSTICO DA EQUIPE DE IAS`.
- Testes Android verificam Activity privada, identidade/vínculo imutáveis, integração automática da IA de Teste, duas sessões saudáveis seguidas de duas falhas gerando tendência `DEGRADING`, detecção de `INSPECT_TOOL_FAILURES` recorrente e ausência dos dados privados — inclusive seus hashes de entrada — no relatório agregado.

**Fronteira de segurança:** diagnóstico de equipe é observação e recomendação. Ele não executa ferramenta, não altera outra IA, não muda orçamento, não promove versão e não aplica melhoria sozinho.


## Propostas de melhoria derivadas do diagnóstico da equipe

- `LaboratoryAiImprovementProposalStore` mantém uma fila create-only de propostas de melhoria. Cada proposta referencia apenas dados sanitizados do diagnóstico agregado: IA afetada, papel atual, recomendação de origem, tendência, quantidade de sessões/falhas e a ação sugerida.
- Propostas não carregam prompt, objetivo, `tool_input`, retorno, stdout, erro bruto, runId ou conteúdo de conversa.
- Cada proposta possui uma chave SHA-256 de deduplicação calculada sobre IA, recomendação, ação sugerida, papel de destino e o estado agregado das evidências. Reexecutar o planejador sobre a mesma evidência retorna a proposta existente em vez de criar spam.
- Quando o diagnóstico agregado muda de forma material (por exemplo, novas sessões ou mais falhas), uma nova proposta pode ser criada, preservando o histórico antigo.
- `LaboratoryAiImprovementPlanner` converte somente códigos conhecidos em ações conhecidas. Mapeamentos iniciais:
  - `REVIEW_REPEATED_FAILURES → RUN_TARGETED_FAILURE_REVIEW → REVIEWER`;
  - `REVIEW_REPEATED_CANCELLATIONS → REVIEW_SESSION_CONTROL_FLOW → REVIEWER`;
  - `REVIEW_FREQUENT_INTERRUPTION → REVIEW_TASK_DECOMPOSITION → ORCHESTRATOR`;
  - `REVIEW_BUDGET_FIT → REVIEW_BUDGET_POLICY → REVIEWER`;
  - `PRIORITIZE_REGRESSION_REVIEW → RUN_REGRESSION_SUITE → TESTER`;
  - `REVIEW_RECURRENT_SIGNALS → CORRELATE_RECURRENT_FAILURE_PATTERN → DIAGNOSTIC`.
- Códigos como `NO_TEAM_ACTION` e `WAIT_FOR_SESSION_DATA` não viram proposta.
- Ao finalizar uma atualização do diagnóstico da equipe, a atualização da fila de propostas é agendada em background. Falha nessa fila nunca controla ou bloqueia a IA que está executando.
- `LaboratoryAiImprovementProposalsActivity` é privada e somente leitura. Mostra IA afetada, origem do diagnóstico, ação sugerida, papel recomendado para revisar e evidências agregadas.
- `SISTEMA > RELATÓRIOS DO LABORATÓRIO` ganhou acesso a `PROPOSTAS DE MELHORIA DAS IAS`.
- Testes Android verificam Activity privada, roteamento para papéis corretos, deduplicação da mesma evidência, criação de nova proposta quando a evidência muda e rejeição de adulteração do arquivo.

**Fronteira de segurança:** proposta é recomendação, não comando. Esta etapa não altera código, não muda orçamento, não executa cenário, não promove ferramenta e não modifica outra IA.


## Decisões humanas sobre propostas de melhoria

- `LaboratoryAiImprovementDecisionStore` mantém um ledger append-only por proposta. O estado é derivado do histórico; nenhum evento antigo é reescrito.
- Estados iniciais: `PENDING`, `ROUTED_FOR_REVIEW` e `DISMISSED`.
- Ações permitidas:
  - `ROUTE_FOR_REVIEW`: PENDING → ROUTED_FOR_REVIEW;
  - `DISMISS`: PENDING/ROUTED_FOR_REVIEW → DISMISSED;
  - `REOPEN`: ROUTED_FOR_REVIEW/DISMISSED → PENDING.
- Cada evento fica preso ao `proposalId` e ao SHA-256 de deduplicação da proposta. Se a proposta for adulterada ou trocada, o histórico deixa de ser aceito.
- Ao enviar para revisão, o evento grava também o papel de destino já definido pela proposta. O ledger rejeita roteamento para papel diferente.
- O ator inicial é sempre `USER`. Nesta etapa nenhuma IA pode decidir por conta própria se uma proposta deve ser roteada, dispensada ou reaberta.
- `ENVIAR PARA REVISÃO` significa somente autorizar análise posterior pelo papel indicado. Não executa cenário, não altera código, não muda orçamento, não cria versão e não promove ferramenta.
- `LaboratoryAiImprovementDecisionsActivity` é privada. Mostra estado atual, contagem de eventos e oferece somente as transições válidas para aquele estado.
- A área `SISTEMA > RELATÓRIOS DO LABORATÓRIO` ganhou acesso separado a `DECISÕES SOBRE MELHORIAS DAS IAS`.
- Testes Android verificam Activity privada, lifecycle PENDING → ROUTED → PENDING → DISMISSED → PENDING, sequência append-only, transições inválidas bloqueadas, destino de revisão preso à proposta, adulteração rejeitada e ausência de qualquer sessão criada pela decisão.

**Fronteira de segurança:** decidir o destino de uma proposta continua sendo workflow, não execução. Uma etapa futura poderá criar a caixa de entrada da IA Revisora, mas deverá consumir somente propostas explicitamente marcadas como `ROUTED_FOR_REVIEW`.


## Caixa de revisão da equipe de IAs

- `LaboratoryAiReviewInbox` é uma visão derivada, somente leitura, das propostas que o usuário marcou como `ROUTED_FOR_REVIEW`.
- A caixa não mantém um segundo estado de workflow. Ela relê a proposta e o ledger append-only de decisões; por isso `REOPEN` ou `DISMISS` remove o item imediatamente sem sincronização paralela.
- É possível consultar todas as propostas roteadas ou filtrar por papel de destino (`REVIEWER`, `TESTER`, `ORCHESTRATOR`, `DIAGNOSTIC` etc.).
- Cada item expõe somente metadados sanitizados da proposta: IA afetada, recomendação de origem, ação sugerida, papel de destino, tendência e contadores agregados.
- A caixa não cria sessão, não recebe `AiHandle`/`HostHandle`, não executa ferramenta e não altera a proposta.
- `LaboratoryAiReviewInboxActivity` é privada e somente leitura. Agrupa os itens pelo papel de destino e deixa explícito que estar na caixa significa **autorizado para análise**, não autorizado para aplicação.
- `SISTEMA > RELATÓRIOS DO LABORATÓRIO` ganhou acesso a `CAIXA DE REVISÃO DAS IAS`.
- Testes Android verificam Activity privada, proposta PENDING ausente, ROUTED presente no papel correto, REOPEN removendo, novo ROUTE recolocando, DISMISS removendo e ausência de qualquer sessão/execução criada pelo roteamento.

**Próxima fronteira:** uma futura IA Revisora poderá receber somente itens desta caixa. Antes disso, ainda será necessário definir um contrato de revisão separado e de uso único, para que analisar uma proposta não dê poder para aplicá-la.


## Status real de execução do planejador local

- `LaboratoryAiExecutionStatus` introduz um contrato imutável de status para acompanhar uma execução do planejador sem conceder nenhuma permissão nova e sem consumir o Goal Lock.
- Cada execução recebe `executionId`, `contractId`, estado, fase, tempo decorrido, tentativa atual e motivo terminal limitado.
- O fluxo do planejador agora publica etapas reais: admissão do modelo, preflight, abertura do modelo, leitura do runtime, planejamento, validação e conclusão.
- A bridge `LlamaBridge` expõe a fase nativa corrente da geração. O JNI diferencia `CONTEXT`, `PROMPT` e `TOKENS`; esses valores vêm dos mesmos atomics usados pelo timeout e não são inferidos por texto de UI.
- `LaboratoryAiLlamaCppBackend` observa a fase nativa durante a geração e também publica a última fase uma vez na saída por erro, preservando o ponto exato do timeout.
- A tela atual do planejador mostra status curto com fase, tentativa e tempo. Quando há falha, o diálogo inclui ID da execução, contrato, estado, fase, tempo, último status e motivo; nenhuma ferramenta é executada e o Goal Lock permanece não consumido.
- O listener de status é somente observabilidade: exceções da UI/observador são ignoradas e nunca controlam a geração.
- Teste Android cobre transições, terminalidade e preservação da fase de trabalho quando a execução falha.

**Próxima extensão prevista:** persistir um histórico limitado dessas execuções e reutilizar o mesmo contrato de eventos no futuro chat da aba IA, para que o status curto e o diagnóstico detalhado consumam a mesma fonte.


## Histórico persistente das execuções do planejador

- `LaboratoryAiExecutionStatus.Tracker` mantém uma sequência imutável em memória de todos os snapshots reais produzidos durante uma execução, além do snapshot atual usado pela UI.
- Ao chegar a um estado terminal (`COMPLETED`, `FAILED` ou `CANCELLED`), `LaboratoryAiExecutionHistoryStore` persiste a sequência completa em `files/laboratory/<escopo>/ai-execution-history/<executionId>/`.
- O armazenamento é create-only, limitado a 128 execuções por projeto, 64 eventos por execução e 8 KiB por evento. Quota atingida não apaga histórico antigo.
- Cada evento registra somente metadados de observabilidade: execução, contrato, horários, estado, fase, tentativa, detalhe curto e motivo terminal. Não são persistidos Goal Lock bruto, prompt, resposta do modelo, plano JSON bruto, `tool_input`, stdout ou fonte executável.
- Leituras revalidam UUIDs, sequência contígua, identidade da execução, monotonicidade de tempo, transições terminais e limites de tamanho antes de aceitar o histórico.
- A tela do planejador ganhou `HISTÓRICO DO PLANEJADOR`, com as execuções mais recentes e seus estados finais. A leitura ocorre fora da thread da interface.
- Falha ao gravar histórico não altera o resultado do planejador: observabilidade continua separada do controle de execução e não ganha permissão sobre Goal Lock, ferramentas ou TestAgent.
- O mesmo contrato de `Snapshot` usado na UI ao vivo é o que alimenta o histórico. Isso deixa a fonte pronta para um futuro chat da aba IA consumir status ao vivo e execuções passadas sem criar um segundo sistema de progresso.

**Limite atual:** o histórico é persistido quando a execução chega a um estado terminal. Uma morte abrupta do processo antes desse ponto ainda pode perder a sequência em memória daquela execução; persistência incremental/crash-safe poderá ser adicionada depois se os testes no aparelho mostrarem necessidade.


## Classificação determinística das falhas do planejador

- `LaboratoryAiPlannerExecutionDiagnostic` transforma o estado terminal e a fase real do runtime em um código de diagnóstico sem usar outro modelo de linguagem e sem alterar a execução.
- As classes iniciais distinguem admissão, preflight, abertura do modelo, preparação de contexto, processamento de prompt, geração de tokens, validação do plano, cancelamento e falha genérica.
- Timeouts são classificados pelo ponto real em que ocorreram. Por exemplo, `MODEL_PROMPT + timed out` vira `PROMPT_TIMEOUT`; `MODEL_TOKENS + timed out` vira `TOKEN_TIMEOUT`.
- Cada diagnóstico fornece uma explicação curta e um código de próxima verificação. Esses códigos são orientação para investigação; não aumentam timeout, não diminuem contexto e não mudam configuração automaticamente.
- O diálogo de falha e o histórico do planejador mostram a classificação derivada da mesma fonte de status usada pelo runtime.
- Testes Android verificam pelo menos `PROMPT_TIMEOUT`, `TOKEN_TIMEOUT` e cancelamento do usuário.

Isso fecha a primeira parte do diagnóstico interno: em vez de apenas saber que o planejador falhou, o app consegue registrar em qual etapa falhou e qual medição deve ser feita em seguida.


## Telemetria de desempenho do modelo local

- O runtime local agora mede o trabalho do `llama.cpp` sem registrar prompt ou resposta: quantidade total de tokens do prompt, tokens de prompt concluídos em batches, tokens gerados, limite de saída, tempo de preparação do contexto, tempo de avaliação do prompt, tempo de geração e limite temporal configurado.
- `LlamaBridge.GenerationMetrics` expõe um snapshot somente leitura desses contadores. A JNI usa apenas atomics pertencentes à sessão do modelo; a leitura de métricas não recebe acesso a Goal Lock, permissões, ferramentas ou código executável.
- Os tempos de `CONTEXT`, `PROMPT` e `TOKENS` continuam avançando ao vivo mesmo quando uma chamada nativa está bloqueada dentro de uma etapa longa. Isso permite distinguir “está processando há 40 s” de uma interface simplesmente congelada.
- `LaboratoryAiLlamaCppBackend` amostra a telemetria em background durante a geração e entrega os valores ao mesmo `LaboratoryAiExecutionStatus` usado pela UI e pelo diagnóstico.
- Durante `MODEL_PROMPT`, quando já existe uma amostra útil, o status mostra `processados/total`, taxa aproximada em tokens/s e ETA calculada com o ritmo observado. Durante `MODEL_TOKENS`, mostra tokens gerados, taxa e uma estimativa até o limite máximo de saída; a resposta pode terminar antes por EOG, portanto esta última é um teto aproximado, não uma promessa.
- Ao terminar ou falhar, os contadores finais entram no histórico persistente da execução. Assim um `PROMPT_TIMEOUT` pode ser inspecionado com números concretos como tokens totais, tokens de batches concluídos, tempo de prompt e ritmo observado.
- O histórico continua sem persistir conteúdo do prompt, texto de saída, Goal Lock bruto ou fonte executável.
- O workflow `CAFEINA Local LLM Compile Probe` também verifica que o símbolo JNI de telemetria está presente no APK ARM64.

**Interpretação importante:** `promptTokensProcessed` conta batches do prompt que terminaram com sucesso. Se o primeiro batch ficar preso até o timeout, esse contador pode continuar em zero enquanto `promptEvalMs` cresce. Isso é informação útil: indica que o gargalo está dentro do primeiro processamento nativo do prompt, e não significa que o runtime ficou sem atividade.


## Chat da CAFEÍNA como superfície principal

- A aba `IA` agora começa pela conversa com a CAFEÍNA, em vez de exigir que o usuário navegue primeiro por telas técnicas do laboratório.
- Mensagens classificadas como conversa comum usam o modelo local sem receber handles de ferramentas, permissões, Goal Lock ou APIs mutáveis. O prompt dessa rota afirma explicitamente que nenhuma ação foi executada.
- Pedidos com sinal claro de ação são desviados para o fluxo controlado. Antes de qualquer execução, o chat mostra as ferramentas STABLE atualmente concedidas e pede uma seleção por tarefa.
- Confirmar as ferramentas cria um Goal Lock imutável com o texto exato do pedido, modo `CREATION` ou `LEARNING` e orçamento inicial limitado. Criar o contrato não executa ferramenta.
- O botão `GERAR PLANO • NÃO EXECUTAR` agora roda o planejador dentro do próprio chat. O chat recebe o mesmo `LaboratoryAiExecutionStatus` usado no diagnóstico: fase real, tentativa, tempo, tokens, throughput e ETA quando há base suficiente para estimativa.
- Falhas do planejador aparecem no chat com `LaboratoryAiPlannerExecutionDiagnostic`, métricas medidas e confirmação explícita de que nenhuma ferramenta foi executada e o Goal Lock permaneceu não consumido.
- Plano aceito aparece no chat como passos, ferramentas e retorno esperado. `PREPARAR TESTADORA • NÃO EXECUTAR` grava o cenário imutável, ainda sem consumir o Goal Lock.
- A execução da Testadora continua protegida por uma confirmação separada. O botão deixa explícito que executar consome o Goal Lock de uso único.
- Durante a Testadora, eventos determinísticos mostram no chat a admissão da sessão, passo atual, ferramenta em teste e resultado de cada passo. Esses eventos são observabilidade somente leitura; exceções no observador não controlam a execução.
- Ao final, o chat mostra status, passos executados, sucessos, falhas, duração, motivo terminal, sessão e relatório persistido, com atalho para os relatórios da Testadora.
- O fluxo técnico antigo do planejador continua disponível para diagnóstico e inspeção; a nova superfície de chat não remove os gates determinísticos já existentes.

### Limites desta etapa

- O roteamento inicial conversa/ação é propositalmente conservador e host-side. Pedidos ambíguos permanecem como conversa até existir um sinal suficientemente claro de ação.
- O histórico curto da conversa ainda é mantido apenas em memória da tela; memória persistente/consolidada da CAFEÍNA continua sendo uma etapa posterior.
- A Testadora agora informa passo e ferramenta ao vivo, mas cancelamento/pausa diretamente pelo chat ainda deverá ser ligado ao controle host da sessão em uma etapa seguinte.
