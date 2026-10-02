package com.cafeina.executor;

import java.util.Locale;

/**
 * Conservative host-side router for the CAFEÍNA chat surface.
 *
 * It never executes anything. Its job is to keep obvious app/action requests
 * out of free-form model calls while allowing model-only analysis and
 * feasibility questions to stay frictionless.
 */
public final class LaboratoryAiChatRouter {
    public enum Kind {
        CONVERSATION,
        ANALYSIS,
        ACTION
    }

    public enum ModeHint {
        CREATION,
        LEARNING
    }

    public static final class Route {
        public final Kind kind;
        public final ModeHint modeHint;
        public final String reasonCode;

        private Route(Kind kind, ModeHint modeHint, String reasonCode) {
            this.kind = kind;
            this.modeHint = modeHint;
            this.reasonCode = reasonCode;
        }
    }

    private static final String[] ACTION_PREFIXES = {
        "crie ", "criar ", "faça ", "faca ", "gere ", "gerar ",
        "execute ", "executa ", "rodar ", "rode ", "teste ", "testar ",
        "altere ", "alterar ", "mude ", "modifique ", "modificar ",
        "salve ", "salvar ", "importe ", "importar ", "instale ", "instalar ",
        "apague ", "apagar ", "remova ", "remover ", "corrija ", "corrigir ",
        "implemente ", "implementar ", "construa ", "construir "
    };

    private static final String[] LEARNING_PREFIXES = {
        "analise ", "analisar ", "estude ", "estudar ", "aprenda ",
        "aprender ", "investigue ", "investigar ", "diagnostique ",
        "diagnosticar ", "pesquise ", "pesquisar ", "verifique ", "verificar ",
        "teste ", "testar "
    };

    private static final String[] ANALYSIS_ONLY_PREFIXES = {
        "analise se ", "analisar se ", "avalie se ", "avaliar se ",
        "me diga se ", "diga se ", "como funcionaria ", "como poderia funcionar ",
        "monte um plano ", "faça um plano ", "faca um plano ",
        "crie um plano ", "qual seria o plano ", "qual seria a melhor forma ",
        "qual seria o melhor caminho "
    };

    private static final String[] ANALYSIS_MARKERS = {
        "é viável", "e viavel", "seria viável", "seria viavel",
        "viabilidade", "faz sentido fazer", "vale a pena fazer"
    };

    private static final String[] ANALYSIS_ESCALATION_MARKERS = {
        " e execute", " e executa", " e rode", " e teste",
        " e implemente", " e aplique", " e altere", " e modifique",
        " e salve", " e instale", " e remova", " e apague",
        " depois execute", " depois rode", " depois teste",
        " depois implemente", " depois aplique", " depois altere",
        " agora execute", " agora rode", " agora teste",
        " agora implemente", " já execute", " ja execute",
        " já implemente", " ja implemente"
    };

    private static final String[] APP_TARGETS = {
        "app", "aplicativo", "projeto", "código", "codigo", "script",
        "planejador", "modelo", "ferramenta", "mundo", "3d", "arquivo",
        "goal lock", "permiss", "laboratório", "laboratorio", "teste"
    };

    private LaboratoryAiChatRouter() {}

    public static Route route(String message) {
        String normalized = normalize(message);
        if (normalized.isEmpty()) {
            return new Route(
                Kind.CONVERSATION,
                ModeHint.CREATION,
                "EMPTY_OR_WHITESPACE");
        }

        boolean analysisIntent =
            startsWithAny(normalized, ANALYSIS_ONLY_PREFIXES)
                || containsAny(normalized, ANALYSIS_MARKERS);
        boolean escalatesToAction =
            containsAny(normalized, ANALYSIS_ESCALATION_MARKERS);

        if (analysisIntent && !escalatesToAction) {
            return new Route(
                Kind.ANALYSIS,
                ModeHint.LEARNING,
                "MODEL_ONLY_ANALYSIS");
        }

        ModeHint hint = startsWithAny(
            normalized, LEARNING_PREFIXES)
                ? ModeHint.LEARNING
                : ModeHint.CREATION;

        if (startsWithAny(normalized, ACTION_PREFIXES)
                || startsWithAny(normalized, LEARNING_PREFIXES)) {
            return new Route(
                Kind.ACTION,
                hint,
                escalatesToAction
                    ? "ANALYSIS_ESCALATED_TO_ACTION"
                    : "EXPLICIT_ACTION_PREFIX");
        }

        boolean mentionsTarget = containsAny(normalized, APP_TARGETS);
        boolean asksToAct =
            normalized.contains("quero que você ")
                || normalized.contains("quero que voce ")
                || normalized.contains("você pode ")
                || normalized.contains("voce pode ")
                || normalized.contains("pode fazer ")
                || normalized.contains("pode criar ")
                || normalized.contains("pode testar ")
                || normalized.contains("pode analisar ")
                || normalized.contains("preciso que ")
                || normalized.contains("vamos fazer ")
                || normalized.contains("vamos criar ")
                || normalized.contains("vamos testar ");

        if (mentionsTarget && asksToAct) {
            return new Route(
                Kind.ACTION,
                hint,
                "ACTION_REQUEST_WITH_APP_TARGET");
        }

        return new Route(
            Kind.CONVERSATION,
            ModeHint.CREATION,
            "NO_HIGH_CONFIDENCE_ACTION");
    }

    private static String normalize(String value) {
        if (value == null) return "";
        return value.trim()
            .toLowerCase(Locale.ROOT)
            .replaceAll("\\s+", " ");
    }

    private static boolean startsWithAny(
            String value, String[] prefixes) {
        for (String prefix : prefixes) {
            if (value.startsWith(prefix)) return true;
        }
        return false;
    }

    private static boolean containsAny(
            String value, String[] parts) {
        for (String part : parts) {
            if (value.contains(part)) return true;
        }
        return false;
    }
}
