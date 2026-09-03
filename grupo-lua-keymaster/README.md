# GRUPO LUA PLATFORM — V0.9.0

Plataforma móvel composta pelo **App 1**, **Keymaster (App 2)** e uma **Control API** server-side com PostgreSQL.

A partir da V0.9, o desenvolvimento completo do App 1 está autorizado e começa pela camada de segurança/identidade antes de Social, Chats e demais interfaces finais.

## Estrutura

```text
apps/keymaster        App 2 / Keymaster Android+iPhone (Expo SDK 57)
apps/app1-probe       Sonda transitória do App 1 durante a Fase 1
services/control-api  API server-side + PostgreSQL
packages/contracts    Roles/permissões/contratos compartilhados
docs                  Especificações e decisões do produto
```

Especificação principal do App 1:

```text
docs/app1-v1-master-spec.md
```

## Princípio central

> O aplicativo pede; o servidor decide.

A Control API é a autoridade para autenticação, role, status, sessões, bloqueios, dispositivos, ownership, retenção, menus, chaves e ações críticas. Esconder um botão na interface nunca substitui uma verificação server-side.

Segredos reais não devem ser enviados ao GitHub. Peppers, chaves de criptografia, credenciais de banco, tokens de provedor, chave mestre do Keymaster e demais segredos ficam apenas no ambiente seguro de produção.

## Keymaster

O Keymaster continua sendo o aplicativo de maior privilégio e é reservado a contas DEV.

Recursos já existentes antes da V0.9:

- login por chave mestre com hash `scrypt` server-side;
- campo preparado para até 16.384 caracteres;
- três falhas consecutivas bloqueiam o dispositivo por 24h;
- fingerprint de dispositivo protegido por HMAC;
- Android ID / IDFV com installation ID como sinal auxiliar;
- estrutura para Play Integrity / App Attest;
- sessão Keymaster revogável;
- dashboard administrativo;
- criação/listagem/suspensão/restauração/rotação/exclusão de contas App 1;
- sessões App 1 visualizáveis/revogáveis;
- auditoria server-side;
- manutenção/reinício do App 1 com step-up DEV;
- administração de menus e chaves FREE/VIP;
- controle de sessões dos menus;
- exclusão protegida de menu.

## App 1 — Fase 1 / V0.9

A V0.9 começa a substituir a antiga sonda de compatibilidade pelo contrato real de segurança do App 1.

### Login e bloqueio

- três tentativas inválidas aplicáveis podem colocar a conta em `LOCKED_SECURITY`;
- o bloqueio é server-side;
- trocar Wi-Fi, dados móveis, VPN, cache ou reinstalar não limpa o estado de segurança no servidor;
- sessões ativas são revogadas quando a conta é bloqueada;
- DEV pode liberar a conta por uma ação crítica auditada;
- logs de tentativa usam fingerprints/identificadores protegidos e nunca armazenam a credencial tentada em texto puro.

### Dispositivos

- primeiro login válido vincula o primeiro dispositivo;
- cada dispositivo recebe uma prova/token próprio armazenado de forma segura no cliente e somente seu hash permanece no servidor;
- credencial válida em dispositivo não autorizado é recusada;
- três eventos aplicáveis em dispositivo não autorizado podem bloquear a conta inteira;
- máximo inicial: dois dispositivos ativos por conta;
- para adicionar outro dispositivo, DEV abre uma autorização server-side de até 10 minutos;
- a autorização é de uso único e é marcada `CONSUMED` imediatamente após o cadastro; tempo restante não pode ser reutilizado;
- DEV pode cancelar janela pendente e revogar dispositivo.

A arquitetura também está preparada para integrar atestação forte de produção via Play Integrity/App Attest. O modo estrito só deve ser habilitado quando o verificador real estiver configurado e testado no servidor.

### Primeiro acesso / onboarding

Um primeiro login correto gera apenas uma sessão provisória curta. O acesso normal só é liberado depois que o servidor confirmar:

1. aceite da versão atual dos termos/privacidade;
2. pseudônimo público válido.

O pseudônimo é separado do login privado. Respostas normais do App 1 não devem devolver o login de autenticação.

Depois da conclusão do onboarding, a sessão normal é fixa por **24 horas**. Reabrir o aplicativo não reinicia o relógio. O cliente guarda somente tokens necessários em armazenamento seguro; login e credencial são apagados da interface após autenticação.

## Social — requisito aprovado, implementação posterior à fundação

O Social é mobile-first e terá:

```text
Like | Comentários | Favorito
```

- likes públicos com contador;
- comentários fechados por padrão e expandidos para baixo ao tocar;
- respostas com apenas um nível visual de indentação;
- favoritos de posts públicos, com contador e lista de perfis que favoritaram;
- perfil com `POSTS | FAVORITOS`;
- um único post principal fixado por DEV por vez;
- identidade DEV oficial em vermelho;
- mensagem global DEV;
- busca somente de perfis por identidade pública;
- notificações Social separadas de mensagens privadas.

Retenção aprovada:

- posts normais: 24h, salvo preservação por favorito/pin;
- mensagens/conversas normais: 24h, salvo preservação aplicável;
- notificações: 24h;
- chaves, menus, scripts, arquivos, configurações, perfil, stickers e auditoria não entram na limpeza automática do Social.

## Privacidade de chats

A arquitetura final deve cumprir a promessa exibida ao usuário:

- conta `ACTIVE`: não existe endpoint administrativo comum para abrir chats privados;
- denúncia relevante pode levar a suspensão;
- somente depois da suspensão um fluxo explícito, limitado e auditado pode liberar o conteúdo necessário para análise;
- suspender não significa expor automaticamente todo o conteúdo ao DEV.

## Menus e chaves — estado atual e próxima fase

A V0.8 já possui menus, chaves FREE/VIP e sessões server-side. Na V0.9 a especificação futura foi consolidada para migrar esse sistema para:

- ownership por ADM;
- DEV com visão global;
- `MENU_1` obrigatório + `MENU_2` opcional, máximo de dois destinos;
- `kind = FREE | VIP` separado de `targetSlot = MENU_1 | MENU_2`;
- um único initializer/Access Gate público;
- chave FREE/VIP vinculada ao primeiro dispositivo que a usar;
- log próprio por menu e visão filtrada por chave;
- tentativa em outro dispositivo registrada e recusada;
- área comum mostra apenas hints mascarados;
- revelação completa somente em aba protegida após autorização curta do servidor;
- para revelação posterior, usar `key_hash` para autenticação e `key_encrypted` para exibição autorizada, com a chave de criptografia somente no ambiente seguro do servidor.

O Access Gate oficial continua baseado no visual **GRUPO LUA Access Gate V3.1**: compacto, horizontal/mobile-landscape, preto/escuro, botão branco, acentos vermelhos sutis, lua crescente e um único campo FREE/VIP.

## Segurança de produção

Antes de considerar a plataforma pronta para uso real:

- configurar PostgreSQL de produção e backups;
- configurar secrets/peppers fora do repositório;
- configurar verificação real de App Integrity e testar em modo report antes de enforce;
- usar rate limiting compartilhado em implantação com múltiplas instâncias;
- manter respostas de autenticação sem vazamento de estado sensível;
- testar migrações em banco limpo e upgrade;
- executar testes unitários, integração e E2E;
- revisar permissões/ownership no servidor;
- definir recuperação das chaves de criptografia server-side.

## CI

O workflow `.github/workflows/keymaster-ci.yml` valida:

- sintaxe da Control API;
- testes unitários de segurança/menus/App 1;
- aplicação das migrations em PostgreSQL de teste;
- contratos compartilhados;
- TypeScript do Keymaster;
- TypeScript da sonda App 1.

## Distribuição Android

Para instalação direta e simples no celular, a estratégia planejada é **EAS Build com distribuição interna**, gerando APK instalável e URL compartilhável. Para Google Play, a build de loja usa AAB.

A etapa final de distribuição deverá incluir assinatura de produção, versão, hash SHA-256 e automação de build/release quando apropriado.

## Ordem de implementação

1. **Segurança e identidade** — V0.9 em andamento.
2. **Menus/chaves** — ownership, dois slots, device binding, logs e reveal protegido.
3. **Social** — perfil, busca, feed, likes, comentários, favoritos, pin DEV e notificações.
4. **Chats** — retenção, favoritos, notificações e fluxo de denúncia/análise.
5. **Arquivos/acabamento** — personalização, acessibilidade, testes E2E, observabilidade e distribuição APK.

Para os detalhes completos e regras que prevalecem em caso de conflito com documentos históricos, consulte `docs/app1-v1-master-spec.md`.
