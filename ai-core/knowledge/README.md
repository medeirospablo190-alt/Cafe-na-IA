# CAFEÍNA AI — branch de memória saneada

Esta branch foi separada da `main` apenas para guardar **índices por jogo**, produzidos pelo CAFEÍNA AI Core.

- Arquivos novos devem ficar em `ai-core/knowledge/<gameId>.json`.
- Apenas metadados estritamente permitidos: `gameId`, `placeId`, `runId`, hashes, contadores de tipos de evento e códigos de lacunas.
- Nunca publicar nomes de jogadores, IDs pessoais, textos capturados, argumentos de remotes, tokens, códigos enviados por terceiros nem dados brutos.
- Todas as hipóteses ficam `EXPERIMENTAL`, não validadas automaticamente.
- Publicação exige GitHub Actions manual com opção explícita, quando o workflow for revisado e habilitado na branch principal.
- O gateway, os scripts do coletor e o Render não leem essa branch e não foram modificados.
- A política de retenção e privacidade histórica continua pendente; a criação desta branch **não resolve** dados antigos que já estejam públicos.

A implementação em desenvolvimento e o progresso oficial estão no PR #228.
