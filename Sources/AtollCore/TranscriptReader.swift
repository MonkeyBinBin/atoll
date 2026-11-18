import Foundation

/// An agent's conversation as last read from its transcript.
public struct TranscriptSnapshot: Equatable, Sendable {
    public var path: String
    public var entries: [TranscriptEntry]
    /// Bytes of the file read so far: changes whenever `entries` can have, so it is a cheap identity for caches.
    public var version: UInt64
    /// Reading started partway into a long file, so older entries are missing.
    public var startsMidway: Bool
    /// The panel text, laid out off the main actor by the reader (nil when built by hand).
    public var rendered: TranscriptRendering.Output?
    /// The file's inode: a file replaced at the same path is another transcript even at the same `version`.
    public var fileID: Int?

    public init(path: String, entries: [TranscriptEntry], version: UInt64, startsMidway: Bool = false,
                rendered: TranscriptRendering.Output? = nil, fileID: Int? = nil) {
        self.path = path
        self.entries = entries
        self.version = version
        self.startsMidway = startsMidway
        self.rendered = rendered
        self.fileID = fileID
    }

    /// Changes whenever the entries can have: what caches and the store compare.
    public var identity: String { "\(path)|\(fileID ?? 0)|\(version)" }
}

/// Reads transcripts incrementally, off the main actor: per agent it keeps the file, how far it has read, the
/// unfinished last line and the parsed entries, so a refresh only parses what was appended. A long file is read
/// from its tail only. A different file (path or inode), or one that got shorter, starts over. The panel text is laid
/// out here too, whenever the entries changed, so the main actor only shows it.
public actor TranscriptReader {
    private struct State {
        var path: String
        var format: TranscriptFormat
        var offset: UInt64
        var pending = Data()
        var entries: [TranscriptEntry] = []
        var startsMidway = false
        /// The file's inode: a file replaced at the same path is read afresh.
        var fileID: Int?
        /// The last bytes before `offset`: different on the next read means the file was rewritten in place.
        var tail = Data()
        var rendered: TranscriptRendering.Output?
        var renderedVersion: UInt64?
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
        // Unreadable for now (being replaced): keep what was read, so the next read doesn't start over.
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return nil }
        let fileID = (try? FileManager.default.attributesOfItem(atPath: url.path)[.systemFileNumber]) as? Int
        var state = states[address].flatMap {
            $0.path == url.path && $0.format == format && $0.offset <= size && $0.fileID == fileID
                && Self.tail(of: handle, before: $0.offset) == $0.tail ? $0 : nil
        } ?? State(path: url.path, format: format, offset: 0, fileID: fileID)
        var dropFirstLine = false
        if size - state.offset > window {
            // First read of a long file, or it grew by more than the window since: only its tail. Unless the window
            // starts right after a newline, its first line is a fragment.
            state = State(path: url.path, format: format, offset: size - window, startsMidway: true, fileID: fileID)
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
                    state.tail = Self.tail(of: handle, before: state.offset)
                    return finish(&state, address: address)
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
            state.tail = Self.tail(of: handle, before: state.offset)
            if state.entries.count > maxEntries {
                state.entries.removeFirst(state.entries.count - maxEntries)
                state.startsMidway = true
            }
        }
        return finish(&state, address: address)
    }

    static let tailLength: UInt64 = 32

    static func tail(of handle: FileHandle, before offset: UInt64) -> Data {
        let start = offset >= tailLength ? offset - tailLength : 0
        guard (try? handle.seek(toOffset: start)) != nil else { return Data() }
        return (try? handle.read(upToCount: Int(offset - start))) ?? Data()
    }

    /// Lays the text out again when the entries changed, keeps the state, and returns the snapshot.
    private func finish(_ state: inout State, address: String) -> TranscriptSnapshot {
        var shot = snapshot(state)
        if state.renderedVersion != shot.version || state.rendered == nil {
            state.rendered = TranscriptRendering.render(shot)
            state.renderedVersion = shot.version
        }
        shot.rendered = state.rendered
        states[address] = state
        return shot
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
            if cached.url == nil, Date().timeIntervalSince(cached.at) < missTTL {
                // Only the folder scan waits out the miss: the cwd's own folder is checked every time, so a session's
                // file is found as soon as it is written (a new session, right after `/clear`).
                guard let url = locator.directTranscript(tool: tool, id: id, cwd: cwd) else { return nil }
                located[key] = (url, Date())
                return url
            }
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
                           startsMidway: state.startsMidway, fileID: state.fileID)
    }
}
