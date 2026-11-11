import Foundation

/// What a finished turn changed in its project's git working tree: `+120 −30 · 6 files`.
/// Computed from git only; never from the terminal screen.
public struct ChangeSummary: Equatable, Sendable {
    public enum Baseline: Equatable, Sendable {
        /// Diffed against the tree as the turn started (exact for tracked files).
        case turnStart
        /// The tree already had uncommitted edits when the turn started; they are included.
        case turnStartDirty
        /// No baseline (Atoll started mid-turn, or the agent moved to another repo): uncommitted changes vs HEAD.
        case head
    }

    public var insertions: Int
    public var deletions: Int
    /// Tracked files changed (from `git diff --shortstat`).
    public var files: Int
    /// Untracked files that appeared during the turn; with a `.head` baseline, all untracked files.
    public var untracked: Int
    public var baseline: Baseline
    /// The working tree's top-level directory.
    public var toplevel: String
    /// Another agent was in the same working tree, so the changes can't be attributed to this one.
    public var sharedTree = false

    public init(insertions: Int, deletions: Int, files: Int, untracked: Int, baseline: Baseline, toplevel: String, sharedTree: Bool = false) {
        self.insertions = insertions
        self.deletions = deletions
        self.files = files
        self.untracked = untracked
        self.baseline = baseline
        self.toplevel = toplevel
        self.sharedTree = sharedTree
    }

    public var isEmpty: Bool { files == 0 && untracked == 0 }

    /// The numbers only: "+120 −30 · 6 files · 2 new", or "no changes".
    public var text: String {
        guard !isEmpty else { return "no changes" }
        var parts: [String] = []
        if files > 0 {
            parts.append("+\(insertions) −\(deletions)")
            parts.append(files == 1 ? "1 file" : "\(files) files")
        }
        if untracked > 0 {
            parts.append(baseline == .head ? "\(untracked) untracked" : "\(untracked) new")
        }
        return parts.joined(separator: " · ")
    }

    /// Why the numbers may not be this turn's alone.
    public var caveats: [String] {
        var list: [String] = []
        switch baseline {
        case .turnStart: break
        case .turnStartDirty: list.append("incl. earlier edits")
        case .head: list.append("uncommitted")
        }
        if sharedTree { list.append("shared tree") }
        return list
    }

    public var label: String { ([text] + caveats).joined(separator: " · ") }

    public var help: String {
        var lines: [String]
        switch baseline {
        case .turnStart: lines = ["Changes in \(toplevel) since this turn started, including commits."]
        case .turnStartDirty: lines = ["Changes in \(toplevel) since the commit this turn started on; the tree already had uncommitted edits then, and they are included."]
        case .head: lines = ["Uncommitted changes in \(toplevel): Atoll didn't see this turn start."]
        }
        if sharedTree { lines.append("Another agent works in the same tree, so not all of this may be this agent's.") }
        return lines.joined(separator: "\n")
    }

    /// Parses `git diff --shortstat`: " 3 files changed, 10 insertions(+), 4 deletions(-)"; empty = nothing.
    public static func parseShortstat(_ text: String) -> (files: Int, insertions: Int, deletions: Int) {
        var result = (files: 0, insertions: 0, deletions: 0)
        for part in text.split(separator: ",") {
            let words = part.split(separator: " ")
            guard let first = words.first, let n = Int(first), words.count > 1 else { continue }
            let word = words[1]
            if word.hasPrefix("file") { result.files = n }
            else if word.hasPrefix("insertion") { result.insertions = n }
            else if word.hasPrefix("deletion") { result.deletions = n }
        }
        return result
    }
}

/// The working tree as a turn started.
public struct TurnBaseline: Equatable, Sendable {
    public var toplevel: String
    public var head: String
    /// Tracked files already had uncommitted changes.
    public var dirty: Bool
    public var untracked: Set<String>

    public init(toplevel: String, head: String, dirty: Bool, untracked: Set<String>) {
        self.toplevel = toplevel
        self.head = head
        self.dirty = dirty
        self.untracked = untracked
    }
}

/// Captures turn baselines and computes summaries. nil means "no summary" (not a repo, git missing,
/// timed out…): the UI shows nothing rather than an error.
public protocol ChangeProbing: Sendable {
    func baseline(in directory: String) async -> TurnBaseline?
    func summary(in directory: String, since baseline: TurnBaseline?) async -> ChangeSummary?
}

/// Which git working tree a directory belongs to; nil when it isn't in one (or git failed).
public protocol WorkingTreeProbing: Sendable {
    func toplevel(in directory: String) async -> String?
}

/// Runs one git command in a directory; nil on failure, nonzero exit or timeout.
public protocol GitRunner: Sendable {
    func run(_ arguments: [String], in directory: String) async -> String?
}

public struct GitProbe: ChangeProbing, WorkingTreeProbing {
    private let runner: GitRunner

    public init(runner: GitRunner = ProcessGitRunner()) {
        self.runner = runner
    }

    public func baseline(in directory: String) async -> TurnBaseline? {
        guard let toplevel = await toplevel(directory),
              let head = await head(directory),
              let status = await runner.run(["status", "--porcelain", "--untracked-files=no"], in: directory),
              let untracked = await untracked(directory) else { return nil }
        return TurnBaseline(toplevel: toplevel, head: head, dirty: !status.isEmpty, untracked: untracked)
    }

    public func summary(in directory: String, since baseline: TurnBaseline?) async -> ChangeSummary? {
        guard let toplevel = await toplevel(directory) else { return nil }
        // The agent may have moved to another repo mid-turn: its old baseline means nothing here.
        let base = baseline?.toplevel == toplevel ? baseline : nil
        let from: String
        if let base {
            from = base.head
        } else {
            guard let head = await head(directory) else { return nil }
            from = head
        }
        guard let stat = await runner.run(["diff", "--no-ext-diff", "--no-textconv", "--shortstat", from], in: directory),
              let untracked = await untracked(directory) else { return nil }
        let counts = ChangeSummary.parseShortstat(stat)
        return ChangeSummary(
            insertions: counts.insertions,
            deletions: counts.deletions,
            files: counts.files,
            untracked: base.map { untracked.subtracting($0.untracked).count } ?? untracked.count,
            baseline: base == nil ? .head : base!.dirty ? .turnStartDirty : .turnStart,
            toplevel: toplevel
        )
    }

    public func toplevel(in directory: String) async -> String? {
        await toplevel(directory)
    }

    private func toplevel(_ directory: String) async -> String? {
        nonEmpty(await runner.run(["rev-parse", "--show-toplevel"], in: directory))
    }

    /// nil in a repo without commits yet.
    private func head(_ directory: String) async -> String? {
        nonEmpty(await runner.run(["rev-parse", "--verify", "--quiet", "HEAD"], in: directory))
    }

    private func untracked(_ directory: String) async -> Set<String>? {
        guard let out = await runner.run(["ls-files", "--others", "--exclude-standard", "-z"], in: directory) else { return nil }
        return Set(out.split(separator: "\0").map(String.init))
    }

    private func nonEmpty(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }
}

/// Runs the real git binary. Skips `/usr/bin/git`: without developer tools that shim pops an
/// install dialog instead of failing.
public struct ProcessGitRunner: GitRunner {
    public static let candidates = [
        "/opt/homebrew/bin/git",
        "/usr/local/bin/git",
        "/Library/Developer/CommandLineTools/usr/bin/git",
        "/Applications/Xcode.app/Contents/Developer/usr/bin/git",
    ]

    public let gitPath: String?
    public let timeout: TimeInterval

    /// The directory is whatever an agent works in, possibly an untrusted checkout: turn off every
    /// config hook that runs a command (fsmonitor, external diff, pager, hooks), the user-level attributes
    /// file, and embedded bare repos. Filter drivers are disabled per run (see `filterOverrides`).
    /// With `--no-optional-locks` (prepended), it also never takes the index lock an agent's own git needs.
    public static let hardening = [
        "-c", "core.fsmonitor=false",
        "-c", "core.hooksPath=/dev/null",
        "-c", "core.pager=cat",
        "-c", "core.attributesFile=/dev/null",
        "-c", "diff.external=",
        "-c", "safe.bareRepository=explicit",
    ]

    public init(timeout: TimeInterval = 2) {
        gitPath = Self.candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
        self.timeout = timeout
    }

    public func run(_ arguments: [String], in directory: String) async -> String? {
        guard let gitPath else { return nil }
        let timeout = timeout
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: Self.runHardened(gitPath, arguments, in: directory, timeout: timeout))
            }
        }
    }

    /// `.gitattributes` in the checkout can route any file through a filter driver whose clean / process
    /// command `status` and `diff` run while hashing modified files. A driver only runs if some config
    /// defines it, so every defined one is blanked out. If they can't be listed, nothing runs.
    static func filterOverrides(_ configKeys: String) -> [String] {
        var names: [String] = []
        for key in configKeys.split(whereSeparator: \.isNewline) {
            // filter.<name>.<variable>; the name itself may contain dots.
            guard key.hasPrefix("filter."), let lastDot = key.lastIndex(of: "."), lastDot > key.index(key.startIndex, offsetBy: 6) else { continue }
            let name = String(key[key.index(key.startIndex, offsetBy: 7)..<lastDot])
            if !names.contains(name) { names.append(name) }
        }
        return names.flatMap { name in
            ["clean=", "smudge=", "process=", "required=false"].flatMap { ["-c", "filter.\(name).\($0)"] }
        }
    }

    private static func runHardened(_ gitPath: String, _ arguments: [String], in directory: String, timeout: TimeInterval) -> String? {
        let base = ["--no-optional-locks"] + hardening + ["-C", directory]
        // Exit 1 = no filter keys at all.
        guard let listed = execute(gitPath, base + ["config", "--name-only", "--get-regexp", "^filter\\."], timeout: timeout),
              listed.status == 0 || listed.status == 1 else { return nil }
        guard let result = execute(gitPath, base + filterOverrides(listed.output) + arguments, timeout: timeout),
              result.status == 0 else { return nil }
        return result.output
    }

    private final class ProcessBox: @unchecked Sendable {
        let process = Process()
    }

    /// nil when it couldn't start or was killed by the timeout.
    private static func execute(_ gitPath: String, _ arguments: [String], timeout: TimeInterval) -> (status: Int32, output: String)? {
        let box = ProcessBox()
        let process = box.process
        process.executableURL = URL(fileURLWithPath: gitPath)
        process.arguments = arguments
        var env = ProcessInfo.processInfo.environment
        env["GIT_TERMINAL_PROMPT"] = "0"
        env["GIT_OPTIONAL_LOCKS"] = "0"
        env["LC_ALL"] = "C"
        process.environment = env
        let out = Pipe()
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
            if box.process.isRunning { box.process.terminate() }
        }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationReason == .exit else { return nil }
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }
}
