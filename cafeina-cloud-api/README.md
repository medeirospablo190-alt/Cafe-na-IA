# CAFEÍNA Cloud API

Neutral backend foundation for the CAFEÍNA application.

This service intentionally contains no Grupo Lua, App 1, Keymaster, FREE/VIP, social, chat, menu-key or Roblox-login business logic.

## Database isolation

It can reuse the same PostgreSQL/Neon database connection that previously hosted Grupo Lua, but all new CAFEÍNA objects live under the dedicated `cafeina_ai` schema.

Legacy tables are not dropped automatically. This prevents accidental data loss while the old product is removed from the repository. A later audited migration can archive or remove legacy database objects after confirming they are no longer needed.

## Endpoints

- `GET /v1/health` — process + PostgreSQL health.
- `GET /v1/system` — initial CAFEÍNA schema state.

## Run

```bash
npm install
npm run migrate
npm start
```
