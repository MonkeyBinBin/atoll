import Foundation
import Testing
@testable import AtollCore

/// Maps project paths to working-tree top levels; unknown paths are not repos.
final class FakeTreeProbe: WorkingTreeProbing, @unchecked Sendable {
    var trees: [String: String] = [:]
    private(set) var calls: [String] = []

    func toplevel(in directory: String) async -> String? {
        calls.append(directory)
        return trees[directory]
    }
}

@MainActor
@Suite("Shared working tree")
struct SharedTreeTests {
    static let repo = "/Users/me/Projects/project-x"
    static let worktree = "/Users/me/Projects/project-x-wt"

    final class Sink {
        var announced: [String] = []
    }

    func harness(_ terminals: [TerminalInfo]) async -> (Harness, FakeTreeProbe, Sink) {
        let h = Harness()
        let probe = FakeTreeProbe()
        probe.trees = [Self.repo: Self.repo, Self.repo + "/sub": Self.repo, Self.worktree: Self.worktree]
        let sink = Sink()
        h.store.treeProbe = probe
        h.store.onSharedTree = { sink.announced.append($0.address) }
        h.connect(terminals)
        await settle()
        return (h, probe, sink)
    }

    func shared(_ h: Harness, _ address: String) -> [String] {
        h.store.agent(address)?.sharedTreeWith ?? []
    }

    @Test("two active agents in one tree (any subdirectory) flag each other")
    func sameTree() async {
        let (h, _, _) = await harness([term("t1", "idle"), term("t2", "idle", cwd: Self.repo + "/sub")])
        #expect(shared(h, "t1").isEmpty)
        h.status("t1", "working", seq: 11)
        h.status("t2", "blocked", kind: "question", seq: 12)
        #expect(shared(h, "t1") == ["t2"])
        #expect(shared(h, "t2") == ["t1"])
    }

    @Test("separate worktrees of one repo don't warn")
    func worktrees() async {
        let (h, _, sink) = await harness([term("t1", "working"), term("t2", "working", cwd: Self.worktree)])
        #expect(shared(h, "t1").isEmpty)
        #expect(sink.announced.isEmpty)
    }

    @Test("an idle / done / exited agent in the tree doesn't count")
    func inactive() async {
        let (h, _, sink) = await harness([term("t1", "working"), term("t2", "idle"), term("t3", "done")])
        h.client.emit(.event(seq: 11, .finished(terminal: "t3", exitCode: 0, reason: nil, finishedMs: nil)))
        #expect(shared(h, "t1").isEmpty)
        #expect(shared(h, "t2").isEmpty)
        #expect(sink.announced.isEmpty)
    }

    @Test("non-git directories are never grouped")
    func notRepo() async {
        let (h, _, _) = await harness([term("t1", "working", cwd: "/tmp/a"), term("t2", "working", cwd: "/tmp/a")])
        #expect(shared(h, "t1").isEmpty)
    }

    @Test("each path is probed once; a new path is probed when an agent moves")
    func cached() async {
        let (h, probe, _) = await harness([term("t1", "working"), term("t2", "idle")])
        h.status("t2", "working", seq: 11)
        h.status("t2", "done", seq: 12)
        await settle()
        #expect(probe.calls == [Self.repo])
        h.client.emit(.event(seq: 13, .foreground(terminal: "t2", foreground: CoreForeground(cwd: Self.worktree))))
        await settle()
        #expect(probe.calls.sorted() == [Self.repo, Self.worktree])
    }

    @Test("announced once for the newcomer; turns flapping in the same pair don't re-announce")
    func announceOnce() async {
        let (h, _, sink) = await harness([term("t1", "working"), term("t2", "idle")])
        h.scheduler.advance(by: 5)
        h.status("t2", "working", seq: 11)
        #expect(sink.announced == ["t2"])
        h.status("t2", "done", seq: 12)
        h.status("t2", "working", seq: 13)
        #expect(sink.announced == ["t2"])
    }

    @Test("a third agent joining is announced; after the tree drops below two, it starts over")
    func newEpisode() async {
        let (h, _, sink) = await harness([term("t1", "working"), term("t2", "working"), term("t3", "idle")])
        #expect(sink.announced.count == 1)
        h.status("t3", "working", seq: 11)
        #expect(sink.announced.last == "t3")
        h.client.emit(.event(seq: 12, .removed(terminal: "t2")))
        h.client.emit(.event(seq: 13, .removed(terminal: "t3")))
        #expect(shared(h, "t1").isEmpty)
        h.client.emit(.event(seq: 14, .created(term("t4", "idle"))))
        await settle()
        h.scheduler.advance(by: 5)
        h.status("t4", "working", seq: 15)
        #expect(sink.announced.last == "t4")
        #expect(sink.announced.count == 3)
    }

    @Test("off: no git, and turning it off clears the flags")
    func disabled() async {
        let (h, probe, _) = await harness([term("t1", "working"), term("t2", "working")])
        #expect(shared(h, "t1") == ["t2"])
        h.store.treeProbe = nil
        #expect(shared(h, "t1").isEmpty)
        h.client.emit(.event(seq: 11, .created(term("t3", "working", cwd: Self.worktree))))
        await settle()
        #expect(probe.calls == [Self.repo])
    }

    @Test("change summary's shared-tree note uses the grouping, even for agents that never started a turn here")
    func summaryUsesGrouping() async throws {
        let h = Harness()
        let trees = FakeTreeProbe()
        trees.trees = [Self.repo: Self.repo]
        h.store.treeProbe = trees
        h.store.changeProbe = FakeProbe()
        h.connect([term("t1", "idle"), term("t2", "working")])
        await settle()
        h.status("t1", "working", seq: 11)
        h.status("t1", "done", seq: 12)
        await settle()
        #expect(try #require(h.store.agent("t1")?.changeSummary).sharedTree)
    }

    @Test("bubble kinds: shared-tree bubbles aren't urgent and last while the tree is shared")
    func bubbleKind() {
        var agent = Agent(address: "t1", state: .needsYou(.question))
        let bubble = AgentBubble(address: "t1", state: agent.state, key: "k", kind: .sharedTree)
        #expect(!bubble.isUrgent)
        #expect(!bubble.stillApplies(to: agent))
        agent.sharedTreeWith = ["t2"]
        #expect(bubble.stillApplies(to: agent))
        #expect(AgentBubble(address: "t1", state: agent.state, key: "k").isUrgent)
    }
}
