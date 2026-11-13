# Tether

Private family location sharing for iPhone, with no subscription. Your circle's locations are stored on **your own server** (`tether-server`, in the keepwatch repo), never with a third party.

## What it does

- **Map:** everyone in your circle as a coloured avatar with a battery ring. Tap one for where they are (place or street address), what they're doing (walking, driving, still), battery and charging, how recently they updated, directions in Apple Maps, and a shortcut to their timeline. The target button fits everyone on screen.
- **Places:** Home, Work, School and so on. Pick a spot on the map or use where you are, set a 50 m to 2 km radius and an icon. Tether tells the rest of the circle when someone arrives or leaves.
- **Timeline:** pick a person and a day (only days with data are offered) to see where they stopped and how they travelled, with the route drawn on the map, distances and durations.
- **Activity:** a feed of arrivals, departures, check-ins, SOS alerts and low batteries.
- **Check-in and SOS:** "I'm here" is one tap (the pencil adds a note such as "On my way"). **SOS is a hold-for-three-seconds button** so it can't be pressed by accident. It sends your location to the whole circle, and a Cancel SOS button appears straight afterwards.
- **Pause sharing** whenever you want. Your circle sees "paused" and nothing is recorded while it's on.
- **Leave the circle** deletes your history from the server.

## Setting it up

1. Whoever runs the server creates an invite code (see `tether-server/README.md`, "Invite someone").
2. Install Tether (from the Stark store, signed with your developer profile).
3. Open it and enter:
   - **Server address:** `https://navidrome.nas-server.co.uk/tether` (already filled in)
   - **Invite code:** the code you were given (case and dashes don't matter)
   - **Your name** and a colour
4. Allow location. iOS asks in two steps:
   1. Choose **Allow While Using App** first.
   2. Tether then asks again: choose **Change to Always Allow**.
   If you miss it, go to **Settings > Tether > Location**, pick **Always** and switch **Precise Location** on. Tether's own Settings tab shows the current state and has an **Open iOS Settings** button.
5. Allow motion & fitness (used to tell walking from driving and to save battery) and notifications.

Without **Always**, Tether only shares while the app is open, and your circle will see you go quiet.

## Battery

- **Precise** (default): best GPS accuracy, an update about every 25 m while you move. After five minutes of standing still it drops to a low-power mode, and goes back up when you move again.
- **Battery saver:** about every 100 m, relying on iOS's significant-change and visit wake-ups. Much lighter, a little less exact.
- Both modes also watch your circle's places with iOS geofencing (up to 20, nearest first), so arriving or leaving uploads your position straight away, even from a sleeping app.
- Expect roughly 5-10% extra battery per day in Precise mode with normal use; Battery saver is usually 2-4%. iOS shows a blue location indicator while Tether runs in the background. That's expected.
- Points are saved on the phone and uploaded in batches. If you're offline nothing is lost: they're sent, oldest first, when the connection comes back.

## Notifications

- **Local alerts** (Settings > Notifications): when iOS wakes Tether in the background, new arrivals, SOS and so on appear as notifications. These can be late or missed, because iOS decides when a closed app may run.
- **Push** (instant): needs the server's push relay running with your Apple APNs key, **and** a copy of Tether signed with your **paid developer profile** that includes the push entitlement. `Tether.entitlements` already asks for `aps-environment` and `time-sensitive` notifications. Once push works, turn off **Local alerts** to avoid doubles.
- A free Apple ID can't receive push. Everything else works without it.

## What needs the paid developer profile

| Feature | Free Apple ID | Paid profile with the push entitlement |
|---|---|---|
| Map, places, timeline, SOS, check-in | yes | yes |
| Background location | yes | yes |
| Local alerts (delayed) | yes | yes |
| Instant push alerts | no | yes |

The push token is sent to the server as a `development` token. If you ever sign with a production profile, the server's `environment` for that device should be `production`; change the single `"environment"` value in `Session.registerDevice()`.

## Build

The Stark builder generates the build script and Codemagic workflow from `project.yml` (bundle id `com.ross.tether`). No third-party packages. The app needs HTTPS to reach the server (iOS blocks plain `http://`).

## Privacy

- Locations go only to the server you enter. Nothing is sent to anyone else.
- The member token is kept in the iOS Keychain, readable after first unlock so background wake-ups can upload.
- Everyone in a circle can see everyone else's location and history. Only invite people you trust.
