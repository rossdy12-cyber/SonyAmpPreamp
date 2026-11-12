# Sources and snapshot notes

## Active live-site build 1.1.1 / 3

The native app loads https://raceboltuk.com/ directly. The site's live layout,
catalog, prices and content are not the retained eight-product snapshot below.
Read-only HTTP 200/browser checks on 11 November 2026 covered:

- Home and motorcycle selector: https://raceboltuk.com/
- Measuring guide: https://raceboltuk.com/how-to-measure-your-motorcycle-bolts/
- Blog: https://raceboltuk.com/blog/
- Basket: https://raceboltuk.com/basket/
- Account: https://raceboltuk.com/my-account/

The home selector uses a GET form targeting `/motorcycle-kit-results/`, with
make/model/year/material/kit-type fields. Honda model options populated in the
read-only browser check. No login, live basket change or purchase was tested.
The live basket page exposed checkout `/checkout/`, standard WooCommerce
`wc-ajax` URLs and PayPal `ppc-create-order`/`ppc-approve-order` integration.
Safeguards were built against those patterns; see README for limitations.

WebKit regex compatibility reference used for the build 3 correction:
https://github.com/WebKit/WebKit/blob/main/Source/WebCore/contentextensions/URLFilterParser.cpp
The `disjunction` callback rejects regex alternatives. Build 3 generates separate
rules instead of using `|`; remote macOS Apple WebKit preflight and iPhone startup
compilation remain required, not inferred from browser/Python regex tests.

## Retained original offline assets (not the native start page)

Snapshot: **11 November 2026**. Private prototype only; no live price, stock, variant or fitment guarantee. Prices below are inclusive VAT; range listings use the lowest displayed value.

## Brand and photography

Source homepage: https://raceboltuk.com/

- Logo, cropped wordmark/monogram and derived app icons: https://racebolt.fsn1.your-objectstorage.com/wp-content/uploads/2026/06/1780476533748-c2ec9c4c-9628-4d7b-a62f-bb0aa57d012b_1.webp
- Homepage racing photograph (`hero.webp`): https://racebolt.fsn1.your-objectstorage.com/wp-content/uploads/2026/06/BSB_R2_DoningtonPark_BSBQ-8081-1-768x512.webp
- Engineering photograph (`engineering.webp`): https://racebolt.fsn1.your-objectstorage.com/wp-content/uploads/2026/04/WSBK-9th-Feb-350x350-1.webp

Racebolt logo, photographs and product information remain their owners’ material. Inclusion is not a license for public distribution. Review permissions before releasing this prototype.

## Product snapshot

### Titanium Race Drilled Hex Head Bolt M10 x 1.5mm x 60mm
- SKU: `RB-TIHX1060R`
- Displayed source price: £ 11.84 – £ 13.38 Price range: £11.84 through £13.38 incl. VAT
- Demo price: £11.84 incl. VAT
- Product page: https://raceboltuk.com/product/titanium/titanium-race-flanged-hex-head-bolts/titanium-c4-titanium-race-flanged-hex-head-bolts-c90-racebolt-titanium-race-drilled-hex-head-bolt-m10-x-1-5mm-x-60mm-black-p37228/
- Image: https://racebolt.fsn1.your-objectstorage.com/wp-content/uploads/2026/03/1680528961-64221800.webp
- Local image: `www/assets/ti-race.webp`

### Titanium Tapered Socket Cap Bolt M6 x 1.0mm x 12mm
- SKU: `RB-TISC612`
- Displayed source price: £ 3.85 – £ 4.04 Price range: £3.85 through £4.04 incl. VAT
- Demo price: £3.85 incl. VAT
- Product page: https://raceboltuk.com/product/titanium/titanium-tapered-socket-cap-bolts/titanium-c4-titanium-tapered-socket-cap-bolts-c1195-racebolt-titanium-tapered-socket-cap-bolt-m6-x-1-0mm-x-12mm-blue-p36960/
- Image: https://racebolt.fsn1.your-objectstorage.com/wp-content/uploads/2026/03/1677769316-09063400.webp
- Local image: `www/assets/ti-blue.webp`

### Titanium Flanged Axle Nut M24 x 1.50mm
- SKU: `RB-TINUT24150001`
- Displayed source price: £ 40.96 incl. VAT
- Demo price: £40.96 incl. VAT
- Product page: https://raceboltuk.com/product/titanium/titanium-axle-nuts/titanium-c4-titanium-axle-nuts-c1290-racebolt-titanium-axle-nut-m24-x-1-50mm-32mm-socket-p30727/
- Image: https://racebolt.fsn1.your-objectstorage.com/wp-content/uploads/2026/03/1677767593-71169200.webp
- Local image: `www/assets/ti-axle.webp`

### Stainless Steel Flanged Hex Head Bolt M5 x 0.8mm x 15mm
- SKU: `RB-SSHX515`
- Displayed source price: £ 2.80 incl. VAT
- Demo price: £2.80 incl. VAT
- Product page: https://raceboltuk.com/product/stainless-steel/stainless-steel-flanged-hex-head-bolts/stainless-steel-c2-stainless-steel-flanged-hex-head-bolts-c12-racebolt-stainless-steel-flanged-hex-head-bolt-m5-x-0-8mm-x-15mm-p27078/
- Image: https://racebolt.fsn1.your-objectstorage.com/wp-content/uploads/2026/03/1662388918-44145200.webp
- Local image: `www/assets/ss-hex.webp`

### Stainless Steel Flat Washer M10 (20mm O/D)
- SKU: `RB-SSWA10`
- Displayed source price: £ 1.73 incl. VAT
- Demo price: £1.73 incl. VAT
- Product page: https://raceboltuk.com/product/stainless-steel/stainless-steel-washers/stainless-steel-c2-stainless-steel-washers-c1235-racebolt-stainless-steel-flat-washer-m10-20mm-o-d-p30133/
- Image: https://racebolt.fsn1.your-objectstorage.com/wp-content/uploads/2026/03/1-x-RB-SSWA10-scaled.webp
- Local image: `www/assets/ss-washer.webp`

### Aluminium Washer M10 (20mm o/d)
- SKU: `RB-ALWA10`
- Displayed source price: £ 0.41 – £ 0.42 Price range: £0.41 through £0.42 incl. VAT
- Demo price: £0.41 incl. VAT
- Product page: https://raceboltuk.com/product/aluminium/aluminium-washers/aluminium-c3-aluminium-washers-c1246-racebolt-aluminium-washer-m10-20mm-o-d-blue-p33394/
- Image: https://racebolt.fsn1.your-objectstorage.com/wp-content/uploads/2026/03/1695030858-77494200.webp
- Local image: `www/assets/al-washer.webp`

### Aluminium Race Drilled Flanged Nut M8x 1.25mm Rolled Thread
- SKU: `RB-ALFLN8RR`
- Displayed source price: £ 3.06 incl. VAT
- Demo price: £3.06 incl. VAT
- Product page: https://raceboltuk.com/product/aluminium/aluminium-nuts-aluminium/aluminium-c3-aluminium-nuts-c47-racebolt-aluminium-race-drilled-flanged-nut-m8x-1-25mm-rolled-thread-blue-p45207/
- Image: https://racebolt.fsn1.your-objectstorage.com/wp-content/uploads/2026/03/1714745746-42719000.webp
- Local image: `www/assets/al-nut.webp`

### Aluminium Dome Head Bolt M4 x 0.5mm x 12mm
- SKU: `RB-ALFB412F`
- Displayed source price: £ 1.57 incl. VAT
- Demo price: £1.57 incl. VAT
- Product page: https://raceboltuk.com/product/aluminium/aluminium-dome-head-bolts/aluminium-c3-aluminium-dome-head-bolts-c46-racebolt-aluminium-dome-head-bolt-m4-x-0-5mm-x-12mm-gold-p31273/
- Image: https://racebolt.fsn1.your-objectstorage.com/wp-content/uploads/2026/03/1695030745-71413800.webp
- Local image: `www/assets/al-dome.webp`

## Fonts

Barlow and Barlow Condensed by Jeremy Tribby, distributed under the SIL Open Font License 1.1. License text is bundled in `www/assets/Barlow-OFL.txt` and `www/assets/BarlowCondensed-OFL.txt`.

- Families: https://fonts.google.com/specimen/Barlow and https://fonts.google.com/specimen/Barlow+Condensed
- Upstream license: https://github.com/google/fonts/blob/main/ofl/barlow/OFL.txt and https://github.com/google/fonts/blob/main/ofl/barlowcondensed/OFL.txt
- Download stylesheet: https://fonts.googleapis.com/css2?family=Barlow:wght@400;500;600;700&family=Barlow+Condensed:wght@600;700;800&display=swap

- Barlow 400: https://fonts.gstatic.com/s/barlow/v13/7cHpv4kjgoGqM7EPCw.ttf
- Barlow 600: https://fonts.gstatic.com/s/barlow/v13/7cHqv4kjgoGqM7E30-8c4A.ttf
- Barlow 700: https://fonts.gstatic.com/s/barlow/v13/7cHqv4kjgoGqM7E3t-4c4A.ttf
- Barlow Condensed 700: https://fonts.gstatic.com/s/barlowcondensed/v13/HTxwL3I-JCGChYJ8VI-L6OO_au7B46r2_3E.ttf
- Barlow Condensed 800: https://fonts.gstatic.com/s/barlowcondensed/v13/HTxwL3I-JCGChYJ8VI-L6OO_au7B47b1_3E.ttf
