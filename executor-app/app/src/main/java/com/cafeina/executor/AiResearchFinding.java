package com.cafeina.executor;
import java.util.*;
public final class AiResearchFinding {
 public final String subject,content; public final List<String> sourceIds;
 public AiResearchFinding(String subject,String content,List<String> sourceIds){if(subject==null||subject.trim().isEmpty()||content==null||content.trim().isEmpty())throw new IllegalArgumentException("finding content required");this.subject=subject;this.content=content;this.sourceIds=Collections.unmodifiableList(new ArrayList<>(sourceIds==null?Collections.emptyList():sourceIds));}
}
