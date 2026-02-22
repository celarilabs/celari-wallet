import SwiftUI

struct TokenListView: View {
    @Environment(WalletStore.self) private var store

    var body: some View {
        if store.tokens.isEmpty {
            emptyState
        } else {
            LazyVStack(spacing: 0) {
                ForEach(store.tokens) { token in
                    tokenRow(token)
                }
            }
        }
    }

    private func tokenRow(_ token: Token) -> some View {
        HStack(spacing: 12) {
            // Diamond icon
            DiamondShape()
                .stroke(Color(hex: token.color), lineWidth: 1)
                .frame(width: 32, height: 32)
                .overlay(
                    Text(token.icon)
                        .font(CelariTypography.title)
                        .foregroundColor(Color(hex: token.color))
                )

            // Name & symbol
            VStack(alignment: .leading, spacing: 2) {
                Text(token.name)
                    .font(CelariTypography.monoSmall)
                    .tracking(1)
                    .foregroundColor(CelariColors.textWarm)
                    .textCase(.uppercase)

                HStack(spacing: 4) {
                    Text(token.symbol)
                        .font(CelariTypography.monoTiny)
                        .foregroundColor(CelariColors.textDim)

                    if token.isCustom {
                        Text("CUSTOM")
                            .font(CelariTypography.monoTiny)
                            .foregroundColor(CelariColors.textFaint)
                    }
                }
            }

            Spacer()

            // Balance
            VStack(alignment: .trailing, spacing: 2) {
                if let priv = token.privateBalance, priv != "0" && priv != "—" {
                    HStack(spacing: 2) {
                        Text("S:")
                            .font(CelariTypography.monoTiny)
                            .foregroundColor(CelariColors.green)
                        Text(priv)
                            .font(CelariTypography.monoSmall)
                            .foregroundColor(CelariColors.green)
                    }
                }
                if let pub = token.publicBalance, pub != "—" {
                    HStack(spacing: 2) {
                        Text("P:")
                            .font(CelariTypography.monoTiny)
                            .foregroundColor(CelariColors.textDim)
                        Text(pub)
                            .font(CelariTypography.monoSmall)
                            .foregroundColor(CelariColors.textBody)
                    }
                }
                if token.privateBalance == nil && token.publicBalance == nil {
                    Text(token.balance)
                        .font(CelariTypography.monoSmall)
                        .foregroundColor(CelariColors.textBody)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) {
            Rectangle().fill(CelariColors.border).frame(height: 1)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            DiamondShape()
                .fill(CelariColors.textFaint.opacity(0.3))
                .frame(width: 24, height: 24)
            Text("NO TOKENS FOUND")
                .font(CelariTypography.monoLabel)
                .tracking(2)
                .foregroundColor(CelariColors.textDim)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }
}
