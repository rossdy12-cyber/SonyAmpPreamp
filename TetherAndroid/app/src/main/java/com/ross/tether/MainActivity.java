package com.ross.tether;

import android.app.Activity;
import android.content.Context;
import android.content.Intent;
import android.location.Location;
import android.location.LocationManager;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.view.View;
import android.widget.FrameLayout;
import android.widget.LinearLayout;
import android.widget.TextView;

import org.json.JSONArray;
import org.json.JSONObject;
import org.osmdroid.config.Configuration;

import java.io.File;
import java.util.ArrayList;

/** The signed-in shell: six tabs, shared circle data, and a 15 second refresh while it is on screen. */
public class MainActivity extends Activity {
    public Prefs prefs;
    public Api api;
    public final ArrayList<Models.Member> members = new ArrayList<>();
    public final ArrayList<Models.Place> places = new ArrayList<>();

    private Screen[] screens;
    private TextView[] tabs;
    private int current = -1;
    private FrameLayout content;
    private TextView banner;
    private String circleError = "";
    private final Handler handler = new Handler(Looper.getMainLooper());

    private final Runnable poll = new Runnable() {
        @Override
        public void run() {
            refreshCircle();
            handler.postDelayed(this, 15000);
        }
    };

    private static final String[] TAB_NAMES = {"Map", "Circle", "Places", "History", "Alerts", "Settings"};

    @Override
    protected void onCreate(Bundle b) {
        super.onCreate(b);
        prefs = new Prefs(this);
        api = new Api(this);
        if (!prefs.isSignedIn()) {
            startActivity(new Intent(this, OnboardingActivity.class));
            finish();
            return;
        }
        Notifier.ensureChannels(this);

        Configuration cfg = Configuration.getInstance();
        cfg.load(getApplicationContext(), getSharedPreferences("osmdroid", MODE_PRIVATE));
        cfg.setUserAgentValue(getPackageName());
        File base = new File(getCacheDir(), "osmdroid");
        cfg.setOsmdroidBasePath(base);
        cfg.setOsmdroidTileCache(new File(base, "tiles"));

        LinearLayout rootLayout = Util.column(this);
        rootLayout.setBackgroundColor(Util.BG);

        banner = Util.text(this, "", 14, 0xFFFFFFFF);
        banner.setBackgroundColor(Util.CRIMSON);
        banner.setPadding(Util.dp(this, 14), Util.dp(this, 10), Util.dp(this, 14), Util.dp(this, 10));
        banner.setVisibility(View.GONE);
        rootLayout.addView(banner, Util.lp(Util.MATCH, Util.WRAP));

        content = new FrameLayout(this);
        rootLayout.addView(content, Util.lp(Util.MATCH, 0, 1f));

        LinearLayout bar = Util.row(this);
        bar.setBackgroundColor(Util.PANEL);
        tabs = new TextView[TAB_NAMES.length];
        for (int i = 0; i < TAB_NAMES.length; i++) {
            final int index = i;
            TextView t = Util.text(this, TAB_NAMES[i], 11, Util.MUTED);
            t.setGravity(android.view.Gravity.CENTER);
            t.setPadding(0, Util.dp(this, 14), 0, Util.dp(this, 14));
            t.setOnClickListener(new View.OnClickListener() {
                @Override
                public void onClick(View v) {
                    show(index);
                }
            });
            tabs[i] = t;
            bar.addView(t, Util.lp(0, Util.WRAP, 1f));
        }
        rootLayout.addView(bar, Util.lp(Util.MATCH, Util.WRAP));
        setContentView(rootLayout);

        screens = new Screen[]{
                new MapScreen(this), new CircleScreen(this), new PlacesScreen(this),
                new HistoryScreen(this), new ActivityScreen(this), new SettingsScreen(this)
        };
        show(0);
    }

    @Override
    protected void onResume() {
        super.onResume();
        if (screens == null) return;
        if (!prefs.isSignedIn()) {
            startActivity(new Intent(this, OnboardingActivity.class));
            finish();
            return;
        }
        if (Perms.hasFine(this) && !prefs.paused()) SharingService.start(this);
        updateBanner();
        refreshCircle();
        handler.removeCallbacks(poll);
        handler.postDelayed(poll, 15000);
        if (current >= 0) screens[current].onShow();
    }

    @Override
    protected void onPause() {
        super.onPause();
        handler.removeCallbacks(poll);
        if (screens != null && current >= 0) screens[current].onHide();
    }

    @Override
    protected void onDestroy() {
        if (screens != null) for (Screen s : screens) s.destroy();
        super.onDestroy();
    }

    @Override
    public void onBackPressed() {
        if (screens != null && current > 0) show(0);
        else super.onBackPressed();
    }

    // ---- navigation ----

    public void show(int index) {
        if (current == index) return;
        if (current >= 0) screens[current].onHide();
        content.removeAllViews();
        current = index;
        content.addView(screens[index].root, new FrameLayout.LayoutParams(Util.MATCH, Util.MATCH));
        screens[index].onShow();
        for (int i = 0; i < tabs.length; i++) {
            tabs[i].setTextColor(i == index ? Util.CRIMSON_LIGHT : Util.MUTED);
        }
    }

    public void showMapAt(String memberId) {
        show(0);
        ((MapScreen) screens[0]).focusMember(memberId);
    }

    public void showMapAtLatLon(double lat, double lon) {
        show(0);
        ((MapScreen) screens[0]).focusPoint(lat, lon);
    }

    public void openHistory(String memberId) {
        show(3);
        ((HistoryScreen) screens[3]).setMember(memberId);
    }

    // ---- data ----

    public void call(String method, String path, JSONObject body, Bg.Done<JSONObject> done) {
        final String m = method;
        final String p = path;
        final JSONObject b = body;
        Bg.async(this, new Bg.Work<JSONObject>() {
            @Override
            public JSONObject run() throws Exception {
                return api.call(m, p, b, true);
            }
        }, done);
    }

    public Models.Member me() {
        for (Models.Member m : members) if (m.id.equals(prefs.memberId())) return m;
        return null;
    }

    public Models.Member memberById(String id) {
        for (Models.Member m : members) if (m.id.equals(id)) return m;
        return null;
    }

    public void refreshCircle() {
        call("GET", "/v1/circle", null, new Bg.Done<JSONObject>() {
            @Override
            public void done(JSONObject r, Exception e) {
                if (screens == null) return;
                if (e != null) {
                    circleError = e instanceof Api.ApiException ? e.getMessage() : "Can't reach the server. Retrying…";
                    updateBanner();
                    return;
                }
                circleError = "";
                members.clear();
                places.clear();
                JSONArray ms = r.optJSONArray("members");
                if (ms != null) {
                    for (int i = 0; i < ms.length(); i++) {
                        JSONObject o = ms.optJSONObject(i);
                        if (o != null) members.add(Models.Member.from(o));
                    }
                }
                JSONArray ps = r.optJSONArray("places");
                if (ps != null) {
                    for (int i = 0; i < ps.length(); i++) {
                        JSONObject o = ps.optJSONObject(i);
                        if (o != null) places.add(Models.Place.from(o));
                    }
                }
                updateBanner();
                for (Screen s : screens) s.onCircle();
            }
        });
    }

    /** The newest position we have for this phone: Android's last fix, else the server's copy. */
    public double[] bestLocation() {
        if (Perms.hasFine(this)) {
            try {
                LocationManager lm = (LocationManager) getSystemService(Context.LOCATION_SERVICE);
                Location best = null;
                String[] providers = {LocationManager.GPS_PROVIDER, LocationManager.NETWORK_PROVIDER, LocationManager.PASSIVE_PROVIDER};
                for (String p : providers) {
                    Location l = lm.getLastKnownLocation(p);
                    if (l != null && (best == null || l.getTime() > best.getTime())) best = l;
                }
                if (best != null && System.currentTimeMillis() - best.getTime() < 6 * 3600 * 1000L) {
                    return new double[]{best.getLatitude(), best.getLongitude()};
                }
            } catch (SecurityException ignored) {
            }
        }
        Models.Member me = me();
        if (me != null && me.loc != null) return new double[]{me.loc.lat, me.loc.lon};
        return null;
    }

    public void addPlaceAt(double lat, double lon) {
        Dialogs.place(this, null, lat, lon);
    }

    public void editPlace(Models.Place p) {
        Dialogs.place(this, p, p.lat, p.lon);
    }

    // ---- banner ----

    private void updateBanner() {
        if (banner == null) return;
        String text = null;
        boolean fix = false;
        if (!Perms.hasFine(this)) {
            text = "Tether needs location access to share where you are. Tap to fix.";
            fix = true;
        } else if (!Perms.hasBackground(this)) {
            text = "Choose \"Allow all the time\" so sharing keeps working with the app closed. Tap to fix.";
            fix = true;
        } else if (!Perms.ignoringBattery(this)) {
            text = "Let Tether run in the background so Samsung doesn't put it to sleep. Tap to fix.";
            fix = true;
        } else if (!circleError.isEmpty()) {
            text = circleError;
        }
        if (text == null) {
            banner.setVisibility(View.GONE);
            return;
        }
        banner.setText(text);
        banner.setVisibility(View.VISIBLE);
        if (fix) {
            banner.setOnClickListener(new View.OnClickListener() {
                @Override
                public void onClick(View v) {
                    Intent i = new Intent(MainActivity.this, OnboardingActivity.class);
                    i.putExtra(OnboardingActivity.EXTRA_PERMS_ONLY, true);
                    startActivity(i);
                }
            });
        } else {
            banner.setOnClickListener(null);
        }
    }
}
