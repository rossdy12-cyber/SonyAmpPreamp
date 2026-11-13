package com.ross.tether;

import org.json.JSONObject;

/** Tolerant parsers for the Tether API objects (missing or null fields never throw). */
public final class Models {
    private Models() {}

    static String str(JSONObject o, String k) {
        return o == null || o.isNull(k) ? "" : o.optString(k, "");
    }

    static double num(JSONObject o, String k, double d) {
        return o == null || o.isNull(k) ? d : o.optDouble(k, d);
    }

    public static final class Loc {
        public double lat, lon, ts;
        public double accuracy = -1, speed = -1, heading = -1, battery = -1;
        public boolean charging;
        public String activity = "unknown", placeId = "", placeName = "";

        static Loc from(JSONObject o) {
            if (o == null) return null;
            Loc l = new Loc();
            l.lat = num(o, "lat", 0);
            l.lon = num(o, "lon", 0);
            l.ts = num(o, "ts", 0);
            l.accuracy = num(o, "accuracy", -1);
            l.speed = num(o, "speed", -1);
            l.heading = num(o, "heading", -1);
            l.battery = num(o, "battery", -1);
            l.charging = o.optBoolean("charging", false);
            String a = str(o, "activity");
            l.activity = a.isEmpty() ? "unknown" : a;
            l.placeId = str(o, "place_id");
            l.placeName = str(o, "place_name");
            return l;
        }
    }

    public static final class Member {
        public String id = "", name = "", color = "DC143C";
        public boolean paused;
        public double pausedSince;
        public Loc loc;

        static Member from(JSONObject o) {
            Member m = new Member();
            m.id = str(o, "id");
            m.name = str(o, "name");
            String c = str(o, "color");
            if (!c.isEmpty()) m.color = c;
            m.paused = o.optBoolean("paused", false);
            m.pausedSince = num(o, "paused_since", 0);
            if (!o.isNull("location")) m.loc = Loc.from(o.optJSONObject("location"));
            return m;
        }

        public String initial() {
            return name.isEmpty() ? "?" : name.substring(0, 1).toUpperCase();
        }
    }

    public static final class Place {
        public String id = "", name = "", icon = "pin";
        public double lat, lon;
        public int radius = 150;

        static Place from(JSONObject o) {
            Place p = new Place();
            p.id = str(o, "id");
            p.name = str(o, "name");
            p.lat = num(o, "lat", 0);
            p.lon = num(o, "lon", 0);
            p.radius = (int) num(o, "radius", 150);
            String i = str(o, "icon");
            if (!i.isEmpty()) p.icon = i;
            return p;
        }
    }

    public static final class Event {
        public long id;
        public double ts, lat = Double.NaN, lon = Double.NaN;
        public String memberId = "", memberName = "", kind = "", placeId = "", placeName = "", text = "";

        static Event from(JSONObject o) {
            Event e = new Event();
            e.id = o.optLong("id", 0);
            e.ts = num(o, "ts", 0);
            e.memberId = str(o, "member_id");
            e.memberName = str(o, "member_name");
            e.kind = str(o, "kind");
            e.placeId = str(o, "place_id");
            e.placeName = str(o, "place_name");
            e.text = str(o, "text");
            e.lat = num(o, "lat", Double.NaN);
            e.lon = num(o, "lon", Double.NaN);
            return e;
        }

        public boolean hasLocation() {
            return !Double.isNaN(lat) && !Double.isNaN(lon);
        }

        public String title() {
            String n = memberName.isEmpty() ? "Someone" : memberName;
            switch (kind) {
                case "arrive":
                    return n + " arrived" + (placeName.isEmpty() ? "" : " at " + placeName);
                case "leave":
                    return n + " left" + (placeName.isEmpty() ? "" : " " + placeName);
                case "checkin":
                    return n + " checked in";
                case "sos":
                    return "SOS from " + n;
                case "low_battery":
                    return n + "'s battery is low";
                case "joined":
                    return n + " joined the circle";
                default:
                    return n + " " + kind;
            }
        }
    }
}
