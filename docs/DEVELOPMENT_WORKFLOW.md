# Fluxo de desenvolvimento da CAFEÍNA — blocos longos

**Autoridade:** `docs/CAFEINA_OPERATIONAL_PROTOCOL.md` (seções 2.1 e 64). Este documento é guia de aplicação, não fonte concorrente.

## Método adotado

O fluxo adapta o método usado nos aplicativos Grupo Lua/Gestão: diagnóstico concentrado no início, execução silenciosa de um bloco grande, correção interna de erros, validação em checkpoints e entrega de resultados consolidados. O objetivo é reduzir chamadas externas, PRs fragmentados, reconstruções após squash e espera ociosa por CI.

**Meta operacional: 25 minutos ou mais de trabalho útil por execução, sempre que a sessão e as ferramentas permitirem.** Trata-se de uma meta, não de garantia de relógio. Não usar esperas artificiais para completar tempo, nem declarar que o trabalho continuou depois do encerramento da resposta.

### Ciclo de uma fase

1. Ler estado real de `main`, branches/PRs abertos, decisões registradas, CI e dependências. Definir um objetivo verificável e riscos.
2. Criar ou retomar uma branch de integração por fase. Agrupar alterações relacionadas em commits claros; não criar PR para cada arquivo.
3. Implementar o bloco completo, com testes e documentação. Fazer revisão local do diff e dos efeitos colaterais.
4. Executar testes de baixo custo durante a implementação. Disparar CI completo quando houver checkpoint estável; evitar commits cosméticos enquanto o CI valida.
5. Durante o CI, executar trabalho independente e útil. Consultar o CI apenas quando o resultado mudar a próxima decisão. Falha: ler logs, corrigir, testar, novo checkpoint.
6. Abrir/atualizar PR com escopo, evidências, riscos, rollback e pendências. Revisar mudanças e dependências. CI aprovado é obrigatório, mas não autoriza merge automaticamente.
7. Após autorização explícita do usuário para merge, mesclar apenas o PR validado. Se houver squash, atualizar branches dependentes e verificar diffs antes de prosseguir.

### Política de interrupção

Não interromper por fim de commit, PR aberto, CI pendente, job lento, documentação concluída ou início de nova subetapa. Continuar trabalho seguro e independente. Pedir intervenção somente quando uma decisão de produto não estiver documentada, um acesso indispensável faltar, uma ação crítica/destrutiva exigir aprovação ou não houver trabalho seguro e executável restante.

Se a sessão atingir um limite, registrar: objetivo, branch, SHA, PR, testes aprovados/pendentes, arquivos alterados, bloqueios e próximo comando/ação. Não apresentar o limite como se fosse uma decisão do usuário.

### Checkpoints mínimos

- **Código:** compila e testes pertinentes passam; mudanças de segurança têm testes negativos.
- **Android/runtime:** testes JVM e instrumentados quando afetados; validar empacotamento nativo quando aplicável.
- **Collector/cloud:** testes de rotas, compatibilidade e isolamento; não mexer em produção por conveniência.
- **Dados:** snapshot/backup antes de migração; rollback e preservação do legado.
- **PR:** diff revisado, CI verde para o SHA atual, riscos explícitos; merge só com autorização.

### Trilhas de trabalho em paralelo

Enquanto uma branch aguarda CI, preparar documentação, desenho de interfaces, testes ou investigação de uma fase seguinte **sem misturar alterações não validadas no mesmo PR**. Dependências não aprovadas devem ficar identificadas; não assumir que o PR pendente já integra a `main`.

### Regras de prioridade

Segurança e preservação de dados > correção e testes > compatibilidade > velocidade. A meta de 25 minutos reduz interrupções; não reduz revisão, CI, autorização para merge nem isolamento do Collector.

Veja `AGENTS.md` para as regras executáveis dos agentes e `README.md` para a arquitetura ativa.
