import SwiftUI
import XCTest
@testable import Folik

@MainActor
final class AppLockTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        suiteName = "AppLockTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
    }

    func testEnabledLockStartsCoveredAndCanBeDisabled() {
        defaults.set(true, forKey: AppLockManager.enabledKey)
        let lock = AppLockManager(defaults: defaults, authenticator: { true })

        XCTAssertTrue(lock.isEnabled)
        XCTAssertTrue(lock.isLocked)
        XCTAssertTrue(lock.obscuresContent)

        lock.setEnabled(false)
        XCTAssertFalse(lock.isEnabled)
        XCTAssertFalse(lock.isLocked)
        XCTAssertFalse(lock.obscuresContent)
    }

    func testGracePeriodDefersAuthenticationUntilDelayExpires() async {
        defaults.set(true, forKey: AppLockManager.enabledKey)
        defaults.set(AppLockDelay.oneMinute.rawValue, forKey: AppLockManager.delayKey)
        var authenticationCount = 0
        let lock = AppLockManager(defaults: defaults, authenticator: {
            authenticationCount += 1
            return true
        })
        let start = Date(timeIntervalSinceReferenceDate: 100)

        await lock.authenticate()
        XCTAssertFalse(lock.isLocked)
        lock.sceneChanged(to: .background, now: start)
        lock.sceneChanged(to: .active, now: start.addingTimeInterval(30))
        await Task.yield()
        XCTAssertFalse(lock.isLocked)
        XCTAssertEqual(authenticationCount, 1)

        lock.sceneChanged(to: .background, now: start)
        lock.sceneChanged(to: .active, now: start.addingTimeInterval(61))
        await Task.yield()
        XCTAssertEqual(authenticationCount, 2)
        XCTAssertFalse(lock.isLocked)
        XCTAssertFalse(lock.obscuresContent)
    }

    func testEnablingPersistsOnlyAfterSuccessfulAuthentication() async {
        let rejected = AppLockManager(defaults: defaults, authenticator: { false })
        rejected.setEnabled(true)
        for _ in 0..<10 { await Task.yield() }
        XCTAssertFalse(rejected.isEnabled)
        XCTAssertFalse(defaults.bool(forKey: AppLockManager.enabledKey))

        let accepted = AppLockManager(defaults: defaults, authenticator: { true })
        accepted.setEnabled(true)
        for _ in 0..<10 where !accepted.isEnabled { await Task.yield() }
        XCTAssertTrue(accepted.isEnabled)
        XCTAssertTrue(defaults.bool(forKey: AppLockManager.enabledKey))
        XCTAssertFalse(accepted.isLocked)
    }
}
