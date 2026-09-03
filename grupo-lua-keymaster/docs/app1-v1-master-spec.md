# GRUPO LUA — APP 1 V1 — ESPECIFICAÇÃO MESTRA

Status: **APROVADO PARA IMPLEMENTAÇÃO**

Este documento consolida as decisões atuais do Aplicativo 1 e substitui requisitos antigos quando houver conflito. O objetivo é manter uma fonte de verdade única antes e durante a implementação.

## 1. Arquitetura geral

O projeto continua dividido em três blocos:

1. **App 1** — aplicativo usado por contas ADM e DEV para Social, Chats, Chaves, Arquivos e administração compatível com a role.
2. **Keymaster / App 2** — aplicativo reservado a DEV para criação e controle de contas, segurança, sessões, dispositivos, auditoria e operações críticas.
3. **Control API** — autoridade server-side para autenticação, permissões, estados, retenção, dispositivos, menus, chaves, logs e ações críticas.

Nenhum cliente é autoridade sobre permissões, role, bloqueio, expiração, vínculo de dispositivo, chave válida, retenção ou ação crítica.

## 2. Roles

### ADM

- entra somente no App 1;
- não entra no Keymaster;
- administra os próprios menus, chaves e conteúdo permitido;
- vê os próprios logs de menu/chaves;
- usa Social, Chats, Arquivos e Perfil conforme as permissões vigentes.

### DEV

- entra no App 1 e no Keymaster;
- cria e administra contas ADM;
- pode criar/remover DEV conforme as regras de autoridade do Keymaster;
- possui visão global de segurança, contas, dispositivos, menus e logs;
- recebe funções oficiais de Social, como identidade DEV e mensagem global;
- ações críticas são server-side e auditadas.

## 3. Credenciais e identidade

Autenticação e identidade social são separadas.

### Dados privados de autenticação

- login interno;
- hash da credencial;
- estado da conta;
- dispositivos;
- sessões;
- histórico de segurança.

Esses dados não aparecem no Social nem nas respostas normais do App 1.

### Identidade pública

- pseudônimo/publicName;
- avatar;
- bio;
- status/pensamento;
- moldura;
- role pública ADM/DEV;
- presença, quando permitida.

O App 1 não deve exibir login ou credencial após autenticação. A API normal do App 1 não deve devolver o login privado.

## 4. Primeiro acesso / onboarding obrigatório

Um login correto no primeiro acesso cria apenas uma **sessão provisória curta**, destinada ao onboarding. Essa sessão não libera Feed, Social, Chats, Chaves ou demais áreas normais.

Fluxo:

```text
LOGIN CORRETO
  -> dispositivo autorizado/vinculado
  -> sessão provisória
  -> aviso + termos
  -> aceite confirmado no servidor
  -> escolha do pseudônimo
  -> pseudônimo validado no servidor
  -> onboarding concluído
  -> sessão completa de 24 horas
  -> App 1 liberado
```

### 4.1 Aviso inicial

O aviso deve começar com destaque equivalente a **LEIA COM ATENÇÃO ANTES DE CONTINUAR** e explicar, sem detalhar a implementação interna:

- Social e mensagens normais são temporários por padrão e podem ser removidos após 24h;
- favoritos podem preservar conteúdo conforme as regras do recurso;
- notificações de Social e mensagens expiram em 24h;
- Chaves, menus, scripts, configurações e dados administrativos não usam a regra de 24h;
- conversas privadas de contas ativas não possuem leitura administrativa comum;
- em caso de denúncia/violação, a conta pode ser suspensa e o conteúdo necessário pode ser analisado conforme processo autorizado;
- não compartilhar aplicativo, login, chave, sessão ou acesso;
- três tentativas inválidas de login podem bloquear a conta;
- três tentativas válidas de credencial em dispositivo não autorizado podem bloquear a conta;
- para trocar/adicionar celular é necessário pedir autorização a um DEV antes de tentar entrar;
- usar apenas pseudônimos;
- não usar nome real, login ou chave como nome público;
- não publicar fotos pessoais ou informações reais que identifiquem o próprio usuário ou terceiros.

O botão Continuar começa desativado e só é liberado após marcar o aceite.

O servidor grava no mínimo:

- accountId;
- termsVersion;
- privacyVersion;
- acceptedAt.

Uma mudança relevante de versão pode exigir novo aceite.

### 4.2 Escolha do pseudônimo

Após o aceite, a tela mostra um campo **Escolha seu nome** e regras em texto pequeno.

Regras iniciais:

- 3 a 30 caracteres;
- apenas pseudônimo;
- não usar nome real;
- não usar login;
- não usar chave/credencial;
- não usar informações pessoais;
- rejeitar caracteres invisíveis/perigosos;
- bloquear nomes reservados e formatos que pareçam credenciais.

A validação final é do servidor. O servidor pode comparar com o login privado sem enviar o login ao App 1.

Resposta de erro deve ser genérica, sem revelar dados privados de autenticação.

## 5. Sessão de 24 horas

Depois de concluir o onboarding, o servidor emite/converte para uma sessão completa válida por **24 horas a partir da conclusão do onboarding ou do novo login completo**.

A sessão é fixa, não deslizante: abrir o app novamente não reinicia as 24h.

O cliente guarda somente o token de sessão em armazenamento seguro. Não guarda login nem credencial para conveniência.

A cada abertura, o App 1 revalida a sessão com o servidor.

A sessão perde validade imediatamente se:

- a conta for suspensa;
- a conta entrar em LOCKED_SECURITY;
- a conta for excluída;
- a credencial for rotacionada quando a política exigir;
- o dispositivo da sessão for revogado;
- a sessão for revogada por DEV;
- houver manutenção que impeça acesso.

## 6. Segurança de login do App 1

### 6.1 Três credenciais inválidas

Por conta, o servidor registra tentativas inválidas. Na terceira tentativa consecutiva aplicável:

```text
status -> LOCKED_SECURITY
sessões -> revogadas
novos logins -> negados
```

A liberação é feita por DEV no Keymaster e deve:

- voltar a conta para ACTIVE;
- zerar os contadores correspondentes;
- manter a credencial existente, salvo se o DEV escolher rotacioná-la;
- gerar auditoria.

### 6.2 Log de tentativas

O Keymaster deve mostrar o alvo da tentativa, resultado, horário, plataforma, identificadores protegidos do dispositivo/rede e fingerprint irreversível da credencial tentada.

Nunca registrar/exibir:

- credencial completa;
- senha completa;
- token de sessão;
- Android ID bruto;
- IP bruto em telas normais.

O fingerprint da credencial tentada permite reconhecer se tentativas reutilizaram a mesma entrada sem armazenar a entrada original.

### 6.3 Proteção contra limpeza de cache/troca de rede

O bloqueio é server-side. Troca de Wi-Fi, dados móveis, VPN, cache ou reinstalação não devem limpar o estado da conta.

## 7. Vínculo de dispositivos do App 1

### 7.1 Primeiro dispositivo

No primeiro login válido, a conta é vinculada ao primeiro dispositivo autorizado.

O desenho de produção deve combinar:

- identificador nativo protegido quando disponível;
- installationId como sinal auxiliar/fallback;
- fingerprint server-side com HMAC/pepper;
- chave criptográfica do dispositivo, preferencialmente hardware-backed quando a plataforma permitir;
- Play Integrity no Android / App Attest no iOS quando configurados;
- histórico server-side.

Não coletar IMEI, número de telefone ou MAC como requisito do produto.

### 7.2 Tentativa em outro dispositivo

Credencial válida + dispositivo não autorizado = acesso negado e contador de dispositivo não autorizado incrementado.

Na terceira tentativa aplicável:

```text
status -> LOCKED_SECURITY
sessões -> revogadas
```

Tentativa com credencial inválida não deve confirmar ao atacante se o dispositivo seria aceito nem se a credencial estava próxima/correta. Mensagens externas devem continuar genéricas.

### 7.3 Segundo/novo dispositivo

O próprio ADM não libera outro aparelho livremente.

Fluxo aprovado:

```text
DEV abre autorização de dispositivo
  -> janela máxima de 10 minutos
  -> conta tenta cadastro no novo aparelho
  -> servidor valida conta + autorização + dispositivo
  -> cadastro concluído
  -> autorização CONSUMED imediatamente
```

Estados da autorização:

- PENDING;
- CONSUMED;
- EXPIRED;
- CANCELLED.

O consumo deve ser atômico e de uso único. Assim que um dispositivo é cadastrado com sucesso, qualquer tempo restante deixa de valer.

O Keymaster deve permitir:

- ver dispositivos autorizados;
- autorizar novo dispositivo;
- cancelar janela pendente;
- revogar um dispositivo;
- liberar conta bloqueada;
- ver histórico de tentativas;
- revogar sessões;
- excluir definitivamente o acesso da conta.

## 8. Exclusão de conta/login ADM

A exclusão definitiva de acesso é uma ação crítica e auditada.

Ela deve inutilizar o acesso antigo e remover/anular material de autenticação necessário, incluindo:

- credencial de autenticação;
- sessões;
- dispositivos;
- autorizações pendentes;
- material criptográfico de acesso.

Quando for necessário manter uma linha técnica para integridade/auditoria, identificadores privados devem ser anonimizados/irreversivelmente substituídos em vez de deixar login e credencial utilizáveis.

Conteúdo operacional pertencente ao usuário (menus, posts, arquivos etc.) deve seguir política própria de transferência/exclusão para evitar apagar dados sem intenção.

## 9. Social

### 9.1 Feed

O Feed é mobile-first e mostra cards compactos.

Ações do post, na ordem visual desejada:

```text
Like | Comentários | Favorito
```

- Like: público, contador visível;
- Comentários: contador visível; conteúdo fechado por padrão;
- Favorito: público, contador visível e lista de perfis que favoritaram.

### 9.2 Comentários

Ao tocar em Comentários, o próprio card expande para baixo e carrega os comentários consecutivamente.

- comentários fechados por padrão;
- campo de escrever comentário na área expandida;
- respostas permitidas;
- somente um nível visual de indentação em mobile;
- respostas a respostas continuam no mesmo nível visual e podem usar @Nome;
- paginação/“ver mais” para evitar cards gigantes;
- texto e figurinha/imagem pequena podem coexistir.

### 9.3 Favoritos

Favoritos de posts são públicos.

No post:

- mostra quantidade de favoritos;
- tocar no contador abre quem favoritou;
- perfis da lista podem ser abertos.

No perfil:

```text
POSTS | FAVORITOS
```

A aba Favoritos mostra posts que aquele perfil marcou como favorito.

Enquanto um post possuir pelo menos um favorito, ele é preservado além da retenção normal de 24h. Quando o último favorito é removido e o post já passou da janela normal, ele volta a ser elegível para limpeza.

Conversas favoritas são tratadas separadamente e não expõem publicamente quem favoritou uma conversa privada.

### 9.4 Likes

- um like por conta/post;
- contador público;
- ação server-side idempotente;
- possibilidade futura de abrir lista de quem curtiu.

### 9.5 Post fixado por DEV

Regra atual substitui a versão antiga de múltiplos pins:

- somente DEV pode fixar;
- existe **um único post principal fixado por vez**;
- fixar outro substitui automaticamente o anterior;
- o anterior volta à posição normal do feed;
- estado é server-side;
- auditoria registra DEV, post, horário e post substituído;
- post fixado não expira enquanto permanecer fixado.

### 9.6 Identidade DEV

- tag DEV apenas para role DEV real;
- moldura/anel vermelho oficial automático;
- ADM não pode escolher identidade oficial DEV;
- tag DEV não pode ser ocultada pelo usuário;
- publicações/ações DEV podem usar acento visual vermelho sem transformar a interface inteira em vermelho.

### 9.7 Mensagem global DEV

DEV terá função de mensagem/anúncio global para usuários do App 1.

- permissão validada no servidor;
- pode gerar notificação;
- entidade separada de chat privado e post comum;
- auditada;
- acesso disponível na área DEV/perfil e/ou Configurações conforme UX final.

## 10. Notificações

Notificações de Social e notificações de mensagens ficam separadas.

### 10.1 Central Social

Categorias:

```text
TODAS | CURTIDAS | COMENTÁRIOS | FAVORITOS
```

Mensagens privadas não entram nessa central.

Cada categoria pode ter contador de não lidas.

### 10.2 Mensagens

Chats/mensagens possuem ícone/contador separado da campainha do Social.

### 10.3 Retenção

Notificações são avisos temporários e expiram após 24h.

A expiração da notificação não apaga o conteúdo preservado relacionado.

Um post antigo preservado pode gerar uma nova notificação se receber atividade nova; a nova notificação recebe sua própria janela de 24h.

## 11. Retenção de conteúdo

Regra central:

- posts normais do Social: 24h, salvo preservação;
- conversas/mensagens normais: 24h, salvo preservação aplicável;
- notificações: 24h;
- favoritos/pins podem preservar o conteúdo-alvo conforme regra;
- chaves, menus, scripts, arquivos, configurações, perfil, stickers e auditoria não são apagados automaticamente pela regra Social de 24h.

O servidor controla createdAt/expiresAt; o relógio do celular não decide retenção.

## 12. Pesquisa do Feed / perfis

A busca do Social pesquisa **somente perfis por identidade pública**.

Não retornar posts, chats, chaves, arquivos nem dados de autenticação.

Campos permitidos na resposta pública devem ser limitados a informações de perfil, como:

- publicProfileId;
- publicName;
- avatar;
- role pública;
- status/presença permitida.

Proteções:

- sessão App 1 válida;
- conta ACTIVE;
- consulta parametrizada;
- normalização Unicode;
- limites de tamanho;
- mínimo de caracteres;
- debounce no cliente;
- rate limit server-side;
- paginação e limite de resultados;
- detecção/limitação de enumeração automatizada.

Login, credencial, hashes internos, IP e IDs de dispositivo não entram na resposta.

## 13. Perfil e personalização

Perfil público prevê:

- avatar;
- pseudônimo;
- bio;
- pensamento/status curto;
- presença;
- moldura;
- tabs Posts/Favoritos.

Personalização prevista:

- cerca de 20 molduras/estilos;
- visual escuro/premium;
- identidade DEV oficial separada das escolhas cosméticas.

Dados de autenticação, role real, estado de segurança e credencial não são editáveis livremente pelo perfil.

## 14. Figurinhas

Comentários/respostas podem usar:

- texto;
- stickerImageId;
- ambos.

Biblioteca por conta:

- Recentes;
- Minhas Figurinhas;
- Adicionar nova;
- Remover figurinha salva.

Arquivos/IDs são server-side; não entram na limpeza automática de 24h só por serem figurinhas.

## 15. Menus e chaves

### 15.1 Propriedade

Cada menu deve ter ownerAccountId.

ADM:

- vê/gerencia apenas os próprios menus e chaves;
- enforcement é server-side.

DEV:

- possui visão global por Administrador -> Menu -> Chaves;
- ações em recursos de outro ADM são auditadas com actor e owner separados.

### 15.2 Até dois destinos por produto

Cada configuração pública pode ter:

- MENU_1 obrigatório/principal;
- MENU_2 opcional.

Máximo de dois destinos, também validado no servidor.

A interface mostra `+` para adicionar MENU_2 somente enquanto ele não existir.

### 15.3 Tipo da chave separado do destino

Não codificar FREE=MENU_1 e VIP=MENU_2.

Modelo:

```text
kind = FREE | VIP
targetSlot = MENU_1 | MENU_2
```

Assim FREE e VIP podem apontar para qualquer slot permitido pela configuração.

### 15.4 Um Access Gate / um initializer

Um único initializer público por produto deve abrir o Access Gate oficial GRUPO LUA.

O initializer conhece apenas o identificador público necessário. Não contém lista de chaves válidas nem as duas URLs de origem.

Fluxo:

```text
initializer
 -> Access Gate
 -> usuário informa chave
 -> servidor valida menu + chave + estado + expiração + uso + dispositivo
 -> servidor determina targetSlot
 -> cria sessão temporária
 -> libera somente o destino autorizado
```

O cliente não é autoridade sobre a chave.

### 15.5 Visual Access Gate aprovado

Base visual: **GRUPO LUA Access Gate V3.1**.

- painel retangular/horizontal compacto;
- mobile/landscape;
- preto/escuro;
- botão principal branco;
- acentos vermelhos sutis;
- overlay escuro;
- lua crescente vermelha;
- um campo para FREE ou VIP;
- texto “Validação protegida pelo servidor”.

Códigos DEMO são somente demonstração e nunca produção.

## 16. Vínculo de dispositivo das chaves FREE/VIP

Cada chave começa não vinculada.

No primeiro uso válido:

```text
key -> boundDevice
```

Depois:

- chave válida + dispositivo vinculado = pode prosseguir;
- chave válida + dispositivo diferente = negado;
- tentativa entra no log do menu/chave.

No ambiente Roblox/executor, o vínculo não possui a mesma força de um app nativo. O servidor deve usar os sinais disponíveis sem prometer identificação de hardware impossível de falsificar.

Sinais podem incluir, conforme disponível:

- identificador de instalação do Access Gate;
- identificador de dispositivo fornecido pelo ambiente;
- sessão server-side;
- Roblox UserId opcional;
- histórico do vínculo.

É recomendável oferecer modo opcional `dispositivo + conta Roblox` para cenários que exigirem vínculo mais forte.

## 17. Log por menu e por chave

Cada menu possui log próprio.

Estrutura:

```text
ADM -> MENU -> CHAVE -> EVENTOS
```

O log do menu pode filtrar:

- Todos;
- Acessos;
- Bloqueados;
- Vínculos.

Eventos mínimos:

- chave criada;
- primeiro uso;
- dispositivo vinculado;
- validação bem-sucedida;
- tentativa em dispositivo diferente;
- chave inválida;
- chave expirada;
- chave suspensa/revogação;
- dispositivo desvinculado/revinculado;
- sessão criada/revogada;
- alteração de targetSlot;
- possível compartilhamento detectado.

A tela de uma chave exibe um filtro do log daquele menu para a chave específica.

Logs exibem somente versões mascaradas/protegidas de chave, dispositivo e rede.

## 18. Visualização protegida de chaves completas

A administração comum mostra apenas hints mascarados.

Para ver chaves completas:

```text
ADM abre área protegida
 -> servidor confirma sessão
 -> conta ACTIVE
 -> ownership do menu
 -> dispositivo autorizado
 -> autorização curta e escopada
 -> aba protegida recebe a chave temporariamente
```

A autorização deve ser curta, específica para usuário + menu + ação `REVEAL_MENU_KEYS`, de uso controlado.

A chave completa não deve ser persistida no armazenamento local, cache, logs ou analytics.

Se for necessário revelar novamente uma chave já criada, o backend precisará manter separadamente:

- `key_hash` para autenticação;
- `key_encrypted` para revelação autorizada.

A chave de criptografia fica somente no ambiente seguro do servidor, nunca no GitHub.

A área deve se fechar/mascarar ao expirar, trocar de tela ou quando o app for para segundo plano.

## 19. Privacidade administrativa de chats

A promessa ao usuário só pode ser feita se a arquitetura cumprir:

- conta ACTIVE: não há endpoint administrativo comum para ler chats privados;
- denúncia grave pode levar a SUSPENDED;
- somente após a suspensão um fluxo administrativo autorizado pode liberar o conteúdo necessário para análise;
- acesso de análise deve ser limitado, explícito e auditado;
- suspensão não deve automaticamente despejar todo o conteúdo ao DEV.

## 20. Distribuição do aplicativo

Para Android, o caminho mais simples de instalação direta será uma build APK assinada.

Plano:

- Expo/EAS Build;
- perfil `internal`/APK para instalação direta;
- URL compartilhável de build ou Release/página oficial;
- build assinada;
- SHA-256 publicado para conferência;
- CI pode automatizar build quando a versão for aprovada.

Para Google Play, usar AAB de produção separadamente.

Atualizações JS compatíveis podem usar EAS Update quando apropriado; mudanças nativas exigem nova build/runtime compatível.

## 21. Segurança de produção

Regras obrigatórias:

- nenhum segredo real em GitHub;
- `SESSION_PEPPER`, `DEVICE_FINGERPRINT_PEPPER`, chave de criptografia de credenciais/chaves e tokens de provedores somente em secrets/env do servidor;
- credenciais são hash forte para autenticação;
- comparações sensíveis usam funções apropriadas/timing-safe quando aplicável;
- endpoints críticos exigem reautenticação/step-up;
- rate limiting de produção deve usar armazenamento compartilhado quando houver múltiplas instâncias;
- auditoria não guarda segredos;
- respostas públicas evitam enumeração e vazamento de estado;
- App Integrity em `enforce` somente depois de verificador server-side real configurado e testado;
- backups, migrações e chaves de criptografia precisam de estratégia de recuperação independente.

## 22. Ordem de implementação recomendada

### Fase 1 — segurança e identidade

1. schema de conta/dispositivo/tentativas/onboarding;
2. login App 1 com bloqueio 3 tentativas;
3. vínculo do primeiro dispositivo;
4. autorização de segundo dispositivo por 10 minutos, consumo atômico;
5. sessões de 24h;
6. aceite dos termos;
7. pseudônimo server-side;
8. Keymaster: segurança da conta, logs, desbloqueio e dispositivos;
9. remover login das respostas normais do App 1.

### Fase 2 — propriedade de menus/chaves

1. ownerAccountId;
2. MENU_1/MENU_2;
3. kind/targetSlot separados;
4. chaves vinculadas a dispositivo;
5. logs por menu/chave;
6. revelação protegida com criptografia server-side;
7. Access Gate server-authoritative.

### Fase 3 — Social

1. perfil público/pseudônimo;
2. busca de perfis protegida;
3. Feed;
4. likes;
5. comentários/respostas;
6. favoritos públicos + preservação;
7. pin único DEV;
8. notificações Social;
9. mensagem global DEV;
10. stickers.

### Fase 4 — Chats

1. conversas privadas;
2. retenção 24h;
3. favoritos/preservação;
4. notificações separadas;
5. fluxo de denúncia/suspensão/análise auditada.

### Fase 5 — Arquivos e acabamento

1. Arquivos;
2. personalização completa;
3. otimização mobile;
4. acessibilidade;
5. testes E2E;
6. observabilidade;
7. build APK assinada e distribuição;
8. preparação iOS/lojas se desejado.

## 23. Situação do código atual antes desta especificação

No baseline V0.8 existente:

- Keymaster já possui login próprio com limite de tentativas por dispositivo;
- App 1 ainda é uma sonda mínima (`app1-probe`), não o produto final;
- login App 1 atual ainda precisa ser migrado para as regras deste documento;
- sessão App 1 atual ainda precisa passar para 24h e onboarding;
- o endpoint atual do App 1 ainda retorna login e precisa ser corrigido;
- menus atuais possuem um único `source_url` e ainda precisam migrar para ownership + dois slots;
- chaves atuais usam hash/hint e ainda precisam receber vínculo de dispositivo, targetSlot, logs e revelação criptografada quando a política exigir;
- Social completo ainda não existe.

Este documento autoriza o início da implementação completa em fases, priorizando segurança e compatibilidade antes da interface final.
