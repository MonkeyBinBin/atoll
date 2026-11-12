import Foundation
import Testing
@testable import AtollCore

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
            labelled("t9", space: "sp6", cwd: "/p/web"),
            labelled("t7", space: "sp7", location: "gone / 1", live: false),
            TerminalInfo(address: "t8"),
        ])
        #expect(spaces.map(\.id) == ["sp1", "sp2", "sp9", "sp8", "sp6"])
        #expect(spaces.map(\.name) == ["atoll-renamed", "dotfiles", "a / b", "sp8", "web"])
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
