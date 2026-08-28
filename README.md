# CAFEÍNA — Scanner File Receiver

Versão enxuta do site.

## O que foi removido
- diagnóstico de scripts
- OpenAI
- chat
- polling de diagnósticos
- upload manual de Lua/TXT

## O que ficou
- POST /upload/start
- POST /upload/chunk
- POST /upload/finish
- POST /upload/cancel
- GET /api/uploads/:uploadId
- GET /api/files
- GET /api/files/:filename/preview
- GET /files/:filename
- DELETE /api/files/:filename
- GET /health

## Estrutura
server.js
package.json
public/index.html
public/styles.css
public/app.js

## Render
Build Command:
npm install

Start Command:
npm start

Variáveis opcionais:
- DATA_DIR: caminho persistente para dados
- UPLOAD_TOKEN: token opcional do scanner
- MAX_CHUNK_BYTES
- MAX_FINAL_BYTES
- SESSION_TTL_MS
- PREVIEW_BYTES

IMPORTANTE:
Sem DATA_DIR apontando para armazenamento persistente, os arquivos podem desaparecer quando a instância for recriada/reimplantada.

O scanner deve continuar usando:
- /upload/start
- /upload/chunk
- /upload/finish
