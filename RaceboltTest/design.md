# Racebolt Test — mobile design

## Live-site revision 1.1.0 / build 2

User approved loading the real Racebolt mobile website, including the motorcycle
selector, measuring guide, blog, product catalog, accounts and basket. Preserve
the actual live site's layout rather than reconstructing it. Native safe-area
toolbar adds Back / Next / Home / Pages / Refresh and a persistent test warning.
Checkout, express payments and payment-method setup are blocked in native
navigation, a WKContentRuleList and a document-start JS guard. No Safari escape.
Live sign-ins, subscriptions, contact forms and basket updates are real actions;
this is not an offline or server-side sandbox. Previous offline assets stay in
the source folder for import compatibility but are not loaded by this version.

## Original offline prototype (not the active screen in build 2)

Use the official Racebolt wordmark/monogram and site's own product/racing imagery.
No generated imagery. Native platform explicitly chosen after managed stack offer;
source ZIP only, no Runable publishing.

- Motorsport editorial: bright white canvas, black/graphite type, Racebolt red #bf1520.
- Headlines: local Barlow Condensed 800, tight uppercase, large on hero. Body: local Barlow 400/600.
- Compact official wordmark header with accessible search/menu controls; persistent DEMO strip.
- Full-bleed real Ducati race photo, dark gradient, oversized white headline and red CTA.
- White product-photo stages, thin borders, short names, clear GBP/inclusive VAT snapshot price.
- Bottom navigation: Home / Shop / Saved / Basket. Large touch targets, red active states.
- Shop filters by material, category, search, sort; detail sheet; saved favourites; local basket with quantities.
- Demo-only sandbox: offline bundled assets, no forms/checkout/live APIs, production navigation blocked.
- Test app name Racebolt Test; bundle com.rossdymond.racebolttest; no overlap with CarbPrep.