# Mira — live virtual try-on

SwiftUI, iOS 17+. Open `Mira.xcodeproj` and run.

Camera only works on device; the Simulator falls back to a flat "dressing room" so the
whole flow is still demoable. Try-on is a parametric garment silhouette laid over the feed —
drag to line it up, double-tap to re-center. Swap the silhouette for the real render when the API lands.

Dev launch args (Xcode → Edit Scheme → Arguments), jump straight to a screen:
`dev:mirror` `dev:closet` `dev:lookbook` `dev:look` `dev:seed` `dev:fit`
`dev:auth` `dev:paywall` `dev:topup` `dev:profile` `dev:pro` `dev:broke`

zsh does not word-split an unquoted variable — pass several with `${=args}`.
