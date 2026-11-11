import Foundation
import Testing
@testable import AtollCore

/// Answers git commands from a table keyed by the joined arguments; missing = failure.
final class FakeGitRunner: GitRunner, @unchecked Sendable {
    var outputs: [String: String] = [:]
    private(set) var calls: [String] = []

    func run(_ arguments: [String], in directory: String) async -> String? {
        let key = arguments.joined(separator: " ")
        calls.append(key)
        return outputs[key]
    }

    static func repo(head: String = "abc123", status: String = "", untracked: [String] = [], shortstat: String = "") -> FakeGitRunner {
        let runner = FakeGitRunner()
        runner.outputs = [
            "rev-parse --show-toplevel": "/repo\n",
            "rev-parse --verify --quiet HEAD": head + "\n",
            "status --porcelain --untracked-files=no": status,
            "ls-files --others --exclude-standard -z": untracked.map { $0 + "\0" }.joined(),
            "diff --shortstat \(head)": shortstat,
        ]
        return runner
    }
}

@Suite("Change summary: git probe")
struct GitProbeTests {
    @Test("shortstat parsing", arguments: [
        (" 3 files changed, 10 insertions(+), 4 deletions(-)\n", 3, 10, 4),
        (" 1 file changed, 2 insertions(+)\n", 1, 2, 0),
        (" 1 file changed, 5 deletions(-)\n", 1, 0, 5),
        ("", 0, 0, 0),
    ])
    func shortstat(text: String, files: Int, insertions: Int, deletions: Int) {
        let parsed = ChangeSummary.parseShortstat(text)
        #expect(parsed.files == files)
        #expect(parsed.insertions == insertions)
        #expect(parsed.deletions == deletions)
    }

    @Test("clean start: diff since the turn's HEAD, only files new this turn count")
    func cleanTurn() async throws {
        let runner = FakeGitRunner.repo(untracked: ["old.txt"])
        let probe = GitProbe(runner: runner)
        let base = try #require(await probe.baseline(in: "/repo/sub"))
        #expect(base == TurnBaseline(toplevel: "/repo", head: "abc123", dirty: false, untracked: ["old.txt"]))
        runner.outputs["ls-files --others --exclude-standard -z"] = "old.txt\0new.swift\0"
        runner.outputs["diff --shortstat abc123"] = " 6 files changed, 120 insertions(+), 30 deletions(-)\n"
        let summary = try #require(await probe.summary(in: "/repo/sub", since: base))
        #expect(summary.baseline == .turnStart)
        #expect(summary.label == "+120 −30 · 6 files · 1 new")
    }

    @Test("an agent that committed: still diffed from the turn's start commit")
    func committed() async throws {
        let runner = FakeGitRunner.repo(shortstat: " 2 files changed, 8 insertions(+)\n")
        let probe = GitProbe(runner: runner)
        let base = try #require(await probe.baseline(in: "/repo"))
        runner.outputs["rev-parse --verify --quiet HEAD"] = "def456\n"
        let summary = try #require(await probe.summary(in: "/repo", since: base))
        #expect(runner.calls.last(where: { $0.hasPrefix("diff") }) == "diff --shortstat abc123")
        #expect(summary.text == "+8 −0 · 2 files")
    }

    @Test("dirty start is flagged: earlier edits are included")
    func dirtyStart() async throws {
        let runner = FakeGitRunner.repo(status: " M a.swift\n", shortstat: " 1 file changed, 1 insertion(+)\n")
        let probe = GitProbe(runner: runner)
        let base = try #require(await probe.baseline(in: "/repo"))
        #expect(base.dirty)
        let summary = try #require(await probe.summary(in: "/repo", since: base))
        #expect(summary.label == "+1 −0 · 1 file · incl. earlier edits")
    }

    @Test("no baseline: uncommitted changes vs HEAD, all untracked files")
    func noBaseline() async throws {
        let runner = FakeGitRunner.repo(untracked: ["a", "b"], shortstat: " 1 file changed, 3 deletions(-)\n")
        let summary = try #require(await GitProbe(runner: runner).summary(in: "/repo", since: nil))
        #expect(summary.label == "+0 −3 · 1 file · 2 untracked · uncommitted")
    }

    @Test("a baseline from another repo is ignored")
    func movedRepo() async throws {
        let runner = FakeGitRunner.repo()
        let base = TurnBaseline(toplevel: "/elsewhere", head: "zzz", dirty: false, untracked: [])
        let summary = try #require(await GitProbe(runner: runner).summary(in: "/repo", since: base))
        #expect(summary.baseline == .head)
    }

    @Test("nothing changed")
    func noChanges() async throws {
        let runner = FakeGitRunner.repo()
        let probe = GitProbe(runner: runner)
        let base = await probe.baseline(in: "/repo")
        let summary = try #require(await probe.summary(in: "/repo", since: base))
        #expect(summary.isEmpty)
        #expect(summary.label == "no changes")
    }

    @Test("not a repo, a failing / timed-out command, or no commits yet: no summary")
    func failures() async {
        #expect(await GitProbe(runner: FakeGitRunner()).summary(in: "/tmp", since: nil) == nil)
        #expect(await GitProbe(runner: FakeGitRunner()).baseline(in: "/tmp") == nil)
        let timedOut = FakeGitRunner.repo()
        timedOut.outputs["diff --shortstat abc123"] = nil
        #expect(await GitProbe(runner: timedOut).summary(in: "/repo", since: nil) == nil)
        let unborn = FakeGitRunner.repo()
        unborn.outputs["rev-parse --verify --quiet HEAD"] = nil
        #expect(await GitProbe(runner: unborn).baseline(in: "/repo") == nil)
        #expect(await GitProbe(runner: unborn).summary(in: "/repo", since: nil) == nil)
    }
}

/// Records what the store asks for; answers with a fixed baseline / summary.
final class FakeProbe: ChangeProbing, @unchecked Sendable {
    var toplevel = "/Users/me/Projects/project-x"
    var baselineResult: Bool = true
    var summaryResult: Bool = true
    private(set) var baselineCalls: [String] = []
    private(set) var summaryCalls: [(String, TurnBaseline?)] = []

    func baseline(in directory: String) async -> TurnBaseline? {
        baselineCalls.append(directory)
        return baselineResult ? TurnBaseline(toplevel: toplevel, head: "h\(baselineCalls.count)", dirty: false, untracked: []) : nil
    }

    func summary(in directory: String, since baseline: TurnBaseline?) async -> ChangeSummary? {
        summaryCalls.append((directory, baseline))
        guard summaryResult else { return nil }
        return ChangeSummary(insertions: 1, deletions: 0, files: 1, untracked: 0,
                             baseline: baseline == nil ? .head : .turnStart, toplevel: toplevel)
    }
}

@MainActor
@Suite("Change summary: turn tracking")
struct TurnTrackingTests {
    func harness(_ terminals: [TerminalInfo] = [term("t1", "idle"), term("t2", "idle", cwd: "/elsewhere")]) -> (Harness, FakeProbe) {
        let h = Harness()
        let probe = FakeProbe()
        h.store.changeProbe = probe
        h.connect(terminals)
        return (h, probe)
    }

    @Test("Working → Done: baseline at the start, summary at the end")
    func fullTurn() async throws {
        let (h, probe) = harness()
        h.status("t1", "working", seq: 11)
        await settle()
        #expect(probe.baselineCalls == ["/Users/me/Projects/project-x"])
        #expect(h.store.agent("t1")?.changeSummary == nil)
        h.status("t1", "done", seq: 12)
        await settle()
        #expect(probe.summaryCalls.first?.1?.head == "h1")
        let summary = try #require(h.store.agent("t1")?.changeSummary)
        #expect(summary.baseline == .turnStart)
        #expect(!summary.sharedTree)
    }

    @Test("Needs you stays inside the turn: no new baseline when it resumes")
    func needsYouMidTurn() async {
        let (h, probe) = harness()
        h.status("t1", "working", seq: 11)
        h.status("t1", "blocked", kind: "question", seq: 12)
        h.status("t1", "working", seq: 13)
        h.status("t1", "done", seq: 14)
        await settle()
        #expect(probe.baselineCalls.count == 1)
        #expect(probe.summaryCalls.count == 1)
    }

    @Test("the next turn clears the summary; Done → Idle keeps it")
    func nextTurnClears() async {
        let (h, probe) = harness()
        h.status("t1", "working", seq: 11)
        h.status("t1", "done", seq: 12)
        await settle()
        h.status("t1", "idle", seq: 13)
        await settle()
        #expect(probe.summaryCalls.count == 1)
        #expect(h.store.agent("t1")?.changeSummary != nil)
        h.status("t1", "working", seq: 14)
        #expect(h.store.agent("t1")?.changeSummary == nil)
    }

    @Test("Idle straight from Working finishes the turn")
    func idleFromWorking() async {
        let (h, _) = harness()
        h.status("t1", "working", seq: 11)
        h.status("t1", "idle", seq: 12)
        await settle()
        #expect(h.store.agent("t1")?.changeSummary != nil)
    }

    @Test("Error closes the turn without a summary")
    func error() async {
        let (h, probe) = harness()
        h.status("t1", "working", seq: 11)
        h.status("t1", "error", seq: 12)
        await settle()
        #expect(probe.summaryCalls.isEmpty)
        #expect(h.store.agent("t1")?.changeSummary == nil)
    }

    @Test("seen mid-turn (already working at connect): summary without a baseline")
    func noBaseline() async throws {
        let (h, probe) = harness([term("t1", "working")])
        h.status("t1", "done", seq: 11)
        await settle()
        #expect(probe.baselineCalls.isEmpty)
        #expect(probe.summaryCalls.count == 1)
        #expect(probe.summaryCalls.first?.1 == nil)
        #expect(try #require(h.store.agent("t1")?.changeSummary).baseline == .head)
    }

    @Test("probe fails: no summary")
    func probeFails() async {
        let (h, probe) = harness()
        probe.summaryResult = false
        h.status("t1", "working", seq: 11)
        h.status("t1", "done", seq: 12)
        await settle()
        #expect(h.store.agent("t1")?.changeSummary == nil)
    }

    @Test("another live agent in the same tree marks it shared")
    func sharedTree() async throws {
        let (h, _) = harness([term("t1", "idle"), term("t2", "idle")])
        h.status("t1", "working", seq: 11)
        h.status("t2", "working", seq: 12)
        await settle()
        h.status("t1", "done", seq: 13)
        await settle()
        #expect(try #require(h.store.agent("t1")?.changeSummary).sharedTree)
        #expect(h.store.agent("t1")?.changeSummary?.label.hasSuffix("shared tree") == true)
    }

    @Test("off: no git at all, and turning it off clears summaries")
    func disabled() async {
        let (h, probe) = harness()
        h.status("t1", "working", seq: 11)
        h.status("t1", "done", seq: 12)
        await settle()
        #expect(h.store.agent("t1")?.changeSummary != nil)
        h.store.changeProbe = nil
        #expect(h.store.agent("t1")?.changeSummary == nil)
        h.status("t1", "working", seq: 13)
        h.status("t1", "done", seq: 14)
        await settle()
        #expect(probe.baselineCalls.count == 1)
        #expect(probe.summaryCalls.count == 1)
    }

    @Test("a late result from an earlier turn doesn't land on the new one")
    func staleResult() async {
        let (h, probe) = harness()
        h.status("t1", "working", seq: 11)
        h.status("t1", "done", seq: 12)
        h.status("t1", "working", seq: 13) // before the Done summary task ran
        await settle()
        #expect(probe.summaryCalls.count == 1)
        #expect(h.store.agent("t1")?.changeSummary == nil)
    }
}

@Suite("Change summary: real git")
struct RealGitTests {
    @Test("a turn in a temporary repo", .enabled(if: ProcessGitRunner().gitPath != nil))
    func temporaryRepo() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("atoll-git-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let runner = ProcessGitRunner()
        let path = dir.path
        for args in [["init", "-q"], ["config", "user.email", "t@example.com"], ["config", "user.name", "t"]] {
            #expect(await runner.run(args, in: path) != nil)
        }
        try "a\nb\n".write(to: dir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        _ = await runner.run(["add", "."], in: path)
        #expect(await runner.run(["commit", "-qm", "init"], in: path) != nil)

        let probe = GitProbe(runner: runner)
        let base = try #require(await probe.baseline(in: path))
        #expect(!base.dirty)
        // The "agent": edits, commits, and leaves a new file.
        try "a\nB\nc\n".write(to: dir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        _ = await runner.run(["commit", "-qam", "edit"], in: path)
        try "new".write(to: dir.appendingPathComponent("new.txt"), atomically: true, encoding: .utf8)
        let summary = try #require(await probe.summary(in: path, since: base))
        #expect(summary.label == "+2 −1 · 1 file · 1 new")
        #expect(await probe.summary(in: FileManager.default.temporaryDirectory.path, since: nil) == nil)
    }
}
