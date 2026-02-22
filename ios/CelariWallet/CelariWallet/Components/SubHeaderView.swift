import SwiftUI

struct SubHeaderView: View {
    @Environment(WalletStore.self) private var store
    var title: String

    var body: some View {
        HStack {
            Button {
                store.screen = .dashboard
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12))
                    .foregroundColor(CelariColors.textDim)
            }

            Text(title)
                .font(CelariTypography.monoLabel)
                .tracking(3)
                .foregroundColor(CelariColors.textWarm)
                .textCase(.uppercase)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) {
            Rectangle().fill(CelariColors.border).frame(height: 1)
        }
    }
}
