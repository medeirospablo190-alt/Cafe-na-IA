package com.cafeina.executor;

import java.text.Normalizer;
import java.util.Locale;

/**
 * Recognizes read-only questions about the current controlled AI action.
 *
 * This classifier never routes to tools or the model. It exists so the user
 * can ask status/ETA/diagnostic questions while a planner or TestAgent run is
 * active without starting a second operation.
 */
public final class LaboratoryAiOperationalQuery {
    public enum Kind {
        NONE,
        STATUS,
        ETA,
        DIAGNOSTIC,
        TIMELINE,
        READINESS
    }

    private LaboratoryAiOperationalQuery() {}

    public static Kind classify(String message) {
        String value = normalize(message);
        if (value.isEmpty()) return Kind.NONE;

        if (containsAny(
                value,
                "esta pronto",
                "ta pronto",
                "esta pronta",
                "ta pronta",
                "pronto para executar",
                "pronta para executar",
                "pode executar",
                "pode comecar",
                "pode iniciar",
                "ja pode executar",
                "ja da para executar",
                "ja da pra executar",
                "esta tudo pronto")) {
            return Kind.READINESS;
        }

        if (containsAny(
                value,
                "linha do tempo",
                "historico da acao",
                "historico desta acao",
                "o que aconteceu nessa acao",
                "o que aconteceu nesta acao",
                "oq aconteceu nessa acao")) {
            return Kind.TIMELINE;
        }

        if (containsAny(
                value,
                "diagnostico",
                "onde travou",
                "onde parou",
                "o que deu errado",
                "oq deu errado",
                "qual erro",
                "deu erro",
                "por que falhou",
                "porque falhou",
                "por que parou",
                "porque parou")) {
            return Kind.DIAGNOSTIC;
        }

        if (containsAny(
                value,
                "quanto falta",
                "quanto tempo falta",
                "tempo previsto",
                "tempo estimado",
                "previsao",
                "estimativa",
                "vai demorar",
                "falta muito",
                "eta")) {
            return Kind.ETA;
        }

        if (containsAny(
                value,
                "status",
                "andamento",
                "o que esta fazendo",
                "oq ta fazendo",
                "oq esta fazendo",
                "em que etapa",
                "qual etapa",
                "onde esta agora",
                "como esta o teste",
                "como esta a tarefa",
                "o que esta acontecendo",
                "oq ta acontecendo")) {
            return Kind.STATUS;
        }

        return Kind.NONE;
    }

    private static String normalize(String value) {
        if (value == null) return "";
        return Normalizer.normalize(
                value.trim().toLowerCase(Locale.ROOT),
                Normalizer.Form.NFD)
            .replaceAll("\\p{M}+", "")
            .replaceAll("\\s+", " ");
    }

    private static boolean containsAny(
            String value,
            String... markers) {
        for (String marker : markers) {
            if (value.contains(marker)) return true;
        }
        return false;
    }
}
