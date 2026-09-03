import SwiftUI

struct ProfileSheet: View {
    @Environment(Account.self) private var account
    @Environment(Studio.self) private var studio
    @Environment(\.dismiss) private var dismiss

    let topup: () -> Void
    let pro: () -> Void

    @Environment(\.openURL) private var open

    @State private var confirmingSignOut = false
    @State private var confirmingDelete = false
    @State private var deleting = false
    @State private var deleteFault: String?
    @State private var legal: Legal? = Dev.has("dev:legal") ? .terms : nil
    @State private var restoring = false
    @State private var restored = false

    // ponytail: dev:profile just fakes the address so the screen shots signed-in.
    private var email: String {
        if let mail = account.email { return mail }
        if Dev.has("dev:profile") { return "you@mira.ai" }
        // Apple will withhold even the relay address if you ask it to, and an account
        // with nothing to print is not the same thing as nobody being signed in.
        return account.signedIn ? "Signed in" : "not signed in"
    }

    var body: some View {
        ZStack {
            M.cream.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    MiraMark(size: 54).padding(.top, 34)

                    Text(email)
                        .tracked(10, 1.6)
                        .foregroundStyle(M.mute)
                        .padding(.top, 14)

                    Text(account.plan.map { "Mira Pro · \($0.rawValue)" } ?? "Free")
                        .tracked(9, 1.6)
                        .foregroundStyle(account.subscribed ? M.onRose : M.mute)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Capsule().fill(account.subscribed ? M.rose : M.blush))
                        .padding(.top, 10)

                    meter.padding(.top, 26)

                    Text(account.subscribed ? "\(Plan.fittings) more every month"
                                            : "one fitting on the house")
                        .tracked(9, 1.6)
                        .foregroundStyle(M.mute)
                        .padding(.top, 12)

                    Button { tap(); topup() } label: {
                        HStack(spacing: 11) {
                            // the same rocket the topup screen opens on, so the button
                            // looks like the door it actually is
                            Image("Rocket")
                                .resizable().scaledToFit()
                                .frame(width: 20, height: 20)
                                .padding(6)
                                .background(Circle().fill(.white))
                            Text("Get more fittings")
                                .tracked(11, 2.4)
                                .foregroundStyle(M.onRose)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Capsule().fill(M.rose))
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 20)

                    if !account.subscribed {
                        Button { tap(); pro() } label: {
                            Text("See Mira Pro")
                                .tracked(11, 2.4)
                                .foregroundStyle(M.rouge)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 17)
                                .background(Capsule().fill(.white))
                                .overlay(Capsule().stroke(M.shell, lineWidth: 1))
                        }
                        .padding(.horizontal, 22)
                        .padding(.top, 10)
                    }

                    HStack(spacing: 18) {
                        stat("Looks kept", "\(studio.looks.count)")
                        Rectangle().fill(M.shell).frame(width: 1, height: 26)
                        stat("Pieces loved", "\(studio.loved.count)")
                    }
                    .padding(.vertical, 18)
                    .frame(maxWidth: .infinity)
                    .background(RoundedRectangle(cornerRadius: 20).fill(.white))
                    .padding(.horizontal, 22)
                    .padding(.top, 22)

                    VStack(spacing: 0) {
                        row("Restore purchases", busy: restoring) {
                            guard !restoring else { return }
                            restoring = true
                            Task { await account.restore(); restoring = false; restored = true }
                        }
                        line
                        // ponytail: the App Store's own subscriptions page. StoreKit's
                        // in-app sheet is prettier and can wait until there is a real
                        // subscription for it to manage.
                        row("Manage subscription") {
                            open(URL(string: "https://apps.apple.com/account/subscriptions")!)
                        }
                        line
                        row("Support") { legal = .support }
                        line
                        row("Terms") { legal = .terms }
                        line
                        row("Privacy") { legal = .privacy }
                        line
                        Button { tap(); confirmingSignOut = true } label: {
                            HStack {
                                // rouge, not rose: rose type on white measures 2.26:1
                                Text("Sign out").font(.system(size: 14, weight: .semibold)).foregroundStyle(M.rouge)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 18).padding(.vertical, 16)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        line
                        // Apple requires this door wherever an account can be created.
                        Button { tap(); confirmingDelete = true } label: {
                            HStack {
                                Text("Delete account").font(.system(size: 14, weight: .semibold)).foregroundStyle(M.rouge)
                                Spacer(minLength: 0)
                                if deleting { Dots(d: 4) }
                            }
                            .padding(.horizontal, 18).padding(.vertical, 16)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(deleting)
                    }
                    .background(RoundedRectangle(cornerRadius: 20).fill(.white))
                    .padding(.horizontal, 22)
                    .padding(.top, 14)
                    .padding(.bottom, 46)
                }
            }
        }
        .confirmationDialog("Sign out of Mira?", isPresented: $confirmingSignOut, titleVisibility: .visible) {
            Button("Sign out", role: .destructive) { account.signOut(); dismiss() }
            Button("Stay", role: .cancel) {}
        } message: {
            Text("Your fittings stay on this account.")
        }
        .confirmationDialog("Delete your account?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete account", role: .destructive) {
                deleting = true
                Task {
                    let fault = await account.deleteAccount()
                    deleting = false
                    if let fault { deleteFault = fault } else { dismiss() }
                }
            }
            Button("Keep my account", role: .cancel) {}
        } message: {
            Text("Your account and any fittings left on it are deleted for good. An active subscription is canceled separately in the App Store.")
        }
        .alert("Hmm", isPresented: Binding(get: { deleteFault != nil },
                                           set: { if !$0 { deleteFault = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(deleteFault ?? "")
        }
        .alert("Up to date", isPresented: $restored) {
            Button("OK", role: .cancel) {}
        } message: {
            // says what it found rather than "Restored", which is a claim it can't make
            Text("You have \(Spend.said(account.sparks)) \(Spend.unit(account.sparks).lowercased()).")
        }
        .sheet(item: $legal) { LegalSheet(page: $0) }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    /// The balance as a dial. ponytail: the ring is trim, not a gauge — there is no honest
    /// denominator for it (the plan grants 600, a pack buys 9000), and a bar that pegs full
    /// on every purchase says less than nothing.
    private var meter: some View {
        ZStack {
            Circle().fill(.white)
            Circle().strokeBorder(M.blush, lineWidth: 9)
            Circle().strokeBorder(M.rose.opacity(0.5), lineWidth: 1.5).padding(4)

            VStack(spacing: 1) {
                Text(Spend.said(account.sparks))
                    .font(M.display(40, .light))
                    .foregroundStyle(M.ink)
                    .contentTransition(.numericText())
                Text(Spend.unit(account.sparks))
                    .tracked(8, 1.6)
                    .foregroundStyle(M.mute)
            }
        }
        .frame(width: 138, height: 138)
        .shadow(color: M.rouge.opacity(0.12), radius: 18, y: 8)
    }

    private var line: some View {
        Rectangle().fill(M.shell).frame(height: 1).padding(.leading, 18)
    }

    private func stat(_ what: String, _ n: String) -> some View {
        VStack(spacing: 4) {
            Text(n).font(M.display(22)).foregroundStyle(M.rose)
            Text(what).tracked(8, 1.2).foregroundStyle(M.mute)
        }
    }

    private func row(_ what: String, busy: Bool = false, _ go: @escaping () -> Void) -> some View {
        Button { tap(); go() } label: {
            HStack {
                Text(what).font(.system(size: 14)).foregroundStyle(M.ink)
                Spacer(minLength: 0)
                if busy {
                    Dots(d: 4)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(M.mute)
                }
            }
            .padding(.horizontal, 18).padding(.vertical, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
