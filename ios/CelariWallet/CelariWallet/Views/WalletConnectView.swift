import SwiftUI

struct WalletConnectView: View {
    @Environment(WalletStore.self) private var store
    @Environment(PXEBridge.self) private var pxeBridge
    @State private var wcUri: String = ""
    @State private var pairing = false

    var body: some View {
        VStack(spacing: 0) {
            SubHeaderView(title: "WalletConnect")

            ScrollView {
                VStack(spacing: 16) {
                    // Pair section
                    VStack(alignment: .leading, spacing: 8) {
                        Text("CONNECT DAPP")
                            .font(CelariTypography.monoLabel)
                            .tracking(2)
                            .foregroundColor(CelariColors.textDim)

                        FormField(label: "WalletConnect URI", text: $wcUri, placeholder: "wc:...")

                        Button {
                            pair()
                        } label: {
                            if pairing {
                                ProgressView()
                                    .tint(CelariColors.textWarm)
                            } else {
                                Text("Connect")
                            }
                        }
                        .buttonStyle(CelariPrimaryButtonStyle())
                        .disabled(wcUri.isEmpty || pairing)
                        .opacity(wcUri.isEmpty ? 0.5 : 1)
                    }

                    DecoSeparator()

                    // Active sessions
                    VStack(alignment: .leading, spacing: 8) {
                        Text("ACTIVE SESSIONS")
                            .font(CelariTypography.monoLabel)
                            .tracking(2)
                            .foregroundColor(CelariColors.textDim)

                        if store.wcSessions.isEmpty {
                            Text("No active sessions")
                                .font(CelariTypography.monoTiny)
                                .foregroundColor(CelariColors.textDim)
                                .padding(.vertical, 12)
                                .frame(maxWidth: .infinity)
                        } else {
                            ForEach(store.wcSessions) { session in
                                HStack(spacing: 12) {
                                    DiamondShape()
                                        .fill(CelariColors.green.opacity(0.15))
                                        .frame(width: 24, height: 24)
                                        .overlay(
                                            Image(systemName: "link")
                                                .font(.system(size: 8))
                                                .foregroundColor(CelariColors.green)
                                        )

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(session.peerName)
                                            .font(CelariTypography.monoSmall)
                                            .foregroundColor(CelariColors.textWarm)
                                        Text(session.peerUrl)
                                            .font(CelariTypography.monoTiny)
                                            .foregroundColor(CelariColors.textDim)
                                            .lineLimit(1)
                                    }

                                    Spacer()

                                    Button {
                                        disconnect(session.topic)
                                    } label: {
                                        Text("DISCONNECT")
                                            .font(CelariTypography.monoTiny)
                                            .foregroundColor(CelariColors.red)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 3)
                                            .overlay(Rectangle().stroke(CelariColors.red.opacity(0.3), lineWidth: 1))
                                    }
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(CelariColors.bgCard)
                                .overlay(Rectangle().stroke(CelariColors.border, lineWidth: 1))
                            }
                        }
                    }
                }
                .padding(16)
            }
        }
    }

    private func pair() {
        pairing = true
        Task {
            do {
                _ = try await pxeBridge.wcPair(uri: wcUri)
                wcUri = ""
                store.showToast("Pairing initiated")
            } catch {
                store.showToast("Pairing failed: \(error.localizedDescription)", type: .error)
            }
            pairing = false
        }
    }

    private func disconnect(_ topic: String) {
        Task {
            do {
                _ = try await pxeBridge.wcDisconnect(topic: topic)
                store.wcSessions.removeAll { $0.topic == topic }
                store.showToast("Disconnected")
            } catch {
                store.showToast("Disconnect failed", type: .error)
            }
        }
    }
}
