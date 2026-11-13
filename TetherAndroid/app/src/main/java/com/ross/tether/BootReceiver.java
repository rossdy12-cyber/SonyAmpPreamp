package com.ross.tether;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;

/** Restarts location sharing after a reboot or an app update, if the user is signed in and not paused. */
public class BootReceiver extends BroadcastReceiver {
    @Override
    public void onReceive(Context context, Intent intent) {
        if (intent == null) return;
        String a = intent.getAction();
        if (!Intent.ACTION_BOOT_COMPLETED.equals(a) && !Intent.ACTION_MY_PACKAGE_REPLACED.equals(a)) return;
        Prefs p = new Prefs(context);
        if (p.isSignedIn() && !p.paused() && Perms.hasFine(context)) {
            SharingService.start(context);
        }
    }
}
