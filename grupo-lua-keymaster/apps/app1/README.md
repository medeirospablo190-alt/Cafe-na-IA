# GRUPO LUA — App 1 Mobile

Aplicativo 1 do ecossistema GRUPO LUA. A versão atual é `0.2.0`.

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

A navegação-base é:

```text
Início | Arquivos | Social | Chaves | Chats
```

A área `Chaves` já é funcional e é o único lugar do sistema em que FREE e VIP devem ser administradas.

## Regras das chaves dos menus

### FREE

- duração configurável entre 1 e 24 horas;
- o relógio começa no primeiro uso;
- a chave fica vinculada ao primeiro aparelho;
- ao terminar o período, entra em `WAITING_ADMIN` / `AGUARDA ADM`;
- não inicia outro ciclo sozinha;
- um ADM/DEV do App 1 precisa liberar novamente a chave;
- a nova liberação também pode escolher de 1 a 24 horas;
- troca de aparelho é uma ação administrativa explícita.

### VIP

- duração em dias, meses ou permanente;
- o relógio começa no primeiro uso;
- também fica vinculada ao primeiro aparelho;
- VIP expirada precisa ser renovada/configurada novamente por ADM/DEV;
- VIP permanente não recebe data final de acesso.

## Login dos menus Roblox

O login-base dos menus usa `GrupoLuaLogin.lua` na raiz do repositório.

O loader de cada menu deve definir o `menuId` antes de executar o login:

```lua
getgenv().GRUPO_LUA_MENU_ID = "menu_xxxxx"
loadstring(game:HttpGet("https://raw.githubusercontent.com/medeirospablo190-alt/Cafe-na-IA/main/GrupoLuaLogin.lua"))()
```

O login salva somente o token de sessão do menu. A chave digitada não é gravada em arquivo. Enquanto a sessão continuar válida e o aparelho continuar autorizado, a próxima execução tenta abrir o menu automaticamente.

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
App: 0.2.0
versionCode: 3
```

O artefato esperado é:

```text
GRUPO-LUA-APP1-v0.2.0-android
└── GRUPO-LUA-APP1-v0.2.0.apk
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
- listagem sem revelar novamente o valor completo da chave.
