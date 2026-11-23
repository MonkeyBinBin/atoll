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
        // Chatter merely ending in the start marker doesn't start the environment.
        let output = "WelcomeATOLL_FOUND:droid\t/opt/bin/droid\nsee ATOLL_ENV\nATOLL_FOUND:opencode\talias opencode=oc\n"
            + "ATOLL_ENV\nPATH=/opt/bin:/usr/bin\0PEM=line1\nPATH=/tmp/x\0=nameless\0PYENV_ROOT=/x\0\nATOLL_END\n"
        let found = AgentCLI.parseFound(output, from: clis)
        #expect(found.clis.map(\.command) == ["droid", "opencode"])
        #expect(found.locations == ["droid": "/opt/bin/droid", "opencode": "alias opencode=oc"])
        #expect(found.environment == ["PATH": "/opt/bin:/usr/bin", "PEM": "line1\nPATH=/tmp/x", "PYENV_ROOT": "/x"])
        #expect(AgentCLI.parseFound("ATOLL_FOUND:droid\t/x\nATOLL_ENV\nPATH=/x\0", from: clis).environment == nil)
    }

    @Test func helpSignatureIgnoresCaseStylingAndWrapping() {
        #expect(AgentCLI.helpMatches("kilo [project]  Start Kilo TUI  [default]", signature: "kilo tui"))
        #expect(AgentCLI.helpMatches("Run the Mistral\n    Vibe interactive CLI", signature: "Mistral Vibe"))
        #expect(AgentCLI.helpMatches("Run the \u{1B}[1mMistral\u{1B}[0m Vibe", signature: "Mistral Vibe"))
        #expect(!AgentCLI.helpMatches("pi - prints digits of pi", signature: "AI coding assistant"))
    }

    @Test func onlyPathsAreRunAndRelativeOnesResolveWhereTheShellWas() {
        #expect(AgentCLI.executable("/opt/bin/pi", in: "/w") == "/opt/bin/pi")
        #expect(AgentCLI.executable("alias pi='npx some/pkg'", in: "/w") == nil)
        #expect(AgentCLI.executable("pi", in: "/w") == nil)
        #expect(AgentCLI.executable("~/bin/pi", in: "/w") == NSHomeDirectory() + "/bin/pi")
        #expect(AgentCLI.executable("./node_modules/.bin/pi", in: "/w/project") == "/w/project/node_modules/.bin/pi")
    }

    @Test func onlyHelpThatWasPrintedCountsAgainstACLI() {
        func output(_ status: Int32, exited: Bool = true, _ text: String) -> ProcessRunner.Output {
            ProcessRunner.Output(status: status, exited: exited, stdout: Data(text.utf8), stderr: Data())
        }
        #expect(AgentCLI.helpCheck(output(0, "Run the Mistral Vibe CLI"), signature: "Mistral Vibe") == .matched)
        #expect(AgentCLI.helpCheck(output(2, "unknown option --help"), signature: "Mistral Vibe") == .mismatched)
        #expect(AgentCLI.helpCheck(output(127, "env: node: No such file or directory"), signature: "Mistral Vibe") == .unknown)
        #expect(AgentCLI.helpCheck(output(126, "permission denied"), signature: "Mistral Vibe") == .unknown)
        #expect(AgentCLI.helpCheck(output(9, exited: false, "partial"), signature: "Mistral Vibe") == .unknown)
        #expect(AgentCLI.helpCheck(output(0, " \n"), signature: "Mistral Vibe") == .unknown)
        #expect(AgentCLI.helpCheck(output(1, "SyntaxError: Unexpected token '?'"), signature: "AI coding assistant") == .unknown)
        #expect(AgentCLI.helpCheck(output(0, "SyntaxError is a word in this other tool's help"), signature: "AI coding assistant") == .mismatched)
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

    @Test func helpCheckOutcomesExpireUnknownSooner() async {
        final class Clock: @unchecked Sendable { var now = Date(timeIntervalSince1970: 0) }
        let clock = Clock()
        let cache = HelpCheckCache(knownLifetime: 3600, unknownLifetime: 300, now: { clock.now })
        #expect(await cache.check("/nonexistent/pi", signature: "s") { .unknown } == .unknown)
        clock.now += 299
        #expect(await cache.check("/nonexistent/pi", signature: "s") { .matched } == .unknown)
        clock.now += 2
        #expect(await cache.check("/nonexistent/pi", signature: "s") { .matched } == .matched)
        clock.now += 3599
        #expect(await cache.check("/nonexistent/pi", signature: "s") { .mismatched } == .matched)
        clock.now += 2
        #expect(await cache.check("/nonexistent/pi", signature: "s") { .mismatched } == .mismatched)
    }

    /// With no time left to run `--help`, a remembered outcome still applies; nothing remembered is unknown.
    @Test func aRememberedOutcomeAppliesWithoutRunning() async {
        let cache = HelpCheckCache()
        #expect(await cache.check("/nonexistent/pi", signature: "s", run: nil) == .unknown)
        #expect(await cache.check("/nonexistent/pi", signature: "s") { .mismatched } == .mismatched)
        #expect(await cache.check("/nonexistent/pi", signature: "s", run: nil) == .mismatched)
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
        #expect(AgentCLI.matching(app: "kiro")?.command == "kiro-cli")
        #expect(AgentCLI.matching(app: "kiro-cli")?.command == "kiro-cli")
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
        #expect(TaskPassing.lastArgument.apply(argv: ["codex"], task: "- fix A\n- fix B") == (["codex"], " - fix A\n- fix B"))
        #expect(TaskPassing.verbatim.apply(argv: ["reviewer"], task: "- check A") == (["reviewer"], "- check A"))
    }

    @Test func subcommandCLIsLaunchWithAndWithoutATask() {
        // What the program gets, through the same argv building a real launch uses.
        func launch(_ command: String, _ task: String) -> [String] {
            let cli = AgentCLI.catalog.first { $0.command == command }!
            let start = cli.taskPassing.apply(argv: [cli.command], task: task)
            let args = CoreRPCAdapter.hcRunArguments(LaunchRequest(argv: start.argv, folder: "/p", task: start.task, space: "sp"),
                                                     shell: "/bin/zsh", newID: { $0 })
            return Array(args.drop { $0 != "/bin/zsh" }.dropFirst(4))
        }
        #expect(launch("kiro-cli", "fix it") == ["kiro-cli", "chat", "fix it"])
        #expect(launch("kiro-cli", "") == ["kiro-cli"])
        #expect(launch("hermes", "fix it") == ["hermes", "chat", "-q", "fix it"])
        #expect(launch("hermes", "") == ["hermes", "chat"])
        #expect(launch("goose", "fix it") == ["goose", "run", "-s", "-t", "fix it"])
        #expect(launch("goose", "") == ["goose", "session"])
        #expect(launch("goose", "- fix A") == ["goose", "run", "-s", "-t", " - fix A"])
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
        #expect(Date().timeIntervalSince(start) < 1.5 + ProcessRunner.terminationGrace + 1.5)
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
        let alias = try bin.install("alias-shell", "printf 'ATOLL_FOUND:pi\\talias pi=npx-pi\\nATOLL_ENV\\nPATH=/usr/bin\\0\\nATOLL_END\\n'")
        #expect(await AgentCLI.detect(signed, shell: alias, timeout: 5)?.map(\.command) == ["pi"])
        let cut = try bin.install("cut-shell", "printf 'ATOLL_FOUND:droid\\t/usr/bin/droid\\n'; exit 1")
        #expect(await AgentCLI.detect(signed, shell: cut, timeout: 5) == nil)
    }

    @Test(arguments: [["/bin/sh"], ["/bin/bash"], ["/bin/zsh", "-f"]])
    func theScriptRunsInEachShell(_ shell: [String]) async throws {
        let bin = try FakeBin()
        let droid = try bin.install("droid", "exit 0")
        let output = try await ProcessRunner.run(shell[0], Array(shell.dropFirst()) + ["-c", AgentCLI.detectionScript(signed)],
                                                 environment: ["PATH": bin.url.path + ":/usr/bin:/bin", "ATOLL_TEST": "1"],
                                                 timeout: 5)
        let found = AgentCLI.parseFound(output.stdoutText, from: signed)
        #expect(found.clis.map(\.command) == ["droid"])
        #expect(found.locations["droid"] == droid)
        #expect(found.environment?["PATH"] == bin.url.path + ":/usr/bin:/bin")
        #expect(found.environment?["ATOLL_TEST"] == "1")
    }

    /// `--help` gets the shell's environment, not just its PATH (pyenv/asdf shims need their variables).
    @Test func helpRunsWithTheShellsEnvironment() async throws {
        let bin = try FakeBin()
        try bin.install("vibe", "[ \"$ATOLL_SHIM_ROOT\" = set ] && echo 'Mistral Vibe' || echo 'shim: root missing'")
        let shell = try bin.install("env-shell", "ATOLL_SHIM_ROOT=set; export ATOLL_SHIM_ROOT; PATH='\(bin.url.path)':/usr/bin:/bin; export PATH; shift; exec /bin/sh -c \"$1\"")
        let found = await AgentCLI.detect(signed, shell: shell, timeout: 5)
        #expect(found?.map(\.command) == ["vibe"])
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
