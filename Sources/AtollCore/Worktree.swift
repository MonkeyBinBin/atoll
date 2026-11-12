import Foundation

/// The repo a launch folder sits in, as the form needs it to offer "New worktree".
public struct WorktreeSource: Equatable, Sendable {
    /// The working tree's top level (as git reports it, symlinks resolved).
    public var toplevel: String
    public var head: String
    /// Tracked files have uncommitted changes, which a new worktree won't carry.
    public var dirty: Bool

    public init(toplevel: String, head: String, dirty: Bool) {
        self.toplevel = toplevel
        self.head = head
        self.dirty = dirty
    }

    public var shortHead: String { String(head.prefix(7)) }
}

/// A worktree about to be created for a launch.
public struct WorktreePlan: Equatable, Sendable {
    public var source: WorktreeSource
    public var branch: String
    public var path: String
    /// Where the agent starts: the same subdirectory of the new worktree the user picked in the repo.
    public var launchFolder: String

    public init(source: WorktreeSource, branch: String, path: String, launchFolder: String) {
        self.source = source
        self.branch = branch
        self.path = path
        self.launchFolder = launchFolder
    }

    /// `<repo parent>/<repo name>.worktrees/<slug>`, outside the repo so it never shows up in its status;
    /// "-2", "-3"… when taken. `folder` is what the user picked (maybe a subdirectory of the repo).
    public static func make(source: WorktreeSource, branch: String, folder: String,
                            exists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) -> WorktreePlan {
        let repo = URL(fileURLWithPath: source.toplevel)
        let container = repo.deletingLastPathComponent().appendingPathComponent(repo.lastPathComponent + ".worktrees")
        let leaf = WorktreeNaming.slug(String(branch.split(separator: "/").last ?? Substring(branch)))
        var path = container.appendingPathComponent(leaf).path
        var n = 2
        while exists(path) {
            path = container.appendingPathComponent("\(leaf)-\(n)").path
            n += 1
        }
        let relative = WorktreeNaming.relativePath(of: folder, in: source.toplevel)
        let launchFolder = relative.isEmpty ? path : URL(fileURLWithPath: path).appendingPathComponent(relative).path
        return WorktreePlan(source: source, branch: branch, path: path, launchFolder: launchFolder)
    }
}

public enum WorktreeNaming {
    /// "Fix login bug!" → "fix-login-bug"; only a-z 0-9 and "-", at most 40 characters; "agent" if nothing is left
    /// (e.g. an all-Chinese task).
    public static func slug(_ text: String, maxLength: Int = 40) -> String {
        var out = ""
        for char in text.lowercased() {
            if char.isASCII, char.isLetter || char.isNumber {
                out.append(char)
            } else if !out.isEmpty, out.last != "-" {
                out.append("-")
            }
            if out.count >= maxLength { break }
        }
        while out.last == "-" { out.removeLast() }
        return out.isEmpty ? "agent" : out
    }

    /// The form's default: from the display name, else the task's first words.
    public static func defaultBranch(name: String, task: String) -> String {
        let base = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? task.split(whereSeparator: \.isWhitespace).prefix(5).joined(separator: " ")
            : name
        return "atoll/" + slug(base)
    }

    /// `folder` relative to `root` after resolving symlinks ("" for the root itself or anything outside it).
    static func relativePath(of folder: String, in root: String) -> String {
        let resolvedRoot = URL(fileURLWithPath: root).resolvingSymlinksInPath().standardizedFileURL.path
        let resolved = URL(fileURLWithPath: folder).resolvingSymlinksInPath().standardizedFileURL.path
        let prefix = resolvedRoot.hasSuffix("/") ? resolvedRoot : resolvedRoot + "/"
        guard resolved.hasPrefix(prefix) else { return "" }
        return String(resolved.dropFirst(prefix.count))
    }
}

/// Inspects a launch folder and creates worktrees. The only git writes Atoll makes.
public protocol WorktreeCreating: Sendable {
    /// nil when the folder isn't in a repo with at least one commit.
    func source(for folder: String) async -> WorktreeSource?
    /// Creates the branch and worktree; on failure, a message for the user (git's own when it has one).
    func create(_ plan: WorktreePlan) async -> Result<Void, WorktreeError>
}

public struct WorktreeError: Error, Equatable, Sendable {
    public var message: String
    public init(_ message: String) { self.message = message }
}

/// `git worktree add` with the same hardening as the read-only probes: hooks (post-checkout included),
/// fsmonitor and filter drivers don't run. Git LFS files therefore come out as pointer files.
public struct GitWorktreeCreator: WorktreeCreating {
    private let runner: GitRunner
    private let createRunner: GitRunner

    /// Checkout of a big repo takes a while: creating gets a longer timeout than the quick queries.
    public init(runner: GitRunner = ProcessGitRunner(), createRunner: GitRunner = ProcessGitRunner(timeout: 30)) {
        self.runner = runner
        self.createRunner = createRunner
    }

    public func source(for folder: String) async -> WorktreeSource? {
        guard let toplevel = trimmed(await runner.run(["rev-parse", "--show-toplevel"], in: folder)),
              let head = trimmed(await runner.run(["rev-parse", "--verify", "--quiet", "HEAD"], in: folder)),
              let status = await runner.run(["status", "--porcelain", "--untracked-files=no"], in: folder) else { return nil }
        return WorktreeSource(toplevel: toplevel, head: head, dirty: !status.isEmpty)
    }

    public func create(_ plan: WorktreePlan) async -> Result<Void, WorktreeError> {
        let repo = plan.source.toplevel
        guard let format = await runner.runCapturing(["check-ref-format", "--branch", plan.branch], in: repo) else {
            return .failure(WorktreeError("Couldn't run git"))
        }
        guard format.status == 0 else { return .failure(WorktreeError("\"\(plan.branch)\" isn't a valid branch name")) }
        if await runner.run(["rev-parse", "--verify", "--quiet", "refs/heads/\(plan.branch)"], in: repo) != nil {
            return .failure(WorktreeError("Branch \(plan.branch) already exists — pick another name"))
        }
        guard !FileManager.default.fileExists(atPath: plan.path) else {
            return .failure(WorktreeError("\(plan.path) already exists"))
        }
        guard let result = await createRunner.runCapturing(
            ["worktree", "add", "-b", plan.branch, plan.path, plan.source.head], in: repo
        ) else {
            return .failure(WorktreeError("git worktree add didn't finish in time"))
        }
        guard result.status == 0 else {
            let message = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return .failure(WorktreeError(message.isEmpty ? "git worktree add failed (exit \(result.status))" : message))
        }
        return .success(())
    }

    private func trimmed(_ text: String?) -> String? {
        guard let value = text?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }
}
