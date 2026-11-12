import Foundation
import Testing
@testable import AtollCore

@Suite("Launch history: recent launches and presets")
struct LaunchHistoryTests {
    func recipe(_ task: String, option: String = "builtin:claude", folder: String = "/p/a", worktree: Bool = false) -> LaunchRecipe {
        LaunchRecipe(optionID: option, folder: folder, task: task, name: "n", space: "", worktree: worktree)
    }

    @Test("the newest launch goes first; the same tool + folder + task keeps only the newest")
    func dedupe() {
        var recent: [LaunchRecipe] = []
        recent = LaunchHistory.recording(recipe("a"), in: recent)
        recent = LaunchHistory.recording(recipe("b"), in: recent)
        var again = recipe("a")
        again.name = "renamed"
        recent = LaunchHistory.recording(again, in: recent)
        #expect(recent.map(\.task) == ["a", "b"])
        #expect(recent.first?.name == "renamed")
        // A different tool or folder is a different combination.
        recent = LaunchHistory.recording(recipe("a", option: "builtin:codex"), in: recent)
        recent = LaunchHistory.recording(recipe("a", folder: "/p/b"), in: recent)
        #expect(recent.count == 4)
    }

    @Test("at most 10 recent launches")
    func cap() {
        var recent: [LaunchRecipe] = []
        for i in 0..<15 { recent = LaunchHistory.recording(recipe("task \(i)"), in: recent) }
        #expect(recent.count == LaunchHistory.maxRecent)
        #expect(recent.first?.task == "task 14")
        #expect(recent.last?.task == "task 5")
    }

    @Test("menu title: tool · folder name · first 40 characters of the task")
    func menuTitle() {
        let long = String(repeating: "x", count: 50)
        #expect(recipe(long).menuTitle(toolTitle: "Claude Code") == "Claude Code · a · \(String(repeating: "x", count: 39))…")
        #expect(recipe("line one\nline two").menuTitle(toolTitle: "Codex") == "Codex · a · line one line two")
        #expect(recipe("").menuTitle(toolTitle: "Codex") == "Codex · a · (no task)")
    }

    @Test("presets: a name is required, at most 20, rename / delete / move")
    func presets() throws {
        var presets: [LaunchPreset] = []
        #expect(LaunchHistory.adding(name: "  ", recipe: recipe("a"), to: presets) == nil)
        presets = try #require(LaunchHistory.adding(name: " Review X ", recipe: recipe("a"), to: presets))
        #expect(presets.map(\.name) == ["Review X"])
        for i in 1..<25 {
            if let next = LaunchHistory.adding(name: "p\(i)", recipe: recipe("t\(i)"), to: presets) { presets = next }
        }
        #expect(presets.count == LaunchHistory.maxPresets)
        #expect(LaunchHistory.adding(name: "one more", recipe: recipe("z"), to: presets) == nil)

        let id = presets[1].id
        presets = LaunchHistory.renaming(id, to: "Tests", in: presets)
        #expect(presets[1].name == "Tests")
        #expect(LaunchHistory.renaming(id, to: " ", in: presets)[1].name == "Tests")
        presets = LaunchHistory.moving(id, by: -1, in: presets)
        #expect(presets[0].id == id)
        #expect(LaunchHistory.moving(id, by: -1, in: presets)[0].id == id)
        presets = LaunchHistory.deleting(id, from: presets)
        #expect(!presets.contains { $0.id == id })
    }

    @Test("restoring: a folder that's gone is left empty, with a note")
    func folderGone() {
        let restored = LaunchHistory.restore(recipe("a"), folderExists: { _ in false },
                                             availableOptionIDs: ["builtin:claude"], defaultOptionID: "builtin:claude",
                                             templatesLoaded: true, spaces: nil)
        #expect(restored.recipe.folder == "")
        #expect(restored.notes == ["Folder /p/a no longer exists"])
        #expect(restored.recipe.task == "a")
    }

    @Test("restoring: a herdr template that's gone falls back to the default tool, with a note")
    func templateGone() {
        let restored = LaunchHistory.restore(recipe("a", option: "template:reviewer"), folderExists: { _ in true },
                                             availableOptionIDs: ["builtin:claude", "builtin:codex"], defaultOptionID: "builtin:claude",
                                             templatesLoaded: true, spaces: nil)
        #expect(restored.recipe.optionID == "builtin:claude")
        #expect(restored.notes == ["Template reviewer is no longer available; using the default tool"])
    }

    @Test("restoring: templates that couldn't be loaded aren't called gone; an unknown built-in isn't called a template")
    func templateUnknown() {
        let failed = LaunchHistory.restore(recipe("a", option: "template:reviewer"), folderExists: { _ in true },
                                           availableOptionIDs: ["builtin:claude"], defaultOptionID: "builtin:claude",
                                           templatesLoaded: false, spaces: nil)
        #expect(failed.recipe.optionID == "builtin:claude")
        #expect(failed.notes == ["Couldn't load herdr-core templates; using the default tool"])
        let builtin = LaunchHistory.restore(recipe("a", option: "builtin:gone"), folderExists: { _ in true },
                                            availableOptionIDs: ["builtin:claude"], defaultOptionID: "builtin:claude",
                                            templatesLoaded: true, spaces: nil)
        #expect(builtin.notes == ["That tool is no longer available; using the default tool"])
    }

    @Test("restoring: a space that's gone falls back to the selected space; unknown spaces are left alone")
    func spaceGone() {
        var withSpace = recipe("a")
        withSpace.space = "sp1"
        let gone = LaunchHistory.restore(withSpace, folderExists: { _ in true }, availableOptionIDs: ["builtin:claude"],
                                         defaultOptionID: "builtin:claude", templatesLoaded: true, spaces: ["sp2"])
        #expect(gone.recipe.space == "")
        #expect(gone.notes == ["That space no longer exists; using the selected space"])
        let unknown = LaunchHistory.restore(withSpace, folderExists: { _ in true }, availableOptionIDs: ["builtin:claude"],
                                            defaultOptionID: "builtin:claude", templatesLoaded: true, spaces: nil)
        #expect(unknown.recipe.space == "sp1")
    }

    @Test("template names come out of option ids")
    func templateName() {
        #expect(LaunchHistory.templateName(of: "template:reviewer") == "reviewer")
        #expect(LaunchHistory.templateName(of: "builtin:claude") == nil)
    }

    @Test("restoring: everything still there comes back unchanged, worktree wish included")
    func unchanged() {
        let original = recipe("a", worktree: true)
        let restored = LaunchHistory.restore(original, folderExists: { _ in true },
                                             availableOptionIDs: ["builtin:claude"], defaultOptionID: "builtin:claude",
                                             templatesLoaded: true, spaces: nil)
        #expect(restored.recipe == original)
        #expect(restored.notes.isEmpty)
    }

    @Test("recipes round-trip through JSON for UserDefaults")
    func codable() throws {
        let preset = LaunchPreset(name: "Review", recipe: recipe("a", worktree: true))
        let data = try JSONEncoder().encode([preset])
        #expect(try JSONDecoder().decode([LaunchPreset].self, from: data) == [preset])
    }

    @Test("a new space comes back as New space with its name, survives restore, round-trips; old recipes have none")
    func newSpace() throws {
        var named = recipe("a")
        named.newSpaceName = "review"
        #expect(named.spaceChoice == .new)
        var unnamed = recipe("a")
        unnamed.newSpaceName = ""
        #expect(unnamed.spaceChoice == .new)
        var existing = recipe("a")
        existing.space = "sp1"
        #expect(existing.spaceChoice == .existing("sp1"))
        #expect(recipe("a").spaceChoice == .selected)

        let restored = LaunchHistory.restore(named, folderExists: { _ in true }, availableOptionIDs: ["builtin:claude"],
                                             defaultOptionID: "builtin:claude", templatesLoaded: true, spaces: ["sp2"])
        #expect(restored.recipe == named)
        #expect(restored.notes.isEmpty)

        let data = try JSONEncoder().encode([named, unnamed])
        #expect(try JSONDecoder().decode([LaunchRecipe].self, from: data) == [named, unnamed])
        let old = #"{"optionID":"builtin:claude","folder":"/p","task":"t","name":"","space":"sp1","worktree":false}"#
        let decoded = try JSONDecoder().decode(LaunchRecipe.self, from: Data(old.utf8))
        #expect(decoded.newSpaceName == nil)
        #expect(decoded.spaceChoice == .existing("sp1"))
    }
}

@MainActor
@Suite("Launch history: what counts as launched")
struct LaunchSucceededTests {
    @Test("Launched and unconfirmed report success once; failures report failure, worktree failures included")
    func outcomes() async {
        let h = Harness()
        h.connect()
        h.store.herdrAppRunning = true
        var outcomes: [Bool] = []
        h.store.onLaunchFinished = { outcomes.append($0) }
        h.store.launch(LaunchRequest(argv: ["claude"], folder: "/p", task: "go"))
        await settle()
        // Started; the agent reporting Working makes it Launched.
        h.client.emit(.event(seq: 11, .created(term("t9"))))
        h.status("t9", "working", seq: 12)
        #expect(outcomes == [true])
        h.status("t9", "done", seq: 13)
        #expect(outcomes == [true])

        h.client.launchResult = .failure(HerdrError(kind: "spawn_failed", message: "nope"))
        h.store.launch(LaunchRequest(argv: ["claude"], folder: "/p", task: "go"))
        await settle()
        #expect(outcomes == [true, false])

        h.client.launchResult = .success(LaunchOutput(terminal: "t8"))
        h.store.launch(LaunchRequest(argv: ["claude"], folder: "/p", task: "go"))
        await settle()
        h.scheduler.advance(by: h.store.timing.launchConfirmWindow + 1)
        if case .unconfirmed = h.store.launchState {} else { Issue.record("expected unconfirmed, got \(h.store.launchState)") }
        #expect(outcomes == [true, false, true])

        // No worktree creator: the worktree step fails before anything starts.
        let source = WorktreeSource(toplevel: "/p", head: "abc", dirty: false)
        h.store.launch(LaunchRequest(argv: ["claude"], folder: "/p", task: "go"),
                       worktree: WorktreePlan.make(source: source, branch: "atoll/x", folder: "/p", exists: { _ in false }))
        #expect(outcomes == [true, false, true, false])
    }
}
