# Analisador offline de Trace V3

Ferramenta de pós-processamento em Node.js puro (sem dependências adicionais), inspirada nas partes úteis do Reverse Engine: normalização, agrupamento, inferência de campos e confiança por volume de amostras.

## Uso

Aponte para uma pasta contendo lotes V3 ou para um arquivo JSON:

```sh
node tools/trace-analysis/analyze.mjs ./inventory-traces-v3 ./trace-analysis-report.json
```

O script percorre JSONs, reconhece lotes V3, agrega sessões, categorias, caminhos/métodos e tipos de campos. O relatório não copia os registros brutos. Os arquivos de origem são somente lidos; nada é enviado para a rede ou alterado.

- Confiança: baixa (<5 amostras), média (5–19), alta (20+).
- Limites: até 5.000 arquivos por execução, profundidade de campos 8, até 2.000 campos inferidos e até 100 avisos.
- Relatório pode conter IDs de jogo/lugar/sessão e caminhos de objetos. Revise antes de publicar ou compartilhar.
- A ferramenta não faz replay, chamadas remotas, exploração ativa nem tenta contornar anti-cheat.
