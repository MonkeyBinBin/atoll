import Foundation

/// One file in a finished turn's changes, from the same baseline as its `ChangeSummary`.
public struct ChangedFile: Equatable, Sendable, Identifiable {
    public enum Kind: Equatable, Sendable {
        case modified
        case added
        case deleted
        case renamed(from: String)
        /// Untracked and new this turn: not in git, so no diff or line counts (its content is never read).
        case untracked
    }

    /// Relative to the working tree's top level; for a rename, the new path.
    public var path: String
    public var kind: Kind
    /// nil for binary files and untracked ones.
    public var insertions: Int?
    public var deletions: Int?

    public var id: String { path }
    public var isBinary: Bool { kind != .untracked && insertions == nil }
    /// Whether a diff can be shown for it.
    public var hasDiff: Bool { kind != .untracked && !isBinary }

    public init(path: String, kind: Kind, insertions: Int? = nil, deletions: Int? = nil) {
        self.path = path
        self.kind = kind
        self.insertions = insertions
        self.deletions = deletions
    }

    /// The file on disk, only if it resolves (symlinks included) to somewhere inside `toplevel`.
    /// nil for deleted files, missing ones, and anything that would escape the tree.
    public func fileURL(in toplevel: String) -> URL? {
        guard kind != .deleted, !path.isEmpty, !path.hasPrefix("/") else { return nil }
        let root = URL(fileURLWithPath: toplevel).resolvingSymlinksInPath().standardizedFileURL.path
        let file = URL(fileURLWithPath: toplevel).appendingPathComponent(path).resolvingSymlinksInPath().standardizedFileURL
        guard file.path.hasPrefix(root.hasSuffix("/") ? root : root + "/"),
              FileManager.default.fileExists(atPath: file.path) else { return nil }
        return file
    }
}

/// One file's diff, cut to `maxLines`.
public struct FileDiff: Equatable, Sendable {
    public var lines: [String]
    /// Lines left out after `maxLines`.
    public var omitted: Int

    public static let maxLines = 500

    public init(lines: [String], omitted: Int = 0) {
        self.lines = lines
        self.omitted = omitted
    }

    /// Drops git's header lines (diff --git, index, ---/+++), keeps hunks, and cuts long diffs.
    public static func parse(_ text: String) -> FileDiff {
        var lines = text.components(separatedBy: "\n")
        if lines.last == "" { lines.removeLast() }
        if let firstHunk = lines.firstIndex(where: { $0.hasPrefix("@@") }) {
            lines.removeFirst(firstHunk)
        }
        guard lines.count > maxLines else { return FileDiff(lines: lines) }
        return FileDiff(lines: Array(lines.prefix(maxLines)), omitted: lines.count - maxLines)
    }
}

/// Lists a turn's changed files and loads one file's diff. nil = couldn't (not a repo, git failed, timed out).
public protocol ChangeInspecting: Sendable {
    func files(for summary: ChangeSummary) async -> [ChangedFile]?
    func diff(of file: ChangedFile, for summary: ChangeSummary) async -> FileDiff?
}

extension GitProbe: ChangeInspecting {
    public func files(for summary: ChangeSummary) async -> [ChangedFile]? {
        guard !summary.baseCommit.isEmpty else { return nil }
        let base = summary.baseCommit
        let directory = summary.toplevel
        let common = ["diff", "--no-ext-diff", "--no-textconv", "--no-color", "-M", "-z"]
        guard let numstat = await runner.run(common + ["--numstat", base], in: directory),
              let nameStatus = await runner.run(common + ["--name-status", base], in: directory) else { return nil }
        var files = Self.merge(numstat: Self.parseNumstat(numstat), kinds: Self.parseNameStatus(nameStatus))
        files += summary.newFiles.map { ChangedFile(path: $0, kind: .untracked) }
        return files.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    public func diff(of file: ChangedFile, for summary: ChangeSummary) async -> FileDiff? {
        guard file.hasDiff, !summary.baseCommit.isEmpty else { return nil }
        var paths = [file.path]
        if case .renamed(let from) = file.kind { paths.insert(from, at: 0) }
        let arguments = ["diff", "--no-ext-diff", "--no-textconv", "--no-color", "-M", summary.baseCommit, "--"] + paths
        guard let text = await runner.run(arguments, in: summary.toplevel) else { return nil }
        return FileDiff.parse(text)
    }

    /// `--numstat -z`: "3\t1\tpath\0", a rename "3\t1\t\0old\0new\0", binary "-\t-\tpath\0".
    static func parseNumstat(_ text: String) -> [(path: String, from: String?, insertions: Int?, deletions: Int?)] {
        var fields = text.split(separator: "\0", omittingEmptySubsequences: false).map(String.init)[...]
        var result: [(String, String?, Int?, Int?)] = []
        while let record = fields.popFirst() {
            let parts = record.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
            guard parts.count == 3 else { continue }
            let insertions = Int(parts[0])
            let deletions = Int(parts[1])
            if parts[2].isEmpty {
                guard let from = fields.popFirst(), let to = fields.popFirst() else { break }
                result.append((to, from, insertions, deletions))
            } else {
                result.append((String(parts[2]), nil, insertions, deletions))
            }
        }
        return result
    }

    /// `--name-status -z`: "M\0path\0", "A\0path\0", "D\0path\0", "R100\0old\0new\0" → kind per (new) path.
    static func parseNameStatus(_ text: String) -> [String: ChangedFile.Kind] {
        var fields = text.split(separator: "\0", omittingEmptySubsequences: false).map(String.init)[...]
        var kinds: [String: ChangedFile.Kind] = [:]
        while let status = fields.popFirst() {
            guard let letter = status.first else { continue }
            if letter == "R" || letter == "C" {
                guard let from = fields.popFirst(), let to = fields.popFirst() else { break }
                kinds[to] = letter == "R" ? .renamed(from: from) : .added
            } else {
                guard let path = fields.popFirst() else { break }
                kinds[path] = switch letter {
                case "A": .added
                case "D": .deleted
                default: .modified
                }
            }
        }
        return kinds
    }

    static func merge(numstat: [(path: String, from: String?, insertions: Int?, deletions: Int?)], kinds: [String: ChangedFile.Kind]) -> [ChangedFile] {
        numstat.map { entry in
            let kind = kinds[entry.path] ?? entry.from.map { .renamed(from: $0) } ?? .modified
            return ChangedFile(path: entry.path, kind: kind, insertions: entry.insertions, deletions: entry.deletions)
        }
    }
}
