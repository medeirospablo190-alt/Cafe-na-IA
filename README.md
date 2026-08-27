# CAFEÍNA AI Backend

Backend HTTP simples para conectar um menu Roblox a uma IA.

## Render

1. Suba estes arquivos em um repositório GitHub.
2. No Render: New > Web Service.
3. Conecte o repositório.
4. Runtime: Node.
5. Build Command: `npm install`
6. Start Command: `npm start`
7. Adicione em Environment:
   - `OPENAI_API_KEY` = sua chave da API
   - `OPENAI_MODEL` = `gpt-5.4` (opcional)
8. Faça o deploy.
9. Use no Lua:
   `https://SEU-SERVICO.onrender.com/chat`

## Teste

GET `/health` deve retornar:

```json
{"ok":true}
```

POST `/chat`:

```json
{
  "message": "Olá",
  "userId": 123,
  "username": "Player"
}
```

Resposta:

```json
{
  "message": "..."
}
```

Nunca coloque `OPENAI_API_KEY` no script Lua.
