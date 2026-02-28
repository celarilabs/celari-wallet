import SwiftUI

// MARK: - Diamond Shape (45-degree rotated square — Art Deco signature)

struct DiamondShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let halfSize = min(rect.width, rect.height) / 2
        path.move(to: CGPoint(x: center.x, y: center.y - halfSize))
        path.addLine(to: CGPoint(x: center.x + halfSize, y: center.y))
        path.addLine(to: CGPoint(x: center.x, y: center.y + halfSize))
        path.addLine(to: CGPoint(x: center.x - halfSize, y: center.y))
        path.closeSubpath()
        return path
    }
}

// MARK: - Deco Corners (corner accent lines on cards)

struct DecoCorners: ViewModifier {
    var color: Color = CelariColors.copper.opacity(0.15)
    var length: CGFloat = 20
    var offset: CGFloat = 8

    func body(content: Content) -> some View {
        content.overlay {
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                Path { path in
                    // Top-left
                    path.move(to: CGPoint(x: offset, y: offset + length))
                    path.addLine(to: CGPoint(x: offset, y: offset))
                    path.addLine(to: CGPoint(x: offset + length, y: offset))
                    // Top-right
                    path.move(to: CGPoint(x: w - offset - length, y: offset))
                    path.addLine(to: CGPoint(x: w - offset, y: offset))
                    path.addLine(to: CGPoint(x: w - offset, y: offset + length))
                    // Bottom-right
                    path.move(to: CGPoint(x: w - offset, y: h - offset - length))
                    path.addLine(to: CGPoint(x: w - offset, y: h - offset))
                    path.addLine(to: CGPoint(x: w - offset - length, y: h - offset))
                    // Bottom-left
                    path.move(to: CGPoint(x: offset + length, y: h - offset))
                    path.addLine(to: CGPoint(x: offset, y: h - offset))
                    path.addLine(to: CGPoint(x: offset, y: h - offset - length))
                }
                .stroke(color, lineWidth: 1)
            }
        }
    }
}

// MARK: - Grain Overlay (subtle noise texture)

struct GrainOverlay: View {
    // Use seeded random generator so the pattern is stable across renders (4.8 audit fix)
    private struct GrainPoint: Identifiable {
        let id: Int
        let x: CGFloat
        let y: CGFloat
        let alpha: Double
    }

    @State private var points: [GrainPoint] = {
        var rng = SplitMix64(seed: 42)
        return (0..<800).map { i in
            GrainPoint(
                id: i,
                x: CGFloat(rng.nextFraction()),
                y: CGFloat(rng.nextFraction()),
                alpha: 0.01 + rng.nextFraction() * 0.03
            )
        }
    }()

    var body: some View {
        Canvas { context, size in
            for pt in points {
                context.fill(
                    Path(CGRect(x: pt.x * size.width, y: pt.y * size.height, width: 1, height: 1)),
                    with: .color(.white.opacity(pt.alpha))
                )
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }
}

// Simple deterministic PRNG (SplitMix64)
private struct SplitMix64 {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9e3779b97f4a7c15
        var z = state
        z = (z ^ (z >> 30)) &* 0xbf58476d1ce4e5b9
        z = (z ^ (z >> 27)) &* 0x94d049bb133111eb
        return z ^ (z >> 31)
    }
    mutating func nextFraction() -> Double {
        Double(next() >> 11) / Double(1 << 53)
    }
}

// MARK: - Button Styles

struct CelariPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(CelariTypography.monoLabel)
            .tracking(2)
            .textCase(.uppercase)
            .foregroundColor(CelariColors.textWarm)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(CelariColors.burgundy)
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

struct CelariSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(CelariTypography.monoLabel)
            .tracking(2)
            .textCase(.uppercase)
            .foregroundColor(CelariColors.textDim)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(CelariColors.bgCard)
            .overlay(Rectangle().stroke(CelariColors.border, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

// MARK: - Deco Separator (line — diamond — line)

struct DecoSeparator: View {
    var body: some View {
        HStack(spacing: 8) {
            Rectangle()
                .fill(CelariColors.border)
                .frame(height: 1)
            DiamondShape()
                .fill(CelariColors.copper.opacity(0.3))
                .frame(width: 6, height: 6)
            Rectangle()
                .fill(CelariColors.border)
                .frame(height: 1)
        }
        .padding(.horizontal, 40)
    }
}

// MARK: - View Extensions

extension View {
    func decoCorners(color: Color = CelariColors.copper.opacity(0.15)) -> some View {
        modifier(DecoCorners(color: color))
    }

    func celariCard() -> some View {
        self
            .background(CelariColors.bgCard)
            .overlay(Rectangle().stroke(CelariColors.border, lineWidth: 1))
    }
}
