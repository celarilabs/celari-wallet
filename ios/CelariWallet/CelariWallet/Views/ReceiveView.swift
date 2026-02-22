import SwiftUI
import CoreImage.CIFilterBuiltins

struct ReceiveView: View {
    @Environment(WalletStore.self) private var store

    var body: some View {
        VStack(spacing: 0) {
            SubHeaderView(title: "Receive")

            ScrollView {
                VStack(spacing: 20) {
                    if let account = store.activeAccount {
                        // QR Code
                        if let qrImage = generateQR(from: account.address) {
                            Image(uiImage: qrImage)
                                .interpolation(.none)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 180, height: 180)
                                .padding(16)
                                .background(Color.white)
                                .overlay(Rectangle().stroke(CelariColors.border, lineWidth: 1))
                        }

                        // Address display
                        VStack(spacing: 8) {
                            Text("YOUR ADDRESS")
                                .font(CelariTypography.monoLabel)
                                .tracking(3)
                                .foregroundColor(CelariColors.textDim)

                            Text(account.address)
                                .font(CelariTypography.monoTiny)
                                .foregroundColor(CelariColors.textBody)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 16)

                            Button {
                                UIPasteboard.general.string = account.address
                                store.showToast("Address copied")
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "doc.on.doc")
                                        .font(.system(size: 10))
                                    Text("COPY ADDRESS")
                                        .font(CelariTypography.monoLabel)
                                        .tracking(1)
                                }
                                .foregroundColor(CelariColors.copper)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .overlay(Rectangle().stroke(CelariColors.copper.opacity(0.3), lineWidth: 1))
                            }
                        }

                        DecoSeparator()

                        Text("Share this address to receive tokens on the Aztec network")
                            .font(CelariTypography.monoTiny)
                            .foregroundColor(CelariColors.textDim)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            }
        }
    }

    private func generateQR(from string: String) -> UIImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"

        guard let outputImage = filter.outputImage else { return nil }
        let scale = 256 / outputImage.extent.width
        let scaledImage = outputImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
