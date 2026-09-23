package com.cafeina.executor;
import java.util.List;
public interface AiMissionStore { void save(AiMissionRecord mission); AiMissionRecord get(String id); List<AiMissionRecord> listForProject(String projectId,int limit); }
