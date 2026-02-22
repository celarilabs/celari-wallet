import SwiftUI

struct WcApproveView: View {
    @Environment(WalletStore.self) private var store
    @Environment(PXEBridge.self) private var pxeBridge
    @State private var approving = false

    var body: some View {
        VStack(spacing: 0) {
            SubHeaderView(title: "Session Proposal")

            if let proposal = store.wcProposal {
                VStack(spacing: 20) {
                    Spacer()

                    DiamondShape()
                        .stroke(CelariColors.copper, lineWidth: 1)
                        .frame(width: 48, height: 48)
                        .overlay(
                            Image(systemName: "link")
                                .font(.system(size: 16))
                                .foregroundColor(CelariColors.copper)
                        )

                    VStack(spacing: 4) {
                        Text(proposal.peerName)
                            .font(CelariTypography.monoSmall)
                            .tracking(1)
                            .foregroundColor(CelariColors.textWarm)
                            .textCase(.uppercase)

                        Text(proposal.peerUrl)
                            .font(CelariTypography.monoTiny)
                            .foregroundColor(CelariColors.textDim)
                    }

                    Text("This dApp wants to connect to your wallet")
                        .font(CelariTypography.monoTiny)
                        .foregroundColor(CelariColors.textBody)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)

                    // Permissions
                    VStack(spacing: 4) {
                        Text("REQUESTED PERMISSIONS")
                            .font(CelariTypography.monoLabel)
                            .tracking(2)
                            .foregroundColor(CelariColors.textDim)

                        VStack(spacing: 2) {
                            permissionRow("View account address")
                            permissionRow("Request transaction signatures")
                            permissionRow("View balances")
                        }
                        .padding(12)
                        .background(CelariColors.bgCard)
                        .overlay(Rectangle().stroke(CelariColors.border, lineWidth: 1))
                    }
                    .padding(.horizontal, 16)

                    HStack(spacing: 12) {
                        Button {
                            reject(proposal)
                        } label: {
                            Text("Reject")
                        }
                        .buttonStyle(CelariSecondaryButtonStyle())

                        Button {
                            approve(proposal)
                        } label: {
                            if approving {
                                ProgressView()
                                    .tint(CelariColors.textWarm)
                            } else {
                                Text("Approve")
                            }
                        }
                        .buttonStyle(CelariPrimaryButtonStyle())
                        .disabled(approving)
                    }
                    .padding(.horizontal, 16)

                    Spacer()
                }
            } else {
                VStack {
                    Spacer()
                    Text("No pending proposals")
                        .font(CelariTypography.mono)
                        .foregroundColor(CelariColors.textDim)
                    Spacer()
                }
            }
        }
    }

    private func permissionRow(_ text: String) -> some View {
        HStack(spacing: 6) {
            DiamondShape()
                .fill(CelariColors.green)
                .frame(width: 5, height: 5)
            Text(text)
                .font(CelariTypography.monoTiny)
                .foregroundColor(CelariColors.textBody)
            Spacer()
        }
    }

    private func approve(_ proposal: WCProposal) {
        approving = true
        Task {
            do {
                let namespaces: [String: Any] = [
                    "aztec": [
                        "accounts": [store.activeAccount?.address ?? ""],
                        "methods": ["aztec_sendTransaction", "aztec_getBalances"],
                        "events": ["accountsChanged"]
                    ]
                ]
                _ = try await pxeBridge.wcApprove(id: proposal.id, namespaces: namespaces)
                store.wcProposal = nil
                store.showToast("Session approved")
                store.screen = .walletConnect
            } catch {
                store.showToast("Approval failed: \(error.localizedDescription)", type: .error)
            }
            approving = false
        }
    }

    private func reject(_ proposal: WCProposal) {
        Task {
            _ = try? await pxeBridge.wcReject(id: proposal.id)
            store.wcProposal = nil
            store.screen = .dashboard
        }
    }
}
