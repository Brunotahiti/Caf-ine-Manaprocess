import XCTest
@testable import CafeineCore

final class PreferencesTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var prefs: Preferences!

    override func setUp() {
        super.setUp()
        suiteName = "cafeine-tests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        prefs = Preferences(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testDefaults() {
        XCTAssertFalse(prefs.acOnly)
        XCTAssertEqual(prefs.batteryThreshold, 20)
        XCTAssertEqual(prefs.duration, .indefinite)
    }

    func testRoundTrip() {
        prefs.acOnly = true
        prefs.batteryThreshold = 30
        prefs.duration = .twoHours
        let reread = Preferences(defaults: defaults)
        XCTAssertTrue(reread.acOnly)
        XCTAssertEqual(reread.batteryThreshold, 30)
        XCTAssertEqual(reread.duration, .twoHours)
    }

    func testCorruptedValuesFallBackToDefaults() {
        defaults.set(55, forKey: "batteryThreshold")
        defaults.set(42, forKey: "duration")
        XCTAssertEqual(prefs.batteryThreshold, 20)
        XCTAssertEqual(prefs.duration, .indefinite)
    }

    func testEndDate() {
        let now = Date(timeIntervalSince1970: 1_000)
        XCTAssertNil(AwakeDuration.indefinite.endDate(from: now))
        XCTAssertEqual(AwakeDuration.oneHour.endDate(from: now), Date(timeIntervalSince1970: 4_600))
    }

    func testLabels() {
        XCTAssertEqual(AwakeDuration.allCases.map(\.label), ["Indéfiniment", "1 h", "2 h", "4 h"])
    }
}
