package com.ross.tether;

import android.app.AlertDialog;
import android.content.DialogInterface;
import android.os.Handler;
import android.os.Looper;
import android.os.SystemClock;
import android.view.Gravity;
import android.view.MotionEvent;
import android.view.View;
import android.widget.Button;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

import org.json.JSONObject;

/** Everyone in the circle, plus check-in and the hold-to-send SOS button. */
final class CircleScreen extends Screen {
    private static final long HOLD_MS = 3000L;

    // Not final: the hold-timer callback below is created in a field initialiser and reads `sos`.
    private LinearLayout list;
    private Button sos;
    private Button cancelSos;
    private TextView status;
    private final Handler handler = new Handler(Looper.getMainLooper());
    private long holdStart;
    private boolean holding;

    private final Runnable holdTick = new Runnable() {
        @Override
        public void run() {
            if (!holding) return;
            long elapsed = SystemClock.uptimeMillis() - holdStart;
            if (elapsed >= HOLD_MS) {
                holding = false;
                Util.vibrate(ctx, 500);
                sendSos();
                resetSosLabel();
                return;
            }
            sos.setText(String.format(java.util.Locale.UK, "Keep holding… %.1f", (HOLD_MS - elapsed) / 1000.0));
            handler.postDelayed(this, 100);
        }
    };

    CircleScreen(MainActivity host) {
        super(host);
        ScrollView scroll = new ScrollView(host);
        LinearLayout col = Util.column(host);
        int pad = Util.dp(host, 16);
        col.setPadding(pad, pad, pad, pad);
        scroll.addView(col);
        scroll.setBackgroundColor(Util.BG);

        col.addView(Util.heading(host, "Your circle"));
        status = Util.text(host, "", 13, Util.MUTED);
        col.addView(status, Util.lpMargins(host, Util.MATCH, Util.WRAP, 0, 2, 0, 10));

        list = Util.column(host);
        col.addView(list, Util.lp(Util.MATCH, Util.WRAP));

        col.addView(Util.heading(host, "Safety"), Util.lpMargins(host, Util.MATCH, Util.WRAP, 0, 22, 0, 8));
        Button checkin = Util.ghost(host, "Check in: \"I'm here\"", new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                checkIn();
            }
        });
        col.addView(checkin, Util.lp(Util.MATCH, Util.WRAP));

        sos = new Button(host);
        sos.setAllCaps(false);
        sos.setTextColor(0xFFFFFFFF);
        sos.setTextSize(18);
        sos.setBackground(Util.rounded(host, 0xFF8B0000, 0xFFDC143C, 12));
        resetSosLabel();
        sos.setOnTouchListener(new View.OnTouchListener() {
            @Override
            public boolean onTouch(View v, MotionEvent ev) {
                switch (ev.getActionMasked()) {
                    case MotionEvent.ACTION_DOWN:
                        holding = true;
                        holdStart = SystemClock.uptimeMillis();
                        Util.vibrate(ctx, 40);
                        handler.post(holdTick);
                        return true;
                    case MotionEvent.ACTION_UP:
                    case MotionEvent.ACTION_CANCEL:
                        if (holding) {
                            holding = false;
                            handler.removeCallbacks(holdTick);
                            resetSosLabel();
                        }
                        return true;
                    default:
                        return true;
                }
            }
        });
        col.addView(sos, Util.lpMargins(host, Util.MATCH, Util.dp(host, 72), 0, 12, 0, 0));
        TextView sosHint = Util.text(host, "Hold for 3 seconds to alert everyone with your location.", 12, Util.MUTED);
        col.addView(sosHint, Util.lpMargins(host, Util.MATCH, Util.WRAP, 0, 4, 0, 0));

        cancelSos = Util.ghost(host, "Cancel SOS (I'm safe)", new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                cancelSosNow();
            }
        });
        col.addView(cancelSos, Util.lpMargins(host, Util.MATCH, Util.WRAP, 0, 12, 0, 0));

        root = scroll;
    }

    private void resetSosLabel() {
        sos.setText("SOS — hold 3 seconds");
    }

    @Override
    void onShow() {
        cancelSos.setVisibility(host.prefs.sosActive() ? View.VISIBLE : View.GONE);
        onCircle();
    }

    @Override
    void onHide() {
        holding = false;
        handler.removeCallbacks(holdTick);
        resetSosLabel();
    }

    @Override
    void onCircle() {
        list.removeAllViews();
        for (final Models.Member m : host.members) {
            LinearLayout row = Util.row(ctx);
            row.setGravity(Gravity.CENTER_VERTICAL);
            row.setBackground(Util.rounded(ctx, Util.PANEL, Util.LINE, 12));
            int p = Util.dp(ctx, 12);
            row.setPadding(p, p, p, p);

            TextView dot = Util.text(ctx, m.initial(), 18, 0xFFFFFFFF);
            dot.setGravity(Gravity.CENTER);
            dot.setTypeface(android.graphics.Typeface.DEFAULT_BOLD);
            dot.setBackground(Util.oval(Util.color(m.color), 0, 0));
            row.addView(dot, Util.lp(Util.dp(ctx, 44), Util.dp(ctx, 44)));

            LinearLayout info = Util.column(ctx);
            boolean mine = m.id.equals(host.prefs.memberId());
            info.addView(Util.text(ctx, m.name + (mine ? " (you)" : ""), 17, Util.BONE));
            info.addView(Util.text(ctx, describe(m), 13, Util.MUTED));
            row.addView(info, Util.lpMargins(ctx, 0, Util.WRAP, 12, 0, 0, 0));
            ((LinearLayout.LayoutParams) info.getLayoutParams()).weight = 1f;

            row.setOnClickListener(new View.OnClickListener() {
                @Override
                public void onClick(View v) {
                    host.showMapAt(m.id);
                }
            });
            list.addView(row, Util.lpMargins(ctx, Util.MATCH, Util.WRAP, 0, 0, 0, 8));
        }
        status.setText(host.members.isEmpty() ? "Loading…" : host.members.size() + " in the circle. Tap someone to see them on the map.");
        cancelSos.setVisibility(host.prefs.sosActive() ? View.VISIBLE : View.GONE);
    }

    private static String describe(Models.Member m) {
        if (m.paused) return "Sharing paused";
        if (m.loc == null) return "No location yet";
        StringBuilder s = new StringBuilder(m.loc.placeName.isEmpty() ? "On the move" : "At " + m.loc.placeName);
        if (m.loc.battery >= 0) s.append(" · ").append(Math.round(m.loc.battery * 100)).append("%");
        s.append(" · ").append(Util.rel(m.loc.ts));
        return s.toString();
    }

    private void checkIn() {
        final EditText input = Util.edit(ctx, "Optional note (On my way, Home safe…)");
        LinearLayout box = Util.column(ctx);
        int pad = Util.dp(ctx, 20);
        box.setPadding(pad, Util.dp(ctx, 8), pad, 0);
        box.addView(input, Util.lp(Util.MATCH, Util.WRAP));
        Dialogs.builder(host).setTitle("Check in").setView(box)
                .setNegativeButton("Cancel", null)
                .setPositiveButton("Send", new DialogInterface.OnClickListener() {
                    @Override
                    public void onClick(DialogInterface dialog, int which) {
                        JSONObject body = Util.obj("text", input.getText().toString().trim());
                        double[] where = host.bestLocation();
                        try {
                            if (where != null) {
                                body.put("lat", where[0]);
                                body.put("lon", where[1]);
                            }
                        } catch (Exception ignored) {
                        }
                        host.call("POST", "/v1/checkin", body, new Bg.Done<JSONObject>() {
                            @Override
                            public void done(JSONObject value, Exception error) {
                                Util.toast(ctx, error == null ? "Checked in." : "Couldn't check in. Try again.");
                            }
                        });
                    }
                }).show();
    }

    private void sendSos() {
        double[] where = host.bestLocation();
        if (where == null) {
            Util.toast(ctx, "Waiting for a location fix. Try again in a moment.");
            return;
        }
        JSONObject body = Util.obj("lat", where[0], "lon", where[1], "text", "SOS from " + host.prefs.name());
        host.call("POST", "/v1/sos", body, new Bg.Done<JSONObject>() {
            @Override
            public void done(JSONObject value, Exception error) {
                if (error == null) {
                    host.prefs.setSosActive(true);
                    cancelSos.setVisibility(View.VISIBLE);
                    Util.toast(ctx, "SOS sent to your circle.");
                } else {
                    Util.toast(ctx, "SOS could not be sent. Check your connection and try again.");
                }
            }
        });
    }

    private void cancelSosNow() {
        host.call("POST", "/v1/sos/cancel", null, new Bg.Done<JSONObject>() {
            @Override
            public void done(JSONObject value, Exception error) {
                if (error == null) {
                    host.prefs.setSosActive(false);
                    cancelSos.setVisibility(View.GONE);
                    Util.toast(ctx, "SOS cancelled.");
                } else {
                    Util.toast(ctx, "Couldn't cancel the SOS. Try again.");
                }
            }
        });
    }
}
