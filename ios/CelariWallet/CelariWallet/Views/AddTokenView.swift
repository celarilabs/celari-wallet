import SwiftUI

struct AddTokenView: View {
    @Environment(WalletStore.self) private var store
    @State private var contractAddress: String = ""
    @State private var name: String = ""
    @State private var symbol: String = ""
    @State private var decimals: String = "18"

    var body: some View {
        VStack(spacing: 0) {
            SubHeaderView(title: "Add Custom Token")

            ScrollView {
                VStack(spacing: 16) {
                    FormField(label: "Contract Address", text: $contractAddress, placeholder: "0x...")
                    FormField(label: "Token Name", text: $name, placeholder: "My Token")
                    FormField(label: "Symbol", text: $symbol, placeholder: "TKN")
                    FormField(label: "Decimals", text: $decimals, placeholder: "18", keyboardType: .numberPad)

                    DecoSeparator()

                    Button {
                        // Prevent duplicate tokens (same address or symbol)
                        if store.customTokens.contains(where: {
                            $0.contractAddress == contractAddress || $0.symbol == symbol
                        }) {
                            store.showToast("Token already exists: \(symbol)")
                            store.screen = .dashboard
                            return
                        }
                        let token = CustomToken(
                            contractAddress: contractAddress,
                            name: name,
                            symbol: symbol,
                            decimals: Int(decimals) ?? 18
                        )
                        store.customTokens.append(token)
                        store.saveCustomTokens()
                        store.tokenAddresses[symbol] = contractAddress
                        store.showToast("Token added: \(symbol)")
                        store.screen = .dashboard
                        // Trigger balance fetch for the new token
                        Task { await store.fetchBalances() }
                    } label: {
                        Text("Add Token")
                    }
                    .buttonStyle(CelariPrimaryButtonStyle())
                    .disabled(contractAddress.isEmpty || name.isEmpty || symbol.isEmpty)
                    .opacity(contractAddress.isEmpty || name.isEmpty || symbol.isEmpty ? 0.5 : 1)
                }
                .padding(16)
            }
        }
    }
}
