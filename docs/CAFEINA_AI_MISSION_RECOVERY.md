# CAFEÍNA AI — recuperação de missões (fundação)

O estado em memória de `AiMission` agora pode produzir um `AiMissionSnapshot` imutável e ser reconstruído a partir dele. Este é um contrato de checkpoint **em memória**; ainda não há gravação em SQLite, UI de retomada nem execução automática.

## Política de recuperação

- `CREATED`, `WAITING_USER`, `COMPLETED`, `FAILED` e `CANCELLED` são restaurados sem mudança.
- `RUNNING` é restaurado como `WAITING_USER`. Após reinício, não é seguro repetir uma operação cujo efeito pode ter sido aplicado antes da interrupção. O host precisa reconciliar a evidência da operação antes de chamar `resume()`.
- O checkpoint exige id, projeto, objetivo e estado válidos. O armazenamento persistente futuro deve validar o projeto e rejeitar dados de outro projeto antes da restauração.
- O snapshot não contém tokens, capabilities, código executável nem resultado presumido. Permissões precisam ser concedidas novamente pelo host para qualquer operação posterior.

## Próxima etapa

Criar armazenamento transacional de checkpoints com isolamento por projeto, schema versionado, testes de reabertura e tratamento de corrupção. Registrar identificadores idempotentes e evidências de efeitos antes de permitir retomada automática. Nenhuma operação `RUNNING` deve ser repetida somente porque o processo reiniciou.

Este PR é independente do PR de roteamento de operações; não altera Collector, Render, cloud, dados existentes ou o schema local.
