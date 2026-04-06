import SwiftUI

struct AccountSelectorV2: View {
    @Environment(WalletStore.self) private var store
    @Environment(PXEBridge.self) private var pxeBridge
    var onAddAccount: () -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(store.accounts.enumerated()), id: \.element.id) { index, account in
                    Button {
                        switchAccount(to: index)
                    } label: {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(index == store.activeAccountIndex ? V2Colors.aztecGreen : V2Colors.textMuted)
                                .frame(width: 6, height: 6)
                            Text(account.label)
                                .font(V2Fonts.mono(11))
                                .foregroundColor(index == store.activeAccountIndex ? V2Colors.textPrimary : V2Colors.textTertiary)
                            Text(account.chipAddress)
                                .font(V2Fonts.mono(10))
                                .foregroundColor(V2Colors.textMuted)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(index == store.activeAccountIndex ? V2Colors.bgCard : V2Colors.bgMuted)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(index == store.activeAccountIndex ? V2Colors.aztecGreen.opacity(0.4) : V2Colors.borderPrimary, lineWidth: 1)
                                )
                        )
                    }
                }

                // Add account button
                Button(action: onAddAccount) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(V2Colors.textTertiary)
                        .frame(width: 32, height: 32)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4]))
                                .foregroundColor(V2Colors.borderPrimary)
                        )
                }
            }
            .padding(.horizontal, 24)
        }
    }

    private func switchAccount(to index: Int) {
        guard index != store.activeAccountIndex else { return }
        store.activeAccountIndex = index
        Task {
            if let account = store.activeAccount, account.deployed {
                do {
                    _ = try await pxeBridge.setActiveAccount(address: account.address)
                } catch {
                    store.showToast("Account switch failed: \(error.localizedDescription)", type: .error)
                }
            }
            await store.fetchBalances()
        }
    }
}
