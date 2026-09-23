package com.cafeina.executor;
import static org.junit.Assert.*; import java.util.*; import org.junit.Test;
public final class AiResearchValidatorTest {
 @Test public void twoDistinctReferencesCorroborate(){AiResearchValidation v=new AiResearchValidator().validate(new AiResearchFinding("s","c",Arrays.asList("a","b")));assertEquals(AiResearchValidation.State.CORROBORATED,v.state);}
 @Test public void duplicateReferenceDoesNotCorroborate(){AiResearchValidation v=new AiResearchValidator().validate(new AiResearchFinding("s","c",Arrays.asList("a","a")));assertEquals(AiResearchValidation.State.CANDIDATE,v.state);}
 @Test public void unsourcedFindingRemainsCandidate(){assertEquals(AiResearchValidation.State.CANDIDATE,new AiResearchValidator().validate(new AiResearchFinding("s","c",Collections.emptyList())).state);}
}
