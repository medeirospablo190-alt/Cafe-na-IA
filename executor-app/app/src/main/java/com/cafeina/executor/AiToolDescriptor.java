package com.cafeina.executor;
import java.util.*;
public final class AiToolDescriptor {
 public final String name,description; public final Set<String> requiredCapabilities;
 public AiToolDescriptor(String name,String description,Set<String> requiredCapabilities){
  if(name==null||name.trim().isEmpty()||description==null)throw new IllegalArgumentException("descriptor fields required");
  this.name=name;this.description=description;this.requiredCapabilities=Collections.unmodifiableSet(new LinkedHashSet<>(requiredCapabilities==null?Collections.emptySet():requiredCapabilities));
 }
}
