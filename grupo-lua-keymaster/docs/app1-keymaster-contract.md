# GRUPO LUA — CONTRATO APP 1 ↔ KEYMASTER

Status: **IMPLEMENTAÇÃO COMPLETA AUTORIZADA / FASE 1 EM PREPARAÇÃO**

A especificação consolidada atual está em `docs/app1-v1-master-spec.md`. Este arquivo mantém somente o contrato entre App 1, Keymaster e Control API.

## Autoridade

A Control API é a autoridade para:

- autenticação;
- role e permissões;
- status da conta;
- bloqueios de segurança;
- dispositivos autorizados;
- sessões;
- onboarding;
- retenção;
- ownership de menus/chaves;
- ações críticas.

O cliente pode esconder/mostrar controles por UX, mas nunca concede permissão sozinho.

## Roles

### ADM

- usa App 1;
- não recebe acesso ao Keymaster;
- administra recursos próprios conforme ownership server-side.

### DEV

- usa App 1 e Keymaster;
- possui funções privilegiadas aprovadas;
- ações críticas são reautenticadas e auditadas.

## Credenciais

Convenções atuais de emissão:

```text
ADM -> 256 caracteres
DEV -> 600 caracteres
```

O servidor gera a credencial e mantém hash para autenticação. Segredos reais não entram no repositório.

O App 1 deve enviar login + credencial apenas durante autenticação e descartá-los da memória da interface depois do login. O App 1 não deve persistir login ou credencial para conveniência.

## Primeiro acesso

Um primeiro login válido não libera diretamente o aplicativo final.

Fluxo obrigatório:

```text
login válido
 -> sessão provisória curta
 -> aceite dos termos no servidor
 -> pseudônimo validado no servidor
 -> onboarding concluído
 -> sessão completa de 24h
```

Enquanto `onboardingCompleted = false`, endpoints normais de Feed, Social, Chats, Chaves e outras áreas devem permanecer indisponíveis.

## Sessão App 1

A sessão completa planejada é fixa por **24 horas** a partir da conclusão do onboarding ou de um novo login completo.

A reabertura do aplicativo não reinicia o prazo.

O cliente persiste somente o token em armazenamento seguro e revalida com o servidor.

Sessões são revogadas quando aplicável em casos como:

- suspensão;
- `LOCKED_SECURITY`;
- exclusão;
- rotação de credencial;
- revogação de dispositivo;
- revogação administrativa;
- manutenção que bloqueie acesso.

## Dispositivos

A conta é vinculada a dispositivo autorizado.

- primeiro dispositivo: vinculado no primeiro login válido;
- dispositivo diferente: acesso negado, salvo autorização válida;
- terceiro evento aplicável de credencial válida em dispositivo não autorizado: conta entra em `LOCKED_SECURITY` e sessões são revogadas;
- segundo/novo dispositivo: exige janela server-side criada por DEV, válida por no máximo 10 minutos;
- ao cadastrar com sucesso, a janela é consumida imediatamente e não pode ser reutilizada.

A implementação de produção deve usar fingerprint protegido, identificadores nativos disponíveis, chave criptográfica do dispositivo e App Integrity/attestation quando configurados.

## Bloqueio de credencial

Três tentativas inválidas consecutivas aplicáveis podem colocar a conta em `LOCKED_SECURITY`.

A liberação é feita por DEV e deve ser auditada. A liberação pode manter a credencial existente; rotação é uma ação separada.

## Privacidade da API do App 1

Respostas normais do App 1 não devem retornar:

- login privado;
- credencial;
- hash da credencial;
- IP bruto;
- identificador nativo bruto do dispositivo;
- tokens de outras sessões.

O Social trabalha com `publicName`/identidade pública, não com login.

## Keymaster — segurança da conta

O Keymaster deve disponibilizar, por conta:

- status;
- motivo de bloqueio;
- contadores de tentativas;
- histórico protegido de login;
- dispositivos autorizados;
- janela pendente de novo dispositivo;
- sessões;
- desbloqueio;
- revogação de dispositivo;
- autorização de novo dispositivo;
- revogação de sessões;
- exclusão crítica do acesso.

Logs nunca guardam credenciais completas.

## Permissões compartilhadas

Permissões existentes continuam como contrato mínimo:

```text
app1.session.use
app1.admin
app1.dev.privileged
app1.social.pin-post
```

Novas permissões devem ser adicionadas conforme as fases forem implementadas, sempre com enforcement server-side.

## App 1 Probe

`apps/app1-probe` continua temporariamente como sonda de compatibilidade. Ele será migrado/substituído progressivamente pelo App 1 real durante a implementação das fases definidas em `app1-v1-master-spec.md`.
