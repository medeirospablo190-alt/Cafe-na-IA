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
