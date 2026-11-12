import Foundation
import Testing
@testable import AtollCore

private func labelled(_ address: String, space: String, location: String? = nil, live: Bool = true) -> TerminalInfo {
    var labels = [HerdrLabels.space: space, HerdrLabels.tab: "tb1"]
    if let location { labels[HerdrLabels.location] = location }
    return TerminalInfo(address: address, state: live ? "live" : "finished", labels: labels)
}

@Suite("Herdr labels")
struct HerdrLabelsTests {
    let atoll = HerdrSpace(id: "sp1", name: "atoll", terminals: ["t1"], active: true)
    let dots = HerdrSpace(id: "sp2", name: "dotfiles")

    @Test("cached spaces first, renamed by `where`, then spaces only the labels know; finished terminals don't count")
    func merge() {
        let spaces = HerdrLabels.spaces(cached: [atoll, dots], terminals: [
            labelled("t1", space: "sp1", location: "atoll-renamed / 1"),
            labelled("t5", space: "sp9", location: "a / b / 2"),
            labelled("t6", space: "sp8"),
            labelled("t7", space: "sp7", location: "gone / 1", live: false),
            TerminalInfo(address: "t8"),
        ])
        #expect(spaces.map(\.id) == ["sp1", "sp2", "sp9", "sp8"])
        #expect(spaces.map(\.name) == ["atoll-renamed", "dotfiles", "a / b", "sp8"])
        #expect(spaces[0].active)
        #expect(spaces[2].terminals == ["t5"])
    }

    @Test("target: the picked space, else the active one, else the first, else none")
    func target() {
        #expect(HerdrLabels.target(picked: "sp2", spaces: [atoll, dots]) == "sp2")
        #expect(HerdrLabels.target(picked: "", spaces: [dots, atoll]) == "sp1")
        #expect(HerdrLabels.target(picked: nil, spaces: [dots]) == "sp2")
        #expect(HerdrLabels.target(picked: nil, spaces: []) == nil)
    }

    @Test("new ids look like Herdr's")
    func newID() {
        let id = HerdrLabels.newID("sp")
        #expect(id.range(of: #"^sp[0-9a-f]{32}$"#, options: .regularExpression) != nil)
    }

    @Test("hc run: kept, labelled, plain argv through a login shell with the task last")
    func hcArguments() {
        let request = LaunchRequest(argv: ["codex", "--no-daemon"], folder: "/p", task: "fix it", name: "fixer", space: "sp1")
        let args = CoreRPCAdapter.hcRunArguments(request, shell: "/bin/zsh", newID: { "\($0)NEW" })
        #expect(args == [
            "run", "--bg", "--keep", "--no-parent", "--json", "--cwd", "/p",
            "--label", "herdr.space=sp1", "--label", "herdr.tab=tbNEW", "--name", "fixer", "--",
            "/bin/zsh", "-lic", #""$@"; exec "$0" -li"#, "/bin/zsh", "codex", "--no-daemon", "fix it",
        ])
    }

    @Test("hc run: a template gets its task from core; no space → a new one; no task → no argument")
    func hcTemplate() {
        let template = LaunchRequest(argv: ["reviewer"], folder: "/p", task: "review x", template: true)
        let args = CoreRPCAdapter.hcRunArguments(template, shell: "/bin/zsh", newID: { "\($0)NEW" })
        #expect(args.contains("herdr.space=spNEW"))
        #expect(Array(args.suffix(3)) == ["--", "reviewer", "review x"])
        let plain = LaunchRequest(argv: ["claude"], folder: "/p", task: "", space: "")
        #expect(CoreRPCAdapter.hcRunArguments(plain, shell: "/bin/sh", newID: { "\($0)NEW" }).last == "claude")
    }
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
}
