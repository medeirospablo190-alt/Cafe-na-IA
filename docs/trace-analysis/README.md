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
- até 12 MiB por arquivo JSON;
- até 8 níveis de inferência de campos e 2.000 campos distintos;
- até 100 avisos no relatório;
- os traces originais são somente leitura.

A confiança indica volume de amostras, não prova que uma hipótese sobre o jogo esteja correta. Padrões e correlações não devem ser descritos como causalidade confirmada sem teste independente.

## Relação com o espelhamento GitHub

O upload e o espelhamento dos lotes continuam sendo feitos pelo endpoint Trace V3 existente. Esta ferramenta analisa os lotes que já foram salvos. Ela não muda a captura Lua, o contrato HTTP, a autenticação, a persistência ou o mecanismo de retry. A execução real no Android e a integração ponta a ponta precisam ser validadas separadamente.
