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
    /// Transcript files found per session id ("tool|id"), so folders are scanned once.
    private var located: [String: URL] = [:]
    /// How much of a file's end is read the first time (and after a jump larger than this).
    let window: UInt64
    /// Entries kept per agent, newest last.
    let maxEntries: Int

    public init(window: UInt64 = 4 << 20, maxEntries: Int = 400) {
        self.window = window
        self.maxEntries = maxEntries
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
            // First read of a long file, or it grew by more than the window since: only its tail.
            state = State(path: url.path, format: format, offset: size - window, startsMidway: true)
            dropFirstLine = true
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

    /// Finds the agent's transcript and reads it; nil when there is none to show (no certain link, or unreadable).
    public func load(address: String, tool: AgentTool, hint: SessionHint, cwd: String,
                     locator: TranscriptLocator) -> TranscriptSnapshot? {
        guard let url = locate(tool: tool, hint: hint, cwd: cwd, locator: locator) else {
            states[address] = nil
            return nil
        }
        return read(address: address, url: url, format: tool == .codex ? .codex : .claudeCode)
    }

    private func locate(tool: AgentTool, hint: SessionHint, cwd: String, locator: TranscriptLocator) -> URL? {
        if let path = locator.explicitPath(hint) { return path }
        for id in locator.sessionIDs(tool: tool, hint: hint, cwd: cwd) {
            let key = "\(tool)|\(id)"
            if let url = located[key], FileManager.default.fileExists(atPath: url.path) { return url }
            if let url = locator.transcript(tool: tool, id: id, cwd: cwd) {
                located[key] = url
                return url
            }
        }
        return locator.openTranscript(tool: tool, hint: hint)
    }

    public func forget(address: String) {
        states[address] = nil
    }

    private func snapshot(_ state: State) -> TranscriptSnapshot {
        TranscriptSnapshot(path: state.path, entries: state.entries, version: state.offset, startsMidway: state.startsMidway)
    }
}
