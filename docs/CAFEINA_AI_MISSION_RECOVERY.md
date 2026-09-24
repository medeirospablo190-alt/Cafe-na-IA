# CAFEÍNA AI — recuperação de missões (fundação)

O estado em memória de `AiMission` agora pode produzir um `AiMissionSnapshot` imutável e ser reconstruído a partir dele. O PR de fundação fornece checkpoint **em memória**. Este PR dependente acrescenta armazenamento SQLite transacional; ainda não há UI de retomada nem execução automática.

## Política de recuperação

- `CREATED`, `WAITING_USER`, `COMPLETED`, `FAILED` e `CANCELLED` são restaurados sem mudança.
- `RUNNING` é restaurado como `WAITING_USER`. Após reinício, não é seguro repetir uma operação cujo efeito pode ter sido aplicado antes da interrupção. O host precisa reconciliar a evidência da operação antes de chamar `resume()`.
- O checkpoint exige id, projeto, objetivo e estado válidos. O armazenamento persistente futuro deve validar o projeto e rejeitar dados de outro projeto antes da restauração.
- O snapshot não contém tokens, capabilities, código executável nem resultado presumido. Permissões precisam ser concedidas novamente pelo host para qualquer operação posterior.

## Persistência adicionada no PR dependente

`AiMissionCheckpointRepository` salva por `(project_id, mission_id)` na versão 3 do banco local, rejeita projeto inválido, mudança de objetivo para a mesma identidade, transições de estado inválidas e reinício de missão terminal. Retransmissões do mesmo estado são idempotentes. Há testes de reabertura, isolamento por projeto e migração de v2 para v3. O armazenamento não concede capabilities e não executa operações.

## Próxima etapa

Integrar a gravação nos pontos de transição do host, validar projetos existentes via `ProjectStore`, registrar identificadores idempotentes e evidências de efeitos, testar corrupção/recuperação e construir a UI de retomada. Nenhuma operação `RUNNING` deve ser repetida somente porque o processo reiniciou.

O PR de fundação é independente do roteamento de operações. Este PR dependente altera apenas o schema **local** da Knowledge Store de v2 para v3, com migração versionada; não altera Collector, Render, cloud ou schema de produção.

## Coordenador de ciclo de vida (PR dependente #169)

`AiMissionLifecycleCoordinator` valida o projeto via `ProjectStore`, cria um checkpoint `CREATED` antes de devolver a missão e persiste cada transição antes de devolver o novo handle. Apenas o handle ativo emitido pelo coordenador atual pode transicionar; um objeto antigo ou de outro processo é rejeitado. Uma chamada explícita de recuperação converte `RUNNING` em `WAITING_USER` no SQLite antes de devolver o handle. O host deve obter evidência de que é seguro retomar antes de chamar `resume()`.

O coordenador **não está conectado à UI ou ao executor de tarefas**. Não tratar o fato de existir como prova de que missões existentes já são persistidas. A integração deve encaminhar todas as mudanças de estado pelo coordenador e nunca executar efeitos antes de registrar o checkpoint e um identificador idempotente. O bloqueio de handles é local ao processo; concorrência entre processos requer controle de versão/compare-and-swap no banco antes de permitir execução simultânea.
