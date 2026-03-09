import SwiftUI

struct ActionButtonV2: View {
    let icon: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(V2Colors.bgCard)
                        .overlay(
                            Circle().stroke(V2Colors.borderPrimary, lineWidth: 1)
                        )
                        .frame(width: 52, height: 52)
                    Image(systemName: icon)
                        .font(.system(size: 22))
                        .foregroundColor(V2Colors.textPrimary)
                }
                Text(label)
                    .font(V2Fonts.bodyMedium(12))
                    .foregroundColor(V2Colors.textSecondary)
            }
            .frame(width: 72)
        }
    }
}
