# GRUPO LUA — Avatar Dump

O coletor `AvatarDumpExecutor.lua` extrai somente dados do avatar visíveis ao cliente Roblox e envia para o gateway do projeto.

## Execução rápida no executor

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/medeirospablo190-alt/Cafe-na-IA/main/AvatarDumpExecutor.lua"))()
```

Alvo padrão:

- Username: `Capuccino40`
- UserId: `765329164`
- Endpoint: `https://cafe-na-ia.onrender.com/api/avatar-dump`

## O que é coletado

- `HumanoidDescription` e acessórios
- `MeshPart.MeshId`
- `MeshPart.TextureID`
- `SpecialMesh.MeshId` / `TextureId`
- `SurfaceAppearance` (Color/Normal/Roughness/Metalness maps)
- roupas clássicas
- decals/textures
- attachments
- `Motor6D`, welds e CFrames
- `WrapLayer` / `WrapTarget` quando visíveis
- cores, materiais, tamanhos e transformações
- referências únicas de assets

O script **não** coleta cookies Roblox, `.ROBLOSECURITY`, senhas ou tokens de login.

## Rotas

### Enviar

`POST /api/avatar-dump`

Limite: 4 MB por JSON.

### Ler último dump

`GET /api/avatar-dump/765329164/latest`

### Estado

`GET /api/avatar-dump/765329164/status`

## Persistência

O gateway salva:

```text
DOWNLOAD_DIR/
└── avatar-dumps/
    └── 765329164/
        ├── <timestamp>_<hash>.json
        └── latest.json
```

Quando `DOWNLOAD_DIR` está em disco persistente do Render, os dumps permanecem após restart/deploy.

## Espelhamento opcional para GitHub

Configure no Render:

- `AVATAR_DUMP_GITHUB_TOKEN`: fine-grained PAT com **Contents: Read and write** somente para este repositório.
- `AVATAR_DUMP_GITHUB_REPO=medeirospablo190-alt/Cafe-na-IA`
- `AVATAR_DUMP_GITHUB_BRANCH=main`
- `AVATAR_DUMP_GITHUB_PATH=avatar-dumps`

O token nunca deve ser colocado no script Lua.

Com o token configurado, cada coleta também grava:

```text
avatar-dumps/765329164/<timestamp>_<hash>.json
avatar-dumps/765329164/latest.json
```

## Chave opcional de upload

Se quiser bloquear uploads de terceiros, configure `AVATAR_DUMP_KEY` somente no Render e antes da execução defina no executor:

```lua
getgenv().GRUPO_LUA_AVATAR_KEY = "SUA_CHAVE"
```

Depois carregue `AvatarDumpExecutor.lua` normalmente.

## Análise pelo ChatGPT

Depois que o executor mostrar `Enviado com sucesso`, basta pedir:

> Analisa o último dump do Capuccino40.

O arquivo pode ser lido pelo endpoint `latest` e, quando o espelhamento estiver configurado, também diretamente no GitHub.
