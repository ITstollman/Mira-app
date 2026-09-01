# App Store listing — Mira

Paste-ready. Every field is inside Apple's character limit.

## Name (30 max) — 25
Mira: Live Virtual Try-On

## Subtitle (30 max) — 28
Try on clothes from any shop

## Keywords (100 max, comma-separated, no spaces) — 98
clothes,outfit,fitting,dressing,room,fashion,wardrobe,closet,style,shopping,dress,mirror,ai,camera

No retailer names here. "shein", "zara" and friends are other people's
trademarks and Apple rejects for it under 5.2.1.

## Promotional text (170 max) — 118
See any garment on your own body, live, before you buy it. Paste a link from
almost any store and it appears on you in real time.

## Description
Mira is a mirror that shows you clothes you do not own yet.

Point your camera at yourself and the garment appears on you — moving as you
move, in real time. Not a flat cut-out pasted onto a photo. A live reflection.

HOW IT WORKS
• Copy a product link from almost any online store
• Mira reads the listing and pulls the garment
• Hold up your phone and see it on you, live
• Keep the looks worth keeping

WHY IT IS DIFFERENT
Most try-on apps generate a still image and hand it back. Mira runs live, so
you can turn, step back, and watch the fit move before you decide. That is the
part a photo cannot tell you.

WHAT YOU CAN TRY
Dresses, tops, jackets, knitwear, trousers, skirts. Anything with a product
page and a photo.

PRIVACY
Your camera feed is used to render your try-on and nothing else. Full terms
and privacy policy: https://getmiratryon.com/legal.html

Questions: support@getmiratryon.com

## Category
Primary: Shopping   Secondary: Lifestyle

## Age rating
4+

## URLs
getmiratryon.com has no TLS certificate yet, and Apple checks these resolve. Use the
Railway host until the cert lands, then swap — all three are editable any time.

Support:   https://mira-production-d6d6.up.railway.app/legal.html#support
Privacy:   https://mira-production-d6d6.up.railway.app/legal.html#privacy
Marketing: leave blank (optional) until the domain answers

Once getmiratryon.com serves:
Support:   https://getmiratryon.com/legal.html#support
Privacy:   https://getmiratryon.com/legal.html#privacy
Marketing: https://getmiratryon.com

## Screenshots
store/export/*.png — 1290x2796, six panels, iPhone 6.9" slot.
See the two rejection risks noted for 06-the-mark.png and 03-any-shop.png.


## Copyright (200 max)
2026 Itamar Stollman

## SKU
mira-ios-001

## App Review Information

Sign-in required: YES — MiraApp gates everything behind AuthView, so a reviewer
with no account sees a sign-in wall and rejects the build. A demo email/password
account is mandatory.

    User name: review@getmiratryon.com
    Password:  <set when the account is created>

Contact:
    First name: Itamar
    Last name:  Stollman
    Phone:      <fill in on the App Store Connect form — this repo is public>
    Email:      support@getmiratryon.com

### Notes (4000 max)
Mira renders a live virtual try-on from the device camera, so the app needs a
physical device — the Simulator has no camera feed and the main screen will be
blank there.

To test:
1. Sign in with the demo account above.
2. Tap the camera button on the home screen.
3. Open the closet sheet and paste a product URL from any clothing retailer's
   website. Mira reads the listing and extracts the garment.
4. Hold the phone so your upper body is in frame. The garment renders onto you
   in real time.

The camera feed is processed to render the try-on and is not stored.

## App Store Version Release
Manually release this version — so launch day is your call, not App Review's.


## App Information page — the four blockers

### Primary category
Shopping. Secondary: Lifestyle.

### Content Rights
"Does your app contain, show, or access third-party content?" -> **Yes**, then tick the
confirmation. Mira fetches and displays garment photos from retailers' own product pages,
which is third-party content by Apple's definition. No documentation upload follows; it is
an attestation. Answering No would be false and is the kind of thing that surfaces at
review when the reviewer pastes a Zara link.

### Age Rating -> 4+
Everything in the content questionnaire is None / No. The two that look like traps:

- **Unrestricted Web Access: No.** The only WKWebView is Legal.swift:64 and it calls
  loadFileURL on the bundled legal.html — it cannot navigate anywhere.
- **User-Generated Content: No.** LookView has a ShareLink, but that exports to the
  user's own share sheet; nothing is published to other users, so no moderation duty.

Answer In-App Purchases = No *for now*. It becomes Yes the moment real StoreKit products
exist, and the rating must be updated then.

### App Privacy — not just the URL
The URL alone will not clear it; the Data Types questionnaire has to be filled too.
FirebaseAnalytics is linked (project.pbxproj:10), so "we collect nothing" is not available:

| Data type | Collected | Linked to user | Tracking | Why |
|---|---|---|---|---|
| Email address | Yes | Yes | No | Firebase Auth sign-in |
| User ID | Yes | Yes | No | Firebase uid keys the server wallet |
| Purchase history | Yes | Yes | No | the sparks ledger |
| Product interaction | Yes | Yes | No | FirebaseAnalytics |
| Crash data | Yes | No | No | FirebaseAnalytics |
| Camera / photos | No | — | — | frames go to the render and are not stored |

Camera is the one worth getting right: the feed is sent to Decart to render the try-on and
is not retained, so it is *not* "collected" under Apple's definition — but say so in the
Notes field so a reviewer does not have to guess.
