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


## Quinta entrega — registro versionado de ferramentas e revisão sem autopromoção

- `LaboratoryToolRegistry` registra somente fontes Luau experimentais já preservadas em snapshot validado. Exige ID seguro, versão numérica `major.minor.patch`, UUID da cópia, hash SHA-256, timeout até 3 segundos e capacidade fixa `LUAU_ISOLATED_NO_FILES`. O catálogo privado é separado por projeto e não altera scripts, runtime ou Mundo.
- Manifestos de versão são criados uma única vez: uma nova versão nunca sobrescreve a anterior. Cada registro inclui digest SHA-256 do manifesto; a leitura revalida manifesto, snapshot, hash da fonte e, quando aplicável, a evidência do teste. Se houver corrupção, links simbólicos ou troca do relatório depois da revisão, a leitura falha de forma explícita, sem apagar o histórico.
- `LaboratoryToolWorkshop` é a orquestração **interna**, sem botão para executar ferramentas na interface do usuário. Faz preflight de versão, solicita execução Luau isolada, espera snapshot e relatório persistidos, registra a versão em EXPERIMENTAL e só cria uma solicitação CANDIDATE se o relatório mostrar PASS do **mesmo** snapshot e código. Execução sem erro não equivale a teste aprovado; um erro de teste mantém a versão em EXPERIMENTAL.
- CANDIDATE significa **aguardando revisão humana**, não aprovada. O registry não fornece qualquer API para STABLE, para adicionar permissões, para escrever no núcleo ou para substituir arquivos. A tela `SISTEMA > RELATÓRIOS DO LABORATÓRIO` mostra as versões, estados, hashes, limites e UUIDs somente para consulta. Não há botão de aprovação nesta entrega.
- Limite inicial: 64 versões por projeto e orçamento de entradas no catálogo. A implementação recusa registros quando chega ao limite; não elimina versões antigas nem executa candidato fora do trabalhador isolado.
- Testes JVM verificam versões imutáveis, IDs, escopos, integridade do manifesto e snapshot e negativa de revisão sem relatório correspondente. Testes Android verificam que a orquestração cria CANDIDATE apenas após PASS, e que falhas continuam EXPERIMENTAL. Os relatórios não armazenam a fonte do candidato.

**Limites de segurança:** estes registros são uma política da aplicação, não um ledger resistente a adulterações para processos com o mesmo UID/root. Um futuro modelo de linguagem operando no processo principal precisará de um controlador de permissões independente. A aprovação humana e a promoção de uma versão STABLE não estão implementadas: não se pode tratar CANDIDATE como liberação de uso no projeto. A integração da IA principal continua bloqueada até o laboratório e o controlador de permissões estarem completos.


## Sexta entrega — aprovação humana separada da execução e da ativação

- \`LaboratoryApprovalActivity\` é uma tela privada (\`exported=false\`) dedicada à decisão do usuário. Ela lista somente versões \`CANDIDATE\` que já possuem evidência válida; não possui campo de código, botão de execução, edição de manifesto ou controle de permissões da ferramenta.
- Para registrar a decisão, a tela exige uma confirmação explícita e depois abre a confirmação de credencial do próprio Android (PIN/senha/bloqueio seguro do aparelho). Se o dispositivo não possuir bloqueio seguro configurado, a aprovação fica indisponível.
- Depois do retorno \`RESULT_OK\`, a candidata é relida e revalidada. \`LaboratoryHumanApprovalStore\` cria um recibo único contendo versão, hash do manifesto, relatório de evidência, hash da fonte, horário e o método \`ANDROID_DEVICE_CREDENTIAL\`. A gravação usa \`CREATE_NEW\`; um recibo existente nunca é substituído.
- A leitura do recibo revalida o estado CANDIDATE e os mesmos hashes/evidências. Recibo corrompido, divergente, ligado simbolicamente ou associado a versão diferente falha de forma explícita. Aprovações ficam separadas por projeto.
- A tela de relatórios mostra \`APROVADA PELO USUÁRIO • NÃO ATIVA\` quando o recibo é válido e oferece um atalho para a área de revisão. O conteúdo da ferramenta continua indisponível nessa interface.
- **Aprovação não é ativação.** O catálogo continua tendo apenas EXPERIMENTAL e CANDIDATE. Não existe API de STABLE, instalador de ferramenta, troca automática da versão ativa ou caminho para a IA invocar a tela de credencial como se fosse uma decisão do usuário.
- Teste Android confirma que a Activity de aprovação não é exportada, que somente uma CANDIDATE aceita recibo, que duplicidade/credencial expirada falham e que o estado do registro continua CANDIDATE após a aprovação.

**Limitação real:** a confirmação de credencial é uma barreira de interface do Android e o recibo é uma política local do aplicativo; não é uma prova criptográfica resistente a root ou a código arbitrário com o mesmo UID. Antes da IA principal, o controlador de permissões deve manter o modelo e ferramentas isoladas sem uma API que consiga chamar o gravador de aprovação. A futura ativação STABLE deverá consumir apenas recibos válidos e ainda exigir uma etapa separada, reversível e auditável.
