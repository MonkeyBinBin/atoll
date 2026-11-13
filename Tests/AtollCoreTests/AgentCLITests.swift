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

    @Test func matchesAnAgentsAppWord() {
        #expect(AgentCLI.matching(app: "OpenCode")?.command == "opencode")
        #expect(AgentCLI.matching(app: "cursor-agent")?.command == "cursor-agent")
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
