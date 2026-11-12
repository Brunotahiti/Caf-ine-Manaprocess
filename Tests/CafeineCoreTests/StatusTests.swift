import XCTest
@testable import CafeineCore

final class StatusTests: XCTestCase {
    private let utc = TimeZone(identifier: "UTC")!
    // 2026-11-12T15:30:00Z
    private let date = Date(timeIntervalSince1970: 1_794_497_400)

    private func text(_ status: Status) -> String {
        StatusText.text(for: status, timeZone: utc)
    }

    func testInactive() { XCTAssertEqual(text(.inactive), "Inactif") }
    func testActive() { XCTAssertEqual(text(.active(until: nil)), "Actif") }
    func testActiveUntil() { XCTAssertEqual(text(.active(until: date)), "Actif jusqu'à 15:30") }
    func testPaused() { XCTAssertEqual(text(.paused(.onBattery)), "En pause : sur batterie") }
    func testStoppedBattery() {
        XCTAssertEqual(text(.stopped(.batteryLow(percent: 19))), "Arrêté : batterie à 19 %")
    }
    func testStoppedThermal() { XCTAssertEqual(text(.stopped(.thermal)), "Arrêté : surchauffe") }
    func testStoppedTimer() { XCTAssertEqual(text(.stopped(.timerElapsed)), "Arrêté : minuteur écoulé") }
    func testError() { XCTAssertEqual(text(.error("Autorisation manquante")), "Autorisation manquante") }

    func testIsAwake() {
        XCTAssertTrue(Status.active(until: nil).isAwake)
        XCTAssertFalse(Status.inactive.isAwake)
        XCTAssertFalse(Status.paused(.onBattery).isAwake)
        XCTAssertFalse(Status.stopped(.thermal).isAwake)
        XCTAssertFalse(Status.error("x").isAwake)
    }
}
