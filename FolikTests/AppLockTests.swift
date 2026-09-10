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

    func testOneBackgroundWindowDoesNotRelockWhileAnotherSceneRemainsActive() async {
        defaults.set(true, forKey: AppLockManager.enabledKey)
        defaults.set(AppLockDelay.oneMinute.rawValue, forKey: AppLockManager.delayKey)
        var authenticationCount = 0
        let lock = AppLockManager(defaults: defaults, authenticator: {
            authenticationCount += 1
            return true
        })
        await lock.authenticate()
        let first = UUID()
        let second = UUID()
        let start = Date(timeIntervalSinceReferenceDate: 200)
        lock.sceneChanged(to: .active, sceneID: first, now: start)
        lock.sceneChanged(to: .active, sceneID: second, now: start)

        lock.sceneChanged(to: .background, sceneID: first, now: start)
        lock.sceneChanged(to: .active, sceneID: second, now: start.addingTimeInterval(120))
        await Task.yield()

        XCTAssertFalse(lock.isLocked)
        XCTAssertEqual(authenticationCount, 1)
    }

    func testRelockDelayStartsWhenLastSceneBackgrounds() async {
        defaults.set(true, forKey: AppLockManager.enabledKey)
        defaults.set(AppLockDelay.oneMinute.rawValue, forKey: AppLockManager.delayKey)
        var authenticationCount = 0
        let lock = AppLockManager(defaults: defaults, authenticator: {
            authenticationCount += 1
            return true
        })
        await lock.authenticate()
        let first = UUID()
        let second = UUID()
        let start = Date(timeIntervalSinceReferenceDate: 300)
        lock.sceneChanged(to: .active, sceneID: first, now: start)
        lock.sceneChanged(to: .active, sceneID: second, now: start)
        lock.sceneChanged(to: .background, sceneID: first, now: start)
        lock.sceneChanged(to: .background, sceneID: second, now: start.addingTimeInterval(10))

        lock.sceneChanged(to: .active, sceneID: first, now: start.addingTimeInterval(71))
        for _ in 0..<10 where lock.isLocked { await Task.yield() }

        XCTAssertEqual(authenticationCount, 2)
        XCTAssertFalse(lock.isLocked)
    }

    func testRelockDelayStartsWhenLastActiveSceneDisconnects() async {
        defaults.set(true, forKey: AppLockManager.enabledKey)
        defaults.set(AppLockDelay.oneMinute.rawValue, forKey: AppLockManager.delayKey)
        var authenticationCount = 0
        let lock = AppLockManager(defaults: defaults, authenticator: {
            authenticationCount += 1
            return true
        })
        await lock.authenticate()
        let active = UUID()
        let background = UUID()
        let start = Date(timeIntervalSinceReferenceDate: 400)
        lock.sceneChanged(to: .active, sceneID: active, now: start)
        lock.sceneChanged(to: .background, sceneID: background, now: start)

        lock.sceneDisconnected(active, now: start.addingTimeInterval(10))
        lock.sceneChanged(to: .active, sceneID: background, now: start.addingTimeInterval(71))
        for _ in 0..<10 where lock.isLocked { await Task.yield() }

        XCTAssertEqual(authenticationCount, 2)
        XCTAssertFalse(lock.isLocked)
    }
}
