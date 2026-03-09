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

            // Right: public/private balances
            VStack(alignment: .trailing, spacing: 3) {
                if let priv = token.privateBalance, priv != "0" && priv != "—" {
                    HStack(spacing: 4) {
                        Image(systemName: "shield.fill")
                            .font(.system(size: 9))
                            .foregroundColor(V2Colors.aztecGreen)
                        Text(priv)
                            .font(V2Fonts.monoSemibold(13))
                            .foregroundColor(V2Colors.textPrimary)
                    }
                }
                if let pub = token.publicBalance, pub != "—" {
                    HStack(spacing: 4) {
                        Image(systemName: "globe")
                            .font(.system(size: 9))
                            .foregroundColor(V2Colors.textTertiary)
                        Text(pub)
                            .font(V2Fonts.mono(12))
                            .foregroundColor(V2Colors.textSecondary)
                    }
                }
                if token.privateBalance == nil && token.publicBalance == nil {
                    Text(token.value)
                        .font(V2Fonts.monoSemibold(15))
                        .foregroundColor(V2Colors.textPrimary)
                    Text("\(token.balance) \(token.symbol)")
                        .font(V2Fonts.mono(11))
                        .tracking(0.5)
                        .foregroundColor(V2Colors.textTertiary)
                }
            }
        }
        .frame(height: 56)
    }
}
