import SwiftUI

struct PXELogViewV2: View {
    @Environment(WalletStore.self) private var store

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                HStack(spacing: 6) {
                    Circle()
                        .fill(V2Colors.aztecGreen)
                        .frame(width: 6, height: 6)
                    Text("PXE LOG")
                        .font(V2Fonts.label(10))
                        .tracking(2)
                        .foregroundColor(V2Colors.textTertiary)
                }
                Spacer()
                Text("\(store.pxeLogs.count)")
                    .font(V2Fonts.mono(10))
                    .foregroundColor(V2Colors.textTertiary)
                Button {
                    store.clearPXELogs()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundColor(V2Colors.textTertiary)
                }
                .padding(.leading, 8)
                Button {
                    store.showLogs = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11))
                        .foregroundColor(V2Colors.textTertiary)
                }
                .padding(.leading, 4)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(V2Colors.bgCard)
            .overlay(alignment: .bottom) {
                Rectangle().fill(V2Colors.borderPrimary).frame(height: 0.5)
            }

            // Log entries
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(store.pxeLogs) { entry in
                            HStack(alignment: .top, spacing: 4) {
                                Text(entry.timeString)
                                    .font(.system(size: 9, weight: .regular, design: .monospaced))
                                    .foregroundColor(V2Colors.textDisabled)
                                Text(entry.levelIcon)
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .foregroundColor(colorForLevel(entry.level))
                                Text(cleanMessage(entry.message))
                                    .font(.system(size: 9, weight: .regular, design: .monospaced))
                                    .foregroundColor(colorForLevel(entry.level))
                                    .lineLimit(3)
                                    .textSelection(.enabled)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 1)
                            .id(entry.id)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .onChange(of: store.pxeLogs.count) {
                    if let last = store.pxeLogs.last {
                        withAnimation(.easeOut(duration: 0.15)) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
        }
        .frame(maxHeight: 280)
        .background(V2Colors.bgCard.opacity(0.98))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(V2Colors.borderPrimary, lineWidth: 1)
        )
    }

    private func colorForLevel(_ level: String) -> Color {
        switch level {
        case "error": return V2Colors.errorRed
        case "warn": return V2Colors.warningOrange
        default: return V2Colors.textSecondary
        }
    }

    private func cleanMessage(_ msg: String) -> String {
        msg.replacingOccurrences(of: "[PXE] ", with: "")
           .replacingOccurrences(of: "[PXE-JS:log] ", with: "")
           .replacingOccurrences(of: "[PXE-JS:error] ", with: "")
           .replacingOccurrences(of: "[PXE-JS:warn] ", with: "")
           .replacingOccurrences(of: "[AuthWit] ", with: "")
    }
}
