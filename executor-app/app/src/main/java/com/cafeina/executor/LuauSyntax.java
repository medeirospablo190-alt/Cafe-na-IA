package com.cafeina.executor;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.HashSet;
import java.util.List;
import java.util.Set;

/** Lightweight, dependency-free lexer for editor decoration; never executes source. */
public final class LuauSyntax {
    public enum Kind { KEYWORD, BUILTIN, STRING, COMMENT, NUMBER }

    public static final class Token {
        public final int start;
        public final int end;
        public final Kind kind;

        Token(int start, int end, Kind kind) {
            this.start = start;
            this.end = end;
            this.kind = kind;
        }
    }

    private static final Set<String> KEYWORDS = Collections.unmodifiableSet(new HashSet<>(
        Arrays.asList("and", "break", "continue", "do", "else", "elseif", "end",
            "export", "false", "for", "function", "if", "in", "local", "nil",
            "not", "or", "repeat", "return", "then", "true", "type", "until", "while")
    ));
    private static final Set<String> BUILTINS = Collections.unmodifiableSet(new HashSet<>(
        Arrays.asList("assert", "error", "fs", "ipairs", "math", "pairs", "pcall",
            "print", "require", "select", "string", "table", "task", "tonumber",
            "tostring", "type", "typeof", "warn", "xpcall")
    ));

    private LuauSyntax() {
    }

    /**
     * Highlight at most maxCharacters to bound per-keystroke CPU and allocations.
     * Tokens never overlap, including strings containing apparent comments or keywords.
     */
    public static List<Token> scan(CharSequence source, int maxCharacters) {
        int length = Math.min(source.length(), Math.max(0, maxCharacters));
        List<Token> tokens = new ArrayList<>();
        for (int i = 0; i < length;) {
            char ch = source.charAt(i);
            int start = i;

            if (ch == '-' && i + 1 < length && source.charAt(i + 1) == '-') {
                int open = longBracketOpen(source, i + 2, length);
                if (open >= 0) {
                    i = longBracketEnd(source, i + 2 + open + 2, length, open);
                } else {
                    i += 2;
                    while (i < length && source.charAt(i) != '\n') i++;
                }
                tokens.add(new Token(start, i, Kind.COMMENT));
                continue;
            }

            if (ch == '"' || ch == '\'') {
                char quote = ch;
                i++;
                while (i < length) {
                    char current = source.charAt(i++);
                    if (current == '\\' && i < length) {
                        i++;
                    } else if (current == quote || current == '\n') {
                        break;
                    }
                }
                tokens.add(new Token(start, i, Kind.STRING));
                continue;
            }

            int longOpen = ch == '[' ? longBracketOpen(source, i, length) : -1;
            if (longOpen >= 0) {
                i = longBracketEnd(source, i + longOpen + 2, length, longOpen);
                tokens.add(new Token(start, i, Kind.STRING));
                continue;
            }

            if (Character.isDigit(ch) && (i == 0 || !isWord(source.charAt(i - 1)))) {
                i++;
                while (i < length) {
                    char next = source.charAt(i);
                    if (!Character.isLetterOrDigit(next) && next != '.' && next != '_') break;
                    i++;
                }
                tokens.add(new Token(start, i, Kind.NUMBER));
                continue;
            }

            if (isWordStart(ch)) {
                i++;
                while (i < length && isWord(source.charAt(i))) i++;
                String name = source.subSequence(start, i).toString();
                if (KEYWORDS.contains(name)) {
                    tokens.add(new Token(start, i, Kind.KEYWORD));
                } else if (BUILTINS.contains(name)) {
                    tokens.add(new Token(start, i, Kind.BUILTIN));
                }
                continue;
            }
            i++;
        }
        return tokens;
    }

    private static boolean isWordStart(char ch) {
        return ch == '_' || Character.isLetter(ch);
    }

    private static boolean isWord(char ch) {
        return isWordStart(ch) || Character.isDigit(ch);
    }

    /** Returns the number of '=' signs in a Lua long-bracket opener, or -1. */
    private static int longBracketOpen(CharSequence source, int start, int length) {
        if (start >= length || source.charAt(start) != '[') return -1;
        int index = start + 1;
        while (index < length && source.charAt(index) == '=') index++;
        if (index >= length || source.charAt(index) != '[') return -1;
        return index - start - 1;
    }

    private static int longBracketEnd(CharSequence source, int start, int length, int equals) {
        for (int i = start; i < length; i++) {
            if (source.charAt(i) != ']') continue;
            int end = i + 1;
            int remaining = equals;
            while (end < length && remaining > 0 && source.charAt(end) == '=') {
                end++;
                remaining--;
            }
            if (remaining == 0 && end < length && source.charAt(end) == ']') return end + 1;
        }
        return length;
    }
}
