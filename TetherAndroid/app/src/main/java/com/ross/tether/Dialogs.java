package com.ross.tether;

import android.app.AlertDialog;
import android.content.DialogInterface;
import android.view.View;
import android.widget.ArrayAdapter;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.SeekBar;
import android.widget.Spinner;
import android.widget.TextView;

import org.json.JSONObject;

/** Shared dialogs. */
public final class Dialogs {
    private Dialogs() {}

    static final String[] ICONS = {"home", "work", "school", "gym", "shop", "heart", "pin"};

    public static AlertDialog.Builder builder(MainActivity h) {
        return new AlertDialog.Builder(h, android.R.style.Theme_Material_Dialog_Alert);
    }

    /** Create (existing == null) or edit a place. */
    public static void place(final MainActivity h, final Models.Place existing, final double lat, final double lon) {
        LinearLayout box = Util.column(h);
        int pad = Util.dp(h, 20);
        box.setPadding(pad, Util.dp(h, 8), pad, 0);

        final EditText name = Util.edit(h, "Name (Home, Work, School…)");
        if (existing != null) name.setText(existing.name);
        box.addView(name, Util.lp(Util.MATCH, Util.WRAP));

        int r0 = existing == null ? 150 : existing.radius;
        final TextView radiusLabel = Util.text(h, "Radius: " + r0 + " m", 14, Util.BONE);
        box.addView(radiusLabel, Util.lpMargins(h, Util.MATCH, Util.WRAP, 0, 14, 0, 0));
        final SeekBar bar = new SeekBar(h);
        bar.setMax(1950);
        bar.setProgress(Math.max(0, Math.min(1950, r0 - 50)));
        bar.setOnSeekBarChangeListener(new SeekBar.OnSeekBarChangeListener() {
            @Override
            public void onProgressChanged(SeekBar seekBar, int progress, boolean fromUser) {
                radiusLabel.setText("Radius: " + (progress + 50) + " m");
            }

            @Override
            public void onStartTrackingTouch(SeekBar seekBar) {
            }

            @Override
            public void onStopTrackingTouch(SeekBar seekBar) {
            }
        });
        box.addView(bar, Util.lp(Util.MATCH, Util.WRAP));

        final Spinner icon = new Spinner(h);
        ArrayAdapter<String> adapter = new ArrayAdapter<>(h, android.R.layout.simple_spinner_item, ICONS);
        adapter.setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item);
        icon.setAdapter(adapter);
        if (existing != null) {
            for (int i = 0; i < ICONS.length; i++) if (ICONS[i].equals(existing.icon)) icon.setSelection(i);
        }
        box.addView(icon, Util.lpMargins(h, Util.MATCH, Util.WRAP, 0, 8, 0, 0));

        AlertDialog.Builder b = builder(h)
                .setTitle(existing == null ? "New place" : "Edit place")
                .setView(box)
                .setNegativeButton("Cancel", null)
                .setPositiveButton("Save", new DialogInterface.OnClickListener() {
                    @Override
                    public void onClick(DialogInterface dialog, int which) {
                        String n = name.getText().toString().trim();
                        if (n.isEmpty()) {
                            Util.toast(h, "Give the place a name.");
                            return;
                        }
                        int radius = bar.getProgress() + 50;
                        String ic = ICONS[icon.getSelectedItemPosition()];
                        final JSONObject body = existing == null
                                ? Util.obj("name", n, "lat", lat, "lon", lon, "radius", radius, "icon", ic)
                                : Util.obj("name", n, "radius", radius, "icon", ic);
                        String method = existing == null ? "POST" : "PATCH";
                        String path = existing == null ? "/v1/places" : "/v1/places/" + existing.id;
                        h.call(method, path, body, new Bg.Done<JSONObject>() {
                            @Override
                            public void done(JSONObject value, Exception error) {
                                if (error != null) {
                                    Util.toast(h, error.getMessage() == null ? "Couldn't save the place." : error.getMessage());
                                } else {
                                    h.refreshCircle();
                                }
                            }
                        });
                    }
                });
        if (existing != null) {
            b.setNeutralButton("Delete", new DialogInterface.OnClickListener() {
                @Override
                public void onClick(DialogInterface dialog, int which) {
                    h.call("DELETE", "/v1/places/" + existing.id, null, new Bg.Done<JSONObject>() {
                        @Override
                        public void done(JSONObject value, Exception error) {
                            if (error != null) Util.toast(h, "Couldn't delete the place.");
                            else h.refreshCircle();
                        }
                    });
                }
            });
        }
        b.show();
    }

    /** Asks a yes/no question. */
    public static void confirm(MainActivity h, String title, String message, String yes, final Runnable onYes) {
        builder(h).setTitle(title).setMessage(message)
                .setNegativeButton("Cancel", null)
                .setPositiveButton(yes, new DialogInterface.OnClickListener() {
                    @Override
                    public void onClick(DialogInterface dialog, int which) {
                        onYes.run();
                    }
                }).show();
    }

    /** Lets the user pick one entry from a list. */
    public static void choose(MainActivity h, String title, final String[] labels, final IntPick pick) {
        builder(h).setTitle(title).setItems(labels, new DialogInterface.OnClickListener() {
            @Override
            public void onClick(DialogInterface dialog, int which) {
                pick.picked(which);
            }
        }).show();
    }

    public interface IntPick {
        void picked(int index);
    }

    public static void setVisible(View v, boolean visible) {
        v.setVisibility(visible ? View.VISIBLE : View.GONE);
    }
}
