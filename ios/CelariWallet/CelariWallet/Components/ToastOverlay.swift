import SwiftUI

struct ToastOverlay: View {
    var toast: Toast

    var body: some View {
        VStack {
            Spacer()

            HStack(spacing: 8) {
                Image(systemName: toast.type == .success ? "checkmark.diamond" : "exclamationmark.triangle")
                    .font(.system(size: 10))
                    .foregroundColor(toast.type == .success ? CelariColors.green : CelariColors.red)

                Text(toast.message)
                    .font(CelariTypography.monoSmall)
                    .foregroundColor(CelariColors.textWarm)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(CelariColors.bgElevated)
            .overlay(
                Rectangle().stroke(
                    toast.type == .success ? CelariColors.green.opacity(0.3) : CelariColors.red.opacity(0.3),
                    lineWidth: 1
                )
            )
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .animation(.easeInOut(duration: 0.25), value: toast.message)
    }
}
