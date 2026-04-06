import Foundation
import os.log

private let networkManagerLog = Logger(subsystem: "com.celari.wallet", category: "WalletNetworkManager")

// MARK: - WalletNetworkManager
//
// Owns all network-connection state that was previously scattered through
// WalletStore: connected, network, nodeUrl, nodeInfo, customNetworks, and
// deployServerUrl.  WalletStore forwards via computed properties so that all
// existing call sites remain unchanged.

@MainActor
@Observable
class WalletNetworkManager {

    // MARK: - State

    var connected: Bool = false
    var network: String = "testnet"
    var nodeUrl: String = "https://rpc.testnet.aztec-labs.com/"
    var nodeInfo: NodeInfo?
    var customNetworks: [CustomNetwork] = []
    var deployServerUrl: String = ""

    // MARK: - Dependencies

    private let httpClient = NetworkManager()

    // MARK: - Check Connection

    func checkConnection() async {
        networkManagerLog.notice("[WalletNetworkManager] checkConnection — nodeUrl: \(self.nodeUrl, privacy: .public)")
        let result = await httpClient.checkConnection(nodeUrl: nodeUrl)
        connected = result.connected
        nodeInfo = result.nodeInfo
        networkManagerLog.notice("[WalletNetworkManager] checkConnection — connected: \(self.connected, privacy: .public), nodeVersion: \(self.nodeInfo?.nodeVersion ?? "nil", privacy: .public)")
    }

    // MARK: - Switch Network

    func switchNetwork(preset: NetworkPreset) async {
        network = preset.rawValue
        nodeUrl = preset.url
        await checkConnection()
    }
}
