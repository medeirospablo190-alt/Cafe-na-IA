package com.cafeina.executor;

import java.util.Collections;
import java.util.LinkedHashSet;
import java.util.Set;

public final class AiCapabilitySet {
    private final Set<String> granted;
    public AiCapabilitySet(Set<String> granted) {
        LinkedHashSet<String> copy=new LinkedHashSet<>();
        if(granted!=null) for(String c:granted){ if(c==null||c.trim().isEmpty()) throw new IllegalArgumentException("capability is required"); copy.add(c); }
        this.granted=Collections.unmodifiableSet(copy);
    }
    public static AiCapabilitySet none(){ return new AiCapabilitySet(Collections.emptySet()); }
    public boolean allows(String c){ return c!=null&&!c.trim().isEmpty()&&granted.contains(c); }
    public Set<String> granted(){ return granted; }
    public void require(String c){ if(!allows(c)) throw new SecurityException("capability not granted: "+c); }
}
