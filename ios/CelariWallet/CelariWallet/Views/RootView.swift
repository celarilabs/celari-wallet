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

            // Toast overlay
            if let toast = store.toast {
                ToastOverlay(toast: toast)
            }

            // Grain texture overlay
            GrainOverlay()
        }
    }
}
