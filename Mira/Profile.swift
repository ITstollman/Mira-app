import SwiftUI

struct ProfileSheet: View {
    @Environment(Account.self) private var account
    @Environment(Studio.self) private var studio
    @Environment(\.dismiss) private var dismiss

    let topup: () -> Void
    let pro: () -> Void

    @State private var confirmingSignOut = false

    // ponytail: dev:profile just fakes the address so the screen shots signed-in.
    private var email: String {
        account.email ?? (Dev.has("dev:profile") ? "you@mira.ai" : "not signed in")
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

                    Text(Spend.said(account.sparks))
                        .font(M.display(52, .light))
                        .foregroundStyle(M.ink)
                        .padding(.top, 26)

                    Text("\(Spend.unit(account.sparks)) · about \(account.looksLeft) looks")
                        .tracked(9, 1.6)
                        .foregroundStyle(M.mute)
                        .padding(.top, 4)

                    Button { tap(); topup() } label: {
                        Text("Get more minutes")
                            .tracked(11, 2.4)
                            .foregroundStyle(M.onRose)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 17)
                            .background(Capsule().fill(M.rose))
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 20)

                    if !account.subscribed {
                        Button { tap(); pro() } label: {
                            Text("See Mira Pro")
                                .tracked(11, 2.4)
                                .foregroundStyle(M.rose)
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

                    // ponytail: Restore/Manage/Terms/Privacy are inert until StoreKit and
                    // the real URLs exist — the rows are the whole feature for now.
                    VStack(spacing: 0) {
                        row("Restore purchases").onTapGesture { tap() }
                        line
                        row("Manage subscription").onTapGesture { tap() }
                        line
                        row("Terms").onTapGesture { tap() }
                        line
                        row("Privacy").onTapGesture { tap() }
                        line
                        Button { tap(); confirmingSignOut = true } label: {
                            HStack {
                                Text("Sign out").font(.system(size: 14, weight: .semibold)).foregroundStyle(M.rose)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 18).padding(.vertical, 16)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .background(RoundedRectangle(cornerRadius: 20).fill(.white))
                    .padding(.horizontal, 22)
                    .padding(.top, 14)
                    .padding(.bottom, 34)
                }
            }
        }
        .confirmationDialog("Sign out of Mira?", isPresented: $confirmingSignOut, titleVisibility: .visible) {
            Button("Sign out", role: .destructive) { account.signOut(); dismiss() }
            Button("Stay", role: .cancel) {}
        } message: {
            Text("Your minutes stay on this account.")
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
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

    private func row(_ what: String) -> some View {
        HStack {
            Text(what).font(.system(size: 14)).foregroundStyle(M.ink)
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(M.mute)
        }
        .padding(.horizontal, 18).padding(.vertical, 16)
        .contentShape(Rectangle())
    }
}
