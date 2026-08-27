import SwiftUI

struct PaywallView: View {
    @Environment(Account.self) private var account
    @Environment(\.dismiss) private var dismiss
    @State private var picked: Plan = .yearly

    var body: some View {
        ZStack(alignment: .top) {
            M.cream.ignoresSafeArea()

            // the buy block sits on the floor and the reel absorbs whatever is left, so
            // this lands the same on a 13 mini as on a Pro Max instead of leaving a hole
            VStack(spacing: 0) {
                Reel(name: "demo", loop: true) { ReelStandin() }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .frame(minHeight: 170)
                    .clipped()
                    .overlay(alignment: .bottom) {
                        // the video has to end in cream or the headline looks pasted on
                        LinearGradient(colors: [M.cream.opacity(0), M.cream],
                                       startPoint: .top, endPoint: .bottom)
                            .frame(height: 120)
                    }

                VStack(spacing: 0) {
                    Text("Start your \(Plan.trialCopy) free to continue")
                        .font(M.display(33, .light))
                        .kerning(0.5)
                        .foregroundStyle(M.ink)
                        .multilineTextAlignment(.center)
                        .lineSpacing(2)
                        .padding(.horizontal, 26)
                        .padding(.bottom, 26)

                    VStack(spacing: 12) {
                        ForEach(Plan.allCases) { plan in
                            PlanRow(plan: plan, on: picked == plan) {
                                tap()
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { picked = plan }
                            }
                        }
                    }
                    .padding(.horizontal, 22)

                    Button {
                        account.subscribe(picked)
                        dismiss()
                    } label: {
                        Text("Continue")
                            .tracked(13, 2.6)
                            .foregroundStyle(M.onRose)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 20)
                            .background(Capsule().fill(M.rose))
                            .shadow(color: M.rouge.opacity(0.28), radius: 16, y: 7)
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 22)

                    Text(picked.note)
                        .font(.system(size: 11))
                        .foregroundStyle(M.mute.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .lineSpacing(2)
                        .padding(.horizontal, 34)
                        .padding(.top, 14)

                    HStack(spacing: 20) {
                        ForEach(["Terms", "Privacy", "Restore"], id: \.self) {
                            Text($0).tracked(8, 1.2).foregroundStyle(M.mute.opacity(0.6))
                        }
                    }
                    .padding(.top, 13)
                }
                .padding(.bottom, 10)
                .fixedSize(horizontal: false, vertical: true)
            }
            .ignoresSafeArea(edges: .top)

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
    let pick: () -> Void

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
                HStack(spacing: 13) {
                    ZStack {
                        Circle().fill(on ? M.rose : .clear).frame(width: 24, height: 24)
                        Circle().stroke(on ? M.rose : M.shell, lineWidth: 1.5).frame(width: 24, height: 24)
                        if on {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(M.onRose)
                        }
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(plan.headline)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(on ? M.ink : M.mute)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                        if let billed = plan.billed {
                            Text(billed).font(.system(size: 12)).foregroundStyle(M.mute)
                        }
                    }
                    Spacer(minLength: 6)
                    Text(plan.perMonth)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(on ? M.ink : M.mute)
                        .fixedSize()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, plan.billed == nil ? 21 : 16)
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

    var body: some View {
        ZStack {
            M.cream.ignoresSafeArea()

            VStack(spacing: 0) {
                Text("Sparks")
                    .font(M.display(36, .light))
                    .kerning(2)
                    .foregroundStyle(M.ink)
                    .padding(.top, 40)

                Text("\(account.sparks) left · about \(account.looksLeft) looks")
                    .tracked(9, 1.6)
                    .foregroundStyle(M.mute)
                    .padding(.top, 8)

                HStack(spacing: 18) {
                    rate("A look", "\(Spend.look)")
                    Rectangle().fill(M.shell).frame(width: 1, height: 26)
                    rate("A minute live", "\(Spend.livePerMinute)")
                }
                .padding(.vertical, 18)
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 20).fill(.white))
                .padding(.horizontal, 22)
                .padding(.top, 22)

                VStack(spacing: 10) {
                    ForEach(Pack.all) { pack in
                        Button {
                            account.topup(pack)
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                Blob().fill(M.rose).frame(width: 26, height: 26)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(pack.sparks) sparks")
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(M.ink)
                                    Text("about \((pack.sparks / Spend.look / 10) * 10) looks")
                                        .font(.system(size: 11)).foregroundStyle(M.mute)
                                }
                                Spacer(minLength: 0)
                                if let note = pack.note {
                                    Text(note)
                                        .tracked(8, 1.1)
                                        .foregroundStyle(M.onRose)
                                        .padding(.horizontal, 9).padding(.vertical, 5)
                                        .background(Capsule().fill(M.rose))
                                }
                                Text(pack.price)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(M.ink)
                            }
                            .padding(.horizontal, 18)
                            .padding(.vertical, 16)
                            .background(RoundedRectangle(cornerRadius: 20).fill(.white))
                            .overlay(RoundedRectangle(cornerRadius: 20).stroke(M.shell, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 18)

                Spacer()

                Text(account.subscribed
                     ? "Sparks never expire. Your plan refills every month."
                     : "Mira Pro refills your sparks every month, for less.")
                    .tracked(8, 1.2)
                    .foregroundStyle(M.mute.opacity(0.7))
                    .padding(.bottom, 26)
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private func rate(_ what: String, _ n: String) -> some View {
        VStack(spacing: 4) {
            Text(n).font(M.display(22)).foregroundStyle(M.rose)
            Text(what).tracked(8, 1.2).foregroundStyle(M.mute)
        }
    }
}
