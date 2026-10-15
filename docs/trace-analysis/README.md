# Análise inteligente de traces CAFÉÍNA V3

Esta ferramenta offline adapta ideias de normalização e agrupamento do Reverse Engine para os registros do CAFÉÍNA. Ela não usa HAR, não faz novas chamadas ao jogo e não altera nem envia os traces de origem.

## Executar

Com Node.js 22 e o repositório disponível:

```sh
npm run analyze:trace -- ./inventory-traces-v3 ./trace-analysis-report.json
```

Também aceita um único arquivo JSON V3:

```sh
npm run analyze:trace -- ./lote.json ./relatorio.json
```

## O que o relatório mostra

- sessões agrupadas por gameId/placeId/runId;
- contagem de registros por tipo;
- grupos por coleção, tipo, caminho e método;
- assinaturas explicitamente presentes nos dados;
- tipos observados de campos, quantidade de amostras e confiança baseada no volume;
- média de qualidade quando o campo existe;
- avisos para JSON inválido e arquivos grandes demais.

O relatório é agregado: não inclui os objetos brutos de `records` nem de `remotes`. Caminhos de objetos e IDs de jogo/sessão podem continuar identificáveis, então trate o relatório como dado de diagnóstico e compartilhe somente quando apropriado.

## Limites de segurança e desempenho

- até 5.000 arquivos por execução;
- profundidade de diretório limitada;
- até 12 MiB por arquivo JSON e 100 MiB somados por execução (arquivos que excedam o orçamento restante são ignorados com aviso);
- até 8 níveis de inferência de campos e 2.000 campos distintos;
- até 100 avisos no relatório;
- os traces originais são somente leitura.

A confiança indica volume de amostras, não prova que uma hipótese sobre o jogo esteja correta. Padrões e correlações não devem ser descritos como causalidade confirmada sem teste independente.

## Análise automática após manifesto

Quando o gateway recebe um lote do tipo `manifest`, ele tenta gerar um relatório agregado para aquele par gameId/placeId e espelhá-lo em:

```text
inventory-traces-v3/<gameId>/<placeId>/analysis/latest.json
```

A resposta do envio inclui `analysis.generated` e contagens agregadas quando essa etapa conclui. A análise é best-effort: se ela falhar, o lote bruto e o manifesto já espelhados continuam sendo a fonte de verdade; o recibo informa a falha sem marcar o relatório como gerado.

A geração tenta primeiro os JSON no disco local. Se o resultado local não contiver registros úteis, parecer incompleto ou falhar, tenta reconstruir o histórico lendo os batches armazenados no GitHub. Essa reconstrução tem limites de até 1.000 arquivos e 30 MiB; também considera incompleta uma listagem de diretório que atinja 1.000 entradas, arquivos inválidos, lotes ausentes ou lotes incompatíveis. Nesses casos, `historyComplete` permanece `false` e o relatório inclui avisos. Esses limites evitam afirmar que um histórico parcial é completo. O relatório é refeito no encerramento de uma sessão, não em cada lote, para evitar muitas chamadas ao GitHub.

O upload e o espelhamento dos lotes continuam sendo feitos pelo endpoint Trace V3 existente. A captura Lua, o contrato HTTP e o mecanismo de retry dos lotes permanecem compatíveis. A execução real no Android e a integração ponta a ponta ainda precisam ser validadas separadamente.


## Consultar o relatório pelo gateway

A rota GET `/api/inventory-trace-v3/<gameId>/<placeId>/analysis` devolve o relatório mais recente, tentando o disco local e depois o GitHub. O campo `historySource` indica se a fonte foi `local_gateway_disk` ou `github_reconstructed`; `historyComplete` só fica `true` quando a reconstrução não detecta os limites ou problemas descritos acima. O relatório é uma visão agregada, não uma garantia de que o gateway tem armazenamento persistente. Históricos que excedam os limites exigem paginação/arquivamento adicionais antes de poderem ser declarados completos.

Reenvios do mesmo manifesto reutilizam o relatório já espelhado para evitar commits repetidos para a mesma sessão. Se a sessão ou os lotes mudarem, uma nova geração pode atualizar o relatório.
