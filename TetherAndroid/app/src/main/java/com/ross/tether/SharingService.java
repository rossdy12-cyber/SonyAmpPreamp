package com.ross.tether;

import android.app.NotificationManager;
import android.app.Service;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.pm.ServiceInfo;
import android.location.Location;
import android.location.LocationListener;
import android.location.LocationManager;
import android.os.BatteryManager;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.IBinder;
import android.os.Looper;
import android.os.PowerManager;

import org.json.JSONArray;
import org.json.JSONObject;

import java.util.concurrent.atomic.AtomicBoolean;

/**
 * Foreground service that shares this phone's location: it listens for fixes, keeps them in a persisted
 * queue, uploads them in batches with back-off, and polls the circle's events for local alerts.
 */
public class SharingService extends Service implements LocationListener {
    public static final String ACTION_PAUSE = "com.ross.tether.PAUSE";
    private static final int NOTIF_ID = 42;
    private static final long TICK_MS = 15000L;
    private static final long POLL_MS = 30000L;

    private Prefs prefs;
    private Api api;
    private LocationManager lm;
    private UploadQueue queue;
    private final Handler handler = new Handler(Looper.getMainLooper());
    private final AtomicBoolean flushing = new AtomicBoolean(false);
    private final AtomicBoolean polling = new AtomicBoolean(false);

    private boolean running;
    private boolean registered;
    private Location last;
    private long lastStoredAt;
    private long lastGpsAt;
    private long lastPollAt;
    private volatile long nextAttempt;
    private volatile int failures;

    /** Separate listener for one-shot heartbeat fixes so they never replace the continuous request. */
    private final LocationListener beatListener = new LocationListener() {
        @Override
        public void onLocationChanged(Location location) {
            SharingService.this.onLocationChanged(location);
        }

        @Override
        public void onStatusChanged(String provider, int status, Bundle extras) {
        }

        @Override
        public void onProviderEnabled(String provider) {
        }

        @Override
        public void onProviderDisabled(String provider) {
        }
    };

    public static void start(Context c) {
        Intent i = new Intent(c, SharingService.class);
        try {
            if (Build.VERSION.SDK_INT >= 26) c.startForegroundService(i);
            else c.startService(i);
        } catch (RuntimeException e) {
            // Starting a foreground service from the background can be refused; the app tries again when opened.
        }
    }

    public static void stop(Context c) {
        c.stopService(new Intent(c, SharingService.class));
    }

    @Override
    public void onCreate() {
        super.onCreate();
        prefs = new Prefs(this);
        api = new Api(this);
        lm = (LocationManager) getSystemService(Context.LOCATION_SERVICE);
        queue = UploadQueue.get(this);
        Notifier.ensureChannels(this);
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        // A service started with startForegroundService() must call startForeground() promptly.
        promote("Starting…");
        String action = intent == null ? null : intent.getAction();
        if (ACTION_PAUSE.equals(action)) {
            pauseFromNotification();
            return START_NOT_STICKY;
        }
        if (!prefs.isSignedIn() || prefs.paused() || !Perms.hasFine(this)) {
            stopForeground(true);
            stopSelf();
            return START_NOT_STICKY;
        }
        running = true;
        registerLocation();
        handler.removeCallbacks(tick);
        handler.postDelayed(tick, 2000);
        return START_STICKY;
    }

    private void promote(String text) {
        try {
            if (Build.VERSION.SDK_INT >= 29) {
                startForeground(NOTIF_ID, Notifier.sharing(this, text), ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION);
            } else {
                startForeground(NOTIF_ID, Notifier.sharing(this, text));
            }
        } catch (Exception ignored) {
        }
    }

    private void updateNotification(String text) {
        try {
            NotificationManager nm = (NotificationManager) getSystemService(Context.NOTIFICATION_SERVICE);
            if (nm != null) nm.notify(NOTIF_ID, Notifier.sharing(this, text));
        } catch (Exception ignored) {
        }
    }

    private void pauseFromNotification() {
        prefs.setPaused(true);
        Bg.run(new Runnable() {
            @Override
            public void run() {
                try {
                    api.call("PATCH", "/v1/me", Util.obj("paused", true), true);
                } catch (Exception ignored) {
                }
            }
        });
        stopForeground(true);
        stopSelf();
    }

    // ---- location ----

    private void registerLocation() {
        unregisterLocation();
        if (!Perms.hasFine(this)) return;
        try {
            if (prefs.precise()) {
                if (lm.isProviderEnabled(LocationManager.GPS_PROVIDER)) {
                    lm.requestLocationUpdates(LocationManager.GPS_PROVIDER, 10000L, 25f, this, Looper.getMainLooper());
                }
                if (lm.isProviderEnabled(LocationManager.NETWORK_PROVIDER)) {
                    lm.requestLocationUpdates(LocationManager.NETWORK_PROVIDER, 30000L, 50f, this, Looper.getMainLooper());
                }
            } else {
                lm.requestLocationUpdates(LocationManager.PASSIVE_PROVIDER, 0L, 0f, this, Looper.getMainLooper());
                if (lm.isProviderEnabled(LocationManager.NETWORK_PROVIDER)) {
                    lm.requestLocationUpdates(LocationManager.NETWORK_PROVIDER, 60000L, 100f, this, Looper.getMainLooper());
                }
            }
            registered = true;
            Location seed = freshestLastKnown();
            if (seed != null && System.currentTimeMillis() - seed.getTime() < 2 * 60 * 1000L) onLocationChanged(seed);
        } catch (SecurityException e) {
            updateNotification("Allow location for Tether to keep sharing");
        } catch (IllegalArgumentException e) {
            updateNotification("Location is unavailable on this phone");
        }
    }

    private void unregisterLocation() {
        try {
            lm.removeUpdates(this);
            lm.removeUpdates(beatListener);
        } catch (Exception ignored) {
        }
        registered = false;
    }

    private Location freshestLastKnown() {
        Location best = null;
        try {
            String[] providers = {LocationManager.GPS_PROVIDER, LocationManager.NETWORK_PROVIDER, LocationManager.PASSIVE_PROVIDER};
            for (String p : providers) {
                Location l = lm.getLastKnownLocation(p);
                if (l != null && (best == null || l.getTime() > best.getTime())) best = l;
            }
        } catch (SecurityException ignored) {
        }
        return best;
    }

    @Override
    public void onLocationChanged(Location loc) {
        if (loc == null || !running) return;
        long now = System.currentTimeMillis();
        boolean precise = prefs.precise();
        if (LocationManager.GPS_PROVIDER.equals(loc.getProvider())) {
            lastGpsAt = now;
        } else if (precise && now - lastGpsAt < 60000L) {
            return; // network fixes are noisy while GPS is fresh
        }
        if (loc.hasAccuracy() && loc.getAccuracy() > 300f) return;
        if (loc.getTime() > 0 && now - loc.getTime() > 10 * 60 * 1000L) return;

        float minMove = precise ? 20f : 80f;
        long beat = precise ? 4 * 60 * 1000L : 15 * 60 * 1000L;
        boolean store = last == null || loc.distanceTo(last) >= minMove || now - lastStoredAt >= beat;
        if (!store) return;

        last = new Location(loc);
        lastStoredAt = now;
        JSONObject point = toPoint(loc, now);
        if (point == null) return;
        queue.add(point);
        updateNotification("Last update " + Util.clock(now / 1000.0));
        submitFlush();
    }

    @Override
    public void onStatusChanged(String provider, int status, Bundle extras) {
        // Required on Android 10 and older, where this method is abstract.
    }

    @Override
    public void onProviderEnabled(String provider) {
        if (running) registerLocation();
    }

    @Override
    public void onProviderDisabled(String provider) {
        // Another provider keeps working; nothing to do.
    }

    private JSONObject toPoint(Location loc, long now) {
        try {
            JSONObject o = new JSONObject();
            long t = loc.getTime() > 0 ? Math.min(loc.getTime(), now) : now;
            o.put("lat", loc.getLatitude());
            o.put("lon", loc.getLongitude());
            o.put("ts", t / 1000.0);
            if (loc.hasAccuracy()) o.put("accuracy", (double) loc.getAccuracy());
            double speed = loc.hasSpeed() ? loc.getSpeed() : -1;
            if (speed >= 0) o.put("speed", speed);
            if (loc.hasBearing()) o.put("heading", (double) loc.getBearing());
            if (loc.hasAltitude()) o.put("altitude", loc.getAltitude());
            Intent b = registerReceiver(null, new IntentFilter(Intent.ACTION_BATTERY_CHANGED));
            if (b != null) {
                int level = b.getIntExtra(BatteryManager.EXTRA_LEVEL, -1);
                int scale = b.getIntExtra(BatteryManager.EXTRA_SCALE, -1);
                int status = b.getIntExtra(BatteryManager.EXTRA_STATUS, -1);
                if (level >= 0 && scale > 0) o.put("battery", level / (double) scale);
                o.put("charging", status == BatteryManager.BATTERY_STATUS_CHARGING || status == BatteryManager.BATTERY_STATUS_FULL);
            }
            o.put("activity", guessActivity(speed));
            return o;
        } catch (Exception e) {
            return null;
        }
    }

    private static String guessActivity(double speed) {
        if (speed < 0) return "unknown";
        if (speed < 0.6) return "still";
        if (speed < 2.2) return "walking";
        if (speed < 4.0) return "running";
        if (speed < 6.5) return "cycling";
        return "driving";
    }

    // ---- uploading ----

    private void submitFlush() {
        if (flushing.compareAndSet(false, true)) {
            Bg.run(new Runnable() {
                @Override
                public void run() {
                    flushNow();
                }
            });
        }
    }

    private void flushNow() {
        PowerManager.WakeLock wl = null;
        try {
            PowerManager pm = (PowerManager) getSystemService(Context.POWER_SERVICE);
            if (pm != null) {
                wl = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "tether:upload");
                wl.acquire(30000L);
            }
            while (System.currentTimeMillis() >= nextAttempt) {
                JSONArray batch = queue.peek(200);
                if (batch.length() == 0) break;
                try {
                    api.call("POST", "/v1/location", Util.obj("points", batch), true);
                    queue.drop(batch.length());
                    failures = 0;
                } catch (Api.ApiException e) {
                    if (e.status == 401) {
                        Bg.ui(new Runnable() {
                            @Override
                            public void run() {
                                Session.signOut(getApplicationContext(), "You were signed out. Please join again.");
                            }
                        });
                        break;
                    }
                    if (e.status == 400 || e.status == 413 || e.status == 422) {
                        queue.drop(batch.length()); // the server will never accept these points
                        continue;
                    }
                    backoff();
                    break;
                } catch (Exception e) {
                    backoff();
                    break;
                }
            }
        } catch (Exception ignored) {
        } finally {
            try {
                if (wl != null && wl.isHeld()) wl.release();
            } catch (Exception ignored) {
            }
            flushing.set(false);
        }
    }

    private void backoff() {
        failures++;
        long delay = Math.min(300000L, 15000L * (1L << Math.min(failures, 5)));
        nextAttempt = System.currentTimeMillis() + delay;
    }

    // ---- periodic work ----

    private final Runnable tick = new Runnable() {
        @Override
        public void run() {
            if (!running) return;
            long now = System.currentTimeMillis();
            if (!registered) registerLocation();
            if (queue.size() > 0 && now >= nextAttempt) submitFlush();
            long beat = prefs.precise() ? 4 * 60 * 1000L : 15 * 60 * 1000L;
            if (now - lastStoredAt >= beat) heartbeat();
            if (now - lastPollAt >= POLL_MS) {
                lastPollAt = now;
                pollEvents();
            }
            handler.postDelayed(this, TICK_MS);
        }
    };

    /** A stationary phone gets no distance-based updates, so ask for one fix to prove it is still alive. */
    private void heartbeat() {
        if (!Perms.hasFine(this)) return;
        try {
            if (lm.isProviderEnabled(LocationManager.NETWORK_PROVIDER)) {
                lm.requestSingleUpdate(LocationManager.NETWORK_PROVIDER, beatListener, Looper.getMainLooper());
            }
            if (prefs.precise() && lm.isProviderEnabled(LocationManager.GPS_PROVIDER)) {
                lm.requestSingleUpdate(LocationManager.GPS_PROVIDER, beatListener, Looper.getMainLooper());
            }
        } catch (Exception ignored) {
        }
    }

    private void pollEvents() {
        if (!polling.compareAndSet(false, true)) return;
        Bg.run(new Runnable() {
            @Override
            public void run() {
                try {
                    long since = prefs.lastEventId();
                    String path = since < 0 ? "/v1/events?limit=1" : "/v1/events?since=" + since + "&limit=50";
                    JSONObject r = api.call("GET", path, null, true);
                    long latest = r.optLong("latest_id", since);
                    JSONArray arr = r.optJSONArray("events");
                    if (since >= 0 && arr != null && prefs.alerts()) {
                        for (int i = 0; i < arr.length(); i++) {
                            JSONObject o = arr.optJSONObject(i);
                            if (o == null) continue;
                            Models.Event e = Models.Event.from(o);
                            if (!e.memberId.equals(prefs.memberId())) Notifier.event(SharingService.this, e);
                        }
                    }
                    if (latest > since) prefs.setLastEventId(latest);
                } catch (Api.ApiException e) {
                    if (e.status == 401) {
                        Bg.ui(new Runnable() {
                            @Override
                            public void run() {
                                Session.signOut(getApplicationContext(), "You were signed out. Please join again.");
                            }
                        });
                    }
                } catch (Exception ignored) {
                } finally {
                    polling.set(false);
                }
            }
        });
    }

    @Override
    public void onDestroy() {
        running = false;
        handler.removeCallbacks(tick);
        unregisterLocation();
        super.onDestroy();
    }

    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }
}
