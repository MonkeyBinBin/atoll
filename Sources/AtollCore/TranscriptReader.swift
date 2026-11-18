import Foundation

/// An agent's conversation as last read from its transcript.
public struct TranscriptSnapshot: Equatable, Sendable {
    public var path: String
    public var entries: [TranscriptEntry]
    /// Bytes of the file read so far: changes whenever `entries` can have, so it is a cheap identity for caches.
    public var version: UInt64
    /// Reading started partway into a long file, so older entries are missing.
    public var startsMidway: Bool

    public init(path: String, entries: [TranscriptEntry], version: UInt64, startsMidway: Bool = false) {
        self.path = path
        self.entries = entries
        self.version = version
        self.startsMidway = startsMidway
    }
}

/// Reads transcripts incrementally, off the main actor: per agent it keeps the file, how far it has read, the
/// unfinished last line and the parsed entries, so a refresh only parses what was appended. A long file is read
/// from its tail only. A different file, or one that got shorter, starts over.
public actor TranscriptReader {
    private struct State {
        var path: String
        var format: TranscriptFormat
        var offset: UInt64
        var pending = Data()
        var entries: [TranscriptEntry] = []
        var startsMidway = false
    }

    private var states: [String: State] = [:]
    /// Session id lookups ("tool|id"): found files are kept while they exist; misses for `missTTL`, so an id that
    /// leads nowhere (cmux's own ids) isn't searched for on every poll, yet a session file created later is found.
    private var located: [String: (url: URL?, at: Date)] = [:]
    let missTTL: TimeInterval
    /// How much of a file's end is read the first time (and after a jump larger than this).
    let window: UInt64
    /// Entries kept per agent, newest last.
    let maxEntries: Int

    public init(window: UInt64 = 4 << 20, maxEntries: Int = 400, missTTL: TimeInterval = 30) {
        self.window = window
        self.maxEntries = maxEntries
        self.missTTL = missTTL
    }

    public func read(address: String, url: URL, format: TranscriptFormat) -> TranscriptSnapshot? {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            states[address] = nil
            return nil
        }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return nil }
        var state = states[address].flatMap { $0.path == url.path && $0.format == format && $0.offset <= size ? $0 : nil }
            ?? State(path: url.path, format: format, offset: 0)
        var dropFirstLine = false
        if size - state.offset > window {
            // First read of a long file, or it grew by more than the window since: only its tail. Unless the window
            // starts right after a newline, its first line is a fragment.
            state = State(path: url.path, format: format, offset: size - window, startsMidway: true)
            try? handle.seek(toOffset: state.offset - 1)
            dropFirstLine = (try? handle.read(upToCount: 1)) != Data([UInt8(ascii: "\n")])
        }
        if size > state.offset {
            try? handle.seek(toOffset: state.offset)
            let chunk = (try? handle.read(upToCount: Int(size - state.offset))) ?? Data()
            state.offset += UInt64(chunk.count)
            var data = state.pending + chunk
            if dropFirstLine {
                // The window starts inside a line: skip to the next one.
                guard let newline = data.firstIndex(of: UInt8(ascii: "\n")) else {
                    state.pending = Data()
                    states[address] = state
                    return snapshot(state)
                }
                data = data[(newline + 1)...]
            }
            var start = data.startIndex
            while let newline = data[start...].firstIndex(of: UInt8(ascii: "\n")) {
                let line = data[start..<newline]
                if !line.isEmpty { state.entries += TranscriptParser.entries(line: Data(line), format: format) }
                start = newline + 1
            }
            state.pending = Data(data[start...])
            if state.entries.count > maxEntries {
                state.entries.removeFirst(state.entries.count - maxEntries)
                state.startsMidway = true
            }
        }
        states[address] = state
        return snapshot(state)
    }

    /// Finds the agent's transcript and reads it; nil when there is none to show (no certain link, or unreadable). A
    /// miss keeps what was read, so a passing failure doesn't mean parsing the whole window again.
    public func load(address: String, tool: AgentTool, hint: SessionHint, cwd: String,
                     locator: TranscriptLocator) -> TranscriptSnapshot? {
        let found = locator.locate(tool: tool, hint: hint, cwd: cwd) { [self] id in self.lookUp(tool: tool, id: id, cwd: cwd, locator: locator) }
        guard let url = found else { return nil }
        return read(address: address, url: url, format: tool == .codex ? .codex : .claudeCode)
    }

    private func lookUp(tool: AgentTool, id: String, cwd: String, locator: TranscriptLocator) -> URL? {
        let key = "\(tool)|\(id)"
        if let cached = located[key] {
            if let url = cached.url, FileManager.default.fileExists(atPath: url.path) { return url }
            if cached.url == nil, Date().timeIntervalSince(cached.at) < missTTL { return nil }
        }
        let url = locator.transcript(tool: tool, id: id, cwd: cwd)
        located[key] = (url, Date())
        return url
    }

    /// Drops what was read for an agent (its panel closed).
    public func forget(address: String) {
        states[address] = nil
    }

    /// Bytes of complete lines read: an unfinished line being written doesn't change it, as it adds no entry yet.
    private func snapshot(_ state: State) -> TranscriptSnapshot {
        TranscriptSnapshot(path: state.path, entries: state.entries, version: state.offset - UInt64(state.pending.count),
                           startsMidway: state.startsMidway)
    }
}
