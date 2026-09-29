package com.cafeina.executor;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import org.junit.Test;

import java.util.List;

public final class LuauSyntaxTest {
    @Test
    public void recognizesKeywordsBuiltinsNumbersAndComments() {
        String source = "local score = 42\nprint(score) -- note\nreturn score";
        List<LuauSyntax.Token> tokens = LuauSyntax.scan(source, source.length());

        assertKind(tokens, source.indexOf("local"), LuauSyntax.Kind.KEYWORD);
        assertKind(tokens, source.indexOf("42"), LuauSyntax.Kind.NUMBER);
        assertKind(tokens, source.indexOf("print"), LuauSyntax.Kind.BUILTIN);
        assertKind(tokens, source.indexOf("-- note"), LuauSyntax.Kind.COMMENT);
        assertKind(tokens, source.indexOf("return"), LuauSyntax.Kind.KEYWORD);
    }

    @Test
    public void stringContentsCannotBecomeKeywordsOrComments() {
        String source = "local value = \"return -- not a comment\"";
        List<LuauSyntax.Token> tokens = LuauSyntax.scan(source, source.length());

        assertKind(tokens, source.indexOf("local"), LuauSyntax.Kind.KEYWORD);
        assertKind(tokens, source.indexOf("\"return"), LuauSyntax.Kind.STRING);
        assertEquals(2, tokens.size());
    }

    @Test
    public void longCommentsAndLongStringsStayIndependentOfFollowingCode() {
        String source = "--[=[ return\nfake ]=]\nreturn [[true]]";
        List<LuauSyntax.Token> tokens = LuauSyntax.scan(source, source.length());

        assertKind(tokens, 0, LuauSyntax.Kind.COMMENT);
        assertKind(tokens, source.lastIndexOf("return"), LuauSyntax.Kind.KEYWORD);
        assertKind(tokens, source.indexOf("[[true]]"), LuauSyntax.Kind.STRING);
        assertEquals(3, tokens.size());
    }

    @Test
    public void scannerDoesNotMistakeIdentifierForKeyword() {
        String source = "returning = 123";
        List<LuauSyntax.Token> tokens = LuauSyntax.scan(source, source.length());

        assertEquals(1, tokens.size());
        assertKind(tokens, source.indexOf("123"), LuauSyntax.Kind.NUMBER);
    }

    @Test
    public void boundsColoringWithoutChangingSource() {
        String source = "local value = 123";
        List<LuauSyntax.Token> tokens = LuauSyntax.scan(source, 5);

        assertEquals(1, tokens.size());
        assertEquals(0, tokens.get(0).start);
        assertEquals(5, tokens.get(0).end);
        assertEquals("local value = 123", source);
        assertTrue(LuauSyntax.scan(source, 0).isEmpty());
        assertFalse(LuauSyntax.scan(source, source.length()).isEmpty());
    }

    private static void assertKind(List<LuauSyntax.Token> tokens, int index, LuauSyntax.Kind kind) {
        for (LuauSyntax.Token token : tokens) {
            if (token.start <= index && index < token.end) {
                assertEquals(kind, token.kind);
                return;
            }
        }
        throw new AssertionError("No " + kind + " token covers index " + index);
    }
}
