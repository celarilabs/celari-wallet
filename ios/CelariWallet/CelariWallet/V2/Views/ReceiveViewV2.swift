import SwiftUI
import CoreImage.CIFilterBuiltins

struct ReceiveViewV2: View {
    @Environment(WalletStore.self) private var store

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Receive")
                    .font(V2Fonts.heading(22))
                    .foregroundColor(V2Colors.textPrimary)
                Spacer()
            }
            .padding(.horizontal, 24)
            .frame(height: 52)

            ScrollView {
                VStack(spacing: 24) {
                    // QR Card
                    VStack(spacing: 16) {
                        // Shielded badge
                        HStack(spacing: 6) {
                            Image(systemName: "shield.checkered")
                                .font(.system(size: 12))
                            Text("Aztec Shielded")
                                .font(V2Fonts.label(10))
                                .tracking(0.5)
                        }
                        .foregroundColor(V2Colors.aztecGreen)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            Capsule().fill(Color(hex2: "2A3D52"))
                        )

                        // QR Code
                        if let address = store.activeAccount?.address {
                            qrCodeImage(for: address)
                                .interpolation(.none)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 200, height: 200)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(V2Colors.textWhite)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(V2Colors.borderPrimary, lineWidth: 2)
                                )
                        } else {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(V2Colors.bgControl)
                                .frame(width: 200, height: 200)
                                .overlay(Text("No address").foregroundColor(V2Colors.textMuted))
                        }

                        Text("Scan to receive tokens")
                            .font(V2Fonts.bodyMedium(13))
                            .foregroundColor(V2Colors.textSecondary)
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(V2Colors.bgCard)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(V2Colors.borderPrimary, lineWidth: 1)
                            )
                    )

                    // Token chips
                    HStack(spacing: 8) {
                        ForEach(["ETH", "DAI", "USDC"], id: \.self) { symbol in
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(chipColor(for: symbol))
                                    .frame(width: 8, height: 8)
                                Text(symbol)
                                    .font(V2Fonts.bodyMedium(12))
                                    .foregroundColor(V2Colors.textPrimary)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill(V2Colors.bgCard)
                                    .overlay(Capsule().stroke(V2Colors.borderPrimary, lineWidth: 1))
                            )
                        }
                    }

                    // Address section
                    VStack(alignment: .leading, spacing: 8) {
                        Text("YOUR SHIELDED ADDRESS")
                            .font(V2Fonts.label(11))
                            .tracking(2)
                            .foregroundColor(V2Colors.textTertiary)

                        HStack {
                            Text(store.activeAccount?.shortAddress ?? "No address")
                                .font(V2Fonts.mono(14))
                                .foregroundColor(V2Colors.textPrimary)
                        }
                        .frame(maxWidth: .infinity)
                        .cardStyle()
                    }

                    // Action buttons
                    HStack(spacing: 12) {
                        Button {
                            UIPasteboard.general.string = store.activeAccount?.address
                            store.showToast("Address copied!")
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "doc.on.doc")
                                Text("Copy")
                            }
                            .font(V2Fonts.bodySemibold(15))
                            .foregroundColor(V2Colors.textWhite)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(V2Colors.aztecDark)
                            )
                        }

                        Button {} label: {
                            HStack(spacing: 8) {
                                Image(systemName: "square.and.arrow.up")
                                Text("Share")
                            }
                            .font(V2Fonts.bodySemibold(15))
                            .foregroundColor(V2Colors.textPrimary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(V2Colors.bgCard)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(V2Colors.borderPrimary, lineWidth: 1)
                                    )
                            )
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
            }
        }
        .background(V2Colors.bgCanvas)
    }

    private func chipColor(for symbol: String) -> Color {
        switch symbol {
        case "ETH": return Color(hex2: "627EEA")
        case "DAI": return V2Colors.soOrange
        case "USDC": return V2Colors.soBlue
        default: return V2Colors.textMuted
        }
    }

    private func qrCodeImage(for string: String) -> Image {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        if let output = filter.outputImage,
           let cgImage = context.createCGImage(output, from: output.extent) {
            return Image(uiImage: UIImage(cgImage: cgImage))
        }
        return Image(systemName: "qrcode")
    }
}
