package com.cafeina.executor;
import java.util.*;
public final class AiResearchCoordinator {
 private final AiResearchService research; private final AiResearchValidator validator;
 public AiResearchCoordinator(AiResearchService research,AiResearchValidator validator){if(research==null||validator==null)throw new IllegalArgumentException("dependencies required");this.research=research;this.validator=validator;}
 public AiResearchBatch run(String projectId,String question){List<AiResearchValidation> out=new ArrayList<>();for(AiResearchFinding f:research.research(projectId,question))out.add(validator.validate(f));return new AiResearchBatch(projectId,question,out);}
}
