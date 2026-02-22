import SwiftUI

struct LoadingView: View {
    @State private var rotating = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // Diamond spinner
            DiamondShape()
                .stroke(CelariColors.copper.opacity(0.4), lineWidth: 1)
                .frame(width: 40, height: 40)
                .rotationEffect(.degrees(rotating ? 360 : 0))
                .animation(.linear(duration: 2).repeatForever(autoreverses: false), value: rotating)
                .onAppear { rotating = true }

            Text("LOADING")
                .font(CelariTypography.monoLabel)
                .tracking(3)
                .foregroundColor(CelariColors.textDim)

            Spacer()
        }
    }
}
