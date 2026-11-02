# Segurança e privacidade

- O histórico V3 no GitHub público pode conter `userId`, `username`, `player`, textos e argumentos de remotes. A existência de campos desses tipos foi confirmada no código do gateway. O protótipo **não publica** esses campos no relatório; armazenar hashes do documento não substitui revisão do histórico.
- Nunca guardar token de escrita do GitHub em script Lua distribuído a clientes. Autenticar o gateway e limitar comandos.
- Capturas do jogo e respostas de modelos são **dados não confiáveis**, jamais instruções para shell ou credenciais.
- O relatório atual só produz `status=PROPOSED` e `executable=false`; não há executor.
- Testes ativos somente com autorização sobre a experiência Roblox; não burlar controles nem operar em jogos de terceiros.
- GitHub Actions deve usar `permissions: contents: read`, fixtures sintéticas e sem segredos.
- Mudanças de gateway/Render/banco/APK e publicação no Roblox exigem aprovação específica, testes e revisão.
- Proteger dados de jogadores antes de processamento externo ou migração. Eliminar um arquivo de branch pública não elimina automaticamente cópias históricas.
- Limitar uso de modelos à cota gratuita; nenhum serviço pode ativar cobrança por conta própria.

**Pendente:** autenticação de missões, fila, rate limit, sandbox, política de execução, revisão de privacidade histórica e auditoria completa do canal bidirecional.

## Proteções adicionadas na ingestão multi-batch

- Não ler campos de argumentos, textos, nomes ou conteúdo de remotes para a memória.
- Validar IDs, nomes de lotes e limites de arquivos, e rejeitar links simbólicos em arquivos JSON.
- Exigir manifesto da mesma sessão e perfil de mesmo jogo.
- Recusar sobrescrita de lote previamente indexado com checksum diferente.
- Persistência atômica local com bloqueio exclusivo; índice remoto não implementado.
- Falta de quantidade declarada de lotes nunca equivale a cobertura completa.

A execução da CI com uma sessão histórica real **não publica registros brutos nos logs** e não oferece essas capturas a modelos externos. Mesmo assim, a revisão de privacidade dos dados já publicados permanece pendente.

## Modelo local e privilegios de CI

- O cliente de modelo permite somente endpoint HTTP local (127.0.0.1/localhost), impõe timeout e limita os tokens gerados.
- As respostas do LLM passam por enums restritos, não podem executar ferramentas, aprovar missões ou elevar hipóteses a VALIDATED.
- Workflow de memória separa dois jobs: leitura com `contents: read` e publicação explícita com `contents: write`.
- A CI principal nunca grava memória remota; a publicação real continua pendente de revisão e teste controlado.

## Teste real do modelo, fonte e fronteiras

O Qwen2.5 0.5B foi baixado pelo Ollama em container Docker no runner efemero do GitHub Actions. A API so ficou acessivel em `127.0.0.1:11434`, sem acesso a secrets de producao, Render ou menu. A entrada foi uma fixture sintetica com campos maliciosos simulados; o contrato de saida manteve a geracao em enum seguro. O modelo nao pode executar ferramentas, adicionar permissoes nem marcar evidencias como comprovadas.

O diario `decision-journal.mjs` aceita somente IDs de jogo/sessao, papeis de agentes e campos controlados. Nao exporta livremente prompts, nomes, mensagens ou respostas integrais do modelo. Um artefato desse diario dura no maximo sete dias.

## API GitHub e limites de requisicao

Os testes de leitura em runners usam o `github.token` efemero do proprio Actions, com `permissions: contents: read`; isso evita depender de chamadas anonimas sujeitas a limite por IP. O token nao e enviado a modelos nem exibido nos logs. Publicacao continua restrita a um job explicitamente solicitado com `contents: write`.

## Missões offline e recuperação

O estado do planejamento não contém payload bruto, nomes de jogadores, tokens ou instruções livres. Limites de duração, tentativas, revisão e lease reduzem loops e duplicações. Somente transições de estado permitidas são gravadas; atualizações conflitantes e atributos extras são rejeitados. A conclusão exige o ID da conversa derivado da sessão e manifesto; todo trabalho continua `OFFLINE_METADATA_ONLY`.

Essas garantias são locais e não equivalem a autorização de ferramentas no menu Roblox ou a persistência durável entre runners. Não há executor de comandos no novo módulo.

## GitHub tasks e REA (integracao read-only)

- O armazenamento remoto de tarefas é restrito à branch `cafeina-ai-knowledge`, aos caminhos `ai-core/tasks/<gameId>/task-<hash>.json` e a estados com campos validados. Cada gravação exige token e revisão esperada; leitura não executa conteúdo.
- Teste em runners distintos usou exclusivamente fixtures **sintéticas**, sem dados reais de jogadores, e não habilitou execução no Roblox.
- O REA foi instalado temporariamente por versão fixada, sem credenciais e com dados vazios. O handoff V3 informa `reaEvidenceAuthenticated=false` e não cria obrigações verificadas de reconstrução.
- Nenhuma dessas integrações fornece autonomamente autoridade para inspecionar jogos de terceiros, executar remotes ou publicar código.
## Propostas e recibos do menu

Toda proposta é não executável e exige aprovação independente. Referências devem pertencer à mesma sessão. O token de teste do gateway local não representa identidade Roblox; o servidor real precisará autenticar a sessão e gerenciar seus próprios tokens. O cliente não recebe acesso GitHub. Nenhuma rota foi adicionada ao Render.

## Registros de ACK e estado de entrega

O registro de missão não contém qualquer resultado de observação nem
identidade do jogador. Ele armazena apenas IDs de jogo/sessão,
hash da proposta, quatro estados enumerados, três instantes, revisão
e a decisão `DECLINED` ou `NOT_EXECUTED`. Todos os registros possuem
`approved=false` e `executed=false`.

Somente os eventos previstos podem mudar o estado; não há endpoint
para elevar permissões. O gateway **simulado** só confirma eventos
após confirmação do armazenamento opcional. As integrações reais da API GitHub para recibos foram exercitadas apenas com dados inteiramente sintéticos em runners isolados. Não reutilizar este contrato como
prova de autenticação de jogadores em Roblox.

## Validação com API real do GitHub, sem acesso Roblox

O experimento `github-menu-real-smoke.mjs` usa somente fixtures sintéticas, GitHub Actions com token efêmero, e branch separada. O gateway HTTP simulado fica em 127.0.0.1, usa uma credencial temporária gerada no processo e não passa credenciais GitHub ao cliente HTTP. Qualquer resposta que afirme aprovação ou execução é rejeitada.

A gravação real deixa metadados sintéticos na branch de conhecimento; definir e testar política de retenção e expurgo antes de uso com dados reais. **A autenticação do simulador não é autenticação Roblox.** Não implantar em produção sem verificação de sessão, propriedade da experiência e limites de uso.
