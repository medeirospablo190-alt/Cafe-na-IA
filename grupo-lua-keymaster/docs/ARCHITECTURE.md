# GRUPO LUA — arquitetura do Keymaster V0.2

## Papéis

O Aplicativo 1 possui somente:

- `ADM`
- `DEV`

Não existe `GENERAL` / Administrador Geral.

## Princípio de autoridade

> O aplicativo pede; o servidor decide.

Role, status, tentativas, bloqueio, validade de sessão, suspensão, exclusão e autorização crítica são decisões server-side.

## Entrada no Keymaster

A `KEYMASTER ACCESS KEY` possui 5.000 caracteres por padrão e a interface aceita até 16.384 caracteres.

A chave original:

- não é embutida no APK/IPA;
- não é salva em AsyncStorage;
- não é persistida em SecureStore;
- é enviada via HTTPS;
- é limpa do estado React após a tentativa;
- no servidor é validada contra hash `scrypt`.

Após autenticação, somente um token de sessão revogável é salvo em SecureStore. Se a biometria desbloquear uma sessão armazenada, o app confirma essa sessão novamente com `/v1/keymaster/session` antes de liberar o painel.

## Bloqueio de login

Aplicado exclusivamente pelo servidor:

- erro 1: resta 2;
- erro 2: resta 1;
- erro 3: dispositivo entra em bloqueio de 24 horas;
- não há rota para antecipar esse desbloqueio;
- relógio do telefone, rede ou alterações de interface não mudam `locked_until`.

A identidade usa HMAC de identificadores do dispositivo e deve ser reforçada em produção com Play Integrity / App Attest em modo `enforce`.

## Contas do App 1

- `ADM`: credencial total de 256 caracteres;
- `DEV`: credencial total de 600 caracteres, com prefixo `DEV-` apenas como formato;
- role é sempre lida do banco, nunca inferida do prefixo;
- servidor guarda apenas hash;
- credencial nova aparece uma única vez;
- suspensão/rotação revogam sessões abertas.

## Step-up para ações críticas

A sessão Keymaster não basta para ações críticas. O fluxo é:

```text
Keymaster session válida
        ↓
DEV login + DEV key
        ↓
servidor valida DEV ACTIVE
        ↓
autorização aleatória de uso único (2 min)
        ↓
execução da ação exata
        ↓
token marcado como usado + auditoria
```

A autorização é escopada. Para exclusão individual, o escopo inclui o `accountId`, impedindo usar autorização de uma conta para apagar outra.

## Manutenção do App 1

O estado `app1_maintenance` fica em `system_settings` no PostgreSQL. Quando ativo:

- `/v1/app1/login` retorna manutenção;
- `/v1/app1/me` retorna manutenção;
- mudar o cliente não remove a condição.

## Reinício

A API pode chamar um webhook privado configurado exclusivamente no servidor. O app nunca recebe o token do provedor.

## Exclusões globais

A infraestrutura de autorização crítica já existe, mas exclusão global de dados/chaves e recuperação crítica permanecem desabilitadas até o esquema definitivo do App 1 completo existir. O motivo é garantir escopo, auditoria e política de retenção corretos antes de introduzir uma operação destrutiva global.
