import XCTest
@testable import CafeineCore

private final class FakeRunner: CommandRunner {
    struct Call: Equatable {
        var executable: String
        var arguments: [String]
    }
    struct Failure: Error {}

    var calls: [Call] = []
    var results: [CommandResult] = []
    var shouldThrow = false

    func run(_ executable: String, _ arguments: [String]) throws -> CommandResult {
        calls.append(Call(executable: executable, arguments: arguments))
        if shouldThrow { throw Failure() }
        return results.isEmpty ? CommandResult(exitCode: 0) : results.removeFirst()
    }
}

final class SleepControllerTests: XCTestCase {
    private var runner: FakeRunner!
    private var controller: SleepController!

    private let rule =
        "bruno ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1"

    override func setUp() {
        super.setUp()
        runner = FakeRunner()
        controller = SleepController(runner: runner, userName: "bruno")
    }

    private func pmsetOutput(_ line: String?) -> CommandResult {
        var lines = ["System-wide power settings:"]
        if let line { lines.append(line) }
        lines += ["Currently in use:", " sleep                1", " displaysleep         10"]
        return CommandResult(exitCode: 0, stdout: lines.joined(separator: "\n") + "\n")
    }

    private func assertThrows(_ expected: SleepError, _ body: () throws -> Void,
                              file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try body(), file: file, line: line) {
            XCTAssertEqual($0 as? SleepError, expected, file: file, line: line)
        }
    }

    // MARK: Règle sudoers

    func testSudoersRuleExactText() throws {
        XCTAssertEqual(try SleepController.sudoersRule(for: "bruno"), rule)
    }

    func testSudoersRuleRejectsInvalidUserNames() {
        for name in ["", "Bruno", "bruno.s", "bruno s", "9bruno", "bruno'x", "a\nb"] {
            XCTAssertThrowsError(try SleepController.sudoersRule(for: name)) {
                XCTAssertEqual($0 as? SleepError, .invalidUserName(name))
            }
        }
    }

    func testSudoersRuleAcceptsValidUserNames() {
        for name in ["bruno", "_www", "jean-luc", "user_2"] {
            XCTAssertNoThrow(try SleepController.sudoersRule(for: name))
        }
    }

    // MARK: Lecture de l'état

    func testIsSleepDisabledTrue() throws {
        runner.results = [pmsetOutput(" SleepDisabled\t\t1")]
        XCTAssertTrue(try controller.isSleepDisabled())
        XCTAssertEqual(runner.calls, [.init(executable: "/usr/bin/pmset", arguments: ["-g"])])
    }

    func testIsSleepDisabledFalse() throws {
        runner.results = [pmsetOutput(" SleepDisabled\t\t0")]
        XCTAssertFalse(try controller.isSleepDisabled())
    }

    func testIsSleepDisabledMissingLine() throws {
        runner.results = [pmsetOutput(nil)]
        XCTAssertFalse(try controller.isSleepDisabled())
    }

    func testIsSleepDisabledIgnoresLookalikes() throws {
        runner.results = [CommandResult(exitCode: 0, stdout: " sleep 1\n displaysleep 10\n")]
        XCTAssertFalse(try controller.isSleepDisabled())
    }

    func testIsSleepDisabledFailure() {
        runner.results = [CommandResult(exitCode: 1, stderr: "boom")]
        assertThrows(.commandFailed("boom")) { _ = try controller.isSleepDisabled() }
    }

    // MARK: Écriture de l'état

    func testSetSleepDisabledOn() throws {
        runner.results = [CommandResult(exitCode: 0), pmsetOutput(" SleepDisabled\t\t1")]
        try controller.setSleepDisabled(true)
        XCTAssertEqual(runner.calls.first, .init(
            executable: "/usr/bin/sudo",
            arguments: ["-n", "/usr/bin/pmset", "-a", "disablesleep", "1"]))
        XCTAssertEqual(runner.calls.count, 2)
    }

    func testSetSleepDisabledOff() throws {
        runner.results = [CommandResult(exitCode: 0), pmsetOutput(" SleepDisabled\t\t0")]
        try controller.setSleepDisabled(false)
        XCTAssertEqual(runner.calls.first, .init(
            executable: "/usr/bin/sudo",
            arguments: ["-n", "/usr/bin/pmset", "-a", "disablesleep", "0"]))
    }

    func testSetSleepDisabledUnauthorized() {
        runner.results = [CommandResult(exitCode: 1, stderr: "sudo: a password is required\n")]
        assertThrows(.unauthorized) { try controller.setSleepDisabled(true) }
    }

    func testSetSleepDisabledOtherFailure() {
        runner.results = [CommandResult(exitCode: 1, stderr: "boom")]
        assertThrows(.commandFailed("boom")) { try controller.setSleepDisabled(true) }
    }

    func testSetSleepDisabledMismatch() {
        runner.results = [CommandResult(exitCode: 0), pmsetOutput(" SleepDisabled\t\t0")]
        assertThrows(.stateMismatch) { try controller.setSleepDisabled(true) }
    }

    // MARK: Autorisation

    func testIsAuthorized() {
        runner.results = [CommandResult(exitCode: 0), CommandResult(exitCode: 1)]
        XCTAssertTrue(controller.isAuthorized())
        XCTAssertFalse(controller.isAuthorized())
        XCTAssertEqual(runner.calls.first, .init(
            executable: "/usr/bin/sudo",
            arguments: ["-n", "-l", "/usr/bin/pmset", "-a", "disablesleep", "1"]))
    }

    func testIsAuthorizedWhenRunnerThrows() {
        runner.shouldThrow = true
        XCTAssertFalse(controller.isAuthorized())
    }

    func testInstallAuthorizationScript() throws {
        try controller.installAuthorization()
        XCTAssertEqual(runner.calls.count, 1)
        let call = try XCTUnwrap(runner.calls.first)
        XCTAssertEqual(call.executable, "/usr/bin/osascript")
        XCTAssertEqual(call.arguments.count, 2)
        XCTAssertEqual(call.arguments[0], "-e")
        let script = call.arguments[1]
        XCTAssertTrue(script.hasPrefix("do shell script \""))
        XCTAssertTrue(script.hasSuffix("\" with administrator privileges"))
        XCTAssertTrue(script.contains("'\(rule)'"))
        XCTAssertTrue(script.contains("/usr/sbin/visudo -cf"))
        XCTAssertTrue(script.contains("-m 0440 -o root -g wheel"))
        XCTAssertTrue(script.contains("/private/etc/sudoers.d/cafeine"))
        // Les guillemets du script shell sont échappés pour AppleScript.
        XCTAssertTrue(script.contains("\\\"$T\\\""))
        XCTAssertFalse(script.contains(" \"$T\""))
    }

    func testInstallAuthorizationCancelled() {
        runner.results = [CommandResult(exitCode: 1, stderr: "execution error: User canceled. (-128)")]
        assertThrows(.authorizationCancelled) { try controller.installAuthorization() }
    }

    func testInstallAuthorizationFailure() {
        runner.results = [CommandResult(exitCode: 1, stderr: "visudo: syntax error")]
        assertThrows(.commandFailed("visudo: syntax error")) { try controller.installAuthorization() }
    }

    func testInstallAuthorizationInvalidUserRunsNothing() {
        controller = SleepController(runner: runner, userName: "Bruno")
        assertThrows(.invalidUserName("Bruno")) { try controller.installAuthorization() }
        XCTAssertTrue(runner.calls.isEmpty)
    }

    // MARK: Capot et mise en veille

    func testIsLidClosedTrue() {
        runner.results = [CommandResult(exitCode: 0, stdout: """
            +-o IOPMrootDomain  <class IOPMrootDomain>
                {
                  "AppleClamshellState" = Yes
                  "AppleClamshellCausesSleep" = Yes
                }
            """)]
        XCTAssertTrue(controller.isLidClosed())
        XCTAssertEqual(runner.calls, [.init(
            executable: "/usr/sbin/ioreg",
            arguments: ["-r", "-k", "AppleClamshellState", "-d", "1"])])
    }

    func testIsLidClosedFalse() {
        runner.results = [CommandResult(exitCode: 0, stdout: """
                  "AppleClamshellState" = No
                  "AppleClamshellCausesSleep" = Yes
            """)]
        XCTAssertFalse(controller.isLidClosed())
    }

    func testIsLidClosedWithoutLid() {
        runner.results = [CommandResult(exitCode: 0, stdout: "")]
        XCTAssertFalse(controller.isLidClosed())
    }

    func testIsLidClosedWhenCommandFails() {
        runner.results = [CommandResult(exitCode: 1, stdout: "\"AppleClamshellState\" = Yes")]
        XCTAssertFalse(controller.isLidClosed())
        runner.shouldThrow = true
        XCTAssertFalse(controller.isLidClosed())
    }

    func testSleepNow() {
        controller.sleepNow()
        XCTAssertEqual(runner.calls, [.init(executable: "/usr/bin/pmset", arguments: ["sleepnow"])])
    }

    func testSleepNowIgnoresFailure() {
        runner.shouldThrow = true
        controller.sleepNow()
        XCTAssertEqual(runner.calls.count, 1)
    }
}
