package com.ross.tether;

import android.content.Context;
import android.view.View;

/** One tab of the main activity. Subclasses build `root` in their constructor. */
public abstract class Screen {
    protected final MainActivity host;
    protected final Context ctx;
    public View root;

    Screen(MainActivity host) {
        this.host = host;
        this.ctx = host;
    }

    /** The tab became visible (or the activity resumed while it was showing). */
    abstract void onShow();

    /** The tab was hidden (or the activity paused). */
    void onHide() {
    }

    /** Fresh circle data (members and places) arrived. */
    void onCircle() {
    }

    void destroy() {
    }
}
