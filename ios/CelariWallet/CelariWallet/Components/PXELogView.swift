import SwiftUI

struct PXELogView: View {
    @Environment(WalletStore.self) private var store

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("PXE LOG")
                    .font(CelariTypography.monoTiny)
                    .tracking(2)
                    .foregroundColor(CelariColors.copper)
                Spacer()
                Text("\(store.pxeLogs.count)")
                    .font(CelariTypography.monoTiny)
                    .foregroundColor(CelariColors.textDim)
                Button {
                    store.clearPXELogs()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 10))
                        .foregroundColor(CelariColors.textDim)
                }
                .padding(.leading, 8)
                Button {
                    store.showLogs = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10))
                        .foregroundColor(CelariColors.textDim)
                }
                .padding(.leading, 4)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(CelariColors.bg.opacity(0.95))
            .overlay(alignment: .bottom) {
                Rectangle().fill(CelariColors.border).frame(height: 0.5)
            }

            // Log entries
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(store.pxeLogs) { entry in
                            HStack(alignment: .top, spacing: 4) {
                                Text(entry.timeString)
                                    .font(.system(size: 9, weight: .regular, design: .monospaced))
                                    .foregroundColor(CelariColors.textDim.opacity(0.5))
                                Text(entry.levelIcon)
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .foregroundColor(colorForLevel(entry.level))
                                Text(cleanMessage(entry.message))
                                    .font(.system(size: 9, weight: .regular, design: .monospaced))
                                    .foregroundColor(colorForLevel(entry.level))
                                    .lineLimit(3)
                            }
                            .padding(.horizontal, 8)
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
        .frame(maxHeight: 260)
        .background(CelariColors.bg.opacity(0.98))
        .overlay(Rectangle().stroke(CelariColors.border, lineWidth: 0.5))
    }

    private func colorForLevel(_ level: String) -> Color {
        switch level {
        case "error": return .red
        case "warn": return CelariColors.copper
        default: return CelariColors.textBody
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
