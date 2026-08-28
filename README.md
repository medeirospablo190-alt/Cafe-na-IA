# CAFEÍNA — Site V2

Site mobile-first com apenas duas áreas:

1. **Diagnóstico de script** — lê `.lua`, `.luau` ou `.txt`, envia o código ao backend e disponibiliza o diagnóstico para download como `NomeDoScript_diagnostico.txt`.
2. **Arquivos do scanner** — recebe o protocolo de upload em chunks do `Samme.lua V3`, lista, visualiza parcialmente e permite baixar o scan completo.

## Estrutura

- `server.js` — backend Express, API de diagnóstico e protocolo `/upload/*`.
- `public/index.html` — interface.
- `public/styles.css` — visual preto/branco otimizado para celular.
- `public/app.js` — lógica do navegador.
- `package.json` — dependências e comando de inicialização.

## Variáveis no Render

Obrigatória para diagnóstico:

- `OPENAI_API_KEY` = sua chave da API.

Recomendadas:

- `OPENAI_MODEL` = modelo usado no diagnóstico. Se ausente, o servidor usa `gpt-5.4`.
- `PUBLIC_BASE_URL` = URL pública sem barra final, por exemplo `https://seu-site.onrender.com`.
- `UPLOAD_TOKEN` = opcional. Se definido, coloque o mesmo valor em `CONFIG.UPLOAD_TOKEN` no scanner.
- `DATA_DIR` = diretório persistente. Com Render Disk, use o caminho de montagem do disco. Sem armazenamento persistente, os scans podem desaparecer após reinicialização/deploy da instância.

## Render

- Runtime: Node
- Build Command: `npm install`
- Start Command: `npm start`

Depois do deploy, teste:

- `/api/health`

Deve retornar `ok: true`, `scannerUpload: true` e `diagnostics: true`.

## Protocolo compatível com Samme.lua V3

- `POST /upload/start` → recebe `filename`, `source`, `metadata` e retorna `uploadId`.
- `POST /upload/chunk` → recebe `uploadId`, `index`, `objects`.
- `POST /upload/finish` → recebe `uploadId`, `totalChunks`, `summary` e retorna `downloadUrl`/`url`.
- `POST /upload/cancel` → recebe `uploadId`.

O backend aceita repetição do mesmo índice de chunk, substituindo aquela parte, o que ajuda nas tentativas automáticas do scanner.

## Diagnóstico por execução real

Na aba **Diagnóstico**, salve o loadstring original ou a URL raw do GitHub. O site cria uma fonte monitorada.

Para executar com diagnóstico automático:

1. Clique em **Copiar loadstring monitorado**.
2. Execute esse loadstring no executor no lugar do loadstring raw original.
3. O loader baixa o script original e registra no site:
   - `EXECUTANDO` assim que a execução começa;
   - `SUCESSO` quando termina sem erro;
   - `ERRO` quando falha;
   - fase do erro (`download`, `compile` ou `runtime`);
   - linha do erro, quando Lua/Luau fornece essa informação;
   - mensagem e traceback;
   - data/hora e histórico das últimas execuções.
4. O botão **Baixar último diagnóstico** baixa um TXT identificado pelo script.
5. **Remover monitoramento** apaga a fonte e seus diagnósticos salvos. O endpoint de relatório deixa de aceitar novas execuções dessa fonte.

Importante: o loadstring raw original não tem como informar ao site se a execução falhou. Para diagnóstico automático é necessário usar o loadstring monitorado gerado pelo site, ou inserir manualmente o protocolo de relatório no próprio script.
