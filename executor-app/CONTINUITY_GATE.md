# CAFEÍNA — Gate de continuidade

Esta linha só pode ser tratada como pronta quando o estado real estiver verificado no código e no APK gerado. Memória de conversa ou intenção anterior não substituem verificação.

## Checkpoint
- Base desta rodada: `0572adaa85dbe7ef912ec88eb9526b5f99739729`.
- Linha de trabalho: `app/cafeina-runtime-ui-continuity-fix`.
- Não continuar a partir de `main` sem reconciliação explícita.

## Dependências obrigatórias do APK ARM64 da IA
- Luau JNI presente.
- Godot ARM64 presente.
- `libcafeina_llama_jni.so` presente.
- JNI de abertura e geração do `LlamaBridge` presente.
- Nenhuma biblioteca de emulador no APK de aparelho.

## Gate funcional mínimo no aparelho
1. Instalar o APK ARM64 produzido por esta linha.
2. Abrir a aba IA sem erro.
3. Abrir e fechar a barra lateral da IA.
4. Sair da aba IA e voltar sem crash nem perda da conversa.
5. Importar ou selecionar um GGUF.
6. Enviar uma mensagem comum no chat.
7. O preflight não pode retornar `RUNTIME_NOT_PACKAGED`.
8. O modelo deve realmente produzir uma resposta local.
9. Só depois validar planejador, Goal Lock e Testadora.

## Gate de interface
- A tela principal da IA é o chat.
- Configuração do modelo, testes, permissões, Goal Locks e diagnóstico ficam fora da tela principal, no menu lateral.
- Status de trabalho só aparece contextualizado enquanto existir uma ação.

Se qualquer item falhar, registrar o estágio real da falha e não marcar a etapa como concluída.
