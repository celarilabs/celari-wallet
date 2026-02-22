import SwiftUI

struct NftDetailView: View {
    @Environment(WalletStore.self) private var store
    @Environment(PXEBridge.self) private var pxeBridge
    @State private var recipientAddress: String = ""
    @State private var transferMode: String = "private"
    @State private var transferring = false

    var nft: NFTItem? {
        guard let detail = store.nftDetail else { return nil }
        return store.nfts.first { $0.contractAddress == detail.contractAddress && $0.tokenId == detail.tokenId }
    }

    var body: some View {
        VStack(spacing: 0) {
            SubHeaderView(title: "NFT Detail")

            if let nft {
                ScrollView {
                    VStack(spacing: 16) {
                        // NFT icon
                        DiamondShape()
                            .stroke(CelariColors.copper, lineWidth: 1)
                            .frame(width: 64, height: 64)
                            .overlay(
                                Text("N")
                                    .font(CelariTypography.heading)
                                    .foregroundColor(CelariColors.copper)
                            )
                            .padding(.top, 16)

                        // Info
                        VStack(spacing: 4) {
                            Text(nft.contractName)
                                .font(CelariTypography.monoSmall)
                                .tracking(1)
                                .foregroundColor(CelariColors.textWarm)
                                .textCase(.uppercase)

                            Text("Token #\(nft.tokenId)")
                                .font(CelariTypography.monoTiny)
                                .foregroundColor(CelariColors.textDim)

                            Text(nft.isPrivate ? "PRIVATE" : "PUBLIC")
                                .font(CelariTypography.monoTiny)
                                .tracking(1.5)
                                .foregroundColor(nft.isPrivate ? CelariColors.green : CelariColors.copper)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .overlay(
                                    Rectangle().stroke(
                                        nft.isPrivate ? CelariColors.green.opacity(0.2) : CelariColors.copper.opacity(0.2),
                                        lineWidth: 1
                                    )
                                )
                        }

                        DecoSeparator()

                        // Transfer section
                        VStack(alignment: .leading, spacing: 8) {
                            Text("TRANSFER NFT")
                                .font(CelariTypography.monoLabel)
                                .tracking(2)
                                .foregroundColor(CelariColors.textDim)

                            // Mode selector
                            HStack(spacing: 0) {
                                ForEach(["private", "public", "shield", "unshield"], id: \.self) { mode in
                                    Button {
                                        transferMode = mode
                                    } label: {
                                        Text(mode.uppercased())
                                            .font(CelariTypography.monoTiny)
                                            .foregroundColor(transferMode == mode ? CelariColors.copper : CelariColors.textDim)
                                            .padding(.vertical, 6)
                                            .frame(maxWidth: .infinity)
                                            .background(transferMode == mode ? CelariColors.copper.opacity(0.08) : .clear)
                                            .overlay(
                                                Rectangle().stroke(
                                                    transferMode == mode ? CelariColors.copper.opacity(0.4) : CelariColors.border,
                                                    lineWidth: 1
                                                )
                                            )
                                    }
                                }
                            }

                            FormField(label: "Recipient", text: $recipientAddress, placeholder: "0x...")
                        }

                        Button {
                            transferNft(nft)
                        } label: {
                            if transferring {
                                ProgressView()
                                    .tint(CelariColors.textWarm)
                            } else {
                                Text("Transfer NFT")
                            }
                        }
                        .buttonStyle(CelariPrimaryButtonStyle())
                        .disabled(recipientAddress.isEmpty || transferring)
                        .opacity(recipientAddress.isEmpty ? 0.5 : 1)
                    }
                    .padding(.horizontal, 16)
                }
            } else {
                VStack {
                    Spacer()
                    Text("NFT not found")
                        .font(CelariTypography.mono)
                        .foregroundColor(CelariColors.textDim)
                    Spacer()
                }
            }
        }
    }

    private func transferNft(_ nft: NFTItem) {
        transferring = true
        Task {
            do {
                _ = try await pxeBridge.transferNft(
                    contractAddress: nft.contractAddress,
                    tokenId: nft.tokenId,
                    to: recipientAddress,
                    mode: transferMode
                )
                store.showToast("NFT transferred")
                store.screen = .dashboard
            } catch {
                store.showToast("Transfer failed: \(error.localizedDescription)", type: .error)
            }
            transferring = false
        }
    }
}
