package com.ross.tether;

import android.content.Context;
import android.content.Intent;

/** Sign-out handling shared by the UI and the background service. */
public final class Session {
    private Session() {}

    public static void signOut(Context app, String message) {
        new Prefs(app).clear();
        try {
            app.stopService(new Intent(app, SharingService.class));
        } catch (Exception ignored) {
        }
        UploadQueue.get(app).clear();
        try {
            Intent i = new Intent(app, OnboardingActivity.class);
            i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TASK);
            i.putExtra(OnboardingActivity.EXTRA_MESSAGE, message);
            app.startActivity(i);
        } catch (Exception ignored) {
            // Started from the background on a recent Android: the sign-in screen shows next time the app opens.
        }
    }
}
