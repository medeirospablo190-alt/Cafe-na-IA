package com.cafeina.executor;
import java.util.*;
public final class AiToolCatalog {
 private final Map<String,AiToolDescriptor> descriptors=new LinkedHashMap<>();
 public synchronized void register(AiToolDescriptor d){if(d==null)throw new IllegalArgumentException("descriptor required");if(descriptors.containsKey(d.name))throw new IllegalArgumentException("duplicate descriptor: "+d.name);descriptors.put(d.name,d);}
 public synchronized AiToolDescriptor require(String name){AiToolDescriptor d=descriptors.get(name);if(d==null)throw new IllegalArgumentException("unknown descriptor: "+name);return d;}
 public synchronized List<AiToolDescriptor> list(){return Collections.unmodifiableList(new ArrayList<>(descriptors.values()));}
}
