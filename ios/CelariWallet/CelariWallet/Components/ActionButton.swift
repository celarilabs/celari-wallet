import SwiftUI

struct ActionButton: View {
    var icon: String
    var label: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                DiamondShape()
                    .stroke(CelariColors.copper.opacity(0.3), lineWidth: 1)
                    .frame(width: 28, height: 28)
                    .overlay(
                        Image(systemName: icon)
                            .font(.system(size: 10))
                            .foregroundColor(CelariColors.copper)
                    )

                Text(label)
                    .font(CelariTypography.monoTiny)
                    .tracking(1)
                    .foregroundColor(CelariColors.textDim)
                    .textCase(.uppercase)
            }
            .frame(maxWidth: .infinity)
        }
    }
}
