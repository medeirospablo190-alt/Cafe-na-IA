# CAFEÍNA AI Core — início da construção

Módulo isolado para o sistema de agentes que vai estudar **jogos próprios ou autorizados**, receber evidências do coletor V3, propor investigações e futuramente gerar **Luau original**.

## Estado atual

Esta versão é **um protótipo local de leitura/planejamento (DRY_RUN)**, não um sistema de IA conectado. Ela importa um batch + latest V3, confere identidade da sessão, resume os tipos de registros sem transportar campos de jogador, cria uma proposta de observação **não executável** e mostra progresso auditável.

**Não faz**: chamadas a modelos pagos, conexão ativa com REA, GitHub, Roblox ou Render, execução de ferramentas em jogo, programação ou publicação.

## Executar (Node 22+)

```bash
cd ai-core
npm run validate
npm run demo
npm run progress
node src/cli.mjs /caminho/0001-data.json /caminho/latest.json
```

Todos os testes usam apenas **dados sintéticos** e bibliotecas nativas do Node. Não há arquivos de jogadores reais nas fixtures.

## Documentação

- `docs/ROADMAP.md` — plano até 100% e critérios.
- `docs/ARCHITECTURE.md` — componentes e contratos futuros.
- `docs/SECURITY.md` — privacidade e permissões.
- `plan/progress.json` — fonte calculável do percentual.

O coletor V3, o gateway e as configurações de produção continuam intocados.
