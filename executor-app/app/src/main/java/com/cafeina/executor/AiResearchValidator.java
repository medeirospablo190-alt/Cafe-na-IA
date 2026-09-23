package com.cafeina.executor;
import java.util.*;
public final class AiResearchValidator {
 public AiResearchValidation validate(AiResearchFinding finding){
  if(finding==null)throw new IllegalArgumentException("finding required");
  LinkedHashSet<String> unique=new LinkedHashSet<>();for(String id:finding.sourceIds)if(id!=null&&!id.trim().isEmpty())unique.add(id);
  if(unique.size()>=2)return new AiResearchValidation(finding,AiResearchValidation.State.CORROBORATED,"multiple independent source references");
  if(unique.size()==1)return new AiResearchValidation(finding,AiResearchValidation.State.CANDIDATE,"single source reference");
  return new AiResearchValidation(finding,AiResearchValidation.State.CANDIDATE,"no source reference");
 }
}
