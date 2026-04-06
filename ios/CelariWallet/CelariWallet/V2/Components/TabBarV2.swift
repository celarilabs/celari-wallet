import SwiftUI

enum V2Tab: Int, CaseIterable {
    case home, send, swap, bridge, receive, history

    var label: String {
        switch self {
        case .home: return "HOME"
        case .send: return "SEND"
        case .swap: return "SWAP"
        case .bridge: return "BRIDGE"
        case .receive: return "RECEIVE"
        case .history: return "HISTORY"
        }
    }

    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .send: return "paperplane.fill"
        case .swap: return "arrow.triangle.2.circlepath"
        case .bridge: return "arrow.left.arrow.right"
        case .receive: return "arrow.down.circle.fill"
        case .history: return "clock.fill"
        }
    }
}

struct TabBarV2: View {
    @Binding var activeTab: V2Tab

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(V2Tab.allCases, id: \.self) { tab in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            activeTab = tab
                        }
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 18))
                            Text(tab.label)
                                .font(.system(size: 10, weight: .semibold))
                                .tracking(0.5)
                        }
                        .foregroundColor(activeTab == tab ? V2Colors.aztecGreen : V2Colors.textMuted)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 26)
                                .fill(activeTab == tab ? V2Colors.aztecDark : .clear)
                        )
                    }
                }
            }
            .frame(height: 62)
            .padding(4)
            .background(
                RoundedRectangle(cornerRadius: 36)
                    .fill(V2Colors.bgCard)
                    .overlay(
                        RoundedRectangle(cornerRadius: 36)
                            .stroke(V2Colors.borderPrimary, lineWidth: 1)
                    )
            )
            .padding(.horizontal, 21)
            .padding(.top, 12)
            .padding(.bottom, 21)
        }
        .background(V2Colors.bgCanvas)
    }
}
