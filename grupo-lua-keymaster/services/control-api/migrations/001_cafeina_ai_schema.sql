CREATE SCHEMA IF NOT EXISTS cafeina_ai;

CREATE TABLE IF NOT EXISTS cafeina_ai.system_state (
  key TEXT PRIMARY KEY,
  value JSONB NOT NULL DEFAULT '{}'::jsonb,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

INSERT INTO cafeina_ai.system_state (key, value)
VALUES (
  'schema',
  '{"name":"CAFEINA_AI","version":1}'::jsonb
)
ON CONFLICT (key) DO NOTHING;
