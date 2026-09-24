# CAFEÍNA AI — contrato inicial de operações

Este documento descreve o primeiro contrato implementado no PR de operações determinísticas. Ele não declara a IA completa nem habilita operações pela interface do aplicativo.

## Fluxo

1. O host cria `CafeinaAiCore.Request` com o projeto, a mensagem e as capacidades solicitadas.
2. `DefaultCafeinaAiCore` verifica todas as capacidades solicitadas contra o conjunto concedido pelo host.
3. Mensagens iniciadas por `operation:` **nunca** são enviadas ao modelo. Sem roteador configurado, a requisição falha.
4. O roteador aceita somente nomes registrados; confere a capacidade exigida tanto na solicitação quanto no conjunto concedido antes de chamar a operação.
5. A operação retorna `CafeinaAiCore.Response`. O roteador rejeita resposta nula, ausência da capacidade exigida e capacidades declaradas que não foram solicitadas e concedidas.
6. Mensagens comuns mantêm o provedor de linguagem existente. O texto produzido pelo modelo não é interpretado como uma nova operação pelo roteador.

## Primeira operação

`operation:project.info` requer `project.read`. Consulta um projeto existente e validado via `ProjectStore` e informa seu identificador e a disponibilidade do layout. Não cria projetos, altera scripts, executa código ou modifica o World. Projeto inexistente ou inválido produz falha explícita.

Exemplo de chamada do host:

```java
AiOperationRouter router = AiOperationRouter.forProjects(projectStore);
AiCapabilitySet granted = new AiCapabilitySet(Collections.singleton(AiOperationRouter.PROJECT_READ));
DefaultCafeinaAiCore core = new DefaultCafeinaAiCore(contextAssembler, modelProvider, granted, router);
CafeinaAiCore.Response result = core.handle(new CafeinaAiCore.Request(
    "default", "operation:project.info", Collections.singletonList(AiOperationRouter.PROJECT_READ)));
```

O exemplo pressupõe que o projeto `default` já existe. O construtor antigo do núcleo continua disponível para mensagens comuns.

## Limites de segurança

A verificação de `usedCapabilities` audita o **relato** da operação; não desfaz efeitos colaterais já realizados. Portanto, somente implementações revisadas e registradas pelo host podem executar operações, e cada operação futura com escrita deverá validar permissões **antes** de qualquer efeito, com testes de rollback e isolamento. Não registrar operações a partir de texto do modelo, scripts de usuários ou dados recuperados da base de conhecimento.

Este PR não conecta o roteador à UI, não adiciona capacidades de escrita e não altera Collector, Render, banco de produção ou schema de armazenamento.
