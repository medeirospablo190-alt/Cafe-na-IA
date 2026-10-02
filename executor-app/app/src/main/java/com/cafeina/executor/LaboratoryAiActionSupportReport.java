package com.cafeina.executor;

import java.io.File;
import java.io.IOException;

/**
 * Bounded, copyable technical report for one AI action.
 *
 * The report deliberately excludes the exact goal text, chat transcript,
 * prompt, model output, raw tool input/output and filesystem paths.
 */
public final class LaboratoryAiActionSupportReport {
    public static final int MAX_REPORT_CHARS = 16 * 1024;

    private LaboratoryAiActionSupportReport() {}

    public static String build(
            File filesDir,
            String projectId,
            String contractId,
            String scenarioId) throws IOException {
        LaboratoryAiActionDiagnostic.Snapshot diagnostic =
            LaboratoryAiActionDiagnostic.inspect(
                filesDir,
                projectId,
                contractId);
        LaboratoryAiActionTimeline.Snapshot timeline =
            LaboratoryAiActionTimeline.inspect(
                filesDir,
                projectId,
                contractId,
                scenarioId);

        StringBuilder out = new StringBuilder();
        out.append("CAFEÍNA • RELATÓRIO TÉCNICO DA AÇÃO")
            .append("\nversão=1")
            .append("\ncontrato=")
            .append(shortId(diagnostic.contractId))
            .append("\nmodo=")
            .append(diagnostic.mode)
            .append("\nferramentas_autorizadas=")
            .append(diagnostic.allowedToolCount)
            .append("\ngoal_lock_consumido=")
            .append(diagnostic.goalLockClaimed)
            .append("\nresultado_registrado=")
            .append(diagnostic.resultRecorded)
            .append("\netapa=")
            .append(diagnostic.stage)
            .append("\nproxima_verificacao=")
            .append(safe(diagnostic.nextCheck));

        if (diagnostic.plannerEnvironment != null) {
            LaboratoryAiPlannerEnvironmentStore.Snapshot env =
                diagnostic.plannerEnvironment;
            out.append("\n\n[AMBIENTE_PLANEJADOR]")
                .append("\nmodelo=")
                .append(safe(env.modelFileName))
                .append("\nmodelo_bytes=")
                .append(env.modelSizeBytes)
                .append("\npreflight=")
                .append(env.preflightStatus)
                .append("\nruntime_empacotado=")
                .append(env.runtimePackaged)
                .append("\nandroid_low_memory=")
                .append(env.androidLowMemory)
                .append("\nram_total_bytes=")
                .append(env.totalRamBytes)
                .append("\nram_disponivel_bytes=")
                .append(env.availableRamBytes)
                .append("\nram_limite_low_memory_bytes=")
                .append(env.lowMemoryThresholdBytes)
                .append("\narmazenamento_app_disponivel_bytes=")
                .append(env.appUsableStorageBytes)
                .append("\ncpu_cores=")
                .append(env.cpuCores)
                .append("\ncontexto_tokens=")
                .append(env.contextTokens)
                .append("\nmax_saida_tokens=")
                .append(env.maxTokens)
                .append("\nthreads=")
                .append(env.threads)
                .append("\ntop_k=")
                .append(env.topK)
                .append("\ntop_p=")
                .append(env.topP)
                .append("\ntimeout_ms=")
                .append(env.maxGenerationMs)
                .append("\nsinais=")
                .append(env.signalCodes);
            if (!env.runtimeVersion.isEmpty()) {
                out.append("\nruntime=")
                    .append(safe(env.runtimeVersion));
            }
            if (!env.modelDescription.isEmpty()) {
                out.append("\ndescricao_modelo=")
                    .append(safe(env.modelDescription));
            }
        }

        if (diagnostic.planner != null) {
            out.append("\n\n[PLANEJADOR]")
                .append("\nestado=")
                .append(diagnostic.planner.state)
                .append("\nfase=")
                .append(diagnostic.planner.phase)
                .append("\ntempo_ms=")
                .append(diagnostic.planner.elapsedMs)
                .append("\ntentativa=")
                .append(diagnostic.planner.attempt)
                .append("/")
                .append(diagnostic.planner.maxAttempts)
                .append("\nprompt_tokens=")
                .append(diagnostic.planner.promptTokensProcessed)
                .append("/")
                .append(diagnostic.planner.promptTokens)
                .append("\nprompt_ms=")
                .append(diagnostic.planner.promptEvalMs)
                .append("\nsaida_tokens=")
                .append(diagnostic.planner.generatedTokens)
                .append("/")
                .append(diagnostic.planner.maxGeneratedTokens)
                .append("\nsaida_ms=")
                .append(diagnostic.planner.tokenGenerationMs);
            if (diagnostic.plannerDiagnostic != null) {
                out.append("\nclassificacao=")
                    .append(diagnostic.plannerDiagnostic.code.name());
            }
        } else if (diagnostic.plannerCheckpoint != null) {
            out.append("\n\n[PLANEJADOR_CHECKPOINT]")
                .append("\nfase=")
                .append(diagnostic.plannerCheckpoint.phase)
                .append("\ntempo_ms=")
                .append(diagnostic.plannerCheckpoint.elapsedMs)
                .append("\ntentativa=")
                .append(diagnostic.plannerCheckpoint.attempt)
                .append("/")
                .append(diagnostic.plannerCheckpoint.maxAttempts)
                .append("\nprompt_tokens=")
                .append(
                    diagnostic.plannerCheckpoint.promptTokensProcessed)
                .append("/")
                .append(diagnostic.plannerCheckpoint.promptTokens)
                .append("\nsaida_tokens=")
                .append(diagnostic.plannerCheckpoint.generatedTokens)
                .append("/")
                .append(
                    diagnostic.plannerCheckpoint.maxGeneratedTokens);
        }

        if (diagnostic.testSession != null) {
            out.append("\n\n[TESTADORA_SESSAO]")
                .append("\nsessao=")
                .append(shortId(diagnostic.testSession.sessionId))
                .append("\nestado=")
                .append(diagnostic.testSession.state)
                .append("\nchamadas=")
                .append(diagnostic.testSession.invocationsUsed)
                .append("/")
                .append(diagnostic.testSession.maxInvocations)
                .append("\nentrada_bytes=")
                .append(diagnostic.testSession.inputBytesUsed)
                .append("/")
                .append(diagnostic.testSession.maxTotalInputBytes)
                .append("\neventos=")
                .append(diagnostic.testSession.eventCount);
        }

        if (diagnostic.testReport != null) {
            out.append("\n\n[TESTADORA_RELATORIO]")
                .append("\nstatus=")
                .append(diagnostic.testReport.status)
                .append("\npassos=")
                .append(diagnostic.testReport.executedSteps)
                .append("/")
                .append(diagnostic.testReport.plannedSteps)
                .append("\npassaram=")
                .append(diagnostic.testReport.passed)
                .append("\nfalharam=")
                .append(diagnostic.testReport.failed);
        }

        out.append("\n\n[LINHA_DO_TEMPO]");
        int index = 1;
        for (LaboratoryAiActionTimeline.Item item : timeline.items) {
            out.append("\n")
                .append(index++)
                .append("|")
                .append(item.atEpochMs)
                .append("|")
                .append(item.source)
                .append("|")
                .append(safe(item.code))
                .append("|")
                .append(safe(item.title));
            if (out.length() >= MAX_REPORT_CHARS - 512) {
                out.append("\n...linha do tempo truncada...");
                break;
            }
        }

        out.append(
            "\n\n[PRIVACIDADE]\n"
                + "objetivo_exato=OMITIDO\n"
                + "chat=OMITIDO\n"
                + "prompt=OMITIDO\n"
                + "saida_modelo=OMITIDA\n"
                + "entrada_saida_ferramenta=OMITIDA");

        if (out.length() > MAX_REPORT_CHARS) {
            return out.substring(0, MAX_REPORT_CHARS);
        }
        return out.toString();
    }

    private static String shortId(String value) {
        if (value == null) return "";
        return value.length() <= 8
            ? value
            : value.substring(0, 8);
    }

    private static String safe(String value) {
        if (value == null) return "";
        return value
            .replace('\n', ' ')
            .replace('\r', ' ')
            .replace('|', '/')
            .trim();
    }
}
