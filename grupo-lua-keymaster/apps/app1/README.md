# GRUPO LUA — App 1 Mobile

Primeira implementação real do Aplicativo 1, separada da antiga sonda `app1-probe`.

## Fluxo implementado

```text
login privado
→ validação server-side
→ vínculo/prova do dispositivo
→ sessão provisória
→ aviso obrigatório + aceite
→ pseudônimo validado pelo servidor
→ onboarding concluído
→ sessão FULL fixa de 24 horas
→ shell do App 1 liberado
```

## Privacidade da autenticação

Depois do login bem-sucedido, o componente limpa `login` e `credential` da interface. O aplicativo persiste somente:

- token da sessão;
- token/prova do dispositivo.

Ambos usam SecureStore/Keychain/Keystore. O pseudônimo público é usado nas telas normais; o login privado não é exibido no shell do aplicativo.

## Telas desta fase

- login;
- aviso/termos completos;
- escolha de pseudônimo com regras pequenas abaixo do campo;
- tela inicial liberada;
- navegação-base `Início | Arquivos | Social | Chaves | Chats`.

Social, Chaves, Chats e Arquivos ainda são shells reservados para as próximas fases.

## Configuração obrigatória do servidor

A build precisa receber:

```text
EXPO_PUBLIC_GRUPO_LUA_API_URL=https://<control-api-verificada>
```

O endereço do portal público de downloads não deve ser usado como Control API.

## Build Android para instalação direta

Com EAS configurado e credenciais de assinatura corretas:

```bash
eas build --platform android --profile production-apk
```

O perfil gera APK para distribuição privada pelo portal do GRUPO LUA. Para Google Play, use `production-store`.
