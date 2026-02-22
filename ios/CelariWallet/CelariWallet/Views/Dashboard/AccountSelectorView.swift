import SwiftUI

struct AccountSelectorView: View {
    @Environment(WalletStore.self) private var store

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Array(store.accounts.enumerated()), id: \.element.id) { index, account in
                    let isActive = index == store.activeAccountIndex

                    Button {
                        store.activeAccountIndex = index
                    } label: {
                        HStack(spacing: 4) {
                            Text(account.label)
                                .font(CelariTypography.monoTiny)
                                .foregroundColor(isActive ? CelariColors.copper : CelariColors.textDim)

                            Text(account.chipAddress)
                                .font(CelariTypography.monoTiny)
                                .foregroundColor(isActive ? CelariColors.copper.opacity(0.6) : CelariColors.textFaint)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(isActive ? CelariColors.copper.opacity(0.08) : CelariColors.bgElevated)
                        .overlay(
                            Rectangle().stroke(
                                isActive ? CelariColors.copper.opacity(0.4) : CelariColors.border,
                                lineWidth: 1
                            )
                        )
                    }
                }

                // Add account button
                Button {
                    store.screen = .addAccount
                } label: {
                    Text("+")
                        .font(CelariTypography.monoSmall)
                        .foregroundColor(CelariColors.textFaint)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .overlay(
                            Rectangle().stroke(CelariColors.border, style: StrokeStyle(lineWidth: 1, dash: [4]))
                        )
                }
            }
            .padding(.horizontal, 16)
        }
    }
}
