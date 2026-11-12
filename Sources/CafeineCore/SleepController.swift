import Foundation

public struct CommandResult: Equatable {
    public var exitCode: Int32
    public var stdout: String
    public var stderr: String

    public init(exitCode: Int32, stdout: String = "", stderr: String = "") {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
    }
}

/// Exécute une commande système et attend sa fin.
public protocol CommandRunner {
    func run(_ executable: String, _ arguments: [String]) throws -> CommandResult
}

public enum SleepError: Error, Equatable {
    case invalidUserName(String)
    case authorizationCancelled
    /// `sudo -n` a refusé : la règle sudoers est absente ou ne correspond plus.
    case unauthorized
    case commandFailed(String)
    /// La commande a réussi mais l'état relu n'est pas celui demandé.
    case stateMismatch
}

/// Lit et modifie le réglage `disablesleep` de `pmset`, et installe la règle
/// sudoers qui permet de le modifier sans mot de passe.
public struct SleepController {
    static let pmset = "/usr/bin/pmset"
    static let sudo = "/usr/bin/sudo"
    static let osascript = "/usr/bin/osascript"
    static let sudoersPath = "/private/etc/sudoers.d/cafeine"

    private let runner: CommandRunner
    private let userName: String

    public init(runner: CommandRunner, userName: String) {
        self.runner = runner
        self.userName = userName
    }

    /// Règle autorisant `userName` à exécuter les deux commandes `pmset`
    /// exactes, et rien d'autre. Le nom est validé strictement parce qu'il
    /// est inséré tel quel dans un fichier sudoers et dans un script root.
    public static func sudoersRule(for userName: String) throws -> String {
        guard isValidUserName(userName) else {
            throw SleepError.invalidUserName(userName)
        }
        return "\(userName) ALL=(root) NOPASSWD: "
            + "\(pmset) -a disablesleep 0, \(pmset) -a disablesleep 1"
    }

    /// Équivalent de `^[a-z_][a-z0-9_-]*$` sur la chaîne entière.
    static func isValidUserName(_ name: String) -> Bool {
        let scalars = Array(name.unicodeScalars)
        guard let first = scalars.first else { return false }
        func isLower(_ s: Unicode.Scalar) -> Bool { s >= "a" && s <= "z" }
        func isDigit(_ s: Unicode.Scalar) -> Bool { s >= "0" && s <= "9" }
        guard isLower(first) || first == "_" else { return false }
        return scalars.dropFirst().allSatisfy { isLower($0) || isDigit($0) || $0 == "_" || $0 == "-" }
    }

    public func isSleepDisabled() throws -> Bool {
        let result = try runner.run(Self.pmset, ["-g"])
        guard result.exitCode == 0 else {
            throw SleepError.commandFailed(Self.message(result))
        }
        // Certains Mac n'affichent pas la ligne : la veille est alors normale.
        return result.stdout.split(whereSeparator: \.isNewline).contains { line in
            line.split(whereSeparator: \.isWhitespace).map(String.init) == ["SleepDisabled", "1"]
        }
    }

    public func setSleepDisabled(_ disabled: Bool) throws {
        let result = try runner.run(
            Self.sudo, ["-n", Self.pmset, "-a", "disablesleep", disabled ? "1" : "0"])
        guard result.exitCode == 0 else {
            if result.stderr.contains("password") {
                throw SleepError.unauthorized
            }
            throw SleepError.commandFailed(Self.message(result))
        }
        guard try isSleepDisabled() == disabled else {
            throw SleepError.stateMismatch
        }
    }

    public func isAuthorized() -> Bool {
        let result = try? runner.run(
            Self.sudo, ["-n", "-l", Self.pmset, "-a", "disablesleep", "1"])
        return result?.exitCode == 0
    }

    /// Installe la règle sudoers via la boîte de dialogue d'authentification
    /// de macOS. La règle est écrite par le script root dans un fichier que
    /// lui seul peut modifier, validée par `visudo`, puis copiée.
    public func installAuthorization() throws {
        let rule = try Self.sudoersRule(for: userName)
        let shell = "umask 077; /bin/mkdir -p /private/etc/sudoers.d; "
            + "T=$(/usr/bin/mktemp /private/etc/cafeine.XXXXXX) || exit 1; "
            + "/usr/bin/printf '%s\\n' '\(rule)' > \"$T\" "
            + "&& /usr/sbin/visudo -cf \"$T\" "
            + "&& /usr/bin/install -m 0440 -o root -g wheel \"$T\" \(Self.sudoersPath); "
            + "S=$?; /bin/rm -f \"$T\"; exit $S"
        let escaped = shell
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let script = "do shell script \"\(escaped)\" with administrator privileges"

        let result = try runner.run(Self.osascript, ["-e", script])
        guard result.exitCode == 0 else {
            // -128 : l'utilisateur a annulé la boîte de dialogue.
            if result.stderr.contains("-128") {
                throw SleepError.authorizationCancelled
            }
            throw SleepError.commandFailed(Self.message(result))
        }
    }

    private static func message(_ result: CommandResult) -> String {
        result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
