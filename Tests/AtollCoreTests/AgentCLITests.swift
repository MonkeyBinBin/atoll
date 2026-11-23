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

@Suite("Agent CLIs added in Settings")
struct CustomAgentCLITests {
    let aider = AgentCLI(command: "aider", title: "Aider", taskPassing: .unsupported)

    @Test func everyTaskPassingSurvivesSaving() throws {
        let clis = [
            AgentCLI(command: "a", title: "A", taskPassing: .lastArgument),
            AgentCLI(command: "b", title: "B", taskPassing: .flag("-i"), appWords: ["bee"], helpSignature: "Bee CLI"),
            AgentCLI(command: "c", title: "C", taskPassing: .arguments(withTask: ["run", "-t"], withoutTask: ["session"])),
            AgentCLI(command: "d", title: "D", taskPassing: .unsupported),
            AgentCLI(command: "e", title: "E", taskPassing: .verbatim),
        ]
        let decoded = try JSONDecoder().decode([AgentCLI].self, from: JSONEncoder().encode(clis))
        #expect(decoded == clis)
    }

    @Test func onlyShellSafeCommandsAreValid() {
        for good in ["aider", "cursor-agent", "kiro-cli", "my.tool", "g++", "x_1"] {
            #expect(AgentCLI.isValidCommand(good), "\(good)")
        }
        for bad in ["", "-x", ".hidden", "a b", "a;rm -rf ~", "$(x)", "a|b", "a`b`", "a'b", "~/bin/x", "a/b"] {
            #expect(!AgentCLI.isValidCommand(bad), "\(bad)")
        }
    }

    @Test func aCustomCLIReplacesTheCatalogEntryInPlaceOrFollowsIt() {
        let pi = AgentCLI(command: "pi", title: "My Pi", taskPassing: .flag("--prompt"))
        let merged = AgentCLI.merged(custom: [aider, pi,
                                              AgentCLI(command: "bad cmd", title: "Bad", taskPassing: .lastArgument),
                                              AgentCLI(command: "aider", title: "Second", taskPassing: .lastArgument)])
        let catalogIndex = AgentCLI.catalog.firstIndex { $0.command == "pi" }!
        #expect(merged.count == AgentCLI.catalog.count + 1)
        #expect(merged[catalogIndex] == pi)
        #expect(merged.last == aider)
        #expect(AgentCLI.merged(custom: []) == AgentCLI.catalog)
    }

    @Test func appWordsMatchInTheGivenList() {
        let clis = AgentCLI.merged(custom: [AgentCLI(command: "aider", title: "Aider", taskPassing: .unsupported,
                                                     appWords: ["aider-chat"])])
        #expect(AgentCLI.matching(app: "aider-chat", in: clis)?.command == "aider")
        #expect(AgentCLI.matching(app: "aider-chat") == nil)
    }

    @Test func updatingTheListRedefinesWhatWasDetected() async {
        let droid = AgentCLI(command: "droid", title: "Factory Droid", taskPassing: .lastArgument)
        let opencode = AgentCLI(command: "opencode", title: "OpenCode", taskPassing: .flag("--prompt"))
        let detector = AgentCLIDetector(clis: [droid, opencode], saved: ["droid", "opencode"], detect: { $0 })
        let edited = AgentCLI(command: "droid", title: "Droid (mine)", taskPassing: .flag("-p"))
        await detector.update(clis: [edited, aider])
        #expect(await detector.lastKnown == [edited])
        #expect(await detector.refresh() == [edited, aider])
    }

    /// A detection still running with the old list reports the current definitions.
    @Test func aDetectionStartedBeforeAnUpdateReportsTheNewDefinitions() async {
        let droid = AgentCLI(command: "droid", title: "Factory Droid", taskPassing: .lastArgument)
        let gate = AsyncGate()
        let detector = AgentCLIDetector(clis: [droid, aider], detect: { clis in await gate.wait(); return clis })
        let refresh = Task { await detector.refresh() }
        await gate.waitUntilWaiting()
        let edited = AgentCLI(command: "aider", title: "Aider", taskPassing: .lastArgument)
        await detector.update(clis: [edited])
        await gate.open()
        #expect(await refresh.value == [edited])
    }

    @Test func claudeAndCodexCantBeRedefined() {
        var draft = AgentCLIDraft()
        draft.command = "claude"
        draft.title = "Claude (mine)"
        #expect(draft.problem == .reservedCommand)
        let merged = AgentCLI.merged(custom: [AgentCLI(command: "codex", title: "Codex", taskPassing: .lastArgument)])
        #expect(merged == AgentCLI.catalog)
    }

    @Test func anExactNameBeatsAPrefixedOne() {
        let dev = AgentCLI(command: "opencode-dev", title: "OpenCode dev", taskPassing: .lastArgument)
        let clis = AgentCLI.merged(custom: [dev])
        #expect(AgentCLI.matching(app: "opencode-dev", in: clis) == dev)
        #expect(AgentCLI.matching(app: "opencode-tui", in: clis)?.command == "opencode")
    }

    @Test func oneUnreadableStoredEntryDropsOnlyItself() throws {
        let good = AgentCLI(command: "aider", title: "Aider", taskPassing: .unsupported)
        let stored = try JSONSerialization.jsonObject(with: JSONEncoder().encode([good]))
        let data = try JSONSerialization.data(withJSONObject: [["command": "x", "title": "X", "taskPassing": ["future": [:]],
                                                                "appWords": []]] + (stored as! [Any]))
        #expect(AgentCLI.decodeList(data) == [good])
        #expect(AgentCLI.decodeList(Data("not json".utf8)) == [])
    }

    /// A newly required help signature isn't vouched for by a detection made without it.
    @Test func aNewHelpSignatureWaitsForTheNextDetection() async {
        let plain = AgentCLI(command: "goose", title: "Goose", taskPassing: .lastArgument)
        let signed = AgentCLI(command: "goose", title: "Goose", taskPassing: .lastArgument, helpSignature: "interactive chat sessions")
        let detector = AgentCLIDetector(clis: [plain], saved: ["goose"], detect: { _ in [] })
        await detector.update(clis: [signed])
        #expect(await detector.lastKnown == [])
    }

    @Test func aRefreshJoiningARunningDetectionGetsTheNewDefinitions() async {
        let gate = AsyncGate()
        let detector = AgentCLIDetector(clis: [aider], detect: { clis in await gate.wait(); return clis })
        let first = Task { await detector.refresh() }
        await gate.waitUntilWaiting()
        let edited = AgentCLI(command: "aider", title: "Aider (mine)", taskPassing: .lastArgument)
        await detector.update(clis: [edited])
        let joined = Task { await detector.refresh() }
        await Task.yield()
        await gate.open()
        #expect(await first.value == [edited])
        #expect(await joined.value == [edited])
    }

    @Test func commandsMatchAndReserveInAnyCase() {
        let upper = AgentCLI(command: "Aider", title: "Aider", taskPassing: .unsupported)
        #expect(AgentCLI.matching(app: "aider", in: AgentCLI.merged(custom: [upper])) == upper)
        var draft = AgentCLIDraft()
        draft.command = "Claude"
        draft.title = "Mine"
        #expect(draft.problem == .reservedCommand)
        #expect(AgentCLI.merged(custom: [AgentCLI(command: "CODEX", title: "X", taskPassing: .lastArgument)]) == AgentCLI.catalog)
    }

    /// Output layouts follow the merged list too: a Settings `opencode-dev` isn't parsed as OpenCode.
    @Test func layoutsAreToldApartWithTheSettingsCLIs() {
        let clis = AgentCLI.merged(custom: [AgentCLI(command: "opencode-dev", title: "Dev", taskPassing: .lastArgument),
                                            AgentCLI(command: "agy-beta", title: "Beta", taskPassing: .lastArgument)])
        #expect(OutputFilter.genericMessages(["x"], app: "opencode-dev", clis: clis) == nil)
        #expect(!OutputFilter.isAntigravity(app: "agy-beta", clis: clis))
        #expect(OutputFilter.isAntigravity(app: "antigravity", clis: clis))
        #expect(OutputFilter.isAntigravity(app: "agy-beta"))
    }

    @Test func aLateOlderUpdateIsIgnored() async {
        let newer = AgentCLI(command: "aider", title: "Newer", taskPassing: .lastArgument)
        let older = AgentCLI(command: "aider", title: "Older", taskPassing: .lastArgument)
        let detector = AgentCLIDetector(clis: [], detect: { $0 })
        await detector.update(clis: [newer], version: 2)
        await detector.update(clis: [older], version: 1)
        #expect(await detector.refresh() == [newer])
    }

    /// A CLI added while a detection runs is detected before that detection finishes.
    @Test func aCLIAddedDuringADetectionIsDetected() async {
        let droid = AgentCLI(command: "droid", title: "Factory Droid", taskPassing: .lastArgument)
        let gate = AsyncGate()
        let passes = Counter()
        let detector = AgentCLIDetector(clis: [droid], detect: { clis in
            passes.increment()
            await gate.wait()
            return clis
        })
        let refresh = Task { await detector.refresh() }
        await gate.waitUntilWaiting()
        await detector.update(clis: [droid, aider])
        await gate.open()
        #expect(await refresh.value == [droid, aider])
        #expect(passes.value == 2)
    }

    @Test func aCustomCommandOverridesWhateverItsCase() {
        let mine = AgentCLI(command: "OpenCode", title: "Mine", taskPassing: .lastArgument)
        let merged = AgentCLI.merged(custom: [mine, AgentCLI(command: "AIDER", title: "A", taskPassing: .lastArgument),
                                              AgentCLI(command: "aider", title: "B", taskPassing: .lastArgument)])
        #expect(merged.count == AgentCLI.catalog.count + 1)
        #expect(merged[AgentCLI.catalog.firstIndex { $0.command == "opencode" }!] == mine)
        var draft = AgentCLIDraft()
        draft.command = "MyTool"
        draft.title = "T"
        #expect((try? draft.build().get())?.command == "mytool")
    }

    @Test func typingABuiltInCommandStartsFromItsDefinition() {
        var draft = AgentCLIDraft()
        draft.command = "AGY"
        let adopted = draft.adoptCatalogEntry()
        #expect(adopted)
        #expect((try? draft.build().get()) == AgentCLI.catalog.first { $0.command == "agy" })
        var titled = AgentCLIDraft()
        titled.command = "agy"
        titled.title = "My agy"
        let titledAdopted = titled.adoptCatalogEntry()
        #expect(!titledAdopted)
        var unknown = AgentCLIDraft()
        unknown.command = "aider"
        let unknownAdopted = unknown.adoptCatalogEntry()
        #expect(!unknownAdopted)
    }

    @Test func editingKeepsATaskPassingTheEditorCantShow() throws {
        let cli = AgentCLI(command: "t", title: "T", taskPassing: .verbatim)
        var draft = AgentCLIDraft(cli)
        draft.title = "Renamed"
        #expect(try draft.build().get().taskPassing == .verbatim)
        draft.passing = .flag
        draft.flag = "-i"
        draft.passing = .lastArgument
        #expect(try draft.build().get().taskPassing == .verbatim)
    }

    @Test func anUpdateSavesTheRemappedDetectionAndCanDetectAgain() async {
        let droid = AgentCLI(command: "droid", title: "Factory Droid", taskPassing: .lastArgument)
        let saved = SavedDetections()
        let passes = Counter()
        let detector = AgentCLIDetector(clis: [droid, aider], saved: ["droid", "aider"], onDetected: saved.record,
                                        detect: { clis in passes.increment(); return clis })
        await detector.update(clis: [droid])
        #expect(saved.all == [["droid"]])
        #expect(passes.value == 0)
        await detector.update(clis: [droid, aider], redetect: true)
        for _ in 0..<100 where passes.value == 0 { await Task.yield() }
        #expect(passes.value == 1)
    }

    @Test func aDraftRoundTripsEveryTaskPassing() throws {
        for cli in [AgentCLI(command: "a", title: "A", taskPassing: .lastArgument),
                    AgentCLI(command: "b", title: "B", taskPassing: .flag("-i"), appWords: ["bee", "b-cli"],
                             helpSignature: "Bee CLI"),
                    AgentCLI(command: "c", title: "C", taskPassing: .arguments(withTask: ["run", "-s", "-t"],
                                                                                 withoutTask: ["session"])),
                    AgentCLI(command: "d", title: "D", taskPassing: .unsupported)] {
            #expect(try AgentCLIDraft(cli).build().get() == cli)
        }
    }

    @Test func aDraftCleansUpWhatWasTyped() throws {
        var draft = AgentCLIDraft()
        draft.command = " goose "
        draft.title = " Goose "
        draft.passing = .subcommand
        draft.withTask = " run  -s -t "
        draft.withoutTask = ""
        draft.appWords = "Goose, goose-ai  GOOSE2"
        draft.helpSignature = "  "
        #expect(try draft.build().get() == AgentCLI(
            command: "goose", title: "Goose", taskPassing: .arguments(withTask: ["run", "-s", "-t"], withoutTask: []),
            appWords: ["goose", "goose-ai", "goose2"]))
    }

    @Test func aDraftSaysWhatIsWrong() {
        var draft = AgentCLIDraft()
        draft.command = "a;b"
        draft.title = "T"
        #expect(draft.problem == .invalidCommand)
        draft.command = "tool"
        draft.title = " "
        #expect(draft.problem == .emptyTitle)
        draft.title = "Tool"
        draft.passing = .flag
        #expect(draft.problem == .invalidFlag)
        draft.flag = "-i -x"
        #expect(draft.problem == .invalidFlag)
        draft.flag = "-i"
        #expect(draft.problem == nil)
        draft.passing = .subcommand
        #expect(draft.problem == .emptySubcommand)
        draft.withTask = "chat"
        #expect(draft.problem == nil)
    }
}

/// Holds a detection until the test opens it.
actor AsyncGate {
    private var opened = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var waitingWatchers: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if opened { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
            waitingWatchers.forEach { $0.resume() }
            waitingWatchers = []
        }
    }

    func waitUntilWaiting() async {
        if !waiters.isEmpty { return }
        await withCheckedContinuation { waitingWatchers.append($0) }
    }

    func open() {
        opened = true
        waiters.forEach { $0.resume() }
        waiters = []
    }
}

final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.withLock { count } }
    func increment() { lock.withLock { count += 1 } }
}
