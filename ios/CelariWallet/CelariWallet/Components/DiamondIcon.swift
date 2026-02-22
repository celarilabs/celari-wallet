import SwiftUI

struct DiamondIcon: View {
    var text: String = ""
    var systemImage: String?
    var color: Color = CelariColors.copper
    var size: CGFloat = 32
    var filled: Bool = false

    var body: some View {
        ZStack {
            if filled {
                DiamondShape()
                    .fill(color.opacity(0.15))
                    .frame(width: size, height: size)
            } else {
                DiamondShape()
                    .stroke(color, lineWidth: 1)
                    .frame(width: size, height: size)
            }

            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: size * 0.35))
                    .foregroundColor(color)
            } else {
                Text(text)
                    .font(size > 24 ? CelariTypography.title : CelariTypography.monoSmall)
                    .foregroundColor(color)
            }
        }
    }
}
