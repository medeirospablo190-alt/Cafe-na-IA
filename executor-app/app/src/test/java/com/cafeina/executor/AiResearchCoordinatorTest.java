package com.cafeina.executor;
import static org.junit.Assert.*; import java.util.*; import org.junit.Test;
public final class AiResearchCoordinatorTest {
 @Test public void validatesEveryProviderFinding(){AiResearchService s=new AiResearchService((p,q)->Arrays.asList(new AiResearchFinding("one","x",Collections.singletonList("a")),new AiResearchFinding("two","y",Arrays.asList("a","b"))));AiResearchBatch b=new AiResearchCoordinator(s,new AiResearchValidator()).run("p","q");assertEquals(2,b.findings.size());assertEquals(AiResearchValidation.State.CANDIDATE,b.findings.get(0).state);assertEquals(AiResearchValidation.State.CORROBORATED,b.findings.get(1).state);assertThrows(UnsupportedOperationException.class,()->b.findings.clear());}
}
