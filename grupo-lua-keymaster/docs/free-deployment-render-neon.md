# GRUPO LUA — implantação gratuita (Render Free + Neon Free)

## Objetivo

Manter a Control API separada do portal `cafe-na-ia.onrender.com` sem custo mensal durante a fase inicial do projeto.

Arquitetura:

```text
App 1 / Keymaster
        |
        v
Render Free — grupo-lua-control-api
        |
        v
Neon Free — PostgreSQL persistente
```

O portal público de downloads continua sendo outro serviço e nunca deve ser usado como `PUBLIC_BASE_URL` da Control API.

## 1. Criar o banco no Neon

1. Entre no Neon e crie um projeto PostgreSQL exclusivo para o GRUPO LUA.
2. Use a branch principal de produção.
3. Mantenha scale-to-zero habilitado enquanto o projeto estiver no plano gratuito.
4. Copie a connection string PostgreSQL fornecida pelo Neon. Prefira a connection string com pooler quando ela estiver disponível para o projeto.
5. Não coloque essa URL em GitHub, arquivo `.env` versionado, mensagem pública ou código do aplicativo.

A connection string entra somente como segredo `DATABASE_URL` no serviço da Control API.

## 2. Criar/sincronizar a Control API no Render

Use o Blueprint `render-control-api.yaml` do repositório.

O serviço deve ficar com:

- tipo: Web Service;
- plano: Free;
- root directory: `grupo-lua-keymaster/services/control-api`;
- health check: `/v1/health`;
- start command: `npm run start:free`;
- auto deploy desativado durante a fase de configuração.

## 3. Variáveis privadas do Render

Configure no painel do serviço:

- `DATABASE_URL` = connection string privada do Neon;
- `KEYMASTER_ACCESS_HASH` = verificador scrypt da Keymaster Access Key;
- `SESSION_PEPPER` = segredo aleatório >= 32 caracteres;
- `DEVICE_FINGERPRINT_PEPPER` = segredo aleatório >= 32 caracteres.

O Blueprint pode gerar os peppers automaticamente. Nunca copie os valores de volta para o GitHub.

Configuração inicial segura:

- `DATABASE_SSL=true`;
- `APP_INTEGRITY_MODE=report`;
- `CRITICAL_ACTIONS_ENABLED=false`;
- `APP1_TERMS_VERSION=1.0`;
- `APP1_PRIVACY_VERSION=1.0`.

`APP_INTEGRITY_MODE=enforce` só deve ser ativado depois que o verificador real de Play Integrity/App Attest estiver configurado e testado.

## 4. Migrations no plano gratuito

Render Free não depende de `preDeployCommand`.

O comando `npm run start:free` executa:

```text
production:check
      ↓
migrate
      ↓
server.js
```

O migrador usa:

- tabela `schema_migrations`;
- checksum SHA-256 por arquivo;
- advisory lock PostgreSQL;
- transação por migration.

Assim um restart/cold start não reaplica migrations já registradas. Se uma migration aplicada for alterada depois, o startup falha em vez de modificar silenciosamente o banco.

Por segurança, um banco antigo que já possua tabelas do GRUPO LUA mas não tenha `schema_migrations` é recusado e precisa de baseline assistido.

## 5. Verificação depois do deploy

Abra:

```text
https://<URL-DA-CONTROL-API>/v1/health
```

A resposta deve ter `ok: true` e `service: GRUPO_LUA_CONTROL_API`.

Somente depois disso configure no ambiente EAS `production` dos dois aplicativos:

```text
EXPO_PUBLIC_GRUPO_LUA_API_URL=https://<URL-DA-CONTROL-API>
```

Nunca use:

```text
https://cafe-na-ia.onrender.com
```

como Control API.

## 6. Builds

Depois do health check real:

1. gerar APK interno do App 1;
2. instalar e testar login/onboarding/sessão de 24h;
3. gerar APK interno do Keymaster;
4. testar contas, bloqueios e autorização de dispositivo;
5. só depois gerar builds finais de distribuição.

## Limitações esperadas no plano gratuito

O Render Free pode dormir após um período sem tráfego. A primeira requisição depois disso pode demorar enquanto a instância acorda.

O Neon Free também usa scale-to-zero. Isso é aceitável para desenvolvimento, testes e fase inicial com poucos usuários, mas não deve ser interpretado como SLA de produção.

Quando o uso crescer, a arquitetura permanece igual: basta subir o plano da API/banco sem redesenhar o App 1 ou Keymaster.
