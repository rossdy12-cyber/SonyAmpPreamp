package com.ross.tether;

import android.content.Context;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.util.ArrayList;

/** Location points waiting to be uploaded. Persisted so nothing is lost while offline or after a restart. */
public final class UploadQueue {
    private static final int MAX_POINTS = 5000;
    private static UploadQueue instance;

    public static synchronized UploadQueue get(Context c) {
        if (instance == null) instance = new UploadQueue(c.getApplicationContext());
        return instance;
    }

    private final File file;
    private final ArrayList<JSONObject> items = new ArrayList<>();

    private UploadQueue(Context c) {
        file = new File(c.getFilesDir(), "queue.json");
        load();
    }

    private void load() {
        try {
            if (!file.exists()) return;
            FileInputStream in = new FileInputStream(file);
            JSONArray a = new JSONArray(Util.readAll(in));
            for (int i = 0; i < a.length(); i++) items.add(a.getJSONObject(i));
        } catch (Exception e) {
            items.clear();
        }
    }

    private void save() {
        try {
            JSONArray a = new JSONArray();
            for (JSONObject o : items) a.put(o);
            File tmp = new File(file.getPath() + ".tmp");
            FileOutputStream out = new FileOutputStream(tmp);
            out.write(a.toString().getBytes("UTF-8"));
            out.close();
            if (!tmp.renameTo(file)) {
                file.delete();
                tmp.renameTo(file);
            }
        } catch (Exception ignored) {
        }
    }

    public synchronized void add(JSONObject point) {
        items.add(point);
        while (items.size() > MAX_POINTS) items.remove(0);
        save();
    }

    /** The oldest n points, oldest first. */
    public synchronized JSONArray peek(int n) {
        JSONArray a = new JSONArray();
        for (int i = 0; i < Math.min(n, items.size()); i++) a.put(items.get(i));
        return a;
    }

    /** Removes the oldest n points after they were uploaded. */
    public synchronized void drop(int n) {
        for (int i = 0; i < n && !items.isEmpty(); i++) items.remove(0);
        save();
    }

    public synchronized int size() {
        return items.size();
    }

    public synchronized void clear() {
        items.clear();
        save();
    }
}
