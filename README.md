CAFEÍNA DARKSIDE CONTROL CENTER
===============================

ESTRUTURA
---------
server.js
package.json
public/index.html
public/app.js
public/styles.css
DiagnosticReporter.lua

ABAS DO SITE
------------
1. Diagnósticos runtime em JSON
2. Arquivos do Scam
3. Analisar Lua

SCRIPTS AUTORIZADOS PARA DIAGNÓSTICO
------------------------------------
Scamtest.lua
Menutest.lua
Samme.lua
CafeinaV1.lua
Cafeinav2.lua
Cafeinav3.lua
Cafeinav4.lua
Explorador de Bots V4.lua
Explorador de Bots V3.lua
Psico test.lua
Psico scam.lua
Psicov1.lua
Psicov2.lua
Psicov3.lua

IMPORTANTE
----------
"Explorador de Bots V4.lua" foi informado duas vezes e foi cadastrado uma vez.

O fluxo do Scam continua independente:
POST /upload/start
POST /upload/chunk
POST /upload/finish
POST /upload/cancel

Os diagnósticos usam outra rota:
POST /api/runtime-diagnostics
GET  /api/runtime-diagnostics
GET  /api/runtime-diagnostics/scripts

VARIÁVEIS DO RENDER
-------------------
OPENAI_API_KEY        opcional para a aba Analisar Lua
OPENAI_MODEL          opcional
UPLOAD_TOKEN          token do upload do Scam
DIAGNOSTIC_TOKEN      recomendado para diagnósticos; se ausente o servidor usa UPLOAD_TOKEN
PUBLIC_BASE_URL       recomendado: https://cafe-na-ia.onrender.com
DATA_DIR              use armazenamento persistente se disponível

COMO USAR O DiagnosticReporter.lua
----------------------------------
Copie o módulo para cada script ou incorpore o código no começo do script.
Altere:
Diagnostic.SCRIPT_NAME
Diagnostic.VERSION
Diagnostic.TOKEN

Exemplos:
Diagnostic.start()
Diagnostic.step("scanner_workspace", "Workspace concluído", { objects = 12000 })
Diagnostic.error("upload", err)
Diagnostic.interrupted("scan", "Parado pelo usuário", { objects = 21000 })
Diagnostic.success("Finalizado", { objects = 34815, chunks = 18 })

Para capturar uma função inteira:
local ok, result = Diagnostic.runStep("nome_da_etapa", function()
    -- seu código
end)

SEGURANÇA / CONFIABILIDADE
--------------------------
O reporter envia em task.spawn + pcall. Se o site estiver fora do ar, o script principal continua.
O servidor remove campos com nomes como token, password, secret, cookie, authorization e api-key do JSON salvo.
Não envie chaves da OpenAI, cookies ou senhas nos campos extra/metrics.

ARQUIVOS DO SCAM
----------------
Continuam salvos em data/uploads e listados por /api/scans.
Diagnósticos runtime ficam em data/diagnostics/runtime/<script>/.
As duas áreas não compartilham arquivos.
