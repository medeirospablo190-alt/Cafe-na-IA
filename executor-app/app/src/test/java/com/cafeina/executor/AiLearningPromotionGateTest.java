package com.cafeina.executor;
import static org.junit.Assert.*; import org.junit.Test;
public final class AiLearningPromotionGateTest {
 @Test public void corroboratedCandidateEntersKnowledgeAsValidated(){AiLearningCandidate c=new AiLearningCandidate("p","s","c",AiResearchValidation.State.CORROBORATED);assertEquals(KnowledgeState.VALIDATED,new AiLearningPromotionGate().prepare(c).targetState);}
 @Test public void candidateEvidenceCannotEnterConsolidatedDirectly(){AiLearningCandidate c=new AiLearningCandidate("p","s","c",AiResearchValidation.State.CORROBORATED);assertThrows(IllegalArgumentException.class,()->new AiLearningPromotion(c,KnowledgeState.CONSOLIDATED));}
}
