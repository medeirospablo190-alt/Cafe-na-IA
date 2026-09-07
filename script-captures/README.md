# Script captures

Área reservada para o fluxo de captura MNX.

A versão atual do menu reutiliza o pipeline já validado de `POST /api/inventory-trace`, porque esse endpoint já salva no Render e confirma o espelhamento no GitHub.

As capturas aparecem em:

- `inventory-traces/<PlaceId>/...json`
- `inventory-traces/<PlaceId>/latest.json`

Cada envio usa um `runId` iniciado por um destes estágios:

- `MNX_CAPTURE_ORIGINAL_...`
- `MNX_CAPTURE_PATCHED_...`
- `MNX_CAPTURE_DEOBFUSCATED_...`

Dentro de `trace.records`, o código completo é dividido em registros `script_source_chunk` com `index`, `total`, `stage` e `data`. A ordem dos chunks recompõe o script exatamente.

O menu só considera o envio concluído quando a resposta do Render contém `github.mirrored = true`.
