import SwiftUI

struct HeaderView: View {
    @Environment(WalletStore.self) private var store
    var title: String = "CELARI"
    var showBack: Bool = false
    var showSettings: Bool = true
    var showWc: Bool = true

    var body: some View {
        HStack {
            if showBack {
                Button {
                    store.screen = .dashboard
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12))
                        .foregroundColor(CelariColors.textDim)
                        .frame(width: 32, height: 32)
                }
            }

            Text(title)
                .font(CelariTypography.headingSmall)
                .foregroundColor(CelariColors.textWarm)
                .tracking(4)

            Spacer()

            if showWc {
                Button {
                    store.screen = .walletConnect
                } label: {
                    Image(systemName: "link")
                        .font(.system(size: 12))
                        .foregroundColor(store.wcSessions.isEmpty ? CelariColors.textDim : CelariColors.green)
                        .frame(width: 32, height: 32)
                }
            }

            if showSettings {
                Button {
                    store.screen = .settings
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 12))
                        .foregroundColor(CelariColors.textDim)
                        .frame(width: 32, height: 32)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) {
            Rectangle().fill(CelariColors.border).frame(height: 1)
        }
    }
}
