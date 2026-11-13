package com.ross.tether;

import android.content.Context;
import android.graphics.Canvas;
import android.graphics.Paint;
import android.graphics.Path;
import android.graphics.Point;
import android.graphics.Typeface;
import android.view.MotionEvent;

import org.osmdroid.util.GeoPoint;
import org.osmdroid.views.MapView;
import org.osmdroid.views.Projection;
import org.osmdroid.views.overlay.Overlay;

import java.util.ArrayList;
import java.util.List;

/**
 * Hand-drawn overlays (members, places, timeline path) so the app depends only on the basic osmdroid
 * Overlay and Projection classes. Each overlay implements both draw signatures osmdroid 6.1 knows about;
 * the library calls only one of them per frame.
 */
public final class MapOverlays {
    private MapOverlays() {}

    public interface MemberTap {
        void onMember(Models.Member m);
    }

    // ---------- members ----------
    public static final class Members extends Overlay {
        private final float d;
        private final Paint fill = new Paint(Paint.ANTI_ALIAS_FLAG);
        private final Paint ring = new Paint(Paint.ANTI_ALIAS_FLAG);
        private final Paint initial = new Paint(Paint.ANTI_ALIAS_FLAG);
        private final Paint label = new Paint(Paint.ANTI_ALIAS_FLAG);
        private final Paint labelOutline = new Paint(Paint.ANTI_ALIAS_FLAG);
        private final MemberTap tap;
        public List<Models.Member> data = new ArrayList<>();
        public String selectedId = "";

        public Members(Context c, MemberTap tap) {
            super();
            this.tap = tap;
            d = c.getResources().getDisplayMetrics().density;
            ring.setStyle(Paint.Style.STROKE);
            initial.setColor(0xFFFFFFFF);
            initial.setTextAlign(Paint.Align.CENTER);
            initial.setTextSize(18 * d);
            initial.setTypeface(Typeface.DEFAULT_BOLD);
            label.setColor(0xFFFFFFFF);
            label.setTextAlign(Paint.Align.CENTER);
            label.setTextSize(11 * d);
            label.setTypeface(Typeface.DEFAULT_BOLD);
            labelOutline.setColor(0xFF000000);
            labelOutline.setTextAlign(Paint.Align.CENTER);
            labelOutline.setTextSize(11 * d);
            labelOutline.setTypeface(Typeface.DEFAULT_BOLD);
            labelOutline.setStyle(Paint.Style.STROKE);
            labelOutline.setStrokeWidth(3 * d);
        }

        public void draw(Canvas c, MapView map, boolean shadow) {
            if (shadow) return;
            render(c, map.getProjection());
        }

        public void draw(Canvas c, Projection pr) {
            render(c, pr);
        }

        private void render(Canvas c, Projection pr) {
            Point p = new Point();
            for (Models.Member m : data) {
                if (m.loc == null) continue;
                pr.toPixels(new GeoPoint(m.loc.lat, m.loc.lon), p);
                float r = 20 * d;
                fill.setColor(Util.color(m.color));
                c.drawCircle(p.x, p.y, r, fill);
                boolean sel = m.id.equals(selectedId);
                ring.setColor(sel ? 0xFFFFFFFF : 0xFF0A0A0A);
                ring.setStrokeWidth((sel ? 3.5f : 2.5f) * d);
                c.drawCircle(p.x, p.y, r, ring);
                c.drawText(m.initial(), p.x, p.y + 6.5f * d, initial);
                String line = m.name;
                if (m.loc.battery >= 0) line += " " + Math.round(m.loc.battery * 100) + "%";
                float y = p.y + r + 14 * d;
                c.drawText(line, p.x, y, labelOutline);
                c.drawText(line, p.x, y, label);
            }
        }

        public boolean onSingleTapConfirmed(MotionEvent e, MapView map) {
            Projection pr = map.getProjection();
            Point p = new Point();
            Models.Member hit = null;
            float best = Float.MAX_VALUE;
            for (Models.Member m : data) {
                if (m.loc == null) continue;
                pr.toPixels(new GeoPoint(m.loc.lat, m.loc.lon), p);
                float dx = e.getX() - p.x;
                float dy = e.getY() - p.y;
                float dist = (float) Math.sqrt(dx * dx + dy * dy);
                if (dist < 28 * d && dist < best) {
                    best = dist;
                    hit = m;
                }
            }
            if (hit != null && tap != null) {
                tap.onMember(hit);
                return true;
            }
            return false;
        }
    }

    // ---------- places ----------
    public static final class Places extends Overlay {
        private final float d;
        private final Paint fill = new Paint(Paint.ANTI_ALIAS_FLAG);
        private final Paint stroke = new Paint(Paint.ANTI_ALIAS_FLAG);
        private final Paint label = new Paint(Paint.ANTI_ALIAS_FLAG);
        private final Paint labelOutline = new Paint(Paint.ANTI_ALIAS_FLAG);
        public List<Models.Place> data = new ArrayList<>();

        public Places(Context c) {
            super();
            d = c.getResources().getDisplayMetrics().density;
            fill.setColor(0x33DC143C);
            stroke.setStyle(Paint.Style.STROKE);
            stroke.setColor(0xFFDC143C);
            stroke.setStrokeWidth(2 * d);
            label.setColor(0xFFFFFFFF);
            label.setTextAlign(Paint.Align.CENTER);
            label.setTextSize(12 * d);
            labelOutline.setColor(0xFF000000);
            labelOutline.setTextAlign(Paint.Align.CENTER);
            labelOutline.setTextSize(12 * d);
            labelOutline.setStyle(Paint.Style.STROKE);
            labelOutline.setStrokeWidth(3 * d);
        }

        public void draw(Canvas c, MapView map, boolean shadow) {
            if (shadow) return;
            render(c, map.getProjection());
        }

        public void draw(Canvas c, Projection pr) {
            render(c, pr);
        }

        private void render(Canvas c, Projection pr) {
            Point p0 = new Point();
            Point p1 = new Point();
            for (Models.Place pl : data) {
                pr.toPixels(new GeoPoint(pl.lat, pl.lon), p0);
                // Radius in pixels: project a point one radius due north of the centre.
                double dLat = pl.radius / 111320.0;
                pr.toPixels(new GeoPoint(pl.lat + dLat, pl.lon), p1);
                float rpx = Math.max(6 * d, Math.abs(p1.y - p0.y));
                c.drawCircle(p0.x, p0.y, rpx, fill);
                c.drawCircle(p0.x, p0.y, rpx, stroke);
                c.drawText(pl.name, p0.x, p0.y + 4 * d, labelOutline);
                c.drawText(pl.name, p0.x, p0.y + 4 * d, label);
            }
        }
    }

    // ---------- timeline path ----------
    public static final class PathLine extends Overlay {
        private final float d;
        private final Paint line = new Paint(Paint.ANTI_ALIAS_FLAG);
        private final Paint dot = new Paint(Paint.ANTI_ALIAS_FLAG);
        private final Paint num = new Paint(Paint.ANTI_ALIAS_FLAG);
        /** Each entry is {lat, lon}. */
        public List<double[]> path = new ArrayList<>();
        public List<double[]> stays = new ArrayList<>();

        public PathLine(Context c) {
            super();
            d = c.getResources().getDisplayMetrics().density;
            line.setStyle(Paint.Style.STROKE);
            line.setStrokeWidth(4 * d);
            line.setColor(0xFFDC143C);
            line.setStrokeJoin(Paint.Join.ROUND);
            line.setStrokeCap(Paint.Cap.ROUND);
            dot.setColor(0xFFE8DCC8);
            num.setColor(0xFF0A0A0A);
            num.setTextAlign(Paint.Align.CENTER);
            num.setTextSize(11 * d);
            num.setTypeface(Typeface.DEFAULT_BOLD);
        }

        public void draw(Canvas c, MapView map, boolean shadow) {
            if (shadow) return;
            render(c, map.getProjection());
        }

        public void draw(Canvas c, Projection pr) {
            render(c, pr);
        }

        private void render(Canvas c, Projection pr) {
            Point p = new Point();
            if (path.size() > 1) {
                Path out = new Path();
                boolean first = true;
                for (double[] pt : path) {
                    pr.toPixels(new GeoPoint(pt[0], pt[1]), p);
                    if (first) {
                        out.moveTo(p.x, p.y);
                        first = false;
                    } else {
                        out.lineTo(p.x, p.y);
                    }
                }
                c.drawPath(out, line);
            }
            int n = 1;
            for (double[] s : stays) {
                pr.toPixels(new GeoPoint(s[0], s[1]), p);
                c.drawCircle(p.x, p.y, 11 * d, dot);
                c.drawText(String.valueOf(n), p.x, p.y + 4 * d, num);
                n++;
            }
        }
    }
}
