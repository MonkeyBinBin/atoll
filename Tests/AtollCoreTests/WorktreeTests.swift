import Foundation
import Testing
@testable import AtollCore

@Suite("Worktree: naming and location")
struct WorktreeNamingTests {
    @Test("slugs", arguments: [
        ("Fix login bug!", "fix-login-bug"),
        ("  --a--b-- ", "a-b"),
        ("修正登入流程", "agent"),
        ("修正 login 錯誤", "login"),
        ("Refactor API v2", "refactor-api-v2"),
        ("", "agent"),
    ])
    func slug(text: String, expected: String) {
        #expect(WorktreeNaming.slug(text) == expected)
    }

    @Test("slugs are capped and never end with a dash")
    func cap() {
        let slug = WorktreeNaming.slug(String(repeating: "abc ", count: 30))
        #expect(slug.count <= 40)
        #expect(!slug.hasSuffix("-"))
    }

    @Test("default branch: display name first, else the task's first words")
    func defaultBranch() {
        #expect(WorktreeNaming.defaultBranch(name: "Login fix", task: "whatever") == "atoll/login-fix")
        #expect(WorktreeNaming.defaultBranch(name: " ", task: "Add dark mode to the settings page please now") == "atoll/add-dark-mode-to-the")
        #expect(WorktreeNaming.defaultBranch(name: "", task: "") == "atoll/agent")
    }

    let source = WorktreeSource(toplevel: "/Users/me/Projects/app", head: "abcdef1234567890", dirty: false)

    @Test("the worktree goes next to the repo, never inside it; taken names get a number")
    func location() {
        let plan = WorktreePlan.make(source: source, branch: "atoll/login-fix", folder: "/Users/me/Projects/app") { _ in false }
        #expect(plan.path == "/Users/me/Projects/app.worktrees/login-fix")
        #expect(plan.launchFolder == plan.path)
        let taken: Set = ["/Users/me/Projects/app.worktrees/login-fix", "/Users/me/Projects/app.worktrees/login-fix-2"]
        let next = WorktreePlan.make(source: source, branch: "atoll/login-fix", folder: "/Users/me/Projects/app") { taken.contains($0) }
        #expect(next.path == "/Users/me/Projects/app.worktrees/login-fix-3")
        #expect(source.shortHead == "abcdef1")
    }

    @Test("a subdirectory of the repo maps to the same subdirectory of the worktree")
    func subdirectory() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("atoll-wt-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("packages/web"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let real = root.resolvingSymlinksInPath().path
        let source = WorktreeSource(toplevel: real, head: "abc", dirty: false)
        // The user's folder may come through a symlink (/var → /private/var) that git resolves.
        let plan = WorktreePlan.make(source: source, branch: "atoll/x", folder: root.appendingPathComponent("packages/web").path) { _ in false }
        #expect(plan.launchFolder == plan.path + "/packages/web")
        let outside = WorktreePlan.make(source: source, branch: "atoll/x", folder: "/somewhere/else") { _ in false }
        #expect(outside.launchFolder == outside.path)
    }
}

/// Scripted git results including stderr; missing = exit 1.
final class FakeCapturingRunner: GitRunner, @unchecked Sendable {
    var results: [String: GitOutput] = [:]
    private(set) var calls: [String] = []

    func run(_ arguments: [String], in directory: String) async -> String? {
        guard let result = await runCapturing(arguments, in: directory), result.status == 0 else { return nil }
        return result.stdout
    }

    func runCapturing(_ arguments: [String], in directory: String) async -> GitOutput? {
        let key = arguments.joined(separator: " ")
        calls.append(key)
        return results[key] ?? GitOutput(status: 1)
    }
}

@Suite("Worktree: git")
struct WorktreeCreatorTests {
    let source = WorktreeSource(toplevel: "/repo", head: "abc123", dirty: true)
    var plan: WorktreePlan { WorktreePlan(source: source, branch: "atoll/x", path: "/nonexistent-\(UUID().uuidString)/x", launchFolder: "/w/x") }

    func runner() -> FakeCapturingRunner {
        let runner = FakeCapturingRunner()
        runner.results["check-ref-format --branch atoll/x"] = GitOutput(status: 0, stdout: "atoll/x\n")
        return runner
    }

    @Test("source: top level, HEAD and whether tracked files are dirty")
    func source() async throws {
        let runner = FakeCapturingRunner()
        runner.results = [
            "rev-parse --show-toplevel": GitOutput(status: 0, stdout: "/repo\n"),
            "rev-parse --verify --quiet HEAD": GitOutput(status: 0, stdout: "abc123\n"),
            "status --porcelain --untracked-files=no": GitOutput(status: 0, stdout: " M a.swift\n"),
        ]
        let found = await GitWorktreeCreator(runner: runner, createRunner: runner).source(for: "/repo/sub")
        #expect(found == WorktreeSource(toplevel: "/repo", head: "abc123", dirty: true))
        // Not a repo, or no commits yet: nothing to offer.
        #expect(await GitWorktreeCreator(runner: FakeCapturingRunner(), createRunner: runner).source(for: "/tmp") == nil)
    }

    @Test("creates the branch from the HEAD the user saw")
    func create() async {
        let runner = runner()
        let plan = plan
        runner.results["worktree add -b atoll/x \(plan.path) abc123"] = GitOutput(status: 0)
        let result = await GitWorktreeCreator(runner: runner, createRunner: runner).create(plan)
        #expect((try? result.get()) != nil)
        #expect(runner.calls.last == "worktree add -b atoll/x \(plan.path) abc123")
    }

    @Test("an existing branch is refused before anything is written")
    func existingBranch() async {
        let runner = runner()
        runner.results["rev-parse --verify --quiet refs/heads/atoll/x"] = GitOutput(status: 0, stdout: "def456\n")
        let result = await GitWorktreeCreator(runner: runner, createRunner: runner).create(plan)
        #expect(result.failureValue == (WorktreeError("Branch atoll/x already exists — pick another name")))
        #expect(!runner.calls.contains { $0.hasPrefix("worktree add") })
    }

    @Test("an invalid branch name is refused")
    func invalidBranch() async {
        let runner = FakeCapturingRunner()
        let result = await GitWorktreeCreator(runner: runner, createRunner: runner).create(plan)
        #expect(result.failureValue == (WorktreeError("\"atoll/x\" isn't a valid branch name")))
    }

    @Test("git's own error message is passed on")
    func gitError() async {
        let runner = runner()
        let plan = plan
        runner.results["worktree add -b atoll/x \(plan.path) abc123"] = GitOutput(status: 128, stderr: "fatal: something broke\n")
        let result = await GitWorktreeCreator(runner: runner, createRunner: runner).create(plan)
        #expect(result.failureValue == (WorktreeError("fatal: something broke")))
    }
}

final class FakeWorktreeCreator: WorktreeCreating, @unchecked Sendable {
    var result: Result<Void, WorktreeError> = .success(())
    private(set) var created: [WorktreePlan] = []

    func source(for folder: String) async -> WorktreeSource? { nil }

    func create(_ plan: WorktreePlan) async -> Result<Void, WorktreeError> {
        created.append(plan)
        return result
    }
}

@MainActor
@Suite("Worktree: launch")
struct WorktreeLaunchTests {
    let plan = WorktreePlan(
        source: WorktreeSource(toplevel: "/p/app", head: "abc", dirty: false),
        branch: "atoll/x", path: "/p/app.worktrees/x", launchFolder: "/p/app.worktrees/x/web"
    )
    let request = LaunchRequest(argv: ["claude"], folder: "/p/app/web", task: "do it")

    func harness() -> (Harness, FakeWorktreeCreator) {
        let h = Harness()
        let creator = FakeWorktreeCreator()
        h.store.worktreeCreator = creator
        h.store.herdrAppRunning = true
        h.connect()
        return (h, creator)
    }

    @Test("creates the worktree, then launches in it")
    func launches() async {
        let (h, creator) = harness()
        var remembered: [String] = []
        h.store.onWorktreeCreated = { remembered.append($0) }
        h.store.launch(request, worktree: plan)
        #expect(h.store.launchState == .creatingWorktree)
        #expect(h.store.launchState.label == "Creating worktree…")
        #expect(h.store.isLaunchBusy)
        await settle()
        #expect(creator.created == [plan])
        var expected = request
        expected.folder = "/p/app.worktrees/x/web"
        #expect(h.client.commands.contains(.launch(expected)))
        #expect(h.store.launchWorktree == "/p/app.worktrees/x")
        #expect(remembered == ["/p/app.worktrees/x/web"])
    }

    @Test("a failed worktree: no launch, git's message shown")
    func worktreeFails() async {
        let (h, creator) = harness()
        creator.result = .failure(WorktreeError("fatal: nope"))
        h.store.launch(request, worktree: plan)
        await settle()
        #expect(h.store.launchState == .failed(HerdrError(kind: "worktree_failed", message: "fatal: nope")))
        #expect(!h.client.commands.contains { if case .launch = $0 { true } else { false } })
        #expect(h.store.launchWorktree == nil)
    }

    @Test("worktree made but the launch fails: the worktree's path stays known")
    func launchFails() async {
        let (h, _) = harness()
        h.client.launchResult = .failure(.unavailable("boom"))
        h.store.launch(request, worktree: plan)
        await settle()
        #expect(h.store.launchState == .failed(.unavailable("boom")))
        #expect(h.store.launchWorktree == "/p/app.worktrees/x")
        h.store.resetLaunch()
        #expect(h.store.launchWorktree == nil)
    }

    @Test("no second launch while the worktree is being made; no creator = failure")
    func guards() async {
        let (h, creator) = harness()
        h.store.launch(request, worktree: plan)
        h.store.launch(request, worktree: plan)
        await settle()
        #expect(creator.created.count == 1)
        let h2 = Harness()
        h2.store.herdrAppRunning = true
        h2.connect()
        h2.store.launch(request, worktree: plan)
        if case .failed = h2.store.launchState {} else { Issue.record("expected failure") }
    }
}

struct RealWorktreeTests {
    @Test("creates a worktree next to a temporary repo without running its hooks", .enabled(if: ProcessGitRunner().gitPath != nil))
    func temporaryRepo() async throws {
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent("atoll-wt-\(UUID().uuidString)")
        let repo = parent.appendingPathComponent("app")
        try FileManager.default.createDirectory(at: repo.appendingPathComponent("web"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: parent) }
        let runner = ProcessGitRunner()
        let path = repo.path
        for args in [["init", "-q"], ["config", "user.email", "t@example.com"], ["config", "user.name", "t"]] {
            _ = await runner.run(args, in: path)
        }
        try "a\n".write(to: repo.appendingPathComponent("web/a.txt"), atomically: true, encoding: .utf8)
        _ = await runner.run(["add", "."], in: path)
        _ = await runner.run(["commit", "-qm", "init"], in: path)
        // Uncommitted edit (not carried over) and a post-checkout hook that would leave a marker.
        try "a\nb\n".write(to: repo.appendingPathComponent("web/a.txt"), atomically: true, encoding: .utf8)
        let marker = parent.appendingPathComponent("hook-ran").path
        let hook = repo.appendingPathComponent(".git/hooks/post-checkout")
        try "#!/bin/sh\ntouch '\(marker)'\n".write(to: hook, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hook.path)

        let creator = GitWorktreeCreator()
        let source = try #require(await creator.source(for: repo.appendingPathComponent("web").path))
        #expect(source.dirty)
        let plan = WorktreePlan.make(source: source, branch: "atoll/try-it", folder: repo.appendingPathComponent("web").path)
        #expect(plan.path.hasSuffix("app.worktrees/try-it"))
        #expect(plan.launchFolder == plan.path + "/web")
        try (await creator.create(plan)).get()

        #expect(try String(contentsOfFile: plan.launchFolder + "/a.txt", encoding: .utf8) == "a\n")
        #expect(await runner.run(["rev-parse", "--abbrev-ref", "HEAD"], in: plan.path)?.trimmingCharacters(in: .whitespacesAndNewlines) == "atoll/try-it")
        #expect(!FileManager.default.fileExists(atPath: marker))
        // The original repo doesn't see the worktree as untracked files.
        #expect(await runner.run(["status", "--porcelain"], in: path) == " M web/a.txt\n")
        // Same branch again: refused.
        let again = WorktreePlan.make(source: source, branch: "atoll/try-it", folder: path)
        #expect(again.path.hasSuffix("try-it-2"))
        #expect(await creator.create(again).failureValue == (WorktreeError("Branch atoll/try-it already exists — pick another name")))
    }
}

extension Result where Success == Void {
    var failureValue: Failure? {
        if case .failure(let error) = self { return error }
        return nil
    }
}
