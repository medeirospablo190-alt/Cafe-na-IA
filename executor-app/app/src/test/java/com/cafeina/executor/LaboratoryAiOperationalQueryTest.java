package com.cafeina.executor;

import static org.junit.Assert.assertEquals;

import org.junit.Test;

public final class LaboratoryAiOperationalQueryTest {
    @Test
    public void recognizesStatusQuestions() {
        assertEquals(
            LaboratoryAiOperationalQuery.Kind.STATUS,
            LaboratoryAiOperationalQuery.classify(
                "O que está fazendo agora?"));
        assertEquals(
            LaboratoryAiOperationalQuery.Kind.STATUS,
            LaboratoryAiOperationalQuery.classify(
                "Qual o andamento do teste?"));
    }

    @Test
    public void recognizesEtaQuestions() {
        assertEquals(
            LaboratoryAiOperationalQuery.Kind.ETA,
            LaboratoryAiOperationalQuery.classify(
                "Quanto tempo falta?"));
        assertEquals(
            LaboratoryAiOperationalQuery.Kind.ETA,
            LaboratoryAiOperationalQuery.classify(
                "Tem uma estimativa?"));
    }

    @Test
    public void recognizesDiagnosticQuestions() {
        assertEquals(
            LaboratoryAiOperationalQuery.Kind.DIAGNOSTIC,
            LaboratoryAiOperationalQuery.classify(
                "Onde travou?"));
        assertEquals(
            LaboratoryAiOperationalQuery.Kind.DIAGNOSTIC,
            LaboratoryAiOperationalQuery.classify(
                "Faz um diagnóstico"));
    }

    @Test
    public void ordinaryConversationIsNotOperational() {
        assertEquals(
            LaboratoryAiOperationalQuery.Kind.NONE,
            LaboratoryAiOperationalQuery.classify(
                "Oi, tudo bem?"));
        assertEquals(
            LaboratoryAiOperationalQuery.Kind.NONE,
            LaboratoryAiOperationalQuery.classify(
                "Explique o que é um Goal Lock"));
    }
}
