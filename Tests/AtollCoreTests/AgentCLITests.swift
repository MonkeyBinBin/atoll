import Foundation
import Testing
@testable import AtollCore

@Suite("Agent CLI detection")
struct AgentCLITests {
    let clis = [AgentCLI(command: "droid", title: "Factory Droid", taskPassing: .lastArgument),
                AgentCLI(command: "opencode", title: "OpenCode", taskPassing: .flag("--prompt"))]

    @Test func keepsCatalogOrderAndIgnoresShellChatter() {
        let output = "Welcome to zsh\nATOLL_FOUND:opencode\nopencode\nATOLL_FOUND:droid\n"
        #expect(AgentCLI.parseDetected(output, from: clis).map(\.command) == ["droid", "opencode"])
    }

    @Test func unknownOrMissingCommandsAreDropped() {
        #expect(AgentCLI.parseDetected("ATOLL_FOUND:aider\n", from: clis).isEmpty)
        #expect(AgentCLI.parseDetected("", from: clis).isEmpty)
    }

    @Test func catalogDoesntRepeatTheAlwaysOfferedTools() {
        let commands = AgentCLI.catalog.map(\.command)
        #expect(!commands.contains("claude") && !commands.contains("codex"))
        #expect(Set(commands).count == commands.count)
    }

    @Test func appWordsBelongToOneCatalogEntry() {
        let entries = AgentCLI.catalog.map { [$0.command] + $0.appWords }
        for (i, words) in entries.enumerated() {
            for (j, others) in entries.enumerated() where i != j {
                for word in words {
                    #expect(!others.contains { word == $0 || word.hasPrefix($0 + "-") },
                            "\(word) also matches \(others)")
                }
            }
        }
    }

    @Test func parsesWhereEachCommandResolvesAndTheShellPath() {
        // Init chatter without a newline glues onto the first marker.
        let output = "WelcomeATOLL_FOUND:droid\t/opt/bin/droid\nATOLL_FOUND:opencode\talias opencode=oc\nATOLL_PATH:/opt/bin:/usr/bin\n"
        let found = AgentCLI.parseFound(output, from: clis)
        #expect(found.clis.map(\.command) == ["droid", "opencode"])
        #expect(found.locations == ["droid": "/opt/bin/droid", "opencode": "alias opencode=oc"])
        #expect(found.searchPath == "/opt/bin:/usr/bin")
    }

    @Test func helpSignatureIgnoresCaseStylingAndWrapping() {
        #expect(AgentCLI.helpMatches("kilo [project]  Start Kilo TUI  [default]", signature: "kilo tui"))
        #expect(AgentCLI.helpMatches("Run the Mistral\n    Vibe interactive CLI", signature: "Mistral Vibe"))
        #expect(AgentCLI.helpMatches("Run the \u{1B}[1mMistral\u{1B}[0m Vibe", signature: "Mistral Vibe"))
        #expect(!AgentCLI.helpMatches("pi - prints digits of pi", signature: "AI coding assistant"))
    }

    @Test func onlyPathsAreRunAndRelativeOnesResolve() {
        let cwd = FileManager.default.currentDirectoryPath
        #expect(AgentCLI.executable("/opt/bin/pi") == "/opt/bin/pi")
        #expect(AgentCLI.executable("alias pi='npx some/pkg'") == nil)
        #expect(AgentCLI.executable("pi") == nil)
        #expect(AgentCLI.executable("~/bin/pi") == NSHomeDirectory() + "/bin/pi")
        #expect(AgentCLI.executable("./bin/pi") == URL(fileURLWithPath: cwd).appendingPathComponent("bin/pi").standardizedFileURL.path)
    }

    /// Volta/mise shims link many commands to one binary; each command keeps its own outcome.
    @Test func helpChecksAreKeptPerCommandPathNotPerBinary() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("atoll-shim-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let shim = dir.appendingPathComponent("shim")
        try Data().write(to: shim)
        for name in ["pi", "kilo"] {
            try FileManager.default.createSymbolicLink(at: dir.appendingPathComponent(name), withDestinationURL: shim)
        }
        let cache = HelpCheckCache()
        #expect(await cache.check(dir.appendingPathComponent("pi").path, signature: "AI coding assistant") { .matched } == .matched)
        #expect(await cache.check(dir.appendingPathComponent("kilo").path, signature: "kilo tui") { .mismatched } == .mismatched)
        #expect(await cache.check(dir.appendingPathComponent("pi").path, signature: "AI coding assistant") { .mismatched } == .matched)
    }

    @Test func anUnknownHelpCheckIsRetriedAfterAWhile() async {
        final class Clock: @unchecked Sendable { var now = Date(timeIntervalSince1970: 0) }
        let clock = Clock()
        let cache = HelpCheckCache(unknownLifetime: 300, now: { clock.now })
        #expect(await cache.check("/nonexistent/pi", signature: "s") { .unknown } == .unknown)
        clock.now += 299
        #expect(await cache.check("/nonexistent/pi", signature: "s") { .matched } == .unknown)
        clock.now += 2
        #expect(await cache.check("/nonexistent/pi", signature: "s") { .matched } == .matched)
        clock.now += 10_000
        #expect(await cache.check("/nonexistent/pi", signature: "s") { .mismatched } == .matched)
    }

    @Test func matchesAnAgentsAppWord() {
        #expect(AgentCLI.matching(app: "OpenCode")?.command == "opencode")
        #expect(AgentCLI.matching(app: "cursor-agent")?.command == "cursor-agent")
        #expect(AgentCLI.matching(app: "antigravity")?.command == "agy")
        #expect(AgentCLI.matching(app: "agy")?.command == "agy")
        #expect(AgentCLI.matching(app: "cursor")?.command == "cursor-agent")
        #expect(AgentCLI.matching(app: "qoder")?.command == "qodercli")
        #expect(AgentCLI.matching(app: "pi")?.command == "pi")
        #expect(AgentCLI.matching(app: "pilot") == nil)
        #expect(AgentCLI.matching(app: "droidx") == nil)
        #expect(AgentCLI.matching(app: "claude") == nil)
    }

    @Test func startsFromTheSavedDetection() async {
        let detector = AgentCLIDetector(clis: clis, saved: ["opencode"], detect: { _ in nil })
        #expect(await detector.lastKnown?.map(\.command) == ["opencode"])
    }

    @Test func aSuccessfulDetectionIsSaved() async {
        let saved = SavedDetections()
        let detector = AgentCLIDetector(clis: clis, onDetected: saved.record, detect: { clis in [clis[1]] })
        _ = await detector.refresh()
        #expect(saved.all == [["opencode"]])
    }

    @Test func anUnchangedDetectionIsntSavedAgain() async {
        let saved = SavedDetections()
        let detector = AgentCLIDetector(clis: clis, saved: ["opencode"], onDetected: saved.record,
                                        detect: { clis in [clis[1]] })
        _ = await detector.refresh()
        _ = await detector.refresh()
        #expect(saved.all.isEmpty)
    }

    @Test func aFailedDetectionKeepsTheSavedOneAndSavesNothing() async {
        let saved = SavedDetections()
        let detector = AgentCLIDetector(clis: clis, saved: ["droid"], onDetected: saved.record, detect: { _ in nil })
        #expect(await detector.refresh() == nil)
        #expect(await detector.lastKnown?.map(\.command) == ["droid"])
        #expect(saved.all.isEmpty)
    }

    @Test func savedCommandsNoLongerInTheCatalogAreIgnored() async {
        let detector = AgentCLIDetector(clis: clis, saved: ["opencode", "aider", "droid"], detect: { _ in nil })
        #expect(await detector.lastKnown?.map(\.command) == ["droid", "opencode"])
    }

    @Test func taskPassing() {
        #expect(TaskPassing.lastArgument.apply(argv: ["droid"], task: "fix it") == (["droid"], "fix it"))
        #expect(TaskPassing.flag("--prompt").apply(argv: ["opencode"], task: "fix it") == (["opencode", "--prompt"], "fix it"))
        #expect(TaskPassing.flag("--prompt").apply(argv: ["opencode"], task: "") == (["opencode"], ""))
        #expect(TaskPassing.unsupported.apply(argv: ["kimi"], task: "fix it") == (["kimi"], ""))
    }
}

/// Spawns real processes, so it's opt-in like the contract tests:
///   ATOLL_PROCESS_TESTS=1 swift test --filter AgentCLIProcess
@Suite("Agent CLI detection (real processes)",
       .enabled(if: ProcessInfo.processInfo.environment["ATOLL_PROCESS_TESTS"] == "1"))
struct AgentCLIProcessTests {
    let clis = [AgentCLI(command: "droid", title: "Factory Droid", taskPassing: .lastArgument),
                AgentCLI(command: "opencode", title: "OpenCode", taskPassing: .flag("--prompt"))]

    @Test func detectsWithAPlainShell() async {
        let found = await AgentCLI.detect([AgentCLI(command: "ls", title: "ls", taskPassing: .lastArgument),
                                           AgentCLI(command: "atoll-no-such-cmd", title: "none", taskPassing: .lastArgument)],
                                          shell: "/bin/sh", timeout: 5)
        #expect(found?.map(\.command) == ["ls"])
    }

    /// A directory of fake commands, removed when the test ends.
    final class FakeBin {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("atoll-cli-\(UUID().uuidString)")
        init() throws { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) }
        deinit { try? FileManager.default.removeItem(at: url) }

        @discardableResult
        func install(_ name: String, _ body: String) throws -> String {
            let file = url.appendingPathComponent(name)
            try "#!/bin/sh\n\(body)\n".write(to: file, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
            return file.path
        }

        /// Stands in for the login shell: puts the fake commands on PATH, then runs the script with `shell`.
        func loginShell(_ shell: String = "/bin/sh") throws -> String {
            try install("login-shell", "PATH='\(url.path)':/usr/bin:/bin; export PATH; shift; exec \(shell) -c \"$1\"")
        }
    }

    let signed = [AgentCLI(command: "pi", title: "Pi", taskPassing: .lastArgument, helpSignature: "AI coding assistant"),
                  AgentCLI(command: "vibe", title: "Mistral Vibe", taskPassing: .lastArgument, helpSignature: "Mistral Vibe"),
                  AgentCLI(command: "kilo", title: "Kilo Code", taskPassing: .lastArgument, helpSignature: "kilo tui"),
                  AgentCLI(command: "droid", title: "Factory Droid", taskPassing: .lastArgument)]

    /// Help without the signature drops a CLI; a hang keeps it (no evidence) and holds up nothing else.
    @Test func onlyAMismatchedHelpDropsACLI() async throws {
        let bin = try FakeBin()
        try bin.install("pi", "echo 'pi - prints digits of pi'")
        try bin.install("vibe", "echo 'Run the MISTRAL VIBE interactive CLI'")
        try bin.install("kilo", "exec sleep 30")
        try bin.install("droid", "exit 1")
        let found = await AgentCLI.detect(signed, shell: try bin.loginShell(), timeout: 5, helpTimeout: 2)
        #expect(found?.map(\.command) == ["vibe", "kilo", "droid"])
    }

    /// Help checks share the detection's `timeout` with the shell, so a slow shell can't stretch the wait.
    @Test func helpChecksFitInWhatIsLeftOfTheTimeout() async throws {
        let bin = try FakeBin()
        try bin.install("kilo", "exec sleep 30")
        let shell = try bin.install("slow-shell", "sleep 1; PATH='\(bin.url.path)':/usr/bin:/bin; export PATH; shift; exec /bin/sh -c \"$1\"")
        let start = Date()
        let found = await AgentCLI.detect(signed, shell: shell, timeout: 1.5, helpTimeout: 3)
        #expect(found?.map(\.command) == ["kilo"])
        #expect(Date().timeIntervalSince(start) < 1.5 + ProcessRunner.terminationGrace + 0.5)
    }

    @Test func helpRunsOncePerExecutable() async throws {
        let bin = try FakeBin()
        let log = bin.url.appendingPathComponent("runs").path
        try bin.install("vibe", "echo run >> '\(log)'; echo 'Mistral Vibe'")
        let shell = try bin.loginShell()
        let cache = HelpCheckCache()
        for _ in 0..<2 {
            let found = await AgentCLI.detect(signed, shell: shell, timeout: 5, helpChecks: cache)
            #expect(found?.map(\.command) == ["vibe"])
        }
        #expect(try String(contentsOfFile: log, encoding: .utf8) == "run\n")
    }

    @Test func anAliasIsTrustedAndACutShortScriptFails() async throws {
        let bin = try FakeBin()
        let alias = try bin.install("alias-shell", "printf 'ATOLL_FOUND:pi\\talias pi=npx-pi\\nATOLL_PATH:/usr/bin\\n'")
        #expect(await AgentCLI.detect(signed, shell: alias, timeout: 5)?.map(\.command) == ["pi"])
        let cut = try bin.install("cut-shell", "printf 'ATOLL_FOUND:droid\\t/usr/bin/droid\\n'; exit 1")
        #expect(await AgentCLI.detect(signed, shell: cut, timeout: 5) == nil)
    }

    @Test(arguments: ["/bin/sh", "/bin/bash", "/bin/zsh"])
    func theScriptRunsInEachShell(_ shell: String) async throws {
        let bin = try FakeBin()
        let droid = try bin.install("droid", "exit 0")
        let output = try await ProcessRunner.run(shell, ["-c", AgentCLI.detectionScript(signed)],
                                                 environment: ["PATH": bin.url.path + ":/usr/bin:/bin"], timeout: 5)
        let found = AgentCLI.parseFound(output.stdoutText, from: signed)
        #expect(found.clis.map(\.command) == ["droid"])
        #expect(found.locations["droid"] == droid)
        // zsh reads ~/.zshenv even with -c, which may prepend to PATH.
        #expect(found.searchPath?.hasSuffix(bin.url.path + ":/usr/bin:/bin") == true)
    }

    @Test func detectorRemembersOnlySuccessfulDetections() async {
        let detector = AgentCLIDetector(clis: clis, shell: "/bin/sh")
        #expect(await detector.lastKnown == nil)
        #expect(await detector.refresh() != nil)
        #expect(await detector.lastKnown != nil)
        let broken = AgentCLIDetector(clis: clis, shell: "/nonexistent/shell")
        #expect(await broken.refresh() == nil)
        #expect(await broken.lastKnown == nil)
    }
}

/// What a detector handed to `onDetected`, in order.
final class SavedDetections: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [[String]] = []

    var all: [[String]] { lock.withLock { values } }

    @Sendable func record(_ commands: [String]) {
        lock.withLock { values.append(commands) }
    }
}
