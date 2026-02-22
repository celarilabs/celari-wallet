import SwiftUI

// MARK: - Colors (from popup.css :root variables)

enum CelariColors {
    // Backgrounds
    static let bg = Color(hex: "0D0A0A")
    static let bgCard = Color(hex: "151111")
    static let bgElevated = Color(hex: "1C1616")
    static let bgSection = Color(hex: "100D0C")
    static let bgInput = Color(hex: "1C1616")

    // Primary palette
    static let burgundy = Color(hex: "8B2D3A")
    static let burgundyDeep = Color(hex: "5C1D28")
    static let burgundyLight = Color(hex: "B84455")
    static let copper = Color(hex: "C87941")
    static let copperLight = Color(hex: "E09A62")
    static let copperMuted = Color(hex: "A06835")
    static let bronze = Color(hex: "9A7B5B")

    // Semantic
    static let green = Color(hex: "4ade80")
    static let greenGlow = Color(hex: "4ade80").opacity(0.08)
    static let red = Color(hex: "ef4444")

    // Text
    static let textWarm = Color(hex: "E8D8CC")
    static let textBody = Color(hex: "BCA898")
    static let textMuted = Color(hex: "8A7A70")
    static let textDim = Color(hex: "5A4E48")
    static let textFaint = Color(hex: "3A3230")

    // Borders
    static let border = Color(hex: "2A2222")
    static let borderWarm = Color(hex: "3A2E2E")

    // Balance card gradient
    static let balanceGradient = LinearGradient(
        colors: [Color(hex: "5C1D28"), Color(hex: "3D1520"), Color(hex: "2A1018")],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

// MARK: - Typography

enum CelariTypography {
    static let heading = Font.custom("PoiretOne-Regular", size: 28)
    static let headingSmall = Font.custom("PoiretOne-Regular", size: 22)
    static let subheading = Font.custom("PoiretOne-Regular", size: 16)
    static let title = Font.custom("PoiretOne-Regular", size: 14)

    static let mono = Font.custom("IBMPlexMono-Regular", size: 12)
    static let monoSmall = Font.custom("IBMPlexMono-Regular", size: 10)
    static let monoLabel = Font.custom("IBMPlexMono-Medium", size: 8)
    static let monoTiny = Font.custom("IBMPlexMono-Regular", size: 7)

    static let accent = Font.custom("TenorSans-Regular", size: 12)
    static let accentItalic = Font.custom("TenorSans-Regular", size: 12).italic()

    static let body = Font.custom("Outfit-Regular", size: 13)
    static let bodySmall = Font.custom("Outfit-Regular", size: 11)

    static let balance = Font.custom("PoiretOne-Regular", size: 34)
}

// MARK: - Color hex initializer

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 6:
            (a, r, g, b) = (255, (int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = ((int >> 24) & 0xFF, (int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
