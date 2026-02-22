import SwiftUI

struct AddNftContractView: View {
    @Environment(WalletStore.self) private var store
    @State private var contractAddress: String = ""
    @State private var name: String = ""
    @State private var symbol: String = ""

    var body: some View {
        VStack(spacing: 0) {
            SubHeaderView(title: "Add NFT Contract")

            ScrollView {
                VStack(spacing: 16) {
                    FormField(label: "Contract Address", text: $contractAddress, placeholder: "0x...")
                    FormField(label: "Collection Name", text: $name, placeholder: "My NFT Collection")
                    FormField(label: "Symbol", text: $symbol, placeholder: "NFT")

                    DecoSeparator()

                    Button {
                        let contract = NFTContract(
                            address: contractAddress,
                            name: name,
                            symbol: symbol
                        )
                        store.customNftContracts.append(contract)
                        store.saveNftContracts()
                        store.showToast("NFT contract added")
                        store.screen = .dashboard
                    } label: {
                        Text("Add Contract")
                    }
                    .buttonStyle(CelariPrimaryButtonStyle())
                    .disabled(contractAddress.isEmpty || name.isEmpty)
                    .opacity(contractAddress.isEmpty || name.isEmpty ? 0.5 : 1)
                }
                .padding(16)
            }
        }
    }
}
