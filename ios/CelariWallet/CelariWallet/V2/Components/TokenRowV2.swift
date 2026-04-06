import SwiftUI

struct TokenRowV2: View {
    let token: Token

    private var iconColor: Color {
        switch token.symbol {
        case "zkETH": return Color(hex2: "627EEA")
        case "zkUSD": return Color(hex2: "F48225")
        case "ZKP": return V2Colors.tealAccent
        default: return V2Colors.textTertiary
        }
    }

    var body: some View {
        HStack {
            // Left: icon + info
            HStack(spacing: 12) {
                // Token icon circle
                ZStack {
                    Circle()
                        .fill(iconColor)
                        .frame(width: 40, height: 40)
                    Text(token.icon)
                        .font(V2Fonts.monoBold(16))
                        .foregroundColor(V2Colors.textWhite)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(token.name)
                        .font(V2Fonts.headingMedium(16))
                        .foregroundColor(V2Colors.textPrimary)
                    Text(token.symbol)
                        .font(V2Fonts.label(11))
                        .tracking(1)
                        .foregroundColor(V2Colors.textTertiary)
                }
            }

            Spacer()

            // Right: total balance + private/public breakdown (AIP-20)
            VStack(alignment: .trailing, spacing: 3) {
                // Total balance line
                Text("\(token.balance) \(token.symbol)")
                    .font(V2Fonts.monoSemibold(14))
                    .foregroundColor(V2Colors.textPrimary)

                // Private/public breakdown (only if either is non-zero)
                if token.hasBalanceBreakdown {
                    Text("Private: \(token.privateBalance)")
                        .font(V2Fonts.mono(11))
                        .foregroundColor(V2Colors.textTertiary)
                    Text("Public: \(token.publicBalance)")
                        .font(V2Fonts.mono(11))
                        .foregroundColor(V2Colors.textTertiary)
                }
            }
        }
        .frame(minHeight: 56)
    }
}
