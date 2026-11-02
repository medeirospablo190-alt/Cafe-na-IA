# CAFEÍNA AI — Entrada pelo executor Roblox (versão de teste)

**O destino do menu é o executor Luau do Roblox no celular.** O navegador
local e o Node.js eram apenas ensaios auxiliares; não são mais o ponto de
entrada planejado para este menu.

## Abrir no executor

O script completo está em:
`ai-core/roblox-reference/ExecutorMenu.client.luau`

Para um executor que suporte `loadstring` e `game:HttpGet`,
execute esta linha para carregar uma **versão fixada** do script:

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/medeirospablo190-alt/Cafe-na-IA/16741de199602d264ef117087461a87214557631/ai-core/roblox-reference/ExecutorMenu.client.luau"))()
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

- **Missões:** informa o estado local e exibe uma proposta sintética.
- **Permissões:** mostra `watch_state`, prazo de 120 segundos, limite
  de 2 prévias, recusa e botão de prévia **fictícia**.
- **Diagnóstico:** indica que GitHub, gateway, coletor e Roblox real
  continuam desconectados e exibe eventos locais limitados.

O menu funciona ao toque, pode ser arrastado pelo cabeçalho, minimizado,
reaberto pelo botão flutuante ou fechado. Uma nova execução remove somente
a instância anterior desta interface, para evitar duplicatas.

## Limites importantes

Este é um **protótipo de apresentação e decisão sintética na memória do
cliente**, não uma autorização real. Não possui
`HttpService`, execução Lua dinâmica, `RemoteEvent`,
`RemoteFunction`, acesso a segredos ou chamada a ferramentas.
A aprovação do botão não é enviada para nenhum servidor ou GitHub.

**Um executor é um cliente não confiável**: valores, UI e decisões locais
podem ser alterados pelo próprio cliente. O servidor de um jogo de
propriedade/autorizado deve verificar identidade, sessão, propriedade,
permissões e validade de forma independente. Nunca coloque tokens do
GitHub, segredos de servidor, credenciais de IA ou dados de jogadores no
executor ou no script do menu.

Este script **não foi executado dentro de um executor real** por nossa CI.
Os testes automatizados são estáticos e verificam a ausência de APIs
proibidas; só um teste manual em ambiente Roblox autorizado pode comprovar
compatibilidade de execução e toque.

A versão de navegador permanece disponível em
`docs/COLLECTOR_REVIEW_BROWSER.md` exclusivamente para testes do
contrato, não como produto final.

## Próximos passos

1. Testar no executor do dispositivo em experiência própria e registrar
   eventuais erros de compatibilidade.
2. Adaptar o modelo de estado do menu para ler propostas permitidas do
   gateway com credencial curta e autenticação validada no servidor.
3. Exibir fluxos reais de permissões sem confundir confirmação do cliente
   com aprovação segura do proprietário.
4. Somente após autorização explícita integrar observações limitadas à
   experiência própria; nada disso existe nesta versão.
