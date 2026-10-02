package com.cafeina.executor;

import android.content.Context;

import java.io.File;
import java.io.IOException;
import java.util.ArrayList;
import java.util.Collections;
import java.util.HashSet;
import java.util.List;
import java.util.Set;

/**
 * Read-only preflight for one controlled AI action before local planning.
 *
 * It verifies only essential dependencies of the current action. It never
 * claims the Goal Lock, opens the model, executes tools, changes permissions,
 * or mutates task state.
 */
public final class LaboratoryAiActionPreflight {
    public enum Status {
        READY,
        ATTENTION,
        BLOCKED
    }

    public static final class Check {
        public final String code;
        public final Status status;
        public final String detail;

        private Check(String code, Status status, String detail) {
            this.code = code;
            this.status = status;
            this.detail = detail;
        }
    }

    public static final class Report {
        public final Status status;
        public final boolean canPlan;
        public final String contractId;
        public final String modelFileName;
        public final List<Check> checks;
        public final long modelSizeBytes;
        public final long availableRamBytes;
        public final long appUsableStorageBytes;
        public final int cpuCores;

        private Report(
                Status status,
                boolean canPlan,
                String contractId,
                String modelFileName,
                List<Check> checks,
                long modelSizeBytes,
                long availableRamBytes,
                long appUsableStorageBytes,
                int cpuCores) {
            this.status = status;
            this.canPlan = canPlan;
            this.contractId = contractId;
            this.modelFileName = modelFileName;
            this.checks = Collections.unmodifiableList(
                new ArrayList<>(checks));
            this.modelSizeBytes = modelSizeBytes;
            this.availableRamBytes = availableRamBytes;
            this.appUsableStorageBytes = appUsableStorageBytes;
            this.cpuCores = cpuCores;
        }
    }

    private LaboratoryAiActionPreflight() {}

    public static Report inspect(
            Context context,
            String projectId,
            String contractId,
            String selectedModelFileName) throws IOException {
        if (context == null
                || contractId == null
                || contractId.isEmpty()) {
            throw new IllegalArgumentException(
                "action preflight input missing");
        }

        Context app = context.getApplicationContext();
        List<Check> checks = new ArrayList<>();

        LaboratoryAiTaskContractStore.Contract contract =
            new LaboratoryAiTaskContractStore(
                app.getFilesDir(),
                projectId == null ? "" : projectId)
                .read(contractId);
        checks.add(check(
            "GOAL_LOCK_INTEGRITY",
            Status.READY,
            "Goal Lock íntegro."));

        if (contract.claimed || contract.resultRecorded) {
            checks.add(check(
                "GOAL_LOCK_ALREADY_USED",
                Status.BLOCKED,
                "Este Goal Lock já foi consumido ou possui resultado registrado."));
        } else {
            checks.add(check(
                "GOAL_LOCK_UNUSED",
                Status.READY,
                "Goal Lock ainda não consumido."));
        }

        Set<String> availableToolIds = new HashSet<>();
        for (LaboratoryAiToolController.Tool tool :
                LaboratoryAiToolController.listAvailable(
                    app,
                    projectId == null ? "" : projectId)) {
            availableToolIds.add(tool.toolId);
        }

        List<String> missingTools = new ArrayList<>();
        for (String toolId : contract.allowedToolIds) {
            if (!availableToolIds.contains(toolId)) {
                missingTools.add(toolId);
            }
        }

        if (contract.allowedToolIds.isEmpty()) {
            checks.add(check(
                "TASK_HAS_NO_TOOLS",
                Status.BLOCKED,
                "A tarefa não possui ferramentas autorizadas."));
        } else if (!missingTools.isEmpty()) {
            checks.add(check(
                "TASK_TOOL_PERMISSION_CHANGED",
                Status.BLOCKED,
                "Ferramenta(s) autorizada(s) no Goal Lock não estão mais "
                    + "disponíveis como STABLE + concedidas: "
                    + String.join(", ", missingTools)));
        } else {
            checks.add(check(
                "TASK_TOOLS_READY",
                Status.READY,
                contract.allowedToolIds.size()
                    + " ferramenta(s) autorizada(s) continuam disponíveis."));
        }

        String selected =
            selectedModelFileName == null
                ? ""
                : selectedModelFileName.trim();
        long modelSize = 0L;
        long availableRam = 0L;
        long usableStorage = Math.max(
            0L,
            app.getFilesDir().getUsableSpace());
        int cpuCores = Math.max(
            1,
            Runtime.getRuntime().availableProcessors());

        if (selected.isEmpty()) {
            checks.add(check(
                "LOCAL_MODEL_NOT_SELECTED",
                Status.BLOCKED,
                "Nenhum modelo local está selecionado."));
        } else {
            try {
                LaboratoryAiLocalModelCatalog.Model model =
                    LaboratoryAiLocalModelCatalog.resolve(
                        app.getFilesDir(),
                        selected);
                modelSize = model.sizeBytes;
                checks.add(check(
                    "LOCAL_MODEL_ADMITTED",
                    Status.READY,
                    "Modelo GGUF selecionado passou pela admissão de arquivo."));

                LaboratoryAiLocalModelAdmission.AdmittedModel admitted =
                    LaboratoryAiLocalModelAdmission.admit(
                        app.getFilesDir(),
                        model.modelFile);
                LaboratoryAiLocalModelPreflight.Report modelPreflight =
                    LaboratoryAiLocalModelPreflight.inspect(
                        app,
                        admitted);
                availableRam = modelPreflight.availableRamBytes;
                usableStorage = modelPreflight.appUsableStorageBytes;
                cpuCores = modelPreflight.cpuCores;

                Status modelStatus;
                if (!modelPreflight.canAttemptLoad) {
                    modelStatus = Status.BLOCKED;
                } else if (LaboratoryAiLocalModelPreflight.STATUS_ATTENTION
                        .equals(modelPreflight.status)) {
                    modelStatus = Status.ATTENTION;
                } else {
                    modelStatus = Status.READY;
                }

                String detail =
                    "Runtime empacotado: "
                        + (modelPreflight.runtimePackaged ? "SIM" : "NÃO")
                        + " • pressão de memória Android: "
                        + (modelPreflight.androidLowMemory ? "SIM" : "NÃO");
                if (!modelPreflight.signalCodes.isEmpty()) {
                    detail += " • sinais: "
                        + String.join(", ", modelPreflight.signalCodes);
                }

                checks.add(check(
                    "LOCAL_MODEL_DEVICE_PREFLIGHT",
                    modelStatus,
                    detail));
            } catch (IOException modelFailure) {
                checks.add(check(
                    "LOCAL_MODEL_ADMISSION_FAILED",
                    Status.BLOCKED,
                    safeReason(modelFailure)));
            }
        }

        Status overall = Status.READY;
        for (Check check : checks) {
            if (check.status == Status.BLOCKED) {
                overall = Status.BLOCKED;
                break;
            }
            if (check.status == Status.ATTENTION) {
                overall = Status.ATTENTION;
            }
        }

        return new Report(
            overall,
            overall != Status.BLOCKED,
            contract.contractId,
            selected,
            checks,
            modelSize,
            availableRam,
            usableStorage,
            cpuCores);
    }

    private static Check check(
            String code,
            Status status,
            String detail) {
        return new Check(
            code,
            status,
            detail == null ? "" : detail);
    }

    private static String safeReason(Throwable error) {
        if (error == null) return "Falha desconhecida.";
        String message = error.getMessage();
        if (message == null || message.trim().isEmpty()) {
            return error.getClass().getSimpleName();
        }
        String clean = message
            .replace('\n', ' ')
            .replace('\r', ' ')
            .trim();
        return clean.length() <= 240
            ? clean
            : clean.substring(0, 240);
    }
}
