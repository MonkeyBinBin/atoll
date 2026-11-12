import Foundation
import Testing
@testable import AtollCore

func labelled(_ address: String, space: String, location: String? = nil, live: Bool = true, cwd: String = "/") -> TerminalInfo {
    var labels = [HerdrLabels.space: space, HerdrLabels.tab: "tb1"]
    if let location { labels[HerdrLabels.location] = location }
    return TerminalInfo(address: address, cwd: cwd, state: live ? "live" : "finished", labels: labels)
}

@MainActor
@Suite("Launch without the Herdr app")
struct OfflineLaunchTests {
    let request = LaunchRequest(argv: ["claude"], folder: "/p", task: "go")

    private func launched(_ h: Harness) -> LaunchRequest? {
        for case .launch(let r) in h.client.commands { return r }
        return nil
    }

    @Test("Selected space → the one the app showed last (cache + labels)")
    func lastSelected() async {
        let h = Harness()
        h.store.cachedSpaces = [HerdrSpace(id: "sp1", name: "a"), HerdrSpace(id: "sp2", name: "b", active: true)]
        h.connect()
        h.store.launch(request)
        await settle()
        #expect(launched(h)?.withoutApp == true)
        #expect(launched(h)?.space == "sp2")
    }

    @Test("launch spaces without the app come from the cache and live terminals' labels")
    func launchSpaces() async {
        let h = Harness()
        h.store.cachedSpaces = [HerdrSpace(id: "sp1", name: "a")]
        h.connect([labelled("t1", space: "sp1", location: "renamed / 1"), labelled("t2", space: "sp3", location: "c / 1")])
        let spaces = await h.store.launchSpaces()
        #expect(spaces.map(\.name) == ["renamed", "c"])
        #expect(h.client.spacesCalls == 0)
    }

    @Test("new space: a fresh id, its name kept until the app shows it, then renamed and dropped")
    func newSpaceNamedLater() async {
        let h = Harness()
        var names: [[String: String]] = []
        h.store.onPendingSpaceNamesChanged = { names.append($0) }
        h.connect()
        var r = request
        r.newSpaceName = "my space"
        h.store.launch(r)
        await settle()
        let id = try! #require(launched(h)?.space)
        #expect(id.hasPrefix("sp"))
        #expect(h.store.pendingSpaceNames == [id: "my space"])
        #expect(names.last == [id: "my space"])

        h.client.spacesResult = .success([HerdrSpace(id: id, name: "p")])
        h.store.herdrAppRunning = true
        await settle()
        #expect(h.client.commands.contains(.renameSpace(id, "my space")))
        #expect(h.store.pendingSpaceNames.isEmpty)
    }

    @Test("a failed rename stays pending; a failed launch drops its name")
    func failures() async {
        let h = Harness()
        h.store.pendingSpaceNames = ["sp5": "x"]
        h.client.renameResult = .failure(.unavailable("herdr-app"))
        h.client.spacesResult = .success([HerdrSpace(id: "sp5", name: "p")])
        h.connect()
        h.store.herdrAppRunning = true
        await settle()
        #expect(h.store.pendingSpaceNames == ["sp5": "x"])

        let g = Harness()
        g.client.launchResult = .failure(HerdrError(kind: "spawn_failed", message: "no"))
        g.connect()
        var r = request
        r.newSpaceName = "doomed"
        g.store.launch(r)
        await settle()
        #expect(g.store.pendingSpaceNames.isEmpty)
    }

    @Test("an unnamed new space needs no rename; with the app running, the app makes it (no id, no pending)")
    func newSpaceVariants() async {
        let h = Harness()
        h.connect()
        var r = request
        r.newSpaceName = ""
        h.store.launch(r)
        await settle()
        #expect(launched(h)?.space?.hasPrefix("sp") == true)
        #expect(h.store.pendingSpaceNames.isEmpty)

        let g = Harness()
        g.connect()
        g.store.herdrAppRunning = true
        await settle()
        r.newSpaceName = "named"
        g.store.launch(r)
        await settle()
        #expect(launched(g) == r)
        #expect(g.store.pendingSpaceNames.isEmpty)
    }

    @Test("spaces read from the app are cached for later")
    func cache() async {
        let h = Harness()
        var cached: [HerdrSpace] = []
        h.store.onSpacesCached = { cached = $0 }
        let atoll = HerdrSpace(id: "sp1", name: "atoll", active: true)
        h.client.spacesResult = .success([atoll])
        h.connect()
        h.store.herdrAppRunning = true
        await settle()
        h.store.herdrAppRunning = false
        #expect(h.store.cachedSpaces == [atoll])
        #expect(cached == [atoll])
    }

    @Test("a space made without the app shows by its pending name (else its folder), not its id")
    func pendingNameShown() async {
        let h = Harness()
        h.store.pendingSpaceNames = ["spN": "my space"]
        h.connect([labelled("t1", space: "spN", cwd: "/p/web"), labelled("t2", space: "spM", cwd: "/p/api")])
        let spaces = await h.store.launchSpaces()
        #expect(spaces.map(\.name) == ["my space", "api"])
    }

    @Test("a new space's name waits only once its launch went out: a failed worktree leaves none")
    func worktreeFailureLeavesNoName() async {
        let h = Harness()
        let creator = FakeWorktreeCreator()
        creator.result = .failure(WorktreeError("no"))
        h.store.worktreeCreator = creator
        h.connect()
        var r = request
        r.newSpaceName = "named"
        h.store.launch(r, worktree: WorktreePlan(
            source: WorktreeSource(toplevel: "/p", head: "abc", dirty: false),
            branch: "atoll/x", path: "/p.worktrees/x", launchFolder: "/p.worktrees/x"))
        await settle()
        #expect(h.store.pendingSpaceNames.isEmpty)
    }

    @Test("with the app open, a pending name whose space isn't shown and has no live terminal is dropped")
    func orphanedNameDropped() async {
        let h = Harness()
        h.store.pendingSpaceNames = ["spGone": "a", "spWaiting": "b"]
        h.client.spacesResult = .success([HerdrSpace(id: "sp1", name: "x")])
        h.connect([labelled("t1", space: "spWaiting")])
        h.store.herdrAppRunning = true
        await settle()
        #expect(h.store.pendingSpaceNames == ["spWaiting": "b"])
    }

    @Test("the form's choices become the request: selected, existing, new (trimmed name), template option ids")
    func requestFromChoices() {
        func make(_ choice: LaunchSpaceChoice, _ optionID: String = "builtin:claude") -> LaunchRequest {
            LaunchRequest(argv: ["x"], folder: "/p", task: "t", name: nil, optionID: optionID, space: choice, newSpaceName: " n ")
        }
        #expect(make(.selected).space == nil)
        #expect(make(.selected).newSpaceName == nil)
        #expect(make(.existing("sp1")).space == "sp1")
        #expect(make(.new).newSpaceName == "n")
        #expect(make(.new).space == nil)
        #expect(make(.selected, "template:reviewer").template)
        #expect(!make(.selected).template)
        #expect(LaunchSpaceChoice(stored: "") == .selected)
        #expect(LaunchSpaceChoice(stored: "sp1").stored == "sp1")
        #expect(LaunchSpaceChoice.new.stored == "")
    }
}
