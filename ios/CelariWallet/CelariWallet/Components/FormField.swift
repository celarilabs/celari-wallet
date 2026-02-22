import SwiftUI

struct FormField: View {
    var label: String
    @Binding var text: String
    var placeholder: String = ""
    var isSecure: Bool = false
    var keyboardType: UIKeyboardType = .default

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(CelariTypography.monoLabel)
                .tracking(2)
                .foregroundColor(CelariColors.textDim)
                .textCase(.uppercase)

            Group {
                if isSecure {
                    SecureField(placeholder, text: $text)
                } else {
                    TextField(placeholder, text: $text)
                        .keyboardType(keyboardType)
                }
            }
            .font(CelariTypography.mono)
            .foregroundColor(CelariColors.textWarm)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(CelariColors.bgInput)
            .overlay(Rectangle().stroke(CelariColors.border, lineWidth: 1))
        }
    }
}
