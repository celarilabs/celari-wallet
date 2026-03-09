import SwiftUI

struct BalanceCardV2: View {
    @Environment(WalletStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Top row: network badge + shield icon
            HStack {
                HStack(spacing: 6) {
                    Circle()
                        .fill(V2Colors.aztecGreen)
                        .frame(width: 8, height: 8)
                    Text(networkLabel)
                        .font(V2Fonts.label(10))
                        .tracking(0.5)
                        .foregroundColor(V2Colors.aztecGreen)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(Color(hex2: "2A3D52"))
                )

                Spacer()

                Image(systemName: "shield.checkered")
                    .font(.system(size: 18))
                    .foregroundColor(V2Colors.textWhite.opacity(0.6))
            }

            // Balance section
            VStack(alignment: .leading, spacing: 4) {
                Text("TOTAL BALANCE")
                    .font(V2Fonts.label(10))
                    .tracking(2)
                    .foregroundColor(V2Colors.textWhite.opacity(0.5))

                Text(store.totalValue)
                    .font(V2Fonts.balance)
                    .foregroundColor(V2Colors.textWhite)

                // Public / Private breakdown
                if hasAnyBalance {
                    HStack(spacing: 16) {
                        HStack(spacing: 4) {
                            Image(systemName: "shield.fill")
                                .font(.system(size: 10))
                                .foregroundColor(V2Colors.aztecGreen)
                            Text(totalPrivateLabel)
                                .font(V2Fonts.mono(11))
                                .foregroundColor(V2Colors.aztecGreen)
                        }
                        HStack(spacing: 4) {
                            Image(systemName: "globe")
                                .font(.system(size: 10))
                                .foregroundColor(V2Colors.textWhite.opacity(0.5))
                            Text(totalPublicLabel)
                                .font(V2Fonts.mono(11))
                                .foregroundColor(V2Colors.textWhite.opacity(0.5))
                        }
                    }
                }

                if store.deploying {
                    HStack(spacing: 6) {
                        ProgressView()
                            .tint(V2Colors.aztecGreen)
                            .scaleEffect(0.7)
                        Text("Deploying...")
                            .font(V2Fonts.mono(11))
                            .foregroundColor(V2Colors.aztecGreen)
                    }
                } else if let account = store.activeAccount, !account.deployed {
                    Text("PENDING")
                        .font(V2Fonts.label(10))
                        .tracking(2)
                        .foregroundColor(V2Colors.soOrange)
                }
            }
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(V2Colors.aztecDark)
        )
    }

    private var hasAnyBalance: Bool {
        store.tokens.contains { token in
            let priv = token.privateBalance ?? "0"
            let pub = token.publicBalance ?? "0"
            return priv != "0" || pub != "0"
        }
    }

    private var totalPrivateLabel: String {
        let tokens = store.tokens.compactMap { $0.privateBalance }
            .filter { $0 != "0" && $0 != "—" }
        if tokens.isEmpty { return "0" }
        return tokens.joined(separator: " + ")
    }

    private var totalPublicLabel: String {
        let tokens = store.tokens.compactMap { $0.publicBalance }
            .filter { $0 != "0" && $0 != "—" }
        if tokens.isEmpty { return "0" }
        return tokens.joined(separator: " + ")
    }

    private var networkLabel: String {
        switch store.network {
        case "devnet": return "Aztec Devnet"
        case "testnet": return "Aztec Testnet"
        case "local": return "Local Sandbox"
        default: return store.network.capitalized
        }
    }
}
