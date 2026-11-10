 # Nightfall — Design

An iPhone-first gothic browser: architectural, quiet and editorial, not Halloween novelty.

## Palette and type

Obsidian #0C0D0E canvas, charcoal #151617 panels, antique gold #C3A16A accents,
ivory #EEE8DC text, stone #96938E secondary text, wine #442531 private banner.
Cinzel display headings and wordmark; Inter body, controls and labels. Fine gold
hairlines, architectural arches, tiny diamond ornaments. No photographic assets.

## Layout and interactions

The mobile home screen has a restrained wordmark, private toggle/settings buttons,
an outlined cathedral-arch moon emblem, a centered editorial welcome, a two-column
quick-passages grid, saved bookmarks and a discrete footer. Generous dark space.
Search/address is one-hand reachable above the bottom navigation. Toolbar actions:
back, forward, share, bookmark/library, tabs. Controls have 44px touch targets.
Tabs, collection/history, settings and downloads use full-height dark sheets.
Dangerous local-data deletions and leaving the app use confirmation dialogs.

## Privacy and website appearance

Sites keep their normal styling unless the user enables locally bundled Dark Reader
dynamic colour transformation (obsidian/ivory). Preserve site layouts and fonts;
never force backgrounds on every container or inputs independently of text.
Settings has an exact-hostname original-appearance exception; normal exceptions
persist locally, private exceptions remain in memory until private tabs close.
Private tabs have a wine banner, an ephemeral iOS WebView and no persisted
tabs/history. Explicit bookmarks/downloads remain saved, including from private
tabs. No claims of anonymity or guaranteed provider authentication.

## Architecture

BrowserScreen is rendered by app/(tabs)/index.tsx through the existing root provider
chain. BrowserView.tsx uses iOS WebKit through react-native-webview; its .web.tsx
counterpart explains that the preview demonstrates controls rather than native
browsing. Browser state is stored locally with AsyncStorage. Native file helpers
handle public downloads and OS sharing; their web counterpart reports limitations.
No app account, backend route or remote database is required.

## Build and handoff

Keep native builds on the external Codemagic M2 machine. ci/ files package unsigned
IPAs and publish through the existing TrueNAS receiver. Never embed credentials in
delivered source. The tested webhook does not substitute for Git source write access.