package com.ross.tether;

import android.content.Context;
import android.content.SharedPreferences;

/**
 * Settings and the sign-in token. SharedPreferences in MODE_PRIVATE keeps them private to the app;
 * a Keystore-backed encrypted store would be a future improvement.
 */
public final class Prefs {
    private final SharedPreferences sp;

    public Prefs(Context c) {
        sp = c.getApplicationContext().getSharedPreferences("tether", Context.MODE_PRIVATE);
    }

    public String server() { return sp.getString("server", Api.DEFAULT_SERVER); }
    public String token() { return sp.getString("token", ""); }
    public String memberId() { return sp.getString("memberId", ""); }
    public String name() { return sp.getString("name", ""); }
    public String color() { return sp.getString("color", "DC143C"); }
    public boolean isSignedIn() { return !token().isEmpty(); }

    public boolean paused() { return sp.getBoolean("paused", false); }
    public void setPaused(boolean v) { sp.edit().putBoolean("paused", v).apply(); }

    /** true = Precise (GPS), false = Battery saver. */
    public boolean precise() { return sp.getBoolean("precise", true); }
    public void setPrecise(boolean v) { sp.edit().putBoolean("precise", v).apply(); }

    /** Local alert notifications for other people's events. */
    public boolean alerts() { return sp.getBoolean("alerts", true); }
    public void setAlerts(boolean v) { sp.edit().putBoolean("alerts", v).apply(); }

    /** -1 means "not set yet": the first poll just records the newest id without notifying. */
    public long lastEventId() { return sp.getLong("lastEvent", -1); }
    public void setLastEventId(long v) { sp.edit().putLong("lastEvent", v).apply(); }

    public boolean sosActive() { return sp.getBoolean("sos", false); }
    public void setSosActive(boolean v) { sp.edit().putBoolean("sos", v).apply(); }

    public void setProfile(String name, String color) {
        sp.edit().putString("name", name).putString("color", color).apply();
    }

    public void setSession(String server, String token, String memberId, String name, String color) {
        sp.edit().putString("server", server).putString("token", token).putString("memberId", memberId)
                .putString("name", name).putString("color", color)
                .putLong("lastEvent", -1).putBoolean("paused", false).putBoolean("sos", false).apply();
    }

    public void clear() {
        sp.edit().clear().apply();
    }
}
