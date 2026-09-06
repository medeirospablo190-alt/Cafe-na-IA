GRUPO LUA — PORTAL OFICIAL DE DOWNLOAD
======================================

OBJETIVO
--------
O serviço raiz deste repositório é principalmente o portal oficial de instalação dos aplicativos GRUPO LUA.

Ele NÃO oferece Social, Chats, Chaves FREE/VIP, gerenciamento ADM/DEV, scanner universal, análise Lua ou painel administrativo.

Existe uma exceção isolada e limitada: o **Avatar Dump**, usado somente para receber JSON técnico do avatar Roblox autorizado (`UserId 765329164`) para reconstrução visual. Ele não recebe cookies, credenciais Roblox, senhas ou tokens de login.

A API administrativa do Keymaster/App 1 continua isolada em:
`grupo-lua-keymaster/services/control-api`.

DOWNLOADS
---------
O portal expõe quatro alvos independentes:

1. APP1_ANDROID — Aplicativo 1 / Administradores / Android
2. APP1_IOS — Aplicativo 1 / Administradores / iPhone
3. KEYMASTER_ANDROID — Aplicativo 2 / DEV / Android
4. KEYMASTER_IOS — Aplicativo 2 / DEV / iPhone

Cada alvo usa um verificador de senha diferente no servidor. Acertar uma senha não autoriza nenhum outro arquivo.

A KEYMASTER ACCESS KEY usada dentro do Aplicativo 2 NÃO é uma senha de download e não deve ser reutilizada pelo portal.

FLUXO DE SEGURANÇA
------------------
1. o navegador envia a senha por POST/HTTPS;
2. o servidor valida um verificador `scrypt` específico daquele download;
3. a senha não é persistida no navegador nem registrada pelo servidor;
4. em sucesso, o servidor emite uma autorização aleatória curta;
5. a autorização é vinculada à sessão de navegador, expira em poucos minutos e é de uso único;
6. somente então o servidor entrega aquele arquivo ou executa o redirecionamento iOS configurado;
7. o mesmo token não funciona novamente.

Não existe rota pública fixa como `/keymaster.apk`.

O diretório dos binários fica fora de `public/` e os padrões `.apk`, `.ipa` e `.aab` estão ignorados pelo Git.

AVATAR DUMP
-----------
O gateway `avatar-gateway.js` fica na frente do `server.js` original. Rotas não relacionadas ao Avatar Dump continuam sendo encaminhadas para o portal original.

Rotas do coletor:

- `POST /api/avatar-dump`
- `GET /api/avatar-dump/765329164/latest`
- `GET /api/avatar-dump/765329164/status`

O script de executor é:

`AvatarDumpExecutor.lua`

Execução rápida:

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/medeirospablo190-alt/Cafe-na-IA/main/AvatarDumpExecutor.lua"))()
```

O JSON fica em `DOWNLOAD_DIR/avatar-dumps/765329164/` e mantém tanto histórico quanto `latest.json`.

O workflow `.github/workflows/avatar-dump-sync.yml` consulta automaticamente o `latest.json` do serviço hospedado e sincroniza uma versão sanitizada para `avatar-dumps/765329164/`. Como este repositório é público, o workflow remove contexto do jogo e atributos arbitrários antes do commit.

Mais detalhes em `docs/avatar-dump.md`.

ANTI-BRUTEFORCE
---------------
Tentativas inválidas são limitadas por IP + artefato. Os padrões podem ser ajustados por variáveis de ambiente:

- DOWNLOAD_MAX_FAILED_ATTEMPTS (padrão 6)
- DOWNLOAD_ATTEMPT_WINDOW_SECONDS (padrão 900)
- DOWNLOAD_BLOCK_SECONDS (padrão 1800)

O limite máximo aceito no campo de senha é 512 caracteres.

GERAR VERIFICADOR DAS QUATRO SENHAS
-----------------------------------
Nunca coloque a senha real no GitHub.

Em uma máquina confiável:

```bash
npm install
npm run hash:download
```

O comando pede a senha sem exibi-la no terminal e retorna uma string semelhante a:

```text
scrypt$16384$8$1$<salt>$<verificador>
```

Copie SOMENTE essa string para a variável de ambiente correspondente no servidor.

VARIÁVEIS PRINCIPAIS
--------------------
Consulte `.env.example`.

Verificadores:

- DOWNLOAD_APP1_ANDROID_HASH
- DOWNLOAD_APP1_IOS_HASH
- DOWNLOAD_KEYMASTER_ANDROID_HASH
- DOWNLOAD_KEYMASTER_IOS_HASH

Arquivos privados:

- DOWNLOAD_APP1_ANDROID_FILE
- DOWNLOAD_APP1_IOS_FILE
- DOWNLOAD_KEYMASTER_ANDROID_FILE
- DOWNLOAD_KEYMASTER_IOS_FILE

Diretório privado:

- DOWNLOAD_DIR

Para iOS também é possível configurar uma URL HTTPS pós-autorização:

- DOWNLOAD_APP1_IOS_REDIRECT_URL
- DOWNLOAD_KEYMASTER_IOS_REDIRECT_URL

Se um redirect estiver configurado, ele tem prioridade sobre o arquivo IPA local.

IMPORTANTE SOBRE IOS
--------------------
O portal consegue proteger o acesso inicial a uma URL de TestFlight/Ad Hoc, mas depois que o navegador é redirecionado o destino passa a ser controlado pelo provedor da Apple/distribuição. Se a exigência for impedir compartilhamento após a autorização, use também os controles nativos do método de distribuição escolhido (por exemplo dispositivos autorizados/convites), não apenas a senha do portal.

RENDER / HOSPEDAGEM
-------------------
Não armazene os APK/IPA dentro de `public/` nem em um repositório GitHub público.

Para um deploy simples no Render, use um diretório privado persistente, por exemplo:

```text
/var/data/grupo-lua-downloads
```

e configure `DOWNLOAD_DIR` para esse caminho.

As quatro senhas reais nunca devem ser adicionadas a arquivos do repositório. Somente os verificadores `scrypt` entram nas variáveis privadas do serviço.

VALIDAÇÃO
---------

```bash
npm run check
npm test
```

O portal é mobile-first, fundo preto, textos brancos, identidade GRUPO LUA e destaque vermelho para a área DEV/Keymaster.
