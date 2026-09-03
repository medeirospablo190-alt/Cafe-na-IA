# GRUPO LUA — topologia de implantação

## Regra principal

O portal público de downloads e a Control API dos aplicativos são serviços diferentes e não devem compartilhar a mesma função pública.

```text
cafe-na-ia.onrender.com
└── Portal oficial de downloads
    ├── App 1 Android/iOS
    └── Keymaster Android/iOS

CONTROL_API_URL HTTPS dedicada
└── grupo-lua-keymaster/services/control-api
    ├── autenticação Keymaster
    ├── autenticação App 1
    ├── PostgreSQL privado
    ├── dispositivos
    ├── onboarding
    ├── menus/chaves
    └── auditoria
```

A Control API precisa ser publicamente alcançável por HTTPS pelos aplicativos móveis, porém usa serviço, banco, secrets e domínio separados do portal de downloads.

## Motivo

O portal recebe somente senhas de download e emite autorizações temporárias para artefatos. Ele não deve receber login, credencial ADM/DEV, KEYMASTER ACCESS KEY, tokens do App 1 nem dados administrativos.

Por isso as builds móveis devem receber `EXPO_PUBLIC_GRUPO_LUA_API_URL` apontando para a Control API dedicada. Enquanto essa URL não for configurada/verificada, o App 1 permanece bloqueado e o Keymaster usa `https://control-api.invalid`, domínio reservado e não resolvível, para evitar envio acidental de segredos ao portal.

## Render

O Blueprint de produção está em `render-control-api.yaml` e o passo a passo completo em `docs/control-api-render.md`.

O banco do Blueprint não aceita conexões públicas e é acessado pela Control API através da rede privada do Render. A URL pública da API é derivada pelo próprio Render e não é hardcoded no repositório.

## Ordem segura de produção

1. Implantar a Control API como serviço separado.
2. Conectar PostgreSQL privado e aplicar migrations.
3. Configurar secrets privados do servidor.
4. Verificar `/v1/health` da Control API.
5. Configurar `EXPO_PUBLIC_GRUPO_LUA_API_URL` nas builds App 1 e Keymaster.
6. Gerar builds assinadas.
7. Testar login/dispositivo/onboarding em ambiente de produção.
8. Colocar APK/IPA no armazenamento privado do portal.
9. Configurar os quatro verificadores de senha de download.
10. Liberar os downloads no portal.

## Nunca colocar no GitHub

- KEYMASTER ACCESS KEY;
- credenciais ADM/DEV reais;
- peppers de sessão/dispositivo;
- `DATABASE_URL` de produção;
- tokens do provedor;
- verificadores/segredos de integridade privados;
- senhas reais de download;
- chaves privadas de assinatura dos aplicativos.
