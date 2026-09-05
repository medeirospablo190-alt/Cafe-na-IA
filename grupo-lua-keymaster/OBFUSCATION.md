# GRUPO LUA — ofuscação do login

O arquivo público `GrupoLuaLogin.lua` pode ser distribuído em forma ofuscada sem alterar o endereço RAW usado pelos loaders.

## Ferramentas

O build usa **Prometheus** em preset `Medium`, alvo `LuaU`, fixado no commit `a4efc5f381c50ae2a111bdbb9272fa3203685be3`.

Based on Prometheus by Elias Oelschner, https://github.com/prometheus-lua/Prometheus

A saída também é compilada pelo compilador oficial **Luau** antes de ser disponibilizada como artefato do GitHub Actions.

## Regras de segurança

- a Control API continua sendo a autoridade das chaves FREE/VIP;
- a ofuscação não muda endpoints, `MENU_ID`, tokens ou o fluxo de validação;
- o arquivo público ofuscado não deve conter a fonte legível ao lado dele;
- o workflow manual recusa executar quando `GrupoLuaLogin.lua` já é um build ofuscado, evitando ofuscação em cascata;
- antes da transformação, a fonte legível passa pelo guard de regressão do login;
- depois da transformação, a saída precisa ser aceita pelo compilador Luau.

## Limite importante

Este repositório já publicou versões legíveis no histórico Git. Ofuscar o HEAD reduz a exposição casual e protege versões futuras publicadas somente como build, mas não apaga commits históricos. Para proteção mais forte no futuro, a fonte legível deve ser mantida em repositório privado ou outro armazenamento privado e apenas o build ofuscado deve ser publicado aqui.
