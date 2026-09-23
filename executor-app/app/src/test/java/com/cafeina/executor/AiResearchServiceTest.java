package com.cafeina.executor;
import static org.junit.Assert.*; import java.util.*; import org.junit.Test;
public final class AiResearchServiceTest {
 @Test public void providerResultsAreDefensivelyCopied(){List<AiResearchFinding> backing=new ArrayList<>();backing.add(new AiResearchFinding("s","c",Collections.singletonList("src")));AiResearchService s=new AiResearchService((p,q)->backing);List<AiResearchFinding> out=s.research("p","q");backing.clear();assertEquals(1,out.size());assertThrows(UnsupportedOperationException.class,()->out.clear());}
 @Test public void nullProviderResultBecomesEmpty(){AiResearchService s=new AiResearchService((p,q)->null);assertTrue(s.research("p","q").isEmpty());}
 @Test public void findingCopiesSourceIds(){List<String> ids=new ArrayList<>();ids.add("a");AiResearchFinding f=new AiResearchFinding("s","c",ids);ids.add("b");assertEquals(Collections.singletonList("a"),f.sourceIds);}
}
