package com.cafeina.executor;

import static org.junit.Assert.assertEquals;

import org.junit.Test;

public final class LaboratoryAiChatRouterTest {
    @Test
    public void casualGreetingStaysConversationOnly() {
        LaboratoryAiChatRouter.Route route =
            LaboratoryAiChatRouter.route("Oi, tudo bem?");

        assertEquals(
            LaboratoryAiChatRouter.Kind.CONVERSATION,
            route.kind);
    }

    @Test
    public void explicitAppActionUsesControlledPath() {
        LaboratoryAiChatRouter.Route route =
            LaboratoryAiChatRouter.route(
                "Teste o planejador local e me diga onde travou");

        assertEquals(
            LaboratoryAiChatRouter.Kind.ACTION,
            route.kind);
        assertEquals(
            LaboratoryAiChatRouter.ModeHint.LEARNING,
            route.modeHint);
    }

    @Test
    public void creationRequestUsesCreationModeHint() {
        LaboratoryAiChatRouter.Route route =
            LaboratoryAiChatRouter.route(
                "Crie uma ferramenta para validar meus scripts");

        assertEquals(
            LaboratoryAiChatRouter.Kind.ACTION,
            route.kind);
        assertEquals(
            LaboratoryAiChatRouter.ModeHint.CREATION,
            route.modeHint);
    }

    @Test
    public void ordinaryQuestionDoesNotEnterExecutionPath() {
        LaboratoryAiChatRouter.Route route =
            LaboratoryAiChatRouter.route(
                "O que é um Goal Lock e para que ele serve?");

        assertEquals(
            LaboratoryAiChatRouter.Kind.CONVERSATION,
            route.kind);
    }

    @Test
    public void feasibilityQuestionUsesModelOnlyAnalysis() {
        LaboratoryAiChatRouter.Route route =
            LaboratoryAiChatRouter.route(
                "Esse processo é viável para um modelo local pequeno?");

        assertEquals(
            LaboratoryAiChatRouter.Kind.ANALYSIS,
            route.kind);
        assertEquals(
            LaboratoryAiChatRouter.ModeHint.LEARNING,
            route.modeHint);
        assertEquals("MODEL_ONLY_ANALYSIS", route.reasonCode);
    }

    @Test
    public void explicitAnalyzeWhetherRequestUsesModelOnlyAnalysis() {
        LaboratoryAiChatRouter.Route route =
            LaboratoryAiChatRouter.route(
                "Analise se esse processo é viável e monte um plano conceitual");

        assertEquals(
            LaboratoryAiChatRouter.Kind.ANALYSIS,
            route.kind);
    }

    @Test
    public void planOnlyRequestDoesNotAskForExecutionPermissions() {
        LaboratoryAiChatRouter.Route route =
            LaboratoryAiChatRouter.route(
                "Faça um plano para organizar esse processo");

        assertEquals(
            LaboratoryAiChatRouter.Kind.ANALYSIS,
            route.kind);
    }

    @Test
    public void analysisThatAlsoRequestsExecutionUsesControlledPath() {
        LaboratoryAiChatRouter.Route route =
            LaboratoryAiChatRouter.route(
                "Analise se é viável e depois implemente no app");

        assertEquals(
            LaboratoryAiChatRouter.Kind.ACTION,
            route.kind);
    }
}
