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
    var body: some View {
        Canvas { context, size in
            for _ in 0..<800 {
                let x = CGFloat.random(in: 0...size.width)
                let y = CGFloat.random(in: 0...size.height)
                let alpha = Double.random(in: 0.01...0.04)
                context.fill(
                    Path(CGRect(x: x, y: y, width: 1, height: 1)),
                    with: .color(.white.opacity(alpha))
                )
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
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
