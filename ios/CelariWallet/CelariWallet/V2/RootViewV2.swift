import SwiftUI

/// V2 root view using a custom pill-style tab bar.
/// Routes based on store.screen: loading → onboarding → dashboard (tab view).
struct RootViewV2: View {
    @Environment(WalletStore.self) private var store
    @Environment(PXEBridge.self) private var pxeBridge
    @State private var activeTab: V2Tab = .home

    var body: some View {
        ZStack {
            V2Colors.bgCanvas.ignoresSafeArea()

            Group {
                switch store.screen {
                case .loading:
                    LoadingView()
                case .onboarding:
                    OnboardingViewV2()
                case .restore:
                    RestoreViewV2()
                case .recoverAccount:
                    RecoverAccountViewV2()
                case .guardianSetup:
                    GuardianSetupViewV2()
                case .backup:
                    BackupViewV2()
                case .addAccount:
                    AddAccountViewV2()
                default:
                    dashboardContent
                }
            }
            .animation(.easeInOut(duration: 0.2), value: store.screen)

            // Toast overlay (always visible)
            if let toast = store.toast {
                VStack {
                    HStack(spacing: 8) {
                        Image(systemName: toast.type == .success ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundColor(toast.type == .success ? V2Colors.successGreen : V2Colors.errorRed)
                        Text(toast.message)
                            .font(V2Fonts.bodyMedium(14))
                            .foregroundColor(V2Colors.textPrimary)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(V2Colors.bgCard)
                            .shadow(color: .black.opacity(0.1), radius: 10, y: 4)
                    )
                    .padding(.horizontal, 24)
                    .padding(.top, 60)

                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .animation(.easeInOut(duration: 0.3), value: store.toast)
            }
        }
    }

    private var dashboardContent: some View {
        ZStack {
            VStack(spacing: 0) {
                Group {
                    switch activeTab {
                    case .home:
                        HomeViewV2(activeTab: $activeTab)
                    case .send:
                        SendViewV2()
                    case .swap:
                        SwapViewV2()
                    case .bridge:
                        BridgeViewV2()
                    case .receive:
                        ReceiveViewV2()
                    case .history:
                        HistoryViewV2()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                TabBarV2(activeTab: $activeTab)
            }

            // Progress status bar (bottom, above tab bar)
            if let progress = store.progressMessage {
                VStack {
                    Spacer()
                    HStack(spacing: 8) {
                        ProgressView()
                            .tint(V2Colors.soOrange)
                            .scaleEffect(0.8)
                        Text(progress)
                            .font(V2Fonts.mono(12))
                            .foregroundColor(V2Colors.textSecondary)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
                    .background(
                        V2Colors.bgCanvas
                            .opacity(0.95)
                            .overlay(
                                Rectangle()
                                    .frame(height: 0.5)
                                    .foregroundColor(V2Colors.borderPrimary),
                                alignment: .top
                            )
                    )
                    .padding(.bottom, 95)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.easeInOut(duration: 0.3), value: store.progressMessage)
            }
        }
    }
}
