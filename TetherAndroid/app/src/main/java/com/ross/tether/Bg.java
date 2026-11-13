package com.ross.tether;

import android.content.Context;
import android.os.Handler;
import android.os.Looper;

import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/** Tiny background-thread helper. Callbacks run on the main thread. */
public final class Bg {
    private Bg() {}

    private static final ExecutorService POOL = Executors.newFixedThreadPool(4);
    private static final Handler MAIN = new Handler(Looper.getMainLooper());

    public interface Work<T> {
        T run() throws Exception;
    }

    public interface Done<T> {
        void done(T value, Exception error);
    }

    public static void run(Runnable r) {
        POOL.execute(r);
    }

    public static void ui(Runnable r) {
        MAIN.post(r);
    }

    /** Runs work off the main thread. A 401 anywhere signs the user out instead of calling back. */
    public static <T> void async(final Context ctx, final Work<T> work, final Done<T> done) {
        final Context app = ctx.getApplicationContext();
        POOL.execute(new Runnable() {
            @Override
            public void run() {
                T value = null;
                Exception error = null;
                try {
                    value = work.run();
                } catch (Exception e) {
                    error = e;
                }
                final T fv = value;
                final Exception fe = error;
                MAIN.post(new Runnable() {
                    @Override
                    public void run() {
                        if (fe instanceof Api.ApiException && ((Api.ApiException) fe).status == 401) {
                            Session.signOut(app, "You were signed out. Please join again.");
                            return;
                        }
                        if (done != null) done.done(fv, fe);
                    }
                });
            }
        });
    }
}
