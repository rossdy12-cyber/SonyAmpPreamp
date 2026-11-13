package com.ross.tether;

import android.content.ActivityNotFoundException;
import android.content.Intent;
import android.net.Uri;
import android.view.Gravity;
import android.view.View;
import android.widget.Button;
import android.widget.FrameLayout;
import android.widget.LinearLayout;
import android.widget.TextView;

import org.osmdroid.events.MapEventsReceiver;
import org.osmdroid.tileprovider.tilesource.TileSourceFactory;
import org.osmdroid.util.BoundingBox;
import org.osmdroid.util.GeoPoint;
import org.osmdroid.views.CustomZoomButtonsController;
import org.osmdroid.views.MapView;
import org.osmdroid.views.overlay.MapEventsOverlay;

import java.util.ArrayList;
import java.util.List;

/** The live map: everyone in the circle, saved places, and a panel with details for the selected person. */
final class MapScreen extends Screen {
    private final MapView map;
    private final MapOverlays.Members membersOverlay;
    private final MapOverlays.Places placesOverlay;
    private final LinearLayout panel;
    private final TextView panelTitle;
    private final TextView panelLine1;
    private final TextView panelLine2;
    private String selectedId = "";
    private boolean fitted;

    MapScreen(MainActivity host) {
        super(host);
        FrameLayout frame = new FrameLayout(host);

        map = new MapView(host);
        map.setTileSource(TileSourceFactory.MAPNIK);
        map.setMultiTouchControls(true);
        map.getZoomController().setVisibility(CustomZoomButtonsController.Visibility.NEVER);
        map.getController().setZoom(5.5);
        map.getController().setCenter(new GeoPoint(54.0, -2.5));

        map.getOverlays().add(new MapEventsOverlay(new MapEventsReceiver() {
            @Override
            public boolean singleTapConfirmedHelper(GeoPoint p) {
                select(null);
                return true;
            }

            @Override
            public boolean longPressHelper(GeoPoint p) {
                MapScreen.this.host.addPlaceAt(p.getLatitude(), p.getLongitude());
                return true;
            }
        }));
        placesOverlay = new MapOverlays.Places(host);
        membersOverlay = new MapOverlays.Members(host, new MapOverlays.MemberTap() {
            @Override
            public void onMember(Models.Member m) {
                select(m);
            }
        });
        map.getOverlays().add(placesOverlay);
        map.getOverlays().add(membersOverlay);
        frame.addView(map, new FrameLayout.LayoutParams(Util.MATCH, Util.MATCH));

        // Fit-all button, top right.
        Button fit = Util.button(host, "Fit all", new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                fitAll();
            }
        });
        fit.setTextSize(13);
        FrameLayout.LayoutParams fp = new FrameLayout.LayoutParams(Util.WRAP, Util.WRAP, Gravity.TOP | Gravity.END);
        fp.setMargins(0, Util.dp(host, 12), Util.dp(host, 12), 0);
        frame.addView(fit, fp);

        TextView hint = Util.text(host, "Long-press the map to add a place", 11, 0xFFFFFFFF);
        hint.setBackgroundColor(0x99000000);
        hint.setPadding(Util.dp(host, 8), Util.dp(host, 3), Util.dp(host, 8), Util.dp(host, 3));
        FrameLayout.LayoutParams hp = new FrameLayout.LayoutParams(Util.WRAP, Util.WRAP, Gravity.TOP | Gravity.START);
        hp.setMargins(Util.dp(host, 12), Util.dp(host, 12), 0, 0);
        frame.addView(hint, hp);

        // Details panel, bottom.
        panel = Util.column(host);
        panel.setBackground(Util.rounded(host, Util.PANEL, Util.LINE, 14));
        panel.setPadding(Util.dp(host, 16), Util.dp(host, 12), Util.dp(host, 16), Util.dp(host, 12));
        panel.setVisibility(View.GONE);
        panelTitle = Util.text(host, "", 20, Util.BONE);
        panelTitle.setTypeface(android.graphics.Typeface.SERIF);
        panelLine1 = Util.text(host, "", 14, Util.BONE);
        panelLine2 = Util.text(host, "", 13, Util.MUTED);
        panel.addView(panelTitle);
        panel.addView(panelLine1);
        panel.addView(panelLine2);
        LinearLayout buttons = Util.row(host);
        Button dir = Util.button(host, "Directions", new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                directions();
            }
        });
        Button hist = Util.ghost(host, "Timeline", new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                if (!selectedId.isEmpty()) MapScreen.this.host.openHistory(selectedId);
            }
        });
        buttons.addView(dir, Util.lpMargins(host, 0, Util.WRAP, 0, 10, 6, 0));
        ((LinearLayout.LayoutParams) dir.getLayoutParams()).weight = 1f;
        buttons.addView(hist, Util.lpMargins(host, 0, Util.WRAP, 6, 10, 0, 0));
        ((LinearLayout.LayoutParams) hist.getLayoutParams()).weight = 1f;
        panel.addView(buttons, Util.lp(Util.MATCH, Util.WRAP));
        FrameLayout.LayoutParams pp = new FrameLayout.LayoutParams(Util.MATCH, Util.WRAP, Gravity.BOTTOM);
        pp.setMargins(Util.dp(host, 10), 0, Util.dp(host, 10), Util.dp(host, 10));
        frame.addView(panel, pp);

        root = frame;
    }

    @Override
    void onShow() {
        map.onResume();
        onCircle();
    }

    @Override
    void onHide() {
        map.onPause();
    }

    @Override
    void destroy() {
        map.onDetach();
    }

    @Override
    void onCircle() {
        membersOverlay.data = new ArrayList<>(host.members);
        membersOverlay.selectedId = selectedId;
        placesOverlay.data = new ArrayList<>(host.places);
        if (!fitted && hasAnyLocation()) {
            fitted = true;
            fitAll();
        }
        if (!selectedId.isEmpty()) {
            Models.Member m = host.memberById(selectedId);
            if (m != null) fillPanel(m);
        }
        map.invalidate();
    }

    private boolean hasAnyLocation() {
        for (Models.Member m : host.members) if (m.loc != null) return true;
        return false;
    }

    private void fitAll() {
        List<GeoPoint> pts = new ArrayList<>();
        for (Models.Member m : host.members) if (m.loc != null) pts.add(new GeoPoint(m.loc.lat, m.loc.lon));
        if (pts.isEmpty()) {
            Util.toast(ctx, "Nobody has shared a location yet.");
            return;
        }
        final BoundingBox box = BoundingBox.fromGeoPoints(pts);
        if (pts.size() == 1 || (box.getLatitudeSpan() < 0.0002 && box.getLongitudeSpan() < 0.0002)) {
            // One person, or everyone in the same spot: a bounding box would have no size.
            map.getController().setZoom(16.0);
            map.getController().animateTo(pts.get(0));
            return;
        }
        map.post(new Runnable() {
            @Override
            public void run() {
                map.zoomToBoundingBox(box, true, Util.dp(ctx, 70));
            }
        });
    }

    void focusMember(String id) {
        Models.Member m = host.memberById(id);
        if (m == null || m.loc == null) {
            Util.toast(ctx, "No location for that person yet.");
            return;
        }
        select(m);
        map.getController().setZoom(16.0);
        map.getController().animateTo(new GeoPoint(m.loc.lat, m.loc.lon));
    }

    void focusPoint(double lat, double lon) {
        map.getController().setZoom(16.0);
        map.getController().animateTo(new GeoPoint(lat, lon));
    }

    private void select(Models.Member m) {
        selectedId = m == null ? "" : m.id;
        membersOverlay.selectedId = selectedId;
        if (m == null) {
            panel.setVisibility(View.GONE);
        } else {
            fillPanel(m);
            panel.setVisibility(View.VISIBLE);
        }
        map.invalidate();
    }

    private void fillPanel(Models.Member m) {
        panelTitle.setText(m.name);
        if (m.paused) {
            panelLine1.setText("Sharing is paused");
            panelLine2.setText(m.pausedSince > 0 ? "Since " + Util.rel(m.pausedSince) : "");
            return;
        }
        if (m.loc == null) {
            panelLine1.setText("No location yet");
            panelLine2.setText("");
            return;
        }
        Models.Loc l = m.loc;
        String where = l.placeName.isEmpty() ? "Not at a saved place" : "At " + l.placeName;
        StringBuilder parts = new StringBuilder(where);
        String act = Util.prettyActivity(l.activity);
        if (!act.isEmpty()) parts.append(" · ").append(act);
        if (l.speed >= 1.0) parts.append(" · ").append(Util.mph(l.speed));
        panelLine1.setText(parts.toString());
        StringBuilder second = new StringBuilder();
        if (l.battery >= 0) {
            second.append(Math.round(l.battery * 100)).append("%").append(l.charging ? " charging" : " battery").append(" · ");
        }
        second.append("updated ").append(Util.rel(l.ts));
        panelLine2.setText(second.toString());
    }

    private void directions() {
        Models.Member m = host.memberById(selectedId);
        if (m == null || m.loc == null) return;
        String label = Uri.encode(m.name);
        Uri geo = Uri.parse("geo:" + m.loc.lat + "," + m.loc.lon + "?q=" + m.loc.lat + "," + m.loc.lon + "(" + label + ")");
        try {
            ctx.startActivity(new Intent(Intent.ACTION_VIEW, geo));
        } catch (ActivityNotFoundException e) {
            Uri web = Uri.parse("https://www.openstreetmap.org/?mlat=" + m.loc.lat + "&mlon=" + m.loc.lon + "#map=17/" + m.loc.lat + "/" + m.loc.lon);
            try {
                ctx.startActivity(new Intent(Intent.ACTION_VIEW, web));
            } catch (ActivityNotFoundException ignored) {
                Util.toast(ctx, "No maps app found.");
            }
        }
    }
}
