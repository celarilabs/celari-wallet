import SwiftUI

struct BalanceCardView: View {
    @Environment(WalletStore.self) private var store
    @Environment(PXEBridge.self) private var pxeBridge

    var body: some View {
        VStack(spacing: 8) {
            // Privacy badge
            HStack(spacing: 4) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 8))
                Text("Shielded")
                    .font(CelariTypography.monoTiny)
                    .tracking(1.5)
            }
            .foregroundColor(CelariColors.green)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .overlay(
                Rectangle().stroke(CelariColors.green.opacity(0.2), lineWidth: 1)
            )

            // Balance label
            Text("TOTAL BALANCE")
                .font(CelariTypography.monoLabel)
                .tracking(3)
                .foregroundColor(CelariColors.textDim)
                .padding(.top, 4)

            // Balance amount
            Text(store.totalValue)
                .font(CelariTypography.balance)
                .tracking(3)
                .foregroundColor(CelariColors.textWarm)

            // Address
            if let account = store.activeAccount {
                HStack(spacing: 6) {
                    if account.deployed || account.type == .demo {
                        Text(account.shortAddress)
                            .font(CelariTypography.monoSmall)
                            .foregroundColor(CelariColors.textMuted)

                        Button {
                            UIPasteboard.general.string = account.address
                            store.showToast("Address copied")
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 10))
                                .foregroundColor(CelariColors.textDim)
                        }
                    }

                    Text(account.deployed ? "DEPLOYED" : account.type == .passkey ? "PENDING" : "DEMO")
                        .font(CelariTypography.monoTiny)
                        .tracking(2)
                        .foregroundColor(account.deployed ? CelariColors.green : account.type == .passkey ? CelariColors.copper : CelariColors.textDim)
                }

                // Deploy button for pending passkey accounts
                if !account.deployed && account.type == .passkey {
                    Button {
                        Task { await store.deployActiveAccount(pxeBridge: pxeBridge) }
                    } label: {
                        HStack(spacing: 6) {
                            if store.deploying {
                                ProgressView()
                                    .tint(CelariColors.bg)
                                    .scaleEffect(0.7)
                            } else {
                                Image(systemName: "paperplane.fill")
                                    .font(.system(size: 10))
                            }
                            Text(store.deploying ? "DEPLOYING..." : "DEPLOY ACCOUNT")
                                .font(CelariTypography.monoTiny)
                                .tracking(2)
                        }
                        .foregroundColor(CelariColors.bg)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(CelariColors.copper)
                        .overlay(Rectangle().stroke(CelariColors.copper.opacity(0.5), lineWidth: 1))
                    }
                    .disabled(store.deploying)
                    .padding(.top, 4)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(CelariColors.balanceGradient)
        .overlay(Rectangle().stroke(CelariColors.border, lineWidth: 1))
        .decoCorners()
    }
}
