import LocalAuthentication
import Combine
import SwiftUI

enum AppLockDelay: Int, CaseIterable, Identifiable {
    case immediately = 0
    case oneMinute = 60
    case fiveMinutes = 300

    var id: Int { rawValue }
    var title: String {
        switch self {
        case .immediately: "Immediately"
        case .oneMinute: "After 1 Minute"
        case .fiveMinutes: "After 5 Minutes"
        }
    }
}

@MainActor
final class AppLockManager: ObservableObject {
    static let enabledKey = "folik.appLockEnabled"
    static let delayKey = "folik.appLockDelay"

    @Published private(set) var isEnabled: Bool
    @Published private(set) var isLocked: Bool
    @Published private(set) var obscuresContent: Bool
    @Published private(set) var isAuthenticating = false
    @Published var errorMessage: String?

    private let defaults: UserDefaults
    private let authenticator: () async throws -> Bool
    private let waitsForManualAuthentication: Bool
    private var backgroundedAt: Date?
    private var scenePhases: [UUID: ScenePhase] = [:]

    init(
        defaults: UserDefaults = .standard,
        authenticator: @escaping () async throws -> Bool = AppLockManager.deviceOwnerAuthentication
    ) {
        self.defaults = defaults
        self.authenticator = authenticator
        #if DEBUG
        waitsForManualAuthentication = ProcessInfo.processInfo.arguments.contains("--ui-test-app-lock")
        #else
        waitsForManualAuthentication = false
        #endif
        let enabled = defaults.bool(forKey: Self.enabledKey) || waitsForManualAuthentication
        isEnabled = enabled
        isLocked = enabled
        obscuresContent = enabled
    }

    var delay: AppLockDelay {
        AppLockDelay(rawValue: defaults.integer(forKey: Self.delayKey)) ?? .immediately
    }

    func setEnabled(_ enabled: Bool) {
        errorMessage = nil
        if enabled {
            Task { await enable() }
        } else {
            defaults.set(false, forKey: Self.enabledKey)
            isEnabled = false
            isLocked = false
            obscuresContent = false
            backgroundedAt = nil
        }
    }

    func setDelay(_ delay: AppLockDelay) {
        defaults.set(delay.rawValue, forKey: Self.delayKey)
    }

    func sceneChanged(to phase: ScenePhase, now: Date = Date()) {
        guard isEnabled else { return }
        switch phase {
        case .inactive:
            obscuresContent = true
        case .background:
            obscuresContent = true
            backgroundedAt = now
        case .active:
            if let backgroundedAt,
               now.timeIntervalSince(backgroundedAt) >= TimeInterval(delay.rawValue) {
                isLocked = true
            }
            self.backgroundedAt = nil
            if isLocked {
                obscuresContent = true
                if !waitsForManualAuthentication {
                    Task { await authenticate() }
                }
            } else {
                obscuresContent = false
            }
        @unknown default:
            obscuresContent = true
        }
    }

    func sceneChanged(to phase: ScenePhase, sceneID: UUID, now: Date = Date()) {
        scenePhases[sceneID] = phase
        guard isEnabled else { return }
        switch phase {
        case .inactive:
            break
        case .background:
            if !scenePhases.values.contains(.active) {
                backgroundedAt = backgroundedAt ?? now
            }
        case .active:
            if let backgroundedAt,
               now.timeIntervalSince(backgroundedAt) >= TimeInterval(delay.rawValue) {
                isLocked = true
            }
            self.backgroundedAt = nil
            obscuresContent = isLocked
            if isLocked, !waitsForManualAuthentication {
                Task { await authenticate() }
            }
        @unknown default:
            break
        }
    }

    func sceneDisconnected(_ sceneID: UUID, now: Date = Date()) {
        scenePhases.removeValue(forKey: sceneID)
        guard isEnabled,
              !scenePhases.values.contains(.active),
              scenePhases.values.contains(.background) else { return }
        backgroundedAt = backgroundedAt ?? now
    }

    func authenticate() async {
        guard isEnabled, isLocked, !isAuthenticating else { return }
        isAuthenticating = true
        errorMessage = nil
        defer { isAuthenticating = false }

        do {
            if try await authenticator() {
                isLocked = false
                obscuresContent = false
            }
        } catch let error as LAError where error.code == .userCancel || error.code == .appCancel || error.code == .systemCancel {
            // Staying locked is the expected result when authentication is cancelled.
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func enable() async {
        guard !isEnabled, !isAuthenticating else { return }
        isAuthenticating = true
        errorMessage = nil
        defer { isAuthenticating = false }
        do {
            guard try await authenticator() else { return }
            defaults.set(true, forKey: Self.enabledKey)
            isEnabled = true
            isLocked = false
            obscuresContent = false
        } catch let error as LAError where error.code == .userCancel || error.code == .appCancel || error.code == .systemCancel {
            // A cancelled enrollment leaves App Lock disabled.
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    static func deviceOwnerAuthentication() async throws -> Bool {
        let context = LAContext()
        context.localizedCancelTitle = "Cancel"
        var policyError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &policyError) else {
            throw policyError ?? LAError(.passcodeNotSet)
        }
        return try await context.evaluatePolicy(
            .deviceOwnerAuthentication,
            localizedReason: "Unlock your private Folik library"
        )
    }
}

struct AppLockView: View {
    @EnvironmentObject private var appLock: AppLockManager

    var body: some View {
        ZStack {
            FolikTheme.surface.ignoresSafeArea()
            VStack(spacing: 18) {
                FolikWordmark()
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 46, weight: .medium))
                    .foregroundStyle(FolikTheme.cobalt)
                    .accessibilityHidden(true)
                Text("Folik is locked")
                    .font(.title2.bold())
                    .foregroundStyle(FolikTheme.ink)
                Text("Authenticate to view your documents.")
                    .foregroundStyle(FolikTheme.mutedInk)
                    .multilineTextAlignment(.center)
                if appLock.isLocked {
                    Button {
                        Task { await appLock.authenticate() }
                    } label: {
                        if appLock.isAuthenticating {
                            ProgressView().frame(minWidth: 140, minHeight: 48)
                        } else {
                            Label("Unlock Folik", systemImage: "lock.open")
                                .frame(minWidth: 140, minHeight: 48)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.roundedRectangle(radius: 14))
                    .disabled(appLock.isAuthenticating)
                    .accessibilityIdentifier("appLock.unlock")
                }
                if let error = appLock.errorMessage {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(32)
            .frame(maxWidth: 480)
        }
    }
}
