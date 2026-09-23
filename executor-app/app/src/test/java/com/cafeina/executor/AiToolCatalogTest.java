package com.cafeina.executor;
import static org.junit.Assert.*; import java.util.*; import org.junit.Test;
public final class AiToolCatalogTest {
 @Test public void preservesRegistrationOrderAndDefensiveCapabilities(){Set<String> caps=new LinkedHashSet<>();caps.add("world.read");AiToolDescriptor d=new AiToolDescriptor("inspect","Inspect world",caps);caps.add("world.write");AiToolCatalog c=new AiToolCatalog();c.register(d);c.register(new AiToolDescriptor("query","Query",Collections.emptySet()));assertEquals(Arrays.asList("inspect","query"),Arrays.asList(c.list().get(0).name,c.list().get(1).name));assertFalse(d.requiredCapabilities.contains("world.write"));assertThrows(UnsupportedOperationException.class,()->d.requiredCapabilities.add("x"));}
 @Test public void rejectsDuplicateDescriptor(){AiToolCatalog c=new AiToolCatalog();c.register(new AiToolDescriptor("x","a",null));assertThrows(IllegalArgumentException.class,()->c.register(new AiToolDescriptor("x","b",null)));}
}
