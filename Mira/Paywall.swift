import SwiftUI

struct PaywallView: View {
    @Environment(Account.self) private var account
    @Environment(\.dismiss) private var dismiss
    @State private var picked: Plan = .yearly

    private var shop: Shop { account.shop }
    private var busy: Bool { shop.buying != nil }

    var body: some View {
        ZStack(alignment: .top) {
            M.cream.ignoresSafeArea()

            // the buy block sits on the floor and the reel absorbs whatever is left, so
            // this lands the same on a 13 mini as on a Pro Max instead of leaving a hole
            VStack(spacing: 0) {
                // resizeAspectFill centres its crop, and centred on a 704:1248 clip in a
                // slot this shape it takes her head off. Hand the reel its full height and
                // pin the top instead: the slot clips the boots, which nobody is buying.
                // ponytail: the ratio is demo.mp4's. Recut the reel, retype the two numbers.
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .frame(minHeight: 170)
                    .overlay(alignment: .top) {
                        Reel(name: "demo", loop: true) { ReelStandin() }
                            .aspectRatio(704.0 / 1248, contentMode: .fill)
                            // flush to the top is all ceiling and no clothes; this gives
                            // back the wall above her head and keeps the face
                            .offset(y: -70)
                    }
                    .clipped()
                    .overlay(alignment: .bottom) {
                        // the video has to end in cream or the headline looks pasted on
                        LinearGradient(colors: [M.cream.opacity(0), M.cream],
                                       startPoint: .top, endPoint: .bottom)
                            .frame(height: 120)
                    }

                VStack(spacing: 0) {
                    // App Review's required-info list for auto-renewables opens with the
                    // title of the subscription, and the headline under this sells the
                    // benefit without ever naming the thing being sold.
                    Text("Mira Pro").tracked(10, 2.2)
                        .foregroundStyle(M.mute)
                        .padding(.bottom, 11)

                    Text("\(Plan.included) a month to keep going")
                        .font(M.display(33, .light))
                        .kerning(0.5)
                        .foregroundStyle(M.ink)
                        .multilineTextAlignment(.center)
                        .lineSpacing(2)
                        .padding(.horizontal, 26)
                        .padding(.bottom, 26)

                    VStack(spacing: 12) {
                        ForEach(Plan.allCases) { plan in
                            PlanRow(plan: plan, on: picked == plan, shop: shop) {
                                tap()
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { picked = plan }
                            }
                        }
                    }
                    .padding(.horizontal, 22)

                    Button {
                        // The sheet closes on a purchase that actually landed, and stays put
                        // on one that didn't — the alert below says which.
                        Task { if await account.subscribe(picked) { dismiss() } }
                    } label: {
                        ZStack {
                            Text("Continue").tracked(13, 2.6).opacity(busy ? 0 : 1)
                            if busy { ProgressView().tint(M.onRose) }
                        }
                        .foregroundStyle(M.onRose)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                        .background(Capsule().fill(M.rose))
                        .shadow(color: M.rouge.opacity(0.28), radius: 16, y: 7)
                    }
                    .disabled(busy)
                    .padding(.horizontal, 22)
                    .padding(.top, 22)

                    Text(picked.note(shop.price(picked.productID) ?? picked.price))
                        .font(.system(size: 11))
                        .foregroundStyle(M.mute.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .lineSpacing(2)
                        .padding(.horizontal, 34)
                        .padding(.top, 14)

                    FinePrint().padding(.top, 13)
                }
                .padding(.bottom, 10)
                .fixedSize(horizontal: false, vertical: true)
            }
            .ignoresSafeArea(edges: .top)
            .faults(shop)

            HStack {
                Spacer()
                Button { tap(); dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(M.ink)
                        .puck(34)
                }
                .accessibilityLabel("Close")
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
        }
    }
}

/// No reel in the bundle yet: the mark on blush, so the top of the paywall still reads
/// as a place a video goes rather than a hole.
private struct ReelStandin: View {
    var body: some View {
        ZStack {
            M.blush
            MiraMark(size: 76)
        }
    }
}

private struct PlanRow: View {
    let plan: Plan
    let on: Bool
    let shop: Shop
    let pick: () -> Void

    /// Apple's price where Apple has one, ours where the store hasn't answered yet — a
    /// row that renders blank while the App Store thinks is worse than a row in dollars.
    private var price: String { shop.price(plan.productID) ?? plan.price }
    private var perMonth: String {
        shop.split(plan.productID, by: plan.months).map { "\($0)/mo" } ?? plan.perMonth
    }

    var body: some View {
        Button(action: pick) {
            VStack(spacing: 0) {
                // the offer rides on top of the card it belongs to, not beside the price
                if let badge = plan.badge {
                    Text(badge)
                        .tracked(9, 1.8)
                        .foregroundStyle(M.onRose)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(M.rose)
                }
                // One number is set large here, and it is the one the card is charged.
                // The cadence, the /mo it works out to and the discount all sit at 9-11pt
                // grey underneath or in the badge. 1.0 (2) was rejected under 3.1.2(c)
                // for setting the /mo figure in semibold on the right, where it read as
                // the headline price and buried the $149.99 in a grey subtitle.
                HStack(spacing: 13) {
                    Tick(on: on)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(price)
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundStyle(on ? M.ink : M.mute)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Text(plan.terms(perMonth))
                            .font(.system(size: 11))
                            .foregroundStyle(M.mute)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                    Spacer(minLength: 6)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 15)
                .frame(maxWidth: .infinity)
                .background(.white)
            }
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(on ? M.rose : M.shell, lineWidth: on ? 2 : 1))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - topups

struct TopupSheet: View {
    @Environment(Account.self) private var account
    @Environment(\.dismiss) private var dismiss
    /// Opens on the badged one, the way the paywall opens on the plan it is selling.
    @State private var picked = Pack.all.first { $0.note != nil }?.id ?? Pack.all[0].id

    private var pack: Pack { Pack.all.first { $0.id == picked } ?? Pack.all[0] }
    private var shop: Shop { account.shop }
    private var busy: Bool { shop.buying != nil }

    /// Out is out. Anyone who can still afford a fitting came here from settings, and
    /// telling them they're empty is a lie they can see through by backing out a screen.
    private var headline: String {
        account.sparks < Spend.perFitting
            ? "Oh no — you're out of fittings. Get more!"
            : "\(Spend.said(account.sparks)) \(Spend.unit(account.sparks)) left. Get more!"
    }

    var body: some View {
        ZStack {
            M.cream.ignoresSafeArea()

            // same shape as the paywall: the buy block sits on the floor and the list
            // above it takes whatever is left
            VStack(spacing: 0) {
                // the header and the packs float as one block between the lid and the buy
                // bar — capping the middle gap is what stops the slack pooling under the
                // headline and leaving the rocket stuck to the ceiling
                Spacer(minLength: 18)

                Image("Rocket")
                    .resizable().scaledToFit()
                    .frame(width: 78, height: 78)

                // one line, said out loud. The rate card that used to sit here was
                // explaining our billing to someone who just wants the mirror back on.
                Text(headline)
                    .font(M.display(25, .light))
                    .foregroundStyle(M.ink)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .padding(.horizontal, 34)
                    .padding(.top, 14)

                Spacer(minLength: 22).frame(maxHeight: 54)

                VStack(spacing: 12) {
                    ForEach(Pack.all) { p in
                        PackRow(pack: p, on: p.id == picked, shop: shop) {
                            tap()
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { picked = p.id }
                        }
                    }
                }
                .padding(.horizontal, 22)

                Spacer(minLength: 12).frame(maxHeight: 48)

                Button {
                    // Closes on a purchase that landed, stays put on one that didn't.
                    Task { if await account.topup(pack) { dismiss() } }
                } label: {
                    // outlined, not filled: a topup is the lesser buy, and the one solid
                    // rose capsule in the app is the mirror itself
                    ZStack {
                        Text("Get \(pack.said) · \(shop.price(pack.id) ?? pack.price)")
                            .tracked(13, 2.6)
                            .opacity(busy ? 0 : 1)
                        if busy { ProgressView().tint(M.rouge) }
                    }
                    .foregroundStyle(M.rouge)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                    .background(Capsule().fill(.white))
                    .overlay(Capsule().strokeBorder(M.rose, lineWidth: 1.5))
                    .shadow(color: M.rouge.opacity(0.1), radius: 12, y: 5)
                }
                .buttonStyle(Squish())
                .disabled(busy)
                .padding(.horizontal, 22)

                Text(account.subscribed
                     ? "Fittings never expire. Your plan refills every month."
                     : "Mira Pro gives you \(Plan.included) every month, for less.")
                    // a sentence, set as one — tracked-out caps edge to edge is a label,
                    // and this is the last thing anyone reads before paying
                    .font(.system(size: 11))
                    .foregroundStyle(M.mute)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 34)
                    .padding(.top, 14)

                FinePrint()
                    .padding(.top, 16)
                    .padding(.bottom, 26)
            }

            // the sheet drags down, but the meter is running behind it and a gesture
            // is a bad only-option — same puck the closet and the paywall close with
            VStack {
                HStack {
                    Spacer()
                    Button { tap(); dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(M.ink)
                            .puck(34)
                    }
                    .accessibilityLabel("Close")
                }
                Spacer()
            }
            .padding(.trailing, 16)
            .padding(.top, 14)
        }
        .faults(shop)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}

private extension View {
    /// The one place either sheet says a purchase didn't happen. Cancelling never sets
    /// it, so this only ever fires on something worth reading.
    @MainActor func faults(_ shop: Shop) -> some View {
        alert("Hmm", isPresented: Binding(get: { shop.fault != nil },
                                          set: { if !$0 { shop.fault = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(shop.fault ?? "")
        }
    }
}

/// The same row the plan picker uses, carrying a pack instead: tick, the mark for the
/// unit, what you get, and what a minute of it costs.
private struct PackRow: View {
    let pack: Pack
    let on: Bool
    let shop: Shop
    let pick: () -> Void

    private var price: String { shop.price(pack.id) ?? pack.price }
    private var each: String {
        shop.split(pack.id, by: pack.fittings).map { "\($0) each" } ?? pack.each
    }

    var body: some View {
        Button(action: pick) {
            VStack(spacing: 0) {
                if let note = pack.note {
                    Text(note)
                        .tracked(9, 1.8)
                        .foregroundStyle(M.onRose)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(M.rose)
                }
                HStack(spacing: 12) {
                    Tick(on: on)
                    Image("Spark")
                        .resizable().scaledToFit()
                        .frame(width: 30, height: 30)
                        .opacity(on ? 1 : 0.62)
                    Text(pack.said)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(on ? M.ink : M.mute)
                    Spacer(minLength: 6)
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(price)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(on ? M.ink : M.mute)
                        Text(each)
                            .font(.system(size: 11)).monospacedDigit()
                            .foregroundStyle(M.mute)
                    }
                    .fixedSize()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 15)
                .frame(maxWidth: .infinity)
                .background(.white)
            }
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(on ? M.rose : M.shell, lineWidth: on ? 2 : 1))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
    }
}
