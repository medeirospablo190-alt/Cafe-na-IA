# CAFEÍNA AI — recuperação de missões (fundação)

O estado em memória de `AiMission` agora pode produzir um `AiMissionSnapshot` imutável e ser reconstruído a partir dele. O PR de fundação fornece checkpoint **em memória**. Este PR dependente acrescenta armazenamento SQLite transacional; ainda não há UI de retomada nem execução automática.

## Política de recuperação

- `CREATED`, `WAITING_USER`, `COMPLETED`, `FAILED` e `CANCELLED` são restaurados sem mudança.
- `RUNNING` é restaurado como `WAITING_USER`. Após reinício, não é seguro repetir uma operação cujo efeito pode ter sido aplicado antes da interrupção. O host precisa reconciliar a evidência da operação antes de chamar `resume()`.
- O checkpoint exige id, projeto, objetivo e estado válidos. O armazenamento persistente futuro deve validar o projeto e rejeitar dados de outro projeto antes da restauração.
- O snapshot não contém tokens, capabilities, código executável nem resultado presumido. Permissões precisam ser concedidas novamente pelo host para qualquer operação posterior.

## Persistência adicionada no PR dependente

`AiMissionCheckpointRepository` salva por `(project_id, mission_id)` na versão 3 do banco local, rejeita projeto inválido, mudança de objetivo para a mesma identidade e reinício de missão terminal. Há testes de reabertura, isolamento por projeto e migração de v2 para v3. O armazenamento não concede capabilities e não executa operações.

## Próxima etapa

Integrar a gravação nos pontos de transição do host, validar projetos existentes via `ProjectStore`, registrar identificadores idempotentes e evidências de efeitos, testar corrupção/recuperação e construir a UI de retomada. Nenhuma operação `RUNNING` deve ser repetida somente porque o processo reiniciou.

O PR de fundação é independente do roteamento de operações. Este PR dependente altera apenas o schema **local** da Knowledge Store de v2 para v3, com migração versionada; não altera Collector, Render, cloud ou schema de produção.
