package com.ross.tether;

import android.view.Gravity;
import android.view.View;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

/** Saved places (Home, Work, School...) that trigger arrive and leave alerts. */
final class PlacesScreen extends Screen {
    private final LinearLayout list;
    private final TextView empty;

    PlacesScreen(MainActivity host) {
        super(host);
        ScrollView scroll = new ScrollView(host);
        scroll.setBackgroundColor(Util.BG);
        LinearLayout col = Util.column(host);
        int pad = Util.dp(host, 16);
        col.setPadding(pad, pad, pad, pad);
        scroll.addView(col);

        col.addView(Util.heading(host, "Places"));
        col.addView(Util.text(host, "Everyone is alerted when someone arrives at or leaves a place. You can also long-press the map to add one.",
                13, Util.MUTED), Util.lpMargins(host, Util.MATCH, Util.WRAP, 0, 2, 0, 12));

        Button add = Util.button(host, "Add a place at my location", new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                double[] where = PlacesScreen.this.host.bestLocation();
                if (where == null) {
                    Util.toast(ctx, "No location yet. Open the Map tab and wait for a fix, or long-press the map.");
                    return;
                }
                PlacesScreen.this.host.addPlaceAt(where[0], where[1]);
            }
        });
        col.addView(add, Util.lp(Util.MATCH, Util.WRAP));

        empty = Util.text(host, "", 14, Util.MUTED);
        col.addView(empty, Util.lpMargins(host, Util.MATCH, Util.WRAP, 0, 14, 0, 0));
        list = Util.column(host);
        col.addView(list, Util.lpMargins(host, Util.MATCH, Util.WRAP, 0, 8, 0, 0));
        root = scroll;
    }

    @Override
    void onShow() {
        onCircle();
    }

    @Override
    void onCircle() {
        list.removeAllViews();
        empty.setText(host.places.isEmpty() ? "No places yet." : "");
        for (final Models.Place p : host.places) {
            LinearLayout row = Util.row(ctx);
            row.setGravity(Gravity.CENTER_VERTICAL);
            row.setBackground(Util.rounded(ctx, Util.PANEL, Util.LINE, 12));
            int pad = Util.dp(ctx, 14);
            row.setPadding(pad, pad, pad, pad);
            LinearLayout info = Util.column(ctx);
            info.addView(Util.text(ctx, p.name, 17, Util.BONE));
            info.addView(Util.text(ctx, p.icon + " · " + p.radius + " m radius", 13, Util.MUTED));
            row.addView(info, Util.lp(0, Util.WRAP, 1f));
            row.addView(Util.text(ctx, "Edit", 14, Util.CRIMSON_LIGHT));
            row.setOnClickListener(new View.OnClickListener() {
                @Override
                public void onClick(View v) {
                    host.editPlace(p);
                }
            });
            list.addView(row, Util.lpMargins(ctx, Util.MATCH, Util.WRAP, 0, 0, 0, 8));
        }
    }
}
