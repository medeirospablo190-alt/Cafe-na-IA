# GRUPO LUA — builds móveis de produção

## Regra

App 1 e Keymaster só podem ser compilados para distribuição quando `EXPO_PUBLIC_GRUPO_LUA_API_URL` apontar para a **Control API HTTPS dedicada**.

O endereço abaixo é exclusivamente o portal de downloads e é proibido como backend móvel:

`https://cafe-na-ia.onrender.com`

## EAS Environment

Os perfis de build usam ambientes explícitos do EAS:

- `preview` → ambiente EAS `preview`;
- `production-apk` → ambiente EAS `production`;
- `production-ios-internal` → ambiente EAS `production`;
- `production-store` → ambiente EAS `production`.

Depois que a Control API estiver implantada e `/v1/health` tiver sido verificado, configure a URL pública real no EAS como variável **plaintext**, porque ela é um endereço público e será embutida no aplicativo:

```bash
eas env:set \
  --name EXPO_PUBLIC_GRUPO_LUA_API_URL \
  --value https://SUA-CONTROL-API-REAL \
  --environment production \
  --visibility plaintext
```

Para preview, configure o mesmo nome no ambiente `preview` apontando para uma Control API de teste válida, ou deliberadamente para a produção enquanto não houver staging:

```bash
eas env:set \
  --name EXPO_PUBLIC_GRUPO_LUA_API_URL \
  --value https://SUA-CONTROL-API-VALIDA \
  --environment preview \
  --visibility plaintext
```

`EXPO_PUBLIC_*` nunca deve conter chaves, senhas, tokens ou outros segredos. Essas variáveis são incluídas no código cliente durante a build.

## Guarda automática

Os dois aplicativos registram o hook oficial `eas-build-pre-install`.

Antes de o EAS instalar dependências, o hook executa:

```bash
node ../../scripts/check-mobile-api-url.mjs
```

A build falha antes de compilar se a URL:

- estiver ausente;
- não usar HTTPS;
- apontar para `cafe-na-ia.onrender.com`;
- usar localhost, loopback ou `.invalid`;
- contiver usuário/senha na própria URL;
- incluir caminho, query string ou fragmento.

Além da guarda de build, App 1 e Keymaster também sanitizam a URL em runtime. O App 1 bloqueia o acesso quando a configuração é inválida; o Keymaster substitui qualquer destino inseguro por `control-api.invalid`, evitando enviar a chave administrativa ao endereço errado.

## Android

### APK interno

Dentro do diretório do aplicativo:

```bash
eas build --platform android --profile production-apk
```

Esse perfil gera APK para instalação direta/testes internos.

### Google Play

```bash
eas build --platform android --profile production-store
```

O perfil usa Android App Bundle (`.aab`).

## iOS

### Distribuição interna / Ad Hoc

```bash
eas build --platform ios --profile production-ios-internal
```

A instalação depende do método de distribuição/assinatura da Apple e dos dispositivos autorizados quando for Ad Hoc.

### App Store / TestFlight

```bash
eas build --platform ios --profile production-store
```

A entrega e instalação final seguem as regras de assinatura e distribuição da Apple.

## Antes de qualquer build final

1. Control API implantada em URL HTTPS própria.
2. `/v1/health` retornando HTTP 200.
3. Banco persistente conectado e migrations aplicadas.
4. `KEYMASTER_ACCESS_HASH` de produção configurado no servidor — nunca a chave original no app.
5. `EXPO_PUBLIC_GRUPO_LUA_API_URL` configurada no EAS `production`.
6. `eas env:list --environment production` conferido.
7. App Integrity revisado; para liberação final, preferir `enforce` somente após o verificador server-side real estar funcionando.
8. Build feita com o perfil correto.
9. APK/AAB/IPA/TestFlight testado em aparelho real.
10. Só depois o artefato/link deve ser colocado no portal de downloads.

## Segredos

Nunca colocar em `eas.json`, `app.json`, código TypeScript, GitHub ou variável `EXPO_PUBLIC_*`:

- chave Keymaster original;
- credenciais ADM/DEV;
- peppers;
- `DATABASE_URL`;
- tokens de integridade;
- chaves privadas de assinatura;
- senhas do portal de downloads.
