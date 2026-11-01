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
