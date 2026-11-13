# Tether for Android

Private family location sharing for Android phones, such as a Samsung Galaxy Note 8. It talks to the same
self-hosted Tether server as the iPhone app (`tether-server`), so everyone shows up on one map. There is no
subscription, no ads, and nothing goes to Google: maps come from OpenStreetMap and locations stay on your NAS.

- **Live map** of everyone in the circle with battery level, speed and last-updated time.
- **Places** (Home, Work, School...) with arrive and leave alerts, set by long-pressing the map.
- **Timeline** for any person and day: where they stayed, trips between, and the path on the map.
- **Alerts** feed, check-in, and a hold-for-3-seconds **SOS** button.
- **Background sharing** in a foreground service, with an offline queue so nothing is lost without signal.

Android 7.0 (API 24) and newer. The Note 8 ships with 7.1 and can be updated to 9; both work.

## Install on the phone

1. On the phone, open the store's login page in Chrome or Samsung Internet:
   `https://navidrome.nas-server.co.uk/sidestore-api/login` and sign in with your own account.
2. Open the **Android** section and tap **Download** next to Tether.
3. When Android asks, allow **Install unknown apps** for that browser (Settings > Apps > the browser >
   Install unknown apps), then open the downloaded file and tap **Install**.
4. Open Tether and enter:
   - **Server address:** `https://navidrome.nas-server.co.uk/tether`
   - **Invite code:** the one-time code from the server admin
   - **Your name** and a colour.

Updates use the same steps; because every build is signed with the same key, Android installs them over the
top without losing your sign-in.

## Permissions (do these once)

The app walks through them, and the Settings tab has a "Check permissions and battery" button.

1. **Location: Allow.**
2. **Location: Allow all the time.** On Android 10 this is a dialog option. On Android 11 and newer, tap the
   button, then in the page that opens choose **Location > Allow all the time**.
3. **Notifications** (Android 13 and newer only).
4. **Battery: let Tether run in the background.** Tap "Let Tether run" and choose **Allow**.

### Samsung battery settings (important on the Note 8)

Samsung's battery management puts apps to sleep and silently stops location sharing. In addition to step 4:

- Settings > Apps > **Tether** > Battery > **Unrestricted**.
- Settings > Battery and device care > Battery > Background usage limits: turn **Put unused apps to sleep**
  off, and make sure Tether is not in **Sleeping apps**. Add it to **Never sleeping apps**.
- If the phone offers it, lock the app in the recent-apps list (tap the icon at the top of its card > Keep open).

## How it works

- A **foreground service** shows a quiet notification ("Tether is sharing your location") with a **Pause**
  button, and listens for location fixes:
  - **Precise:** GPS every 10 s / 25 m while moving, with network location as a fallback.
  - **Battery saver:** passive and network fixes only (60 s / 100 m).
  - A stationary phone gets no movement updates, so the service asks for one fix every 4 minutes (15 in
    Battery saver) to show it is still alive.
- Points are saved to a file first, then uploaded in batches of up to 200 with exponential back-off.
- Every 30 seconds the service asks the server for new events and shows a local notification for other
  people's arrivals, check-ins, low batteries and SOS alerts. SOS uses a separate loud channel.
- The server decides when someone arrives at or leaves a place; the app only reports where it is.
- A boot receiver restarts sharing after the phone reboots, if you are signed in and have not paused.

## Known limits

- **No push notifications.** There is no Google Play services or Firebase here, so alerts come from the 30
  second poll while the service runs. If Samsung kills the service, alerts and location updates stop until
  you open the app. Do the battery steps above.
- Arrive and leave alerts can be a minute or two late (polling plus the movement filter).
- The sign-in token is kept in the app's private storage (SharedPreferences, `MODE_PRIVATE`). Moving it into
  the Android Keystore would be a future improvement.
- Not tested on a real device yet: this build was written without an Android toolchain, so the first CI build
  is the real compile test.

## Build

`build-and-publish.sh` runs on Codemagic (JDK 17 plus the Android SDK). It downloads Gradle 8.7, runs
`assembleRelease`, signs the APK with the persistent keystore stored on the NAS (created on first use), and
uploads it to the store. Locally: install JDK 17 and the Android SDK (platform 34, build-tools 34.0.0), put
`sdk.dir=...` in `local.properties`, and run Gradle 8.7 `assembleRelease`; an unsigned APK appears in
`app/build/outputs/apk/release/`.

The code uses only platform classes (no AppCompat, Compose, Kotlin, Play services or Firebase). The one
library is osmdroid for the OpenStreetMap tiles. `android.useAndroidX=true` is set only because osmdroid pulls
in androidx annotation libraries.
