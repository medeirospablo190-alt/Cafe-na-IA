# CAFEÍNA Executor Trace V1

Coletor separado do Universal Game Trace. Ele usa apenas a infraestrutura já validada de transporte/ACK do gateway CAFEÍNA V3 e não altera o coletor original.

## Objetivo

Mapear passivamente o que o ambiente Luau consegue enxergar do executor depois que o usuário entrou normalmente:

- estrutura da UI exposta em `gethui`, `CoreGui` e candidatos em `PlayerGui`;
- propriedades visuais/layout de abas, botões, labels, imagens e contêineres;
- mudanças de UI por 24 segundos, úteis para minimizar/restaurar e trocar abas;
- presença de APIs/capacidades comuns do executor e identidade exposta por `identifyexecutor`/`getexecutorname`.

## Privacidade e limites

- Conteúdo de todo `TextBox` é redigido; chave e texto do editor não são enviados.
- Não chama `decompile`, `getgc`, debug introspection, clipboard, readfile/listfiles ou dumps de callbacks.
- Não tenta ler código Java/Kotlin/C++ do APK.
- Se o menu for overlay Android nativo e não aparecer na árvore Luau, o manifesto registra `nativeOverlayPossiblyInvisible`.

## Upload

Usa:

- `GET https://cafe-na-ia.onrender.com/api/inventory-trace-v3/health`
- `POST https://cafe-na-ia.onrender.com/api/inventory-trace-v3/batch`

Um lote só é aceito localmente quando a resposta confirma `github.mirrored=true`. Retry reutiliza exatamente o mesmo corpo JSON.

Os dados ficam no mesmo espelho funcional do CAFEÍNA, sob:

`inventory-traces-v3/<gameId>/<placeId>/<runId>/`

## Uso

Entre normalmente no APK com uma chave válida e deixe o menu/executor aberto. Execute o loader. Durante a janela de 24 segundos, passe pelas abas e minimize/restaure uma vez para expor estados criados sob demanda. Ao terminar, aguarde a mensagem `UPLOAD CONFIRMADO NO GITHUB ✓`.
