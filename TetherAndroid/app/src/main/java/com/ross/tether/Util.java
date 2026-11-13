package com.ross.tether;

import android.content.Context;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.os.Build;
import android.os.VibrationEffect;
import android.os.Vibrator;
import android.text.InputType;
import android.view.View;
import android.view.ViewGroup;
import android.widget.Button;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.TextView;
import android.widget.Toast;

import org.json.JSONObject;

import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.Locale;

/** Colours, view builders and small formatting helpers shared by every screen. */
public final class Util {
    private Util() {}

    public static final int BG = 0xFF0A0A0A;
    public static final int PANEL = 0xFF140808;
    public static final int CRIMSON = 0xFFB3001B;
    public static final int CRIMSON_LIGHT = 0xFFDC143C;
    public static final int BONE = 0xFFE8DCC8;
    public static final int MUTED = 0xFFA89880;
    public static final int LINE = 0xFF3A0A10;

    public static final int MATCH = ViewGroup.LayoutParams.MATCH_PARENT;
    public static final int WRAP = ViewGroup.LayoutParams.WRAP_CONTENT;

    /** Member colours offered at sign-up (hex, no #). */
    public static final String[] COLORS = {
            "DC143C", "E8590C", "F2B01E", "2F9E44", "1C7ED6", "7048E8", "D6336C", "868E96"
    };

    public static int dp(Context c, float v) {
        return Math.round(v * c.getResources().getDisplayMetrics().density);
    }

    public static int color(String hex) {
        try {
            return Color.parseColor("#" + hex);
        } catch (Exception e) {
            return CRIMSON_LIGHT;
        }
    }

    public static GradientDrawable rounded(Context c, int fill, int stroke, float radiusDp) {
        GradientDrawable g = new GradientDrawable();
        g.setColor(fill);
        g.setCornerRadius(dp(c, radiusDp));
        if (stroke != 0) g.setStroke(dp(c, 1), stroke);
        return g;
    }

    public static GradientDrawable oval(int fill, int stroke, int strokePx) {
        GradientDrawable g = new GradientDrawable();
        g.setShape(GradientDrawable.OVAL);
        g.setColor(fill);
        if (stroke != 0) g.setStroke(strokePx, stroke);
        return g;
    }

    public static TextView text(Context c, CharSequence s, float sp, int color) {
        TextView t = new TextView(c);
        t.setText(s);
        t.setTextSize(sp);
        t.setTextColor(color);
        return t;
    }

    public static TextView heading(Context c, CharSequence s) {
        TextView t = text(c, s, 24, CRIMSON_LIGHT);
        t.setTypeface(Typeface.SERIF);
        return t;
    }

    public static Button button(Context c, String label, View.OnClickListener l) {
        Button b = new Button(c);
        b.setText(label);
        b.setAllCaps(false);
        b.setTextColor(0xFFFFFFFF);
        b.setTextSize(16);
        b.setBackground(rounded(c, CRIMSON, 0, 10));
        b.setPadding(dp(c, 16), dp(c, 10), dp(c, 16), dp(c, 10));
        b.setOnClickListener(l);
        return b;
    }

    public static Button ghost(Context c, String label, View.OnClickListener l) {
        Button b = button(c, label, l);
        b.setTextColor(CRIMSON_LIGHT);
        b.setBackground(rounded(c, 0x00000000, CRIMSON, 10));
        return b;
    }

    public static EditText edit(Context c, String hint) {
        EditText e = new EditText(c);
        e.setHint(hint);
        e.setHintTextColor(MUTED);
        e.setTextColor(BONE);
        e.setTextSize(16);
        e.setSingleLine(true);
        e.setInputType(InputType.TYPE_CLASS_TEXT);
        e.setBackground(rounded(c, PANEL, LINE, 8));
        e.setPadding(dp(c, 12), dp(c, 10), dp(c, 12), dp(c, 10));
        return e;
    }

    public static LinearLayout column(Context c) {
        LinearLayout l = new LinearLayout(c);
        l.setOrientation(LinearLayout.VERTICAL);
        return l;
    }

    public static LinearLayout row(Context c) {
        LinearLayout l = new LinearLayout(c);
        l.setOrientation(LinearLayout.HORIZONTAL);
        return l;
    }

    public static LinearLayout.LayoutParams lp(int w, int h) {
        return new LinearLayout.LayoutParams(w, h);
    }

    public static LinearLayout.LayoutParams lp(int w, int h, float weight) {
        return new LinearLayout.LayoutParams(w, h, weight);
    }

    public static LinearLayout.LayoutParams lpMargins(Context c, int w, int h, int l, int t, int r, int b) {
        LinearLayout.LayoutParams p = new LinearLayout.LayoutParams(w, h);
        p.setMargins(dp(c, l), dp(c, t), dp(c, r), dp(c, b));
        return p;
    }

    public static void toast(Context c, String s) {
        Toast.makeText(c, s, Toast.LENGTH_LONG).show();
    }

    public static String rel(double ts) {
        long d = (long) (System.currentTimeMillis() / 1000.0 - ts);
        if (d < 0) d = 0;
        if (d < 60) return "just now";
        if (d < 3600) return (d / 60) + " min ago";
        if (d < 86400) return (d / 3600) + " h ago";
        return (d / 86400) + " d ago";
    }

    public static String mph(double metresPerSecond) {
        return String.format(Locale.UK, "%.0f mph", metresPerSecond * 2.23694);
    }

    public static String distance(double metres) {
        double miles = metres * 0.000621371;
        if (miles < 0.1) return String.format(Locale.UK, "%.0f yd", metres * 1.09361);
        return String.format(Locale.UK, "%.1f mi", miles);
    }

    public static String duration(double seconds) {
        long s = (long) seconds;
        long h = s / 3600;
        long m = (s % 3600) / 60;
        if (h > 0) return h + " h " + m + " min";
        if (m > 0) return m + " min";
        return s + " s";
    }

    public static String clock(double ts) {
        return new SimpleDateFormat("HH:mm", Locale.UK).format(new Date((long) (ts * 1000)));
    }

    public static String prettyActivity(String a) {
        if (a == null) return "";
        switch (a) {
            case "still": return "Still";
            case "walking": return "Walking";
            case "running": return "Running";
            case "cycling": return "Cycling";
            case "driving": return "Driving";
            default: return "";
        }
    }

    public static void vibrate(Context c, long ms) {
        try {
            Vibrator v = (Vibrator) c.getSystemService(Context.VIBRATOR_SERVICE);
            if (v == null || !v.hasVibrator()) return;
            if (Build.VERSION.SDK_INT >= 26) {
                v.vibrate(VibrationEffect.createOneShot(ms, VibrationEffect.DEFAULT_AMPLITUDE));
            } else {
                v.vibrate(ms);
            }
        } catch (Exception ignored) {
        }
    }

    public static String readAll(InputStream in) throws java.io.IOException {
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        byte[] buf = new byte[8192];
        int n;
        while ((n = in.read(buf)) > 0) out.write(buf, 0, n);
        in.close();
        return out.toString("UTF-8");
    }

    /** Builds a JSONObject from alternating key, value arguments. */
    public static JSONObject obj(Object... kv) {
        JSONObject o = new JSONObject();
        try {
            for (int i = 0; i + 1 < kv.length; i += 2) o.put((String) kv[i], kv[i + 1]);
        } catch (Exception ignored) {
        }
        return o;
    }
}
