# CAFEÍNA AI — Tela local de revisão de ferramentas (simulação)

## O que foi implementado

Uma tela real de navegador, com HTML e formulário acessível, em um
**servidor HTTP somente local** vinculado a `127.0.0.1`.
O código fica em `src/collector-review-browser.mjs`, e a demonstração
em `src/collector-review-browser-demo.mjs`.

A tela exibe a ferramenta planejada, finalidade, limites (2 simulações
offline de 10 segundos de orçamento), expiração e estado do pedido.
Os botões permitem somente `DENIED` ou `SIMULATION_ALLOWED` **de teste**.
Após uma decisão final ou o vencimento, não permite nova revisão.
Também pode abrir, em modo somente leitura, um registro já encerrado
e validado, sem reativar os controles.

### Como abrir em ambiente Node.js 22+

Na raiz do repositório, após selecionar a branch do PR:

```bash
npm --prefix ai-core run collector:review-browser
```

Abra o endereço `http://127.0.0.1:<porta>` exibido no terminal
**no navegador do mesmo dispositivo**. Encerre com Ctrl+C.
A porta é alocada pelo sistema. O comando não requer token, login,
banco de dados ou Roblox Studio.

**No celular:** exige um ambiente Node compatível executado no
próprio aparelho. A página não é acessível remotamente pelo GitHub
sem um serviço web adicional, e nenhum serviço foi implantado.

## Limites e segurança

- `NODE_ENV=production` recusa iniciar o servidor de demonstração.
- Não oferece arquivos JavaScript de execução, scripts Luau, endpoints
  para o coletor, ferramentas de IA ou qualquer comunicação com GitHub.
- A interface usa formulário HTML simples, bloqueia origem e Host
  diferentes do loopback, e exige desafio CSRF aleatório em cada decisão.
- Corpo de POST limitado a 512 bytes, campos exatos, tipos de decisão
  enumerados, verificação de expiração e apenas **uma transição final**.
- HTML escapa campos interpolados e usa CSP restritiva sem JavaScript.
- Não envia nomes de jogadores, tokens, segredos ou conteúdos brutos.
- A confirmação do formulário é avaliada com um operador **fictício
  dentro do próprio processo**. **Isto não autentica um humano real.**
- O estado de demonstração reside apenas na memória do processo e
  se perde ao encerrá-lo; não é persistido no GitHub.

O armazenamento real de **registros sintéticos** já tem módulo
separado (`github-collector-permissions.mjs`). O servidor local
pode receber um documento final previamente validado, mas não faz
gravações remotas e não serve como interface de consentimento de produção.

### O que ainda falta para o Roblox real

Autenticação do proprietário, identidade confiável do servidor e
jogador, teste numa experiência própria, permissão separada para
instrumentos ativos, revogação persistente, auditoria, interface
integrada ao menu Roblox e implantação autorizada de gateway.

**A decisão `SIMULATION_ALLOWED` não permite interagir com o jogo,
executar Luau nem ler/alterar dados do coletor real.**

## Testes

```bash
node --test ai-core/test/collector-review-browser.test.mjs ai-core/test/collector-review-import.test.mjs
```

Os testes usam apenas fixtures sintéticas e HTTP local.

## Direcionamento do produto

O objetivo final não é iniciar pelo navegador. A interface de teste do **executor Roblox** está em `roblox-reference/ExecutorMenu.client.luau` e documentada em `docs/EXECUTOR_MENU.md`. O servidor Node local permanece apenas como ensaio de contratos.
