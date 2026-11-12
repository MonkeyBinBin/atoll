import Foundation
import Testing
@testable import AtollCore

@Suite("Turn changes: parsing")
struct TurnChangesParsingTests {
    @Test("numstat -z: plain, rename (empty path then old / new), binary")
    func numstat() {
        let text = "3\t1\tSources/a.swift\0" + "2\t0\t\0old/b.swift\0new/b.swift\0" + "-\t-\tlogo.png\0" + "0\t4\tgone.txt\0"
        let parsed = GitProbe.parseNumstat(text)
        #expect(parsed.count == 4)
        #expect(parsed[0].path == "Sources/a.swift" && parsed[0].insertions == 3 && parsed[0].deletions == 1 && parsed[0].from == nil)
        #expect(parsed[1].path == "new/b.swift" && parsed[1].from == "old/b.swift" && parsed[1].insertions == 2)
        #expect(parsed[2].path == "logo.png" && parsed[2].insertions == nil && parsed[2].deletions == nil)
    }

    @Test("paths with tabs, spaces and arrows survive -z")
    func oddPaths() {
        let parsed = GitProbe.parseNumstat("1\t1\tweird\tname => x.txt\0")
        #expect(parsed.first?.path == "weird\tname => x.txt")
    }

    @Test("name-status -z: M / A / D / R100 / C")
    func nameStatus() {
        let kinds = GitProbe.parseNameStatus("M\0a.swift\0A\0added.swift\0D\0gone.txt\0R100\0old/b.swift\0new/b.swift\0C75\0src.c\0copy.c\0")
        #expect(kinds["a.swift"] == .modified)
        #expect(kinds["added.swift"] == .added)
        #expect(kinds["gone.txt"] == .deleted)
        #expect(kinds["new/b.swift"] == .renamed(from: "old/b.swift"))
        #expect(kinds["copy.c"] == .added)
    }

    @Test("merge: kinds from name-status, counts from numstat")
    func merge() {
        let files = GitProbe.merge(
            numstat: GitProbe.parseNumstat("0\t4\tgone.txt\0-\t-\tlogo.png\0"),
            kinds: ["gone.txt": .deleted, "logo.png": .added]
        )
        #expect(files == [
            ChangedFile(path: "gone.txt", kind: .deleted, insertions: 0, deletions: 4),
            ChangedFile(path: "logo.png", kind: .added),
        ])
        #expect(files[1].isBinary && !files[1].hasDiff)
        #expect(!ChangedFile(path: "n.txt", kind: .untracked).hasDiff)
        #expect(!ChangedFile(path: "n.txt", kind: .untracked).isBinary)
    }

    @Test("diff: git's header is dropped, hunks kept")
    func diffHeader() {
        let text = "diff --git a/a.txt b/a.txt\nindex 1..2 100644\n--- a/a.txt\n+++ b/a.txt\n@@ -1,2 +1,2 @@\n a\n-b\n+B\n"
        #expect(FileDiff.parse(text) == FileDiff(lines: ["@@ -1,2 +1,2 @@", " a", "-b", "+B"]))
    }

    @Test("diff: cut after maxLines, counting what was left out")
    func diffCut() {
        let text = "@@ -1 +1 @@\n" + (0..<700).map { "+\($0)" }.joined(separator: "\n") + "\n"
        let diff = FileDiff.parse(text)
        #expect(diff.lines.count == FileDiff.maxLines)
        #expect(diff.omitted == 701 - FileDiff.maxLines)
    }
}

@Suite("Turn changes: git probe")
struct TurnChangesProbeTests {
    let summary = ChangeSummary(insertions: 5, deletions: 1, files: 2, untracked: 1, baseline: .turnStart,
                                toplevel: "/repo", baseCommit: "abc123", newFiles: ["notes.md"])

    @Test("files: diffed from the summary's base commit, untracked new files appended, sorted")
    func files() async throws {
        let runner = FakeGitRunner()
        runner.outputs = [
            "diff --no-ext-diff --no-textconv --no-color -M -z --numstat abc123": "4\t1\tz.swift\0" + "1\t0\t\0a.swift\0b.swift\0",
            "diff --no-ext-diff --no-textconv --no-color -M -z --name-status abc123": "M\0z.swift\0R090\0a.swift\0b.swift\0",
        ]
        let files = try #require(await GitProbe(runner: runner).files(for: summary))
        #expect(files == [
            ChangedFile(path: "b.swift", kind: .renamed(from: "a.swift"), insertions: 1, deletions: 0),
            ChangedFile(path: "notes.md", kind: .untracked),
            ChangedFile(path: "z.swift", kind: .modified, insertions: 4, deletions: 1),
        ])
    }

    @Test("diff of a rename asks for both paths")
    func renameDiff() async throws {
        let runner = FakeGitRunner()
        runner.outputs["diff --no-ext-diff --no-textconv --no-color -M abc123 -- a.swift b.swift"] = "@@ -1 +1 @@\n-x\n+y\n"
        let diff = await GitProbe(runner: runner).diff(of: ChangedFile(path: "b.swift", kind: .renamed(from: "a.swift"), insertions: 1, deletions: 1), for: summary)
        #expect(diff?.lines == ["@@ -1 +1 @@", "-x", "+y"])
    }

    @Test("failures and things without a diff give nil, without running git for the latter")
    func failures() async {
        let runner = FakeGitRunner()
        let probe = GitProbe(runner: runner)
        #expect(await probe.files(for: summary) == nil)
        var noBase = summary
        noBase.baseCommit = ""
        #expect(await probe.files(for: noBase) == nil)
        let before = runner.calls.count
        #expect(await probe.diff(of: ChangedFile(path: "n.md", kind: .untracked), for: summary) == nil)
        #expect(await probe.diff(of: ChangedFile(path: "logo.png", kind: .modified), for: summary) == nil)
        #expect(runner.calls.count == before)
    }
}

@Suite("Turn changes: opening files")
struct ChangedFileURLTests {
    func tree() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("atoll-open-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("src"), withIntermediateDirectories: true)
        try "x".write(to: dir.appendingPathComponent("src/a.swift"), atomically: true, encoding: .utf8)
        return dir
    }

    @Test("a file inside the tree opens")
    func inside() throws {
        let dir = try tree()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = ChangedFile(path: "src/a.swift", kind: .modified).fileURL(in: dir.path)
        #expect(url?.lastPathComponent == "a.swift")
    }

    @Test("escapes, absolute paths, deleted and missing files don't")
    func refused() throws {
        let dir = try tree()
        defer { try? FileManager.default.removeItem(at: dir) }
        let outside = FileManager.default.temporaryDirectory.appendingPathComponent("atoll-outside-\(UUID().uuidString)")
        try "secret".write(to: outside, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: outside) }
        try FileManager.default.createSymbolicLink(at: dir.appendingPathComponent("link"), withDestinationURL: outside)
        for file in [
            ChangedFile(path: "../\(outside.lastPathComponent)", kind: .modified),
            ChangedFile(path: "src/../../\(outside.lastPathComponent)", kind: .modified),
            ChangedFile(path: outside.path, kind: .modified),
            ChangedFile(path: "link", kind: .added),
            ChangedFile(path: "src/a.swift", kind: .deleted),
            ChangedFile(path: "missing.swift", kind: .modified),
        ] {
            #expect(file.fileURL(in: dir.path) == nil, "\(file.path)")
        }
    }
}

final class FakeInspector: ChangeInspecting, @unchecked Sendable {
    var filesResult: [ChangedFile]? = [
        ChangedFile(path: "a.swift", kind: .modified, insertions: 1, deletions: 0),
        ChangedFile(path: "new.md", kind: .untracked),
    ]
    var diffResult: FileDiff? = FileDiff(lines: ["@@ -1 +1 @@", "+x"])
    private(set) var fileCalls = 0
    private(set) var diffCalls: [String] = []

    func files(for summary: ChangeSummary) async -> [ChangedFile]? {
        fileCalls += 1
        return filesResult
    }

    func diff(of file: ChangedFile, for summary: ChangeSummary) async -> FileDiff? {
        diffCalls.append(file.path)
        return diffResult
    }
}

@MainActor
@Suite("Turn changes: panel")
struct PanelChangesTests {
    func finishedTurn() async -> (Harness, FakeInspector) {
        let h = Harness()
        h.store.changeProbe = FakeProbe()
        let inspector = FakeInspector()
        h.store.changeInspector = inspector
        h.connect([term("t1", "idle")])
        h.status("t1", "working", seq: 11)
        h.status("t1", "done", seq: 12)
        await settle()
        h.store.openPanel("t1")
        return (h, inspector)
    }

    @Test("showing the changes lists the files only when asked")
    func show() async throws {
        let (h, inspector) = await finishedTurn()
        #expect(inspector.fileCalls == 0)
        h.store.showChanges()
        #expect(h.store.panel?.changes?.files == .loading)
        await settle()
        #expect(inspector.fileCalls == 1)
        guard case .loaded(let files) = h.store.panel?.changes?.files else { Issue.record("not loaded"); return }
        #expect(files.map(\.path) == ["a.swift", "new.md"])
    }

    @Test("a failed listing says so; hide goes back to output")
    func failure() async {
        let (h, inspector) = await finishedTurn()
        inspector.filesResult = nil
        h.store.showChanges()
        await settle()
        #expect(h.store.panel?.changes?.files == .failed)
        h.store.hideChanges()
        #expect(h.store.panel?.changes == nil)
    }

    @Test("a file's diff loads on first expand only; collapsing keeps it")
    func diffOnce() async throws {
        let (h, inspector) = await finishedTurn()
        h.store.showChanges()
        await settle()
        let file = ChangedFile(path: "a.swift", kind: .modified, insertions: 1, deletions: 0)
        h.store.toggleDiff(file)
        await settle()
        #expect(h.store.panel?.changes?.diffs["a.swift"] == .loaded(FileDiff(lines: ["@@ -1 +1 @@", "+x"])))
        h.store.toggleDiff(file)
        #expect(h.store.panel?.changes?.expanded.isEmpty == true)
        h.store.toggleDiff(file)
        await settle()
        #expect(inspector.diffCalls == ["a.swift"])
        // Untracked files have no diff to load.
        h.store.toggleDiff(ChangedFile(path: "new.md", kind: .untracked))
        #expect(inspector.diffCalls == ["a.swift"])
    }

    @Test("closing the panel drops everything; a new turn closes the view")
    func dropped() async {
        let (h, _) = await finishedTurn()
        h.store.showChanges()
        await settle()
        h.store.closePanel()
        h.store.openPanel("t1")
        #expect(h.store.panel?.changes == nil)
        h.store.showChanges()
        await settle()
        #expect(h.store.panel?.changes != nil)
        h.status("t1", "working", seq: 13)
        #expect(h.store.panel?.changes == nil)
    }

    @Test("a listing that comes back after the panel moved on is discarded")
    func late() async {
        let (h, _) = await finishedTurn()
        h.store.showChanges()
        h.store.closePanel()
        await settle()
        #expect(h.store.panel == nil)
    }

    @Test("no inspector (setting off) or no summary: nothing to show")
    func unavailable() async {
        let (h, _) = await finishedTurn()
        h.store.changeInspector = nil
        h.store.showChanges()
        #expect(h.store.panel?.changes == nil)
    }
}

struct RealTurnChangesTests {
    @Test("a turn in a temporary repo: commit, edit, rename, delete, new file", .enabled(if: ProcessGitRunner().gitPath != nil))
    func temporaryRepo() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("atoll-diff-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let runner = ProcessGitRunner()
        let path = dir.path
        for args in [["init", "-q"], ["config", "user.email", "t@example.com"], ["config", "user.name", "t"]] {
            _ = await runner.run(args, in: path)
        }
        try "a\nb\n".write(to: dir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try "one\ntwo\nthree\nfour\n".write(to: dir.appendingPathComponent("old.txt"), atomically: true, encoding: .utf8)
        try "bye\n".write(to: dir.appendingPathComponent("gone.txt"), atomically: true, encoding: .utf8)
        _ = await runner.run(["add", "."], in: path)
        _ = await runner.run(["commit", "-qm", "init"], in: path)

        let probe = GitProbe(runner: runner)
        let base = try #require(await probe.baseline(in: path))
        // The "agent": commits an edit, then renames, deletes and adds without committing.
        try "a\nB\n".write(to: dir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        _ = await runner.run(["commit", "-qam", "edit"], in: path)
        _ = await runner.run(["mv", "old.txt", "renamed.txt"], in: path)
        _ = await runner.run(["rm", "-q", "gone.txt"], in: path)
        try "new\n".write(to: dir.appendingPathComponent("new.txt"), atomically: true, encoding: .utf8)
        let summary = try #require(await probe.summary(in: path, since: base))
        #expect(summary.newFiles == ["new.txt"])

        let files = try #require(await probe.files(for: summary))
        #expect(files.map(\.path) == ["a.txt", "gone.txt", "new.txt", "renamed.txt"])
        #expect(files[0] == ChangedFile(path: "a.txt", kind: .modified, insertions: 1, deletions: 1))
        #expect(files[1].kind == .deleted)
        #expect(files[2].kind == .untracked)
        #expect(files[3].kind == .renamed(from: "old.txt"))
        let diff = try #require(await probe.diff(of: files[0], for: summary))
        #expect(diff.lines == ["@@ -1,2 +1,2 @@", " a", "-b", "+B"])
        #expect(files[3].fileURL(in: summary.toplevel) != nil)
        #expect(files[1].fileURL(in: summary.toplevel) == nil)
    }
}
