import SwiftUI

struct ActivityListView: View {
    @Environment(WalletStore.self) private var store

    var body: some View {
        if store.activities.isEmpty {
            VStack(spacing: 8) {
                DiamondShape()
                    .fill(CelariColors.textFaint.opacity(0.3))
                    .frame(width: 24, height: 24)
                Text("NO TRANSACTIONS YET")
                    .font(CelariTypography.monoLabel)
                    .tracking(2)
                    .foregroundColor(CelariColors.textDim)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 32)
        } else {
            LazyVStack(spacing: 0) {
                ForEach(store.activities) { activity in
                    HStack(spacing: 12) {
                        DiamondShape()
                            .fill(activity.type == .send ? CelariColors.burgundy.opacity(0.15) : CelariColors.copper.opacity(0.15))
                            .frame(width: 28, height: 28)
                            .overlay(
                                Image(systemName: activity.type == .send ? "arrow.up.right" : "arrow.down.left")
                                    .font(.system(size: 10))
                                    .foregroundColor(activity.type == .send ? CelariColors.burgundyLight : CelariColors.copper)
                            )

                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 4) {
                                Text(activity.label)
                                    .font(CelariTypography.monoSmall)
                                    .tracking(1)
                                    .foregroundColor(CelariColors.textWarm)
                                    .textCase(.uppercase)

                                if activity.isPrivate {
                                    Circle()
                                        .fill(CelariColors.green)
                                        .frame(width: 5, height: 5)
                                }
                            }
                            Text(activity.time)
                                .font(CelariTypography.monoTiny)
                                .foregroundColor(CelariColors.textDim)
                        }

                        Spacer()

                        Text(activity.amount)
                            .font(CelariTypography.monoSmall)
                            .foregroundColor(activity.type == .send ? CelariColors.red : CelariColors.copper)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(CelariColors.border).frame(height: 1)
                    }
                }
            }
        }
    }
}
