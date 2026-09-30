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
