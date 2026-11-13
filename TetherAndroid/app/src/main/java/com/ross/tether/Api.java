package com.ross.tether;

import org.json.JSONException;
import org.json.JSONObject;

import java.io.InputStream;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.ProtocolException;
import java.net.URL;

/** Blocking HTTP client for the Tether server. Call from a background thread only. */
public final class Api {
    public static final String DEFAULT_SERVER = "https://navidrome.nas-server.co.uk/tether";

    /** The server answered with an error status. Network failures throw plain IOExceptions instead. */
    public static final class ApiException extends Exception {
        public final int status;
        public final String code;

        ApiException(int status, String code, String message) {
            super(message);
            this.status = status;
            this.code = code;
        }
    }

    private final Prefs prefs;

    public Api(android.content.Context c) {
        prefs = new Prefs(c);
    }

    /** Accepts a bare host, a trailing slash, or a full URL. */
    public static String normalize(String s) {
        String t = s == null ? "" : s.trim();
        if (t.isEmpty()) return DEFAULT_SERVER;
        if (!t.contains("://")) t = "https://" + t;
        while (t.endsWith("/")) t = t.substring(0, t.length() - 1);
        return t;
    }

    public JSONObject call(String method, String path, JSONObject body, boolean auth) throws Exception {
        return callTo(prefs.server(), method, path, body, auth ? prefs.token() : null);
    }

    public static JSONObject callTo(String base, String method, String path, JSONObject body, String token)
            throws Exception {
        URL url = new URL(normalize(base) + path);
        HttpURLConnection c = (HttpURLConnection) url.openConnection();
        try {
            c.setConnectTimeout(15000);
            c.setReadTimeout(30000);
            c.setRequestProperty("Accept", "application/json");
            if (token != null && !token.isEmpty()) c.setRequestProperty("Authorization", "Bearer " + token);
            try {
                c.setRequestMethod(method);
            } catch (ProtocolException e) {
                // Very old HttpURLConnection builds reject PATCH; fall back to an override header.
                c.setRequestMethod("POST");
                c.setRequestProperty("X-HTTP-Method-Override", method);
            }
            if (body == null && ("POST".equals(method) || "PATCH".equals(method))) body = new JSONObject();
            if (body != null) {
                byte[] data = body.toString().getBytes("UTF-8");
                c.setDoOutput(true);
                c.setRequestProperty("Content-Type", "application/json");
                c.setFixedLengthStreamingMode(data.length);
                OutputStream os = c.getOutputStream();
                os.write(data);
                os.close();
            }
            int status = c.getResponseCode();
            InputStream is = status >= 400 ? c.getErrorStream() : c.getInputStream();
            String text = is == null ? "" : Util.readAll(is);
            JSONObject json;
            try {
                json = text.isEmpty() ? new JSONObject() : new JSONObject(text);
            } catch (JSONException e) {
                json = new JSONObject();
            }
            if (status >= 400) {
                String msg = json.optString("message", "");
                if (msg.isEmpty()) msg = "The server said no (" + status + ").";
                throw new ApiException(status, json.optString("error", "http_" + status), msg);
            }
            return json;
        } finally {
            c.disconnect();
        }
    }
}
