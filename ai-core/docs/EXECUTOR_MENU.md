# CAFEÍNA AI — Entrada pelo executor Roblox (prévia v0.3)

**O destino do menu é o executor Luau do Roblox no celular.** O navegador
local e o Node.js eram apenas ensaios auxiliares; não são mais o ponto de
entrada planejado para este menu.

## Abrir no executor

O script completo está em:
`ai-core/roblox-reference/ExecutorMenu.client.luau`

Para um executor que suporte `loadstring` e `game:HttpGet`,
execute esta linha para carregar uma **versão fixada** do script:

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/medeirospablo190-alt/Cafe-na-IA/df543e66623322fba2496edc190e6db284d9210b/ai-core/roblox-reference/ExecutorMenu.client.luau"))()
```

A versão está fixada no commit acima, para que mudanças futuras na
branch não alterem silenciosamente o código executado. Leia o script antes
de executá-lo. Se o executor não oferecer essas duas funções, copie o
conteúdo integral de `ExecutorMenu.client.luau` e cole no editor do
executor. Nenhuma API especial de executor é usada **dentro** do menu.

**Use somente na sua experiência Roblox ou em uma experiência que você
tenha autorização para testar.** Não há integração com outros jogos.

## O que aparece

A interface no `PlayerGui` possui três abas:

- **Missões:** exibe a proposta sintética local e, se a ponte estiver instalada pelo proprietário no servidor da experiência, consulta propostas não executáveis no GitHub por intermédio desse servidor.
- **Permissões:** mostra `watch_state`, prazo de 120 segundos, limite
  de 2 prévias, recusa e botão de prévia **fictícia**.
- **Diagnóstico:** mostra a presença do RemoteFunction autorizado, permite consultar o status local do servidor e mostra dimensões úteis da interface,
  exibe eventos locais limitados e permite executar **autodiagnóstico offline**.

O menu funciona ao toque, pode ser arrastado pelo cabeçalho, minimizado,
reaberto pelo botão flutuante ou fechado. A interface agora respeita
`CoreUISafeInsets`, limita o movimento às bordas visíveis, recentraliza
em mudança de orientação e atualiza o contador de prazo de aprovação.
Ao fechar ou reinjetar, desconecta os ouvintes globais de entrada desta interface.
Uma nova execução remove somente a instância anterior, para evitar duplicatas.

## Limites importantes

Este é um **protótipo de comunicação restrita**, sem autorização de ferramentas reais.
Não possui `HttpService`, acesso HTTP direto, segredos, execução Lua dinâmica ou chamadas a ferramentas de coleta.
Usa somente o `RemoteFunction` nomeado `CAFEINA_MENU_REMOTE`, se o servidor autorizado o tiver instalado.
O botão de aprovação na aba Permissões permanece fictício; apenas a leitura, confirmação e recusa de missões não executáveis pode atravessar a ponte.

**Um executor é um cliente não confiável**: valores, UI e decisões locais
podem ser alterados pelo próprio cliente. O servidor de um jogo de
propriedade/autorizado deve verificar identidade, sessão, propriedade,
permissões e validade de forma independente. Nunca coloque tokens do
GitHub, segredos de servidor, credenciais de IA ou dados de jogadores no
executor ou no script do menu.

O usuário já informou que a versão v0.2 abriu no dispositivo. A versão v0.3
com integração opcional ainda **não** foi testada manualmente no Roblox.
O CI apenas verifica os contratos e simula o transporte pelo Node; não valida o Studio nem o gateway público.

A versão de navegador permanece disponível em
`docs/COLLECTOR_REVIEW_BROWSER.md` exclusivamente para testes do
contrato, não como produto final.

## Roteiro de teste manual Android (obrigatório antes de integrar)

1. Abrir **somente uma experiência própria ou autorizada**, iniciar o menu
   pela linha fixada acima e observar se abre sem erro.
2. No modo retrato e paisagem, abrir as três abas e conferir se botões e
   textos cabem, ficam visíveis e respondem a toques.
3. Arrastar pelo cabeçalho até cada borda: a janela não deve ficar
   inacessível; rotacionar o celular e verificar se ela volta ao centro.
4. Minimizar, abrir pelo botão **C**, fechar e carregar novamente.
   Não devem surgir duas interfaces nem toques duplicados.
5. Em **Diagnóstico**, tocar **Verificar interface (offline)**.
   Esperado: **APROVADO** e `UI_SELF_TEST_OK`. Isso verifica somente
   integridade básica da UI, **não** conectividade nem segurança do executor.
6. Em **Permissões**, verificar o contador de 120 segundos, recusar ou
   permitir a prévia fictícia e confirmar que não acontece nenhuma ação no jogo.

Anotar apenas: modelo/versão do Android, modo retrato/paisagem, executor
utilizado se quiser informar, etapa que falhou e mensagem de erro.
**Não compartilhar senhas, tokens, IDs privados ou dados de jogadores.**

## Próximo marco

Instalar e configurar, em experiência Roblox própria/autorizada, o script de servidor e o gateway isolado descritos em [`OWNER_MENU_BRIDGE.md`](OWNER_MENU_BRIDGE.md). Validar no Android o fluxo de consulta, confirmação e recusa. Nenhuma ferramenta real será executada nesse teste.
