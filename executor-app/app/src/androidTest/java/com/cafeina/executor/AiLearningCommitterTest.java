package com.cafeina.executor;
import static org.junit.Assert.*; import android.content.Context; import androidx.test.core.app.ApplicationProvider; import java.util.*; import org.junit.*;
public final class AiLearningCommitterTest {
 private Context context;private CafeinaKnowledgeDatabase db;
 @Before public void setUp(){context=ApplicationProvider.getApplicationContext();context.deleteDatabase(CafeinaKnowledgeDatabase.DATABASE_NAME);db=new CafeinaKnowledgeDatabase(context);}
 @After public void tearDown(){db.close();context.deleteDatabase(CafeinaKnowledgeDatabase.DATABASE_NAME);}
 @Test public void commitsCorroboratedLearningAsValidatedKnowledge(){KnowledgeRepository k=new KnowledgeRepository(db);AiLearningCandidate c=new AiLearningCandidate("p","subject","content",AiResearchValidation.State.CORROBORATED);AiLearningPromotion promotion=new AiLearningPromotionGate().prepare(c);long id=new AiLearningCommitter(k).commit(promotion,10);assertTrue(id>0);java.util.List<KnowledgeRepository.Entry> entries=k.list("p",KnowledgeState.VALIDATED);assertEquals(1,entries.size());assertEquals("subject",entries.get(0).subject);assertTrue(k.list("p",KnowledgeState.CONSOLIDATED).isEmpty());}
}
