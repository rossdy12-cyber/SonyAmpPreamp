package com.ross.tether;

import android.view.View;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

import org.json.JSONArray;
import org.json.JSONObject;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;

/** The feed of arrivals, departures, check-ins and SOS alerts. */
final class ActivityScreen extends Screen {
    private final LinearLayout list;
    private final TextView status;
    private boolean loading;

    ActivityScreen(MainActivity host) {
        super(host);
        ScrollView scroll = new ScrollView(host);
        scroll.setBackgroundColor(Util.BG);
        LinearLayout col = Util.column(host);
        int pad = Util.dp(host, 16);
        col.setPadding(pad, pad, pad, pad);
        scroll.addView(col);

        col.addView(Util.heading(host, "Alerts"));
        status = Util.text(host, "", 13, Util.MUTED);
        col.addView(status, Util.lpMargins(host, Util.MATCH, Util.WRAP, 0, 2, 0, 8));
        Button refresh = Util.ghost(host, "Refresh", new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                load();
            }
        });
        col.addView(refresh, Util.lp(Util.MATCH, Util.WRAP));
        list = Util.column(host);
        col.addView(list, Util.lpMargins(host, Util.MATCH, Util.WRAP, 0, 12, 0, 0));
        root = scroll;
    }

    @Override
    void onShow() {
        load();
    }

    private void load() {
        if (loading) return;
        loading = true;
        status.setText("Loading…");
        // No `since`: the server then returns the latest 50 events (oldest first within that window).
        host.call("GET", "/v1/events?limit=50", null, new Bg.Done<JSONObject>() {
            @Override
            public void done(JSONObject r, Exception e) {
                loading = false;
                if (e != null) {
                    status.setText("Couldn't load alerts.");
                    return;
                }
                List<Models.Event> events = new ArrayList<>();
                JSONArray a = r.optJSONArray("events");
                if (a != null) {
                    for (int i = 0; i < a.length(); i++) {
                        JSONObject o = a.optJSONObject(i);
                        if (o != null) events.add(Models.Event.from(o));
                    }
                }
                Collections.reverse(events); // newest first
                render(events);
            }
        });
    }

    private void render(List<Models.Event> events) {
        list.removeAllViews();
        status.setText(events.isEmpty() ? "Nothing yet. Arrivals, departures and check-ins show up here." : "");
        for (final Models.Event e : events) {
            LinearLayout row = Util.column(ctx);
            boolean sos = "sos".equals(e.kind);
            row.setBackground(Util.rounded(ctx, sos ? 0xFF2A0508 : Util.PANEL, sos ? Util.CRIMSON : Util.LINE, 12));
            int pad = Util.dp(ctx, 14);
            row.setPadding(pad, pad, pad, pad);
            row.addView(Util.text(ctx, e.title(), 16, sos ? Util.CRIMSON_LIGHT : Util.BONE));
            String detail = Util.rel(e.ts);
            if (!e.text.isEmpty() && !"sos".equals(e.kind)) detail = e.text + " · " + detail;
            row.addView(Util.text(ctx, detail, 13, Util.MUTED));
            if (e.hasLocation()) {
                row.setOnClickListener(new View.OnClickListener() {
                    @Override
                    public void onClick(View v) {
                        host.showMapAtLatLon(e.lat, e.lon);
                    }
                });
            }
            list.addView(row, Util.lpMargins(ctx, Util.MATCH, Util.WRAP, 0, 0, 0, 8));
        }
    }
}
