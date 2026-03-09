import SwiftUI

struct HistoryViewV2: View {
    @Environment(WalletStore.self) private var store
    @State private var activeFilter = "All"
    private let filters = ["All", "Sent", "Received", "Shielded"]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("History")
                    .font(V2Fonts.heading(22))
                    .foregroundColor(V2Colors.textPrimary)
                Spacer()
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 20))
                    .foregroundColor(V2Colors.textTertiary)
            }
            .padding(.horizontal, 24)
            .frame(height: 52)

            ScrollView {
                VStack(spacing: 20) {
                    // Filter chips
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(filters, id: \.self) { filter in
                                Button {
                                    activeFilter = filter
                                } label: {
                                    Text(filter)
                                        .font(V2Fonts.bodyMedium(13))
                                        .foregroundColor(activeFilter == filter ? V2Colors.textWhite : V2Colors.textPrimary)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 6)
                                        .background(
                                            Capsule()
                                                .fill(activeFilter == filter ? V2Colors.aztecDark : V2Colors.bgCard)
                                                .overlay(
                                                    activeFilter == filter ? nil :
                                                    Capsule().stroke(V2Colors.borderPrimary, lineWidth: 1)
                                                )
                                        )
                                }
                            }
                        }
                    }

                    if store.activities.isEmpty {
                        // Empty state
                        VStack(spacing: 12) {
                            Image(systemName: "clock")
                                .font(.system(size: 40))
                                .foregroundColor(V2Colors.textDisabled)
                            Text("No transactions yet")
                                .font(V2Fonts.bodyMedium(15))
                                .foregroundColor(V2Colors.textSecondary)
                            Text("Your transaction history will appear here")
                                .font(V2Fonts.body(13))
                                .foregroundColor(V2Colors.textTertiary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 60)
                    } else {
                        // Today section
                        VStack(alignment: .leading, spacing: 8) {
                            Text("TODAY")
                                .font(V2Fonts.label(11))
                                .tracking(2)
                                .foregroundColor(V2Colors.textTertiary)

                            VStack(spacing: 0) {
                                ForEach(store.activities) { activity in
                                    activityRow(activity)
                                    if activity.id != store.activities.last?.id {
                                        Divider()
                                            .background(V2Colors.borderDivider)
                                            .padding(.horizontal, 16)
                                    }
                                }
                            }
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(V2Colors.bgCard)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(V2Colors.borderPrimary, lineWidth: 1)
                                    )
                            )
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
            }
        }
        .background(V2Colors.bgCanvas)
    }

    private func activityRow(_ activity: Activity) -> some View {
        HStack {
            // Icon
            ZStack {
                Circle()
                    .fill(activityIconBg(activity))
                    .frame(width: 40, height: 40)
                Image(systemName: activityIcon(activity))
                    .font(.system(size: 16))
                    .foregroundColor(activityIconColor(activity))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(activity.label)
                    .font(V2Fonts.bodyMedium(15))
                    .foregroundColor(V2Colors.textPrimary)
                Text(activity.time)
                    .font(V2Fonts.mono(11))
                    .foregroundColor(V2Colors.textTertiary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(activity.amount)
                    .font(V2Fonts.monoSemibold(14))
                    .foregroundColor(activity.type == .receive ? V2Colors.successGreen : V2Colors.textPrimary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func activityIcon(_ activity: Activity) -> String {
        switch activity.type {
        case .send: return "arrow.up.right"
        case .receive: return "arrow.down.left"
        }
    }

    private func activityIconBg(_ activity: Activity) -> Color {
        switch activity.type {
        case .send: return V2Colors.soOrange.opacity(0.1)
        case .receive: return V2Colors.successGreen.opacity(0.1)
        }
    }

    private func activityIconColor(_ activity: Activity) -> Color {
        switch activity.type {
        case .send: return V2Colors.soOrange
        case .receive: return V2Colors.successGreen
        }
    }
}
