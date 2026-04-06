import SwiftUI

@main
struct CelariWalletApp: App {
    @State private var store = WalletStore()
    @State private var pxeBridge = PXEBridge()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootViewV2()
                .environment(store)
                .environment(pxeBridge)
                .preferredColorScheme(.light)
                .onAppear {
                    pxeBridge.store = store
                    pxeBridge.setupWebView()
                    Task {
                        await store.initialize(pxeBridge: pxeBridge)
                        // Initialize WalletConnect after PXE is ready
                        do {
                            _ = try await pxeBridge.wcInit()
                        } catch {
                            print("[CelariWalletApp] WalletConnect init failed: \(error)")
                        }
                    }
                    Task {
                        await NotificationManager.shared.requestPermission()
                    }
                }
                .onChange(of: scenePhase) { _, newPhase in
                    switch newPhase {
                    case .active:
                        // Re-check connection when app comes to foreground
                        Task { await store.checkConnection() }
                    case .background:
                        // Save PXE snapshot before app is suspended
                        Task { await store.savePXESnapshot() }
                    default:
                        break
                    }
                }
                .onOpenURL { url in
                    handleDeepLink(url)
                }
        }
    }

    private func handleDeepLink(_ url: URL) {
        guard url.scheme == "celari" else { return }

        if url.host == "wc",
           let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let uri = components.queryItems?.first(where: { $0.name == "uri" })?.value {
            Task {
                do {
                    try await pxeBridge.wcPair(uri: uri)
                } catch {
                    store.showToast("WalletConnect pairing failed", type: .error)
                }
            }
        }
    }
}
