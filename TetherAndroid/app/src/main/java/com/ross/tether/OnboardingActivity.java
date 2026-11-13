package com.ross.tether;

import android.Manifest;
import android.app.Activity;
import android.content.ActivityNotFoundException;
import android.content.Intent;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.provider.Settings;
import android.view.View;
import android.widget.Button;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

import org.json.JSONObject;

/**
 * Sign-in (invite code) and the permission steps. With EXTRA_PERMS_ONLY it shows only the permission
 * steps, so the main screen and Settings can send people back to fix them.
 */
public class OnboardingActivity extends Activity {
    public static final String EXTRA_MESSAGE = "message";
    public static final String EXTRA_PERMS_ONLY = "perms_only";

    private static final int REQ_FOREGROUND = 11;
    private static final int REQ_BACKGROUND = 12;
    private static final int REQ_NOTIFY = 13;

    private Prefs prefs;
    private ScrollView scroll;
    private boolean permsOnly;
    private boolean showingPerms;
    private String chosenColor = Util.COLORS[0];

    // Permission-step views, rebuilt when the stage changes.
    private TextView locStatus, bgStatus, notifStatus, batteryStatus;
    private Button finishButton;

    @Override
    protected void onCreate(Bundle b) {
        super.onCreate(b);
        prefs = new Prefs(this);
        Notifier.ensureChannels(this);
        permsOnly = getIntent().getBooleanExtra(EXTRA_PERMS_ONLY, false);
        scroll = new ScrollView(this);
        scroll.setBackgroundColor(Util.BG);
        setContentView(scroll);
        if (permsOnly || prefs.isSignedIn()) showPermissions();
        else showJoin(getIntent().getStringExtra(EXTRA_MESSAGE));
    }

    @Override
    protected void onResume() {
        super.onResume();
        if (showingPerms) refreshPermStatus();
    }

    private LinearLayout page() {
        LinearLayout col = Util.column(this);
        int pad = Util.dp(this, 20);
        col.setPadding(pad, Util.dp(this, 28), pad, pad);
        scroll.removeAllViews();
        scroll.addView(col);
        return col;
    }

    // ---------- step 1: join ----------

    private void showJoin(String message) {
        showingPerms = false;
        LinearLayout col = page();
        col.addView(Util.heading(this, "Tether"));
        col.addView(Util.text(this, "Private family location sharing. No subscription, no ads: your locations stay on your own server.",
                14, Util.MUTED), Util.lpMargins(this, Util.MATCH, Util.WRAP, 0, 4, 0, 18));

        if (message != null && !message.isEmpty()) {
            TextView m = Util.text(this, message, 14, 0xFFFFFFFF);
            m.setBackground(Util.rounded(this, 0xFF2A0508, Util.CRIMSON, 8));
            int p = Util.dp(this, 10);
            m.setPadding(p, p, p, p);
            col.addView(m, Util.lpMargins(this, Util.MATCH, Util.WRAP, 0, 0, 0, 14));
        }

        col.addView(fieldLabel("Server address"));
        final EditText server = Util.edit(this, Api.DEFAULT_SERVER);
        server.setText(Api.DEFAULT_SERVER);
        server.setInputType(android.text.InputType.TYPE_CLASS_TEXT | android.text.InputType.TYPE_TEXT_VARIATION_URI);
        col.addView(server, Util.lp(Util.MATCH, Util.WRAP));

        col.addView(fieldLabel("Invite code"));
        final EditText code = Util.edit(this, "ABCD-EFGH");
        code.setInputType(android.text.InputType.TYPE_CLASS_TEXT
                | android.text.InputType.TYPE_TEXT_FLAG_CAP_CHARACTERS
                | android.text.InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS);
        col.addView(code, Util.lp(Util.MATCH, Util.WRAP));

        col.addView(fieldLabel("Your name"));
        final EditText name = Util.edit(this, "Mum");
        name.setInputType(android.text.InputType.TYPE_CLASS_TEXT | android.text.InputType.TYPE_TEXT_FLAG_CAP_WORDS);
        col.addView(name, Util.lp(Util.MATCH, Util.WRAP));

        col.addView(fieldLabel("Your colour"));
        final LinearLayout swatches = Util.row(this);
        col.addView(swatches, Util.lp(Util.MATCH, Util.WRAP));
        drawSwatches(swatches);

        final TextView error = Util.text(this, "", 14, Util.CRIMSON_LIGHT);
        col.addView(error, Util.lpMargins(this, Util.MATCH, Util.WRAP, 0, 12, 0, 0));

        final Button join = Util.button(this, "Join the circle", null);
        join.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                final String base = Api.normalize(server.getText().toString());
                final String inviteCode = code.getText().toString().trim();
                final String who = name.getText().toString().trim();
                if (inviteCode.isEmpty() || who.isEmpty()) {
                    error.setText("Enter the invite code and your name.");
                    return;
                }
                error.setText("");
                join.setEnabled(false);
                join.setText("Joining…");
                final String hex = chosenColor;
                Bg.async(OnboardingActivity.this, new Bg.Work<JSONObject>() {
                    @Override
                    public JSONObject run() throws Exception {
                        JSONObject body = Util.obj("code", inviteCode, "name", who, "color", hex);
                        return Api.callTo(base, "POST", "/v1/join", body, null);
                    }
                }, new Bg.Done<JSONObject>() {
                    @Override
                    public void done(JSONObject r, Exception e) {
                        join.setEnabled(true);
                        join.setText("Join the circle");
                        if (e != null) {
                            if (e instanceof Api.ApiException) error.setText(e.getMessage());
                            else error.setText("Can't reach the server. Check the address and your connection.");
                            return;
                        }
                        JSONObject member = r.optJSONObject("member");
                        String token = r.optString("token", "");
                        if (member == null || token.isEmpty()) {
                            error.setText("The server gave an unexpected answer.");
                            return;
                        }
                        prefs.setSession(base, token, Models.str(member, "id"), Models.str(member, "name"),
                                Models.str(member, "color").isEmpty() ? hex : Models.str(member, "color"));
                        showPermissions();
                    }
                });
            }
        });
        col.addView(join, Util.lpMargins(this, Util.MATCH, Util.WRAP, 0, 8, 0, 0));
    }

    private void drawSwatches(final LinearLayout row) {
        row.removeAllViews();
        for (final String hex : Util.COLORS) {
            View v = new View(this);
            boolean sel = hex.equalsIgnoreCase(chosenColor);
            v.setBackground(Util.oval(Util.color(hex), sel ? 0xFFFFFFFF : 0, Util.dp(this, 3)));
            v.setOnClickListener(new View.OnClickListener() {
                @Override
                public void onClick(View view) {
                    chosenColor = hex;
                    drawSwatches(row);
                }
            });
            row.addView(v, Util.lpMargins(this, Util.dp(this, 32), Util.dp(this, 32), 0, 0, 8, 0));
        }
    }

    private TextView fieldLabel(String s) {
        TextView t = Util.text(this, s, 13, Util.MUTED);
        t.setPadding(0, Util.dp(this, 14), 0, Util.dp(this, 4));
        return t;
    }

    // ---------- step 2: permissions ----------

    private void showPermissions() {
        showingPerms = true;
        LinearLayout col = page();
        col.addView(Util.heading(this, "Let Tether share your location"));
        col.addView(Util.text(this, "Four quick steps so sharing keeps working when the app is closed.",
                14, Util.MUTED), Util.lpMargins(this, Util.MATCH, Util.WRAP, 0, 4, 0, 12));

        locStatus = stepStatus(col, "1. Location access",
                "Allow Tether to use your location.", "Allow location", new View.OnClickListener() {
                    @Override
                    public void onClick(View v) {
                        requestPermissions(new String[]{Manifest.permission.ACCESS_FINE_LOCATION,
                                Manifest.permission.ACCESS_COARSE_LOCATION}, REQ_FOREGROUND);
                    }
                });

        if (Build.VERSION.SDK_INT >= 29) {
            bgStatus = stepStatus(col, "2. Allow all the time",
                    "Choose \"Allow all the time\" (on Android 11 and newer this opens the app's permission page: pick Location, then Allow all the time).",
                    "Allow all the time", new View.OnClickListener() {
                        @Override
                        public void onClick(View v) {
                            if (!Perms.hasFine(OnboardingActivity.this)) {
                                Util.toast(OnboardingActivity.this, "Do step 1 first.");
                                return;
                            }
                            if (Build.VERSION.SDK_INT >= 30) {
                                openAppSettings();
                            } else {
                                requestPermissions(new String[]{Manifest.permission.ACCESS_BACKGROUND_LOCATION}, REQ_BACKGROUND);
                            }
                        }
                    });
        } else {
            bgStatus = null;
        }

        if (Build.VERSION.SDK_INT >= 33) {
            notifStatus = stepStatus(col, "3. Notifications",
                    "So you hear about arrivals, check-ins and SOS alerts.", "Allow notifications", new View.OnClickListener() {
                        @Override
                        public void onClick(View v) {
                            requestPermissions(new String[]{Manifest.permission.POST_NOTIFICATIONS}, REQ_NOTIFY);
                        }
                    });
        } else {
            notifStatus = null;
        }

        batteryStatus = stepStatus(col, "4. Stay awake in the background",
                "Samsung phones put apps to sleep, which stops sharing. Allow Tether to run in the background.",
                "Let Tether run", new View.OnClickListener() {
                    @Override
                    public void onClick(View v) {
                        requestBatteryExemption();
                    }
                });

        TextView samsung = Util.text(this,
                "Samsung Galaxy (Note 8 and others): also open Settings > Battery and device care > Battery > "
                        + "Background usage limits, turn off \"Put unused apps to sleep\", and check Tether is not listed under "
                        + "\"Sleeping apps\" (add it to \"Never sleeping apps\"). In Settings > Apps > Tether > Battery choose Unrestricted.",
                13, Util.MUTED);
        samsung.setBackground(Util.rounded(this, Util.PANEL, Util.LINE, 10));
        int p = Util.dp(this, 12);
        samsung.setPadding(p, p, p, p);
        col.addView(samsung, Util.lpMargins(this, Util.MATCH, Util.WRAP, 0, 16, 0, 0));

        finishButton = Util.button(this, permsOnly ? "Done" : "Start sharing", new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                finishUp();
            }
        });
        col.addView(finishButton, Util.lpMargins(this, Util.MATCH, Util.WRAP, 0, 20, 0, 0));
        refreshPermStatus();
    }

    /** Adds a titled step with a status line and an action button; returns the status TextView. */
    private TextView stepStatus(LinearLayout col, String title, String why, String buttonLabel, View.OnClickListener action) {
        LinearLayout box = Util.column(this);
        box.setBackground(Util.rounded(this, Util.PANEL, Util.LINE, 12));
        int p = Util.dp(this, 14);
        box.setPadding(p, p, p, p);
        box.addView(Util.text(this, title, 17, Util.BONE));
        box.addView(Util.text(this, why, 13, Util.MUTED), Util.lpMargins(this, Util.MATCH, Util.WRAP, 0, 4, 0, 6));
        TextView status = Util.text(this, "", 14, Util.CRIMSON_LIGHT);
        box.addView(status);
        box.addView(Util.ghost(this, buttonLabel, action), Util.lpMargins(this, Util.MATCH, Util.WRAP, 0, 8, 0, 0));
        col.addView(box, Util.lpMargins(this, Util.MATCH, Util.WRAP, 0, 0, 0, 10));
        return status;
    }

    private void setStatus(TextView t, boolean ok, String okText, String todoText) {
        if (t == null) return;
        t.setText(ok ? "✓ " + okText : todoText);
        t.setTextColor(ok ? 0xFF2F9E44 : Util.CRIMSON_LIGHT);
    }

    private void refreshPermStatus() {
        setStatus(locStatus, Perms.hasFine(this), "Allowed", "Not allowed yet");
        setStatus(bgStatus, Perms.hasBackground(this), "Allowed all the time", "Not set to all the time yet");
        setStatus(notifStatus, Perms.hasNotifications(this), "Allowed", "Not allowed yet");
        setStatus(batteryStatus, Perms.ignoringBattery(this), "Tether can run in the background", "Not exempt from battery limits yet");
    }

    private void requestBatteryExemption() {
        try {
            Intent i = new Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS);
            i.setData(Uri.parse("package:" + getPackageName()));
            startActivity(i);
        } catch (ActivityNotFoundException | SecurityException e) {
            try {
                startActivity(new Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS));
            } catch (ActivityNotFoundException e2) {
                openAppSettings();
            }
        }
    }

    private void openAppSettings() {
        try {
            Intent i = new Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS);
            i.setData(Uri.parse("package:" + getPackageName()));
            startActivity(i);
        } catch (ActivityNotFoundException e) {
            Util.toast(this, "Open Settings > Apps > Tether > Permissions.");
        }
    }

    @Override
    public void onRequestPermissionsResult(int requestCode, String[] permissions, int[] grantResults) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults);
        refreshPermStatus();
        if (requestCode == REQ_FOREGROUND && Perms.hasFine(this) && Build.VERSION.SDK_INT >= 29 && !Perms.hasBackground(this)) {
            Util.toast(this, "Now choose \"Allow all the time\" in step 2.");
        }
    }

    private void finishUp() {
        if (!Perms.hasFine(this)) {
            Util.toast(this, "Tether can't share without location access. Do step 1 first.");
            return;
        }
        if (prefs.isSignedIn() && !prefs.paused()) SharingService.start(this);
        if (!permsOnly) {
            Intent i = new Intent(this, MainActivity.class);
            i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TASK);
            startActivity(i);
        }
        finish();
    }
}
