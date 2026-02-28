import SwiftUI

struct RootView: View {
    @Environment(WalletStore.self) private var store
    @Environment(PXEBridge.self) private var pxeBridge

    var body: some View {
        ZStack {
            CelariColors.bg.ignoresSafeArea()

            Group {
                switch store.screen {
                case .loading:
                    LoadingView()
                case .onboarding:
                    OnboardingView()
                case .dashboard:
                    DashboardView()
                case .send:
                    SendView()
                case .receive:
                    ReceiveView()
                case .settings:
                    SettingsView()
                case .addToken:
                    AddTokenView()
                case .addAccount:
                    AddAccountView()
                case .backup:
                    BackupView()
                case .restore:
                    RestoreView()
                case .confirmTx:
                    ConfirmTxView()
                case .addNftContract:
                    AddNftContractView()
                case .nftDetail:
                    NftDetailView()
                case .walletConnect:
                    WalletConnectView()
                case .wcApprove:
                    WcApproveView()
                }
            }
            .animation(.easeInOut(duration: 0.2), value: store.screen)

            // Progress status bar (bottom)
            if let progress = store.progressMessage {
                VStack {
                    Spacer()
                    HStack(spacing: 8) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: CelariColors.copper))
                            .scaleEffect(0.8)
                        Text(progress)
                            .font(CelariTypography.monoLabel)
                            .foregroundColor(CelariColors.textDim)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
                    .background(
                        CelariColors.bg
                            .opacity(0.95)
                            .overlay(
                                Rectangle()
                                    .frame(height: 0.5)
                                    .foregroundColor(CelariColors.copper.opacity(0.3)),
                                alignment: .top
                            )
                    )
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.easeInOut(duration: 0.3), value: store.progressMessage)
            }

            // Toast overlay
            if let toast = store.toast {
                ToastOverlay(toast: toast)
            }

            // Grain texture overlay
            GrainOverlay()
        }
    }
}
