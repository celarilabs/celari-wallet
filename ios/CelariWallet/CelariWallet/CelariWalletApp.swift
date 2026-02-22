import SwiftUI

@main
struct CelariWalletApp: App {
    @State private var store = WalletStore()
    @State private var pxeBridge = PXEBridge()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(pxeBridge)
                .preferredColorScheme(.dark)
                .onAppear {
                    pxeBridge.store = store
                    pxeBridge.setupWebView()
                    Task { await store.initialize(pxeBridge: pxeBridge) }
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
        }
    }
}
