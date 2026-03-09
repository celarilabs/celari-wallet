import SwiftUI

// MARK: - Design Tokens (from Pencil .pen file)

enum V2Colors {
    // Backgrounds
    static let bgCanvas = Color(hex2: "FAFAFA")
    static let bgCard = Color(hex2: "FFFFFF")
    static let bgControl = Color(hex2: "F0F0F0")
    static let bgMuted = Color(hex2: "F8F8F8")

    // Aztec palette
    static let aztecDark = Color(hex2: "1B2A3D")
    static let aztecDarker = Color(hex2: "0F1B2A")
    static let aztecGreen = Color(hex2: "D4FF28")

    // Accent
    static let soOrange = Color(hex2: "F48225")
    static let soBlue = Color(hex2: "0077CC")
    static let tealAccent = Color(hex2: "0D6E6E")

    // Semantic
    static let errorRed = Color(hex2: "D1383D")
    static let successGreen = Color(hex2: "48A868")
    static let warningOrange = Color(hex2: "E07B54")

    // Text
    static let textPrimary = Color(hex2: "1A1A1A")
    static let textSecondary = Color(hex2: "666666")
    static let textTertiary = Color(hex2: "888888")
    static let textMuted = Color(hex2: "AAAAAA")
    static let textDisabled = Color(hex2: "CCCCCC")
    static let textWhite = Color(hex2: "FFFFFF")

    // Borders
    static let borderPrimary = Color(hex2: "E5E5E5")
    static let borderDivider = Color(hex2: "F0F0F0")

    // Gradients
    static let shieldGradient = LinearGradient(
        colors: [Color(hex2: "D4FF28"), Color(hex2: "0D6E6E")],
        startPoint: .leading,
        endPoint: .trailing
    )
}

// MARK: - Typography

enum V2Fonts {
    // Headings (Newsreader → system serif fallback)
    static func heading(_ size: CGFloat = 22) -> Font {
        .custom("Newsreader-SemiBold", size: size, relativeTo: .title2)
    }
    static func headingMedium(_ size: CGFloat = 16) -> Font {
        .custom("Newsreader-Medium", size: size, relativeTo: .body)
    }

    // Body (Inter → system default)
    static func body(_ size: CGFloat = 15) -> Font {
        .system(size: size, weight: .regular)
    }
    static func bodyMedium(_ size: CGFloat = 15) -> Font {
        .system(size: size, weight: .medium)
    }
    static func bodySemibold(_ size: CGFloat = 16) -> Font {
        .system(size: size, weight: .semibold)
    }

    // Mono (JetBrains Mono → system monospaced)
    static func mono(_ size: CGFloat = 13) -> Font {
        .system(size: size, weight: .medium, design: .monospaced)
    }
    static func monoSemibold(_ size: CGFloat = 13) -> Font {
        .system(size: size, weight: .semibold, design: .monospaced)
    }
    static func monoBold(_ size: CGFloat = 16) -> Font {
        .system(size: size, weight: .bold, design: .monospaced)
    }

    // Labels
    static func label(_ size: CGFloat = 11) -> Font {
        .system(size: size, weight: .semibold, design: .monospaced)
    }

    // Balance
    static let balance = Font.system(size: 38, weight: .bold, design: .monospaced)
}

// MARK: - Color hex initializer (V2 namespace to avoid conflict)

extension Color {
    init(hex2: String) {
        let hex = hex2.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
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
