package com.ross.tether;

import android.view.View;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

import org.json.JSONArray;
import org.json.JSONObject;
import org.osmdroid.tileprovider.tilesource.TileSourceFactory;
import org.osmdroid.util.BoundingBox;
import org.osmdroid.util.GeoPoint;
import org.osmdroid.views.CustomZoomButtonsController;
import org.osmdroid.views.MapView;

import java.net.URLEncoder;
import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Date;
import java.util.List;
import java.util.Locale;
import java.util.TimeZone;

/** A day timeline for one person: where they stayed, the trips between, and the path on a map. */
final class HistoryScreen extends Screen {
    private final MapView map;
    private final MapOverlays.PathLine pathOverlay;
    private final Button memberButton;
    private final Button dateButton;
    private final TextView summary;
    private final LinearLayout items;

    private String memberId = "";
    private String date = "";
    private final List<String> dates = new ArrayList<>();
    private boolean loadedOnce;

    HistoryScreen(MainActivity host) {
        super(host);
        LinearLayout col = Util.column(host);
        col.setBackgroundColor(Util.BG);
        int pad = Util.dp(host, 12);
        col.setPadding(pad, pad, pad, 0);

        LinearLayout top = Util.row(host);
        memberButton = Util.ghost(host, "Person", new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                pickMember();
            }
        });
        dateButton = Util.ghost(host, "Date", new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                pickDate();
            }
        });
        top.addView(memberButton, Util.lpMargins(host, 0, Util.WRAP, 0, 0, 4, 0));
        ((LinearLayout.LayoutParams) memberButton.getLayoutParams()).weight = 1f;
        top.addView(dateButton, Util.lpMargins(host, 0, Util.WRAP, 4, 0, 0, 0));
        ((LinearLayout.LayoutParams) dateButton.getLayoutParams()).weight = 1f;
        col.addView(top, Util.lp(Util.MATCH, Util.WRAP));

        summary = Util.text(host, "", 13, Util.MUTED);
        col.addView(summary, Util.lpMargins(host, Util.MATCH, Util.WRAP, 0, 8, 0, 8));

        map = new MapView(host);
        map.setTileSource(TileSourceFactory.MAPNIK);
        map.setMultiTouchControls(true);
        map.getZoomController().setVisibility(CustomZoomButtonsController.Visibility.NEVER);
        map.getController().setZoom(5.5);
        map.getController().setCenter(new GeoPoint(54.0, -2.5));
        pathOverlay = new MapOverlays.PathLine(host);
        map.getOverlays().add(pathOverlay);
        col.addView(map, Util.lp(Util.MATCH, Util.dp(host, 230)));

        ScrollView scroll = new ScrollView(host);
        items = Util.column(host);
        items.setPadding(0, Util.dp(host, 10), 0, Util.dp(host, 10));
        scroll.addView(items);
        col.addView(scroll, Util.lp(Util.MATCH, 0, 1f));
        root = col;
    }

    void setMember(String id) {
        memberId = id;
        date = "";
        dates.clear();
        loadedOnce = false;
        loadDates();
    }

    @Override
    void onShow() {
        map.onResume();
        if (memberId.isEmpty()) memberId = host.prefs.memberId();
        updateButtons();
        if (!loadedOnce) loadDates();
    }

    @Override
    void onHide() {
        map.onPause();
    }

    @Override
    void destroy() {
        map.onDetach();
    }

    private void updateButtons() {
        Models.Member m = host.memberById(memberId);
        memberButton.setText(m == null ? "Person" : m.name);
        dateButton.setText(date.isEmpty() ? "Date" : date);
    }

    private void pickMember() {
        if (host.members.isEmpty()) return;
        final String[] names = new String[host.members.size()];
        for (int i = 0; i < names.length; i++) names[i] = host.members.get(i).name;
        Dialogs.choose(host, "Whose timeline?", names, new Dialogs.IntPick() {
            @Override
            public void picked(int index) {
                setMember(host.members.get(index).id);
            }
        });
    }

    private void pickDate() {
        if (dates.isEmpty()) {
            Util.toast(ctx, "No recorded days for this person yet.");
            return;
        }
        final String[] labels = dates.toArray(new String[0]);
        Dialogs.choose(host, "Pick a day", labels, new Dialogs.IntPick() {
            @Override
            public void picked(int index) {
                date = labels[index];
                updateButtons();
                loadTimeline();
            }
        });
    }

    private void loadDates() {
        loadedOnce = true;
        updateButtons();
        summary.setText("Loading…");
        host.call("GET", "/v1/dates?member=" + memberId, null, new Bg.Done<JSONObject>() {
            @Override
            public void done(JSONObject r, Exception e) {
                dates.clear();
                if (e == null) {
                    JSONArray a = r.optJSONArray("dates");
                    if (a != null) for (int i = 0; i < a.length(); i++) dates.add(a.optString(i));
                }
                if (dates.isEmpty()) {
                    date = "";
                    updateButtons();
                    summary.setText(e == null ? "No recorded days yet." : "Couldn't load the timeline.");
                    items.removeAllViews();
                    pathOverlay.path = new ArrayList<>();
                    pathOverlay.stays = new ArrayList<>();
                    map.invalidate();
                    return;
                }
                if (date.isEmpty() || !dates.contains(date)) date = dates.get(0);
                updateButtons();
                loadTimeline();
            }
        });
    }

    private void loadTimeline() {
        String tz = TimeZone.getDefault().getID();
        String enc;
        try {
            enc = URLEncoder.encode(tz, "UTF-8");
        } catch (Exception e) {
            enc = "Europe%2FLondon";
        }
        summary.setText("Loading…");
        host.call("GET", "/v1/timeline?member=" + memberId + "&date=" + date + "&tz=" + enc, null, new Bg.Done<JSONObject>() {
            @Override
            public void done(JSONObject r, Exception e) {
                if (e != null) {
                    summary.setText("Couldn't load that day.");
                    return;
                }
                render(r);
            }
        });
    }

    private void render(JSONObject r) {
        items.removeAllViews();
        List<double[]> path = new ArrayList<>();
        JSONArray pts = r.optJSONArray("points");
        if (pts != null) {
            for (int i = 0; i < pts.length(); i++) {
                JSONArray p = pts.optJSONArray(i);
                if (p != null && p.length() >= 2) path.add(new double[]{p.optDouble(0), p.optDouble(1)});
            }
        }
        List<double[]> stays = new ArrayList<>();
        double totalDistance = 0;
        int tripCount = 0;
        int stayCount = 0;
        JSONArray arr = r.optJSONArray("items");
        if (arr != null) {
            for (int i = 0; i < arr.length(); i++) {
                JSONObject it = arr.optJSONObject(i);
                if (it == null) continue;
                String type = it.optString("type");
                double start = it.optDouble("start", 0);
                double end = it.optDouble("end", 0);
                if ("stay".equals(type)) {
                    stayCount++;
                    stays.add(new double[]{it.optDouble("lat", 0), it.optDouble("lon", 0)});
                    String where = Models.str(it, "place_name");
                    if (where.isEmpty()) where = "Stayed here";
                    addRow(stayCount + ". " + where, Util.clock(start) + " – " + Util.clock(end) + " · " + Util.duration(end - start));
                } else if ("trip".equals(type)) {
                    tripCount++;
                    double dist = it.optDouble("distance", 0);
                    totalDistance += dist;
                    String mode = Models.str(it, "mode");
                    String line = Util.clock(start) + " – " + Util.clock(end) + " · " + Util.distance(dist);
                    if (it.optDouble("max_speed", 0) > 1) line += " · max " + Util.mph(it.optDouble("max_speed", 0));
                    if (!mode.isEmpty() && !"unknown".equals(mode)) line += " · " + mode;
                    addRow("Trip", line);
                }
            }
        }
        if (stayCount + tripCount == 0) {
            summary.setText("Nothing recorded on " + date + ".");
        } else {
            summary.setText(stayCount + " stays · " + tripCount + " trips · " + Util.distance(totalDistance));
        }
        pathOverlay.path = path;
        pathOverlay.stays = stays;
        zoomToPath(path);
        map.invalidate();
    }

    private void addRow(String title, String detail) {
        LinearLayout row = Util.column(ctx);
        row.setBackground(Util.rounded(ctx, Util.PANEL, Util.LINE, 10));
        int pad = Util.dp(ctx, 12);
        row.setPadding(pad, pad, pad, pad);
        row.addView(Util.text(ctx, title, 16, Util.BONE));
        row.addView(Util.text(ctx, detail, 13, Util.MUTED));
        items.addView(row, Util.lpMargins(ctx, Util.MATCH, Util.WRAP, 0, 0, 0, 8));
    }

    private void zoomToPath(List<double[]> path) {
        if (path.isEmpty()) return;
        if (path.size() == 1) {
            map.getController().setZoom(16.0);
            map.getController().setCenter(new GeoPoint(path.get(0)[0], path.get(0)[1]));
            return;
        }
        List<GeoPoint> pts = new ArrayList<>();
        for (double[] p : path) pts.add(new GeoPoint(p[0], p[1]));
        final BoundingBox box = BoundingBox.fromGeoPoints(pts);
        if (box.getLatitudeSpan() < 0.0002 && box.getLongitudeSpan() < 0.0002) {
            map.getController().setZoom(16.0);
            map.getController().setCenter(pts.get(0));
            return;
        }
        map.post(new Runnable() {
            @Override
            public void run() {
                map.zoomToBoundingBox(box, false, Util.dp(ctx, 40));
            }
        });
    }

    /** Today's date in the phone's time zone, for callers that need a default. */
    static String today() {
        return new SimpleDateFormat("yyyy-MM-dd", Locale.UK).format(new Date());
    }
}
