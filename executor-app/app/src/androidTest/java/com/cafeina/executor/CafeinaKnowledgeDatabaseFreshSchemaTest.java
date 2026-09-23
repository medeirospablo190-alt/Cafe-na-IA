package com.cafeina.executor;
import static org.junit.Assert.*;
import android.content.Context;
import android.database.Cursor;
import android.database.sqlite.SQLiteDatabase;
import androidx.test.core.app.ApplicationProvider;
import org.junit.*;
public final class CafeinaKnowledgeDatabaseFreshSchemaTest{
 private Context context; private CafeinaKnowledgeDatabase database;
 @Before public void setUp(){context=ApplicationProvider.getApplicationContext();context.deleteDatabase(CafeinaKnowledgeDatabase.DATABASE_NAME);database=new CafeinaKnowledgeDatabase(context);}
 @After public void tearDown(){database.close();context.deleteDatabase(CafeinaKnowledgeDatabase.DATABASE_NAME);}
 @Test public void freshV2ContainsKnowledgeLinksAndForeignKeys(){SQLiteDatabase db=database.getWritableDatabase();try(Cursor c=db.rawQuery("SELECT name FROM sqlite_master WHERE type='table' AND name='knowledge_links'",null)){assertTrue(c.moveToFirst());}try(Cursor c=db.rawQuery("PRAGMA foreign_keys",null)){assertTrue(c.moveToFirst());assertEquals(1,c.getInt(0));}}
}
