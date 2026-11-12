import XCTest
@testable import CafeineCore

final class PolicyTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000)

    private func decide(
        enabled: Bool = true,
        acOnly: Bool = false,
        batteryThreshold: Int = 20,
        power: PowerState = PowerState(onAC: true, batteryPercent: 80),
        thermal: ThermalLevel = .nominal,
        endDate: Date? = nil
    ) -> Decision {
        Policy.decide(enabled: enabled, acOnly: acOnly, batteryThreshold: batteryThreshold,
                      power: power, thermal: thermal, endDate: endDate, now: now)
    }

    private func battery(_ percent: Int) -> PowerState {
        PowerState(onAC: false, batteryPercent: percent)
    }

    func testDisabledIsInactive() {
        XCTAssertEqual(decide(enabled: false, thermal: .critical), .inactive)
    }

    func testNominalStaysAwake() {
        XCTAssertEqual(decide(), .stayAwake)
    }

    func testFairThermalStaysAwake() {
        XCTAssertEqual(decide(thermal: .fair), .stayAwake)
    }

    func testSeriousThermalStops() {
        XCTAssertEqual(decide(thermal: .serious), .stop(.thermal))
    }

    func testCriticalThermalStops() {
        XCTAssertEqual(decide(thermal: .critical), .stop(.thermal))
    }

    func testTimerElapsedStops() {
        XCTAssertEqual(decide(endDate: now), .stop(.timerElapsed))
    }

    func testTimerNotElapsedStaysAwake() {
        XCTAssertEqual(decide(endDate: now.addingTimeInterval(1)), .stayAwake)
    }

    func testBatteryBelowThresholdStops() {
        XCTAssertEqual(decide(power: battery(19)), .stop(.batteryLow(percent: 19)))
    }

    func testBatteryAtThresholdStops() {
        XCTAssertEqual(decide(power: battery(20)), .stop(.batteryLow(percent: 20)))
    }

    func testBatteryAboveThresholdStaysAwake() {
        XCTAssertEqual(decide(power: battery(21)), .stayAwake)
    }

    func testLowBatteryOnACStaysAwake() {
        XCTAssertEqual(decide(power: PowerState(onAC: true, batteryPercent: 5)), .stayAwake)
    }

    func testACOnlyOnBatteryPauses() {
        XCTAssertEqual(decide(acOnly: true, power: battery(80)), .pause(.onBattery))
    }

    func testACOnlyOnACStaysAwake() {
        XCTAssertEqual(decide(acOnly: true), .stayAwake)
    }

    func testNoBatteryIgnoresThreshold() {
        XCTAssertEqual(decide(power: PowerState(onAC: false, batteryPercent: nil)), .stayAwake)
    }

    func testThermalBeatsTimerAndBattery() {
        XCTAssertEqual(decide(power: battery(5), thermal: .serious, endDate: now), .stop(.thermal))
    }

    func testTimerBeatsBattery() {
        XCTAssertEqual(decide(power: battery(5), endDate: now), .stop(.timerElapsed))
    }

    func testLowBatteryBeatsACOnly() {
        XCTAssertEqual(decide(acOnly: true, power: battery(5)), .stop(.batteryLow(percent: 5)))
    }

    func testACOnlyOnBatteryWithUnreadableLevelPauses() {
        XCTAssertEqual(decide(acOnly: true, power: PowerState(onAC: false, batteryPercent: nil)),
                       .pause(.onBattery))
    }
}
