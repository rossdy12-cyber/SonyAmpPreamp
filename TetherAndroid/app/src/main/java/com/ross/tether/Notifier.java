package com.ross.tether;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.media.AudioAttributes;
import android.media.RingtoneManager;
import android.net.Uri;
import android.os.Build;

/** Notification channels and builders. */
public final class Notifier {
    private Notifier() {}

    public static final String CH_SHARE = "share";
    public static final String CH_ALERT = "alerts";
    public static final String CH_SOS = "sos";

    private static final long[] SOS_PATTERN = {0, 600, 300, 600, 300, 600};

    public static void ensureChannels(Context c) {
        if (Build.VERSION.SDK_INT < 26) return;
        NotificationManager nm = (NotificationManager) c.getSystemService(Context.NOTIFICATION_SERVICE);
        if (nm == null) return;

        NotificationChannel share = new NotificationChannel(CH_SHARE, "Location sharing", NotificationManager.IMPORTANCE_LOW);
        share.setDescription("The quiet notification that keeps Tether sharing your location.");
        share.setShowBadge(false);
        nm.createNotificationChannel(share);

        NotificationChannel alerts = new NotificationChannel(CH_ALERT, "Circle alerts", NotificationManager.IMPORTANCE_DEFAULT);
        alerts.setDescription("Arrivals, departures, check-ins and low batteries.");
        nm.createNotificationChannel(alerts);

        NotificationChannel sos = new NotificationChannel(CH_SOS, "SOS alerts", NotificationManager.IMPORTANCE_HIGH);
        sos.setDescription("Emergency alerts from people in your circle.");
        sos.enableVibration(true);
        sos.setVibrationPattern(SOS_PATTERN);
        AudioAttributes attrs = new AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_ALARM)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build();
        sos.setSound(RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM), attrs);
        nm.createNotificationChannel(sos);
    }

    private static int immutable() {
        return Build.VERSION.SDK_INT >= 23 ? PendingIntent.FLAG_IMMUTABLE : 0;
    }

    @SuppressWarnings("deprecation")
    private static Notification.Builder builder(Context c, String channel) {
        if (Build.VERSION.SDK_INT >= 26) return new Notification.Builder(c, channel);
        return new Notification.Builder(c);
    }

    private static PendingIntent openApp(Context c) {
        Intent i = new Intent(c, MainActivity.class);
        i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_SINGLE_TOP);
        return PendingIntent.getActivity(c, 0, i, PendingIntent.FLAG_UPDATE_CURRENT | immutable());
    }

    @SuppressWarnings("deprecation")
    public static Notification sharing(Context c, String text) {
        Intent pause = new Intent(c, SharingService.class);
        pause.setAction(SharingService.ACTION_PAUSE);
        PendingIntent pausePi = PendingIntent.getService(c, 1, pause, PendingIntent.FLAG_UPDATE_CURRENT | immutable());
        Notification.Builder b = builder(c, CH_SHARE)
                .setSmallIcon(R.drawable.ic_stat_tether)
                .setContentTitle("Tether is sharing your location")
                .setContentText(text)
                .setOngoing(true)
                .setContentIntent(openApp(c))
                .addAction(R.drawable.ic_stat_tether, "Pause", pausePi);
        if (Build.VERSION.SDK_INT < 26) b.setPriority(Notification.PRIORITY_LOW);
        return b.build();
    }

    @SuppressWarnings("deprecation")
    public static void event(Context c, Models.Event e) {
        NotificationManager nm = (NotificationManager) c.getSystemService(Context.NOTIFICATION_SERVICE);
        if (nm == null) return;
        boolean sos = "sos".equals(e.kind);
        Notification.Builder b = builder(c, sos ? CH_SOS : CH_ALERT)
                .setSmallIcon(R.drawable.ic_stat_tether)
                .setContentTitle(e.title())
                .setContentText(e.text.isEmpty() ? Util.clock(e.ts) : e.text)
                .setAutoCancel(true)
                .setContentIntent(openApp(c));
        if (Build.VERSION.SDK_INT < 26) {
            if (sos) {
                Uri alarm = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM);
                b.setPriority(Notification.PRIORITY_HIGH).setSound(alarm).setVibrate(SOS_PATTERN);
            } else {
                b.setPriority(Notification.PRIORITY_DEFAULT).setDefaults(Notification.DEFAULT_ALL);
            }
        }
        if (sos) b.setCategory(Notification.CATEGORY_ALARM);
        nm.notify((int) (e.id % 100000) + 1000, b.build());
    }
}
