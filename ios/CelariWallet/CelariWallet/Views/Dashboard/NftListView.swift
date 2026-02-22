import SwiftUI

struct NftListView: View {
    @Environment(WalletStore.self) private var store

    var body: some View {
        if store.nfts.isEmpty {
            VStack(spacing: 12) {
                DiamondShape()
                    .fill(CelariColors.textFaint.opacity(0.3))
                    .frame(width: 24, height: 24)
                Text("NO NFTS FOUND")
                    .font(CelariTypography.monoLabel)
                    .tracking(2)
                    .foregroundColor(CelariColors.textDim)

                Button {
                    store.screen = .addNftContract
                } label: {
                    Text("ADD NFT CONTRACT")
                        .font(CelariTypography.monoLabel)
                        .tracking(1)
                        .foregroundColor(CelariColors.copper)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .overlay(Rectangle().stroke(CelariColors.copper.opacity(0.3), lineWidth: 1))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 32)
        } else {
            LazyVStack(spacing: 0) {
                ForEach(store.nfts) { nft in
                    Button {
                        store.nftDetail = NFTDetailSelection(contractAddress: nft.contractAddress, tokenId: nft.tokenId)
                        store.screen = .nftDetail
                    } label: {
                        HStack(spacing: 12) {
                            DiamondShape()
                                .stroke(CelariColors.copper, lineWidth: 1)
                                .frame(width: 32, height: 32)
                                .overlay(
                                    Text("N")
                                        .font(CelariTypography.title)
                                        .foregroundColor(CelariColors.copper)
                                )

                            VStack(alignment: .leading, spacing: 2) {
                                Text(nft.contractName)
                                    .font(CelariTypography.monoSmall)
                                    .tracking(1)
                                    .foregroundColor(CelariColors.textWarm)
                                    .textCase(.uppercase)
                                Text("#\(nft.tokenId)")
                                    .font(CelariTypography.monoTiny)
                                    .foregroundColor(CelariColors.textDim)
                            }

                            Spacer()

                            Text(nft.isPrivate ? "PRIVATE" : "PUBLIC")
                                .font(CelariTypography.monoTiny)
                                .tracking(1.5)
                                .foregroundColor(nft.isPrivate ? CelariColors.green : CelariColors.copper)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .overlay(
                                    Rectangle().stroke(
                                        nft.isPrivate ? CelariColors.green.opacity(0.2) : CelariColors.copper.opacity(0.2),
                                        lineWidth: 1
                                    )
                                )
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(CelariColors.border).frame(height: 1)
                        }
                    }
                }
            }
        }
    }
}
