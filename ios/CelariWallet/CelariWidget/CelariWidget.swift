import WidgetKit
import SwiftUI

// MARK: - Data

struct WalletEntry: TimelineEntry {
    let date: Date
    let totalBalance: String
    let tokens: [(symbol: String, balance: String)]
}

// MARK: - Provider

struct WalletProvider: TimelineProvider {
    private let suiteName = "group.com.celari.wallet"

    func placeholder(in context: Context) -> WalletEntry {
        WalletEntry(date: .now, totalBalance: "***", tokens: [("ETH", "***"), ("CLR", "***")])
    }

    func getSnapshot(in context: Context, completion: @escaping (WalletEntry) -> Void) {
        completion(loadEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WalletEntry>) -> Void) {
        let entry = loadEntry()
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: .now)!
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }

    private func loadEntry() -> WalletEntry {
        let defaults = UserDefaults(suiteName: suiteName)
        let balance = defaults?.string(forKey: "widgetTotalBalance") ?? "0.00"
        var tokens: [(String, String)] = []
        if let data = defaults?.data(forKey: "widgetTokens"),
           let decoded = try? JSONDecoder().decode([[String]].self, from: data) {
            tokens = decoded.map { ($0[0], $0[1]) }
        }
        if tokens.isEmpty {
            tokens = [("ETH", "0.00"), ("CLR", "0.00")]
        }
        return WalletEntry(date: .now, totalBalance: balance, tokens: tokens)
    }
}

// MARK: - Views

struct CelariWidgetSmallView: View {
    let entry: WalletEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "shield.checkered")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.purple)
                Text("Celari")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
            }
            Spacer()
            Text("Balance")
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.6))
            Text(entry.totalBalance)
                .font(.system(size: 22, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
        }
        .padding()
        .containerBackground(for: .widget) {
            LinearGradient(
                colors: [Color(hex: "1a1a2e"), Color(hex: "16213e")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}

struct CelariWidgetMediumView: View {
    let entry: WalletEntry

    var body: some View {
        HStack(spacing: 16) {
            // Left: Total balance
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: "shield.checkered")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.purple)
                    Text("Celari")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                }
                Spacer()
                Text("Total Balance")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.6))
                Text(entry.totalBalance)
                    .font(.system(size: 20, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
            }

            // Right: Token list
            VStack(alignment: .leading, spacing: 6) {
                ForEach(entry.tokens.prefix(3), id: \.symbol) { token in
                    HStack {
                        Text(token.symbol)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.white.opacity(0.7))
                            .frame(width: 36, alignment: .leading)
                        Text(token.balance)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(.white)
                            .lineLimit(1)
                    }
                }
                if entry.tokens.count < 3 {
                    Spacer()
                }
            }
        }
        .padding()
        .containerBackground(for: .widget) {
            LinearGradient(
                colors: [Color(hex: "1a1a2e"), Color(hex: "16213e")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}

// MARK: - Widget

struct CelariWidget: Widget {
    let kind = "CelariWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WalletProvider()) { entry in
            if #available(iOSApplicationExtension 17.0, *) {
                switch entry.tokens.count {
                case 0...1:
                    CelariWidgetSmallView(entry: entry)
                default:
                    CelariWidgetMediumView(entry: entry)
                }
            }
        }
        .configurationDisplayName("Celari Balance")
        .description("View your wallet balance at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Bundle

@main
struct CelariWidgetBundle: WidgetBundle {
    var body: some Widget {
        CelariWidget()
    }
}

// MARK: - Color Helper

extension Color {
    init(hex: String) {
        let scanner = Scanner(string: hex)
        var rgb: UInt64 = 0
        scanner.scanHexInt64(&rgb)
        self.init(
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255
        )
    }
}
