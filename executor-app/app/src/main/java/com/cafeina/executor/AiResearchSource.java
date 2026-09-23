package com.cafeina.executor;
public final class AiResearchSource {
 public final String id,uri,title,provenance; public final long retrievedAt;
 public AiResearchSource(String id,String uri,String title,String provenance,long retrievedAt){if(id==null||id.trim().isEmpty()||provenance==null||provenance.trim().isEmpty())throw new IllegalArgumentException("research source identity required");this.id=id;this.uri=uri;this.title=title;this.provenance=provenance;this.retrievedAt=retrievedAt;}
}
