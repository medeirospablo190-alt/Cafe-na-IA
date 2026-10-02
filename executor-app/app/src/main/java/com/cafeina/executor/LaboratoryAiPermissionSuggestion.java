package com.cafeina.executor;

import java.text.Normalizer;
import java.util.ArrayList;
import java.util.Collections;
import java.util.HashSet;
import java.util.List;
import java.util.Locale;
import java.util.Set;

/**
 * Deterministic least-privilege suggestion for task permissions.
 *
 * This class never grants permission. It only ranks already-STABLE,
 * already-globally-granted tools against words in the user's action request.
 */
public final class LaboratoryAiPermissionSuggestion {
    public static final class Result {
        public final List<String> suggestedToolIds;
        public final boolean confident;

        private Result(List<String> suggestedToolIds, boolean confident) {
            this.suggestedToolIds = Collections.unmodifiableList(
                new ArrayList<>(suggestedToolIds));
            this.confident = confident;
        }
    }

    private LaboratoryAiPermissionSuggestion() {}

    public static Result suggest(
            String request,
            List<LaboratoryAiToolController.Tool> tools) {
        if (request == null || tools == null || tools.isEmpty()) {
            return new Result(Collections.emptyList(), false);
        }

        Set<String> requestTerms = terms(request);
        if (requestTerms.isEmpty()) {
            return new Result(Collections.emptyList(), false);
        }

        List<String> selected = new ArrayList<>();
        int bestScore = 0;
        for (LaboratoryAiToolController.Tool tool : tools) {
            int score = score(requestTerms, tool);
            if (score > bestScore) {
                bestScore = score;
                selected.clear();
                selected.add(tool.toolId);
            } else if (score > 0 && score == bestScore) {
                selected.add(tool.toolId);
            }
        }

        // A single weak substring match is not enough to pre-check a tool.
        boolean confident = bestScore >= 2 && !selected.isEmpty();
        if (!confident) {
            return new Result(Collections.emptyList(), false);
        }
        return new Result(selected, true);
    }

    private static int score(
            Set<String> requestTerms,
            LaboratoryAiToolController.Tool tool) {
        int score = 0;
        Set<String> toolTerms = new HashSet<>();
        toolTerms.addAll(terms(tool.toolId));
        for (String capability : tool.capabilities) {
            toolTerms.addAll(terms(capability));
        }

        for (String term : requestTerms) {
            if (toolTerms.contains(term)) {
                score += 2;
                continue;
            }
            if (term.length() >= 5) {
                for (String toolTerm : toolTerms) {
                    if (toolTerm.length() >= 5
                            && (toolTerm.contains(term)
                                || term.contains(toolTerm))) {
                        score += 1;
                        break;
                    }
                }
            }
        }
        return score;
    }

    private static Set<String> terms(String value) {
        if (value == null) return Collections.emptySet();
        String normalized = Normalizer.normalize(
                value.toLowerCase(Locale.ROOT),
                Normalizer.Form.NFD)
            .replaceAll("\\p{M}+", "")
            .replaceAll("[^a-z0-9]+", " ")
            .trim();

        if (normalized.isEmpty()) {
            return Collections.emptySet();
        }

        Set<String> result = new HashSet<>();
        for (String term : normalized.split("\\s+")) {
            if (term.length() >= 3 && !stopWord(term)) {
                result.add(term);
            }
        }
        return result;
    }

    private static boolean stopWord(String term) {
        switch (term) {
            case "que":
            case "para":
            case "por":
            case "com":
            case "uma":
            case "uns":
            case "das":
            case "dos":
            case "esse":
            case "essa":
            case "este":
            case "esta":
            case "meu":
            case "minha":
            case "fazer":
            case "faca":
            case "criar":
            case "teste":
            case "testar":
                return true;
            default:
                return false;
        }
    }
}
