package com.ross.tether;

import android.content.Intent;
import android.content.pm.PackageInfo;
import android.view.View;
import android.widget.Button;
import android.widget.CompoundButton;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.RadioButton;
import android.widget.RadioGroup;
import android.widget.ScrollView;
import android.widget.Switch;
import android.widget.TextView;

import org.json.JSONObject;

/** Profile, sharing controls, permissions help and leaving the circle. */
final class SettingsScreen extends Screen {
    private final EditText nameField;
    private final LinearLayout swatches;
    private final Switch pauseSwitch;
    private final Switch alertSwitch;
    private final RadioButton precise;
    private final RadioButton saver;
    private final TextView serverLine;
    private String color = "DC143C";
    private boolean binding;

    SettingsScreen(MainActivity host) {
        super(host);
        ScrollView scroll = new ScrollView(host);
        scroll.setBackgroundColor(Util.BG);
        LinearLayout col = Util.column(host);
        int pad = Util.dp(host, 16);
        col.setPadding(pad, pad, pad, pad);
        scroll.addView(col);

        col.addView(Util.heading(host, "Settings"));

        col.addView(label("Your name and colour"));
        nameField = Util.edit(host, "Name");
        col.addView(nameField, Util.lp(Util.MATCH, Util.WRAP));
        swatches = Util.row(host);
        col.addView(swatches, Util.lpMargins(host, Util.MATCH, Util.WRAP, 0, 10, 0, 0));
        Button save = Util.button(host, "Save name and colour", new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                saveProfile();
            }
        });
        col.addView(save, Util.lpMargins(host, Util.MATCH, Util.WRAP, 0, 10, 0, 0));

        col.addView(label("Sharing"));
        pauseSwitch = new Switch(host);
        pauseSwitch.setText("Pause sharing my location");
        pauseSwitch.setTextColor(Util.BONE);
        pauseSwitch.setOnCheckedChangeListener(new CompoundButton.OnCheckedChangeListener() {
            @Override
            public void onCheckedChanged(CompoundButton b, boolean checked) {
                if (!binding) setPaused(checked);
            }
        });
        col.addView(pauseSwitch, Util.lpMargins(host, Util.MATCH, Util.WRAP, 0, 6, 0, 0));

        RadioGroup group = new RadioGroup(host);
        precise = new RadioButton(host);
        precise.setText("Precise (GPS, updates as you move)");
        precise.setTextColor(Util.BONE);
        precise.setId(View.generateViewId());
        saver = new RadioButton(host);
        saver.setText("Battery saver (fewer, coarser updates)");
        saver.setTextColor(Util.BONE);
        saver.setId(View.generateViewId());
        group.addView(precise);
        group.addView(saver);
        group.setOnCheckedChangeListener(new RadioGroup.OnCheckedChangeListener() {
            @Override
            public void onCheckedChanged(RadioGroup g, int checkedId) {
                if (binding) return;
                SettingsScreen.this.host.prefs.setPrecise(checkedId == precise.getId());
                if (Perms.hasFine(ctx) && !SettingsScreen.this.host.prefs.paused()) SharingService.start(ctx);
            }
        });
        col.addView(group, Util.lpMargins(host, Util.MATCH, Util.WRAP, 0, 6, 0, 0));

        alertSwitch = new Switch(host);
        alertSwitch.setText("Alert me about arrivals, check-ins and SOS");
        alertSwitch.setTextColor(Util.BONE);
        alertSwitch.setOnCheckedChangeListener(new CompoundButton.OnCheckedChangeListener() {
            @Override
            public void onCheckedChanged(CompoundButton b, boolean checked) {
                if (!binding) SettingsScreen.this.host.prefs.setAlerts(checked);
            }
        });
        col.addView(alertSwitch, Util.lpMargins(host, Util.MATCH, Util.WRAP, 0, 10, 0, 0));

        col.addView(label("Keeping Tether running"));
        TextView help = Util.text(host,
                "Samsung phones put apps to sleep to save battery, which stops location sharing. To prevent that:\n"
                        + "• Settings > Apps > Tether > Battery > Unrestricted\n"
                        + "• Settings > Battery and device care > Battery > Background usage limits: turn off "
                        + "\"Put unused apps to sleep\" and make sure Tether is not in Sleeping apps (add it to Never sleeping apps)\n"
                        + "• Location permission: Allow all the time",
                13, Util.MUTED);
        col.addView(help, Util.lpMargins(host, Util.MATCH, Util.WRAP, 0, 4, 0, 8));
        Button perms = Util.ghost(host, "Check permissions and battery", new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                Intent i = new Intent(ctx, OnboardingActivity.class);
                i.putExtra(OnboardingActivity.EXTRA_PERMS_ONLY, true);
                ctx.startActivity(i);
            }
        });
        col.addView(perms, Util.lp(Util.MATCH, Util.WRAP));

        col.addView(label("Circle"));
        serverLine = Util.text(host, "", 13, Util.MUTED);
        col.addView(serverLine);
        Button leave = Util.ghost(host, "Leave the circle", new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                leaveCircle();
            }
        });
        col.addView(leave, Util.lpMargins(host, Util.MATCH, Util.WRAP, 0, 10, 0, 0));

        TextView version = Util.text(host, "Tether " + versionName(), 12, Util.MUTED);
        col.addView(version, Util.lpMargins(host, Util.MATCH, Util.WRAP, 0, 20, 0, 0));
        root = scroll;
    }

    private TextView label(String s) {
        TextView t = Util.text(ctx, s, 14, Util.CRIMSON_LIGHT);
        t.setTypeface(android.graphics.Typeface.SERIF);
        t.setPadding(0, Util.dp(ctx, 22), 0, Util.dp(ctx, 6));
        return t;
    }

    private String versionName() {
        try {
            PackageInfo pi = ctx.getPackageManager().getPackageInfo(ctx.getPackageName(), 0);
            return pi.versionName == null ? "" : pi.versionName;
        } catch (Exception e) {
            return "";
        }
    }

    @Override
    void onShow() {
        binding = true;
        nameField.setText(host.prefs.name());
        color = host.prefs.color();
        drawSwatches();
        pauseSwitch.setChecked(host.prefs.paused());
        alertSwitch.setChecked(host.prefs.alerts());
        precise.setChecked(host.prefs.precise());
        saver.setChecked(!host.prefs.precise());
        serverLine.setText("Server: " + host.prefs.server());
        binding = false;
    }

    private void drawSwatches() {
        swatches.removeAllViews();
        for (final String hex : Util.COLORS) {
            View v = new View(ctx);
            boolean sel = hex.equalsIgnoreCase(color);
            v.setBackground(Util.oval(Util.color(hex), sel ? 0xFFFFFFFF : 0, Util.dp(ctx, 3)));
            v.setOnClickListener(new View.OnClickListener() {
                @Override
                public void onClick(View view) {
                    color = hex;
                    drawSwatches();
                }
            });
            swatches.addView(v, Util.lpMargins(ctx, Util.dp(ctx, 32), Util.dp(ctx, 32), 0, 0, 8, 0));
        }
    }

    private void saveProfile() {
        final String n = nameField.getText().toString().trim();
        if (n.isEmpty()) {
            Util.toast(ctx, "Enter a name.");
            return;
        }
        final String c = color;
        host.call("PATCH", "/v1/me", Util.obj("name", n, "color", c), new Bg.Done<JSONObject>() {
            @Override
            public void done(JSONObject value, Exception error) {
                if (error != null) {
                    Util.toast(ctx, error.getMessage() == null ? "Couldn't save." : error.getMessage());
                } else {
                    host.prefs.setProfile(n, c);
                    Util.toast(ctx, "Saved.");
                    host.refreshCircle();
                }
            }
        });
    }

    private void setPaused(final boolean paused) {
        host.call("PATCH", "/v1/me", Util.obj("paused", paused), new Bg.Done<JSONObject>() {
            @Override
            public void done(JSONObject value, Exception error) {
                if (error != null) {
                    Util.toast(ctx, "Couldn't change that. Check your connection.");
                    binding = true;
                    pauseSwitch.setChecked(!paused);
                    binding = false;
                    return;
                }
                host.prefs.setPaused(paused);
                if (paused) SharingService.stop(ctx);
                else if (Perms.hasFine(ctx)) SharingService.start(ctx);
                host.refreshCircle();
            }
        });
    }

    private void leaveCircle() {
        Dialogs.confirm(host, "Leave the circle?",
                "Your location history is deleted from the server and you will need a new invite code to rejoin.",
                "Leave", new Runnable() {
                    @Override
                    public void run() {
                        host.call("DELETE", "/v1/me", null, new Bg.Done<JSONObject>() {
                            @Override
                            public void done(JSONObject value, Exception error) {
                                if (error != null) {
                                    Util.toast(ctx, "Couldn't leave right now. Check your connection.");
                                } else {
                                    Session.signOut(ctx.getApplicationContext(), "You left the circle.");
                                }
                            }
                        });
                    }
                });
    }
}
