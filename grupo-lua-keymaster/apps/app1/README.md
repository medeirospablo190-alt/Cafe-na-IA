# GRUPO LUA — App 1 Mobile

Aplicativo 1 do ecossistema GRUPO LUA. A versão atual é `0.3.2`.

## Fluxo de acesso do App 1

```text
login privado
→ validação server-side
→ vínculo/prova do dispositivo
→ sessão provisória
→ aviso obrigatório + aceite
→ pseudônimo validado pelo servidor
→ onboarding concluído
→ sessão FULL
→ shell do App 1 liberado
```

Depois do login bem-sucedido, o aplicativo não mantém a credencial digitada na interface. A sessão e a prova do dispositivo ficam protegidas pelo SecureStore/Keychain/Keystore.

## Navegação atual

```text
Início | Arquivos | Social | Chaves | Chats | Configurações
```

### Arquivos

- biblioteca de códigos e loadstrings;
- criação, leitura, edição e exclusão;
- favoritos;
- ações em lote;
- compartilhamento no Social;
- cofre privado local de fotos e vídeos, separado por instalação e perfil;
- importação pelo seletor nativo, busca, visualização de fotos e reprodução de vídeos;
- limite total de 1 GB, limites por arquivo e reserva de espaço livre;
- índice transacional com cópia de segurança e recuperação de arquivos locais.

### Social

- feed;
- perfis públicos por pseudônimo;
- curtidas;
- comentários e respostas;
- favoritos;
- lista de favoritos;
- notificações sociais;
- publicações fixadas;
- mensagem global exclusiva para DEV.

### Chats

- conversas privadas 1:1;
- busca por pseudônimo;
- mensagens não lidas;
- favorito e silenciar conversa;
- denúncia auditada;
- mensagens normais com retenção de 24 horas;
- preservação da conversa enquanto estiver favoritada;
- carregamento paginado de mensagens antigas sem perder o histórico já aberto durante a atualização automática.

### Configurações

- bio;
- pensamento/status;
- avatar;
- moldura;
- presença;
- gerenciamento de perfil e sessão.

## Chaves dos menus

A área `Chaves` é funcional e é o único lugar do sistema em que FREE e VIP devem ser administradas.

### FREE

- duração configurável entre 1 e 24 horas;
- o relógio começa no primeiro uso;
- a chave fica vinculada ao primeiro aparelho;
- ao terminar o período, entra em `WAITING_ADMIN` / `AGUARDA ADM`;
- não inicia outro ciclo sozinha;
- um ADM/DEV do App 1 precisa liberar novamente a chave;
- a cada nova liberação o ADM/DEV escolhe novamente de 1 a 24 horas;
- troca de aparelho é uma ação administrativa explícita e não reinicia automaticamente o tempo de acesso já iniciado.

### VIP

- duração em dias, meses ou permanente;
- o relógio começa no primeiro uso;
- também fica vinculada ao primeiro aparelho;
- a cada renovação/reconfiguração o ADM/DEV pode escolher novamente dias, meses ou permanente;
- reiniciar uma VIP ativa encerra as sessões atuais e a nova validade começa no próximo uso;
- VIP permanente não recebe data final de acesso.

### Loadstring do menu

Ao abrir um menu na área `Chaves`, o App 1 pode copiar o loadstring daquele menu diretamente usando o `public_id` cadastrado no servidor.

O formato gerado é:

```lua
getgenv().GRUPO_LUA_MENU_ID = "menu_xxxxx"
loadstring(game:HttpGet("https://raw.githubusercontent.com/medeirospablo190-alt/Cafe-na-IA/main/GrupoLuaLogin.lua"))()
```

O login-base salva somente o token de sessão do menu. A chave digitada não é gravada em arquivo. Enquanto a sessão continuar válida e o aparelho continuar autorizado, a próxima execução tenta abrir o menu automaticamente.

## Configuração obrigatória da Control API

A build precisa receber:

```text
EXPO_PUBLIC_GRUPO_LUA_API_URL=https://grupo-lua-control-api.onrender.com
```

O portal público de downloads não deve ser usado como Control API.

## Build Android

O workflow `.github/workflows/app1-android-apk.yml` compila um APK standalone e usa a versão definida em `apps/app1/app.json` no nome do artefato.

A versão Android atual é:

```text
App: 0.3.2
versionCode: 6
```

O artefato esperado é:

```text
GRUPO-LUA-APP1-v0.3.2-android
└── GRUPO-LUA-APP1-v0.3.2.apk
```

## Cobertura de testes relevante

A Control API possui testes para:

- limite FREE de 24 horas;
- duração VIP em dias e meses;
- tratamento de fim de mês e ano bissexto;
- VIP permanente;
- vínculo da chave ao primeiro aparelho;
- bloqueio de uso em outro aparelho;
- expiração FREE e exigência de nova liberação;
- administração FREE/VIP pelas rotas autenticadas do App 1;
- troca/desvínculo de aparelho;
- listagem sem revelar novamente o valor completo da chave;
- perfil, Social, curtidas, favoritos, comentários e notificações;
- criação de chat, mensagem, não lidas, favorito e denúncia;
- proteção por sessão FULL e dispositivo autorizado.
