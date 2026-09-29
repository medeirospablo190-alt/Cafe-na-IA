package com.cafeina.executor;

import android.content.Context;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.Typeface;
import android.text.Editable;
import android.text.Layout;
import android.text.TextWatcher;
import android.text.style.ForegroundColorSpan;
import android.widget.EditText;

import java.util.Arrays;

/**
 * Native mobile code editor with a fixed line-number gutter and bounded Luau coloring.
 * The source is always the ordinary EditText content; decoration never rewrites code.
 */
public final class LuauCodeEditor extends EditText {
    private static final int MAX_HIGHLIGHT_CHARACTERS = 24000;
    private static final long HIGHLIGHT_DELAY_MS = 130;
    private static final int GUTTER_BACKGROUND = Color.rgb(30, 32, 42);
    private static final int GUTTER_TEXT = Color.rgb(151, 157, 174);

    private final Paint gutterPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint numberPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Runnable highlightRunnable = this::highlightSource;
    private int[] lineStarts = {0};
    private int lineCount = 1;
    private int gutterWidth;

    public LuauCodeEditor(Context context) {
        super(context);
        setTypeface(Typeface.MONOSPACE);
        numberPaint.setTypeface(Typeface.MONOSPACE);
        numberPaint.setTextAlign(Paint.Align.RIGHT);
        numberPaint.setColor(GUTTER_TEXT);
        gutterWidth = dp(46);
        super.setPadding(gutterWidth + dp(12), dp(12), dp(12), dp(12));

        addTextChangedListener(new TextWatcher() {
            @Override public void beforeTextChanged(CharSequence source, int start, int count, int after) {
            }

            @Override public void onTextChanged(CharSequence source, int start, int before, int count) {
            }

            @Override public void afterTextChanged(Editable source) {
                updateLineStarts(source);
                removeCallbacks(highlightRunnable);
                postDelayed(highlightRunnable, HIGHLIGHT_DELAY_MS);
                invalidate();
            }
        });
    }

    private void updateLineStarts(CharSequence source) {
        int[] starts = new int[Math.max(16, Math.min(source.length() + 1, 128))];
        int count = 1;
        starts[0] = 0;
        for (int i = 0; i < source.length(); i++) {
            if (source.charAt(i) != '\n') continue;
            if (count == starts.length) starts = Arrays.copyOf(starts, starts.length * 2);
            starts[count++] = i + 1;
        }
        lineStarts = starts;
        lineCount = count;

        numberPaint.setTextSize(getTextSize() * 0.70f);
        int needed = Math.max(dp(46),
            (int) Math.ceil(numberPaint.measureText(Integer.toString(count))) + dp(22));
        if (needed != gutterWidth) {
            gutterWidth = needed;
            super.setPadding(gutterWidth + dp(12), getPaddingTop(), getPaddingRight(), getPaddingBottom());
        }
    }

    private void highlightSource() {
        Editable source = getText();
        if (source == null) return;
        for (SyntaxColorSpan previous : source.getSpans(0, source.length(), SyntaxColorSpan.class)) {
            source.removeSpan(previous);
        }
        for (LuauSyntax.Token token : LuauSyntax.scan(source, MAX_HIGHLIGHT_CHARACTERS)) {
            source.setSpan(new SyntaxColorSpan(colorFor(token.kind)), token.start, token.end,
                android.text.Spanned.SPAN_EXCLUSIVE_EXCLUSIVE);
        }
    }

    private int colorFor(LuauSyntax.Kind kind) {
        switch (kind) {
            case KEYWORD: return Color.rgb(185, 159, 255);
            case BUILTIN: return Color.rgb(124, 203, 244);
            case STRING: return Color.rgb(166, 215, 159);
            case COMMENT: return Color.rgb(143, 154, 173);
            case NUMBER: return Color.rgb(255, 194, 145);
            default: return getCurrentTextColor();
        }
    }

    @Override
    protected void onDraw(Canvas canvas) {
        super.onDraw(canvas);
        Layout layout = getLayout();
        if (layout == null) return;

        gutterPaint.setColor(GUTTER_BACKGROUND);
        canvas.drawRect(0, 0, gutterWidth, getHeight(), gutterPaint);
        gutterPaint.setColor(GUTTER_TEXT);
        gutterPaint.setStrokeWidth(dp(1));
        canvas.drawLine(gutterWidth - dp(1), 0, gutterWidth - dp(1), getHeight(), gutterPaint);

        numberPaint.setTextSize(getTextSize() * 0.70f);
        int scroll = getScrollY();
        int first = layout.getLineForVertical(Math.max(0, scroll - getTotalPaddingTop()));
        int last = layout.getLineForVertical(Math.max(0, scroll + getHeight()));
        for (int visualLine = first; visualLine <= last; visualLine++) {
            int sourceOffset = layout.getLineStart(visualLine);
            int logicalLine = Arrays.binarySearch(lineStarts, 0, lineCount, sourceOffset);
            if (logicalLine < 0) continue; // Wrapped visual line: do not invent a line number.
            float baseline = getTotalPaddingTop() + layout.getLineBaseline(visualLine) - scroll;
            if (baseline >= 0 && baseline <= getHeight() + getTextSize()) {
                canvas.drawText(Integer.toString(logicalLine + 1),
                    gutterWidth - dp(12), baseline, numberPaint);
            }
        }
    }

    @Override
    protected void onDetachedFromWindow() {
        removeCallbacks(highlightRunnable);
        super.onDetachedFromWindow();
    }

    private int dp(int value) {
        return Math.round(value * getResources().getDisplayMetrics().density);
    }

    private static final class SyntaxColorSpan extends ForegroundColorSpan {
        SyntaxColorSpan(int color) {
            super(color);
        }
    }
}
