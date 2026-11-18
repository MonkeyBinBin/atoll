import Foundation
import Testing
@testable import AtollCore

/// Synthetic transcript rows in the shapes Claude Code and Codex write (ticket 61).
private enum Rows {
    static func json(_ object: [String: Any]) -> String {
        String(decoding: try! JSONSerialization.data(withJSONObject: object, options: .sortedKeys), as: UTF8.self)
    }

    static func claudeUser(_ content: Any, extra: [String: Any] = [:]) -> String {
        json(["type": "user", "isSidechain": false, "message": ["role": "user", "content": content]].merging(extra) { $1 })
    }

    static func claudeAssistant(_ blocks: [[String: Any]], extra: [String: Any] = [:]) -> String {
        json(["type": "assistant", "isSidechain": false, "message": ["role": "assistant", "content": blocks]].merging(extra) { $1 })
    }

    static func codex(_ payload: [String: Any]) -> String {
        json(["type": "response_item", "payload": payload])
    }
}

private func parse(_ line: String, _ format: TranscriptFormat) -> [TranscriptEntry] {
    TranscriptParser.entries(line: Data(line.utf8), format: format)
}

@Suite("Transcript parser")
struct TranscriptParserTests {
    @Test("Claude Code: prompts, replies, tool calls and shortened results; thinking, meta and side chains skipped")
    func claude() {
        #expect(parse(Rows.claudeUser("fix the build"), .claudeCode) == [TranscriptEntry(.user, "fix the build")])
        #expect(parse(Rows.claudeUser("hidden", extra: ["isMeta": true]), .claudeCode).isEmpty)
        #expect(parse(Rows.claudeUser("sub-agent", extra: ["isSidechain": true]), .claudeCode).isEmpty)
        let reply = Rows.claudeAssistant([
            ["type": "thinking", "thinking": "secret"],
            ["type": "text", "text": "  Done.  "],
            ["type": "tool_use", "name": "Bash", "input": ["command": "swift test\nmore", "description": "run"]],
        ])
        #expect(parse(reply, .claudeCode) == [
            TranscriptEntry(.assistant, "Done."),
            TranscriptEntry(.toolCall(name: "Bash"), "swift test"),
        ])
        let result = Rows.claudeUser([["type": "tool_result", "content": "a\n\nb\nc\nd\ne\nf"]])
        #expect(parse(result, .claudeCode) == [TranscriptEntry(.toolResult, "a\nb\nc\nd\n… +2 lines")])
        let blocks = Rows.claudeUser([["type": "tool_result", "content": [["type": "text", "text": "ok"]]], ["type": "image"]])
        #expect(parse(blocks, .claudeCode) == [TranscriptEntry(.toolResult, "ok"), TranscriptEntry(.user, "[image]")])
    }

    @Test("Claude Code wrappers: slash commands and ! commands show as typed, their output as notes, the rest skipped")
    func claudeWrappers() {
        let command = "<command-message>review</command-message>\n<command-name>/review</command-name>\n<command-args>12</command-args>"
        #expect(parse(Rows.claudeUser(command), .claudeCode) == [TranscriptEntry(.user, "/review 12")])
        #expect(parse(Rows.claudeUser("<bash-input>ls</bash-input>"), .claudeCode) == [TranscriptEntry(.user, "! ls")])
        #expect(parse(Rows.claudeUser("<local-command-stdout>Set model</local-command-stdout>"), .claudeCode)
            == [TranscriptEntry(.note, "Set model")])
        for skipped in ["<system-reminder>x</system-reminder>", "<local-command-caveat>x</local-command-caveat>",
                        "<task-notification>x</task-notification>"] {
            #expect(parse(Rows.claudeUser(skipped), .claudeCode).isEmpty)
        }
    }

    @Test("Claude Code: only its own wrappers are skipped; other text starting with < is the user's")
    func claudeAngleBrackets() {
        #expect(parse(Rows.claudeUser("<hc from=\"t7\">run the tests</hc>"), .claudeCode)
            == [TranscriptEntry(.user, "run the tests")])
        #expect(parse(Rows.claudeUser("<scheduled-task>daily</scheduled-task>"), .claudeCode).count == 1)
        #expect(parse(Rows.claudeUser("<pasted_content>log</pasted_content> what is this?"), .claudeCode).count == 1)
        #expect(parse(Rows.claudeUser("summary", extra: ["isCompactSummary": true]), .claudeCode).isEmpty)
    }

    @Test("tool calls and results carry the ids that pair them")
    func ids() {
        let call = Rows.claudeAssistant([["type": "tool_use", "id": "tu1", "name": "Read", "input": ["file_path": "/a"]]])
        #expect(parse(call, .claudeCode) == [TranscriptEntry(.toolCall(name: "Read"), "/a", id: "tu1")])
        let result = Rows.claudeUser([["type": "tool_result", "tool_use_id": "tu1", "content": "x"]])
        #expect(parse(result, .claudeCode) == [TranscriptEntry(.toolResult, "x", id: "tu1")])
        let codexCall = Rows.codex(["type": "function_call", "name": "exec", "call_id": "c1", "arguments": "{}"])
        #expect(parse(codexCall, .codex).first?.id == "c1")
        let codexImage = Rows.codex(["type": "message", "role": "user", "content": [["type": "input_text", "text": "<image name=[Image #1]>"]]])
        #expect(parse(codexImage, .codex).isEmpty)
    }

    @Test("Claude Code: other row types (request copies, attachments) are never read, even with text blocks")
    func claudeOtherRows() {
        let copy = Rows.json(["type": "api-request-blob", "message": ["content": [["type": "text", "text": "x"]]]])
        #expect(parse(copy, .claudeCode).isEmpty)
        #expect(parse("not json", .claudeCode).isEmpty)
        #expect(parse(Rows.json(["type": "user"]), .claudeCode).isEmpty)
    }

    @Test("Codex: user and assistant text, tool calls with their output; developer, injected context and reasoning skipped")
    func codex() {
        let message = { (role: String, type: String, text: String) in
            Rows.codex(["type": "message", "role": role, "content": [["type": type, "text": text]]])
        }
        #expect(parse(message("user", "input_text", "add tests"), .codex) == [TranscriptEntry(.user, "add tests")])
        #expect(parse(message("user", "input_text", "<environment_context>x</environment_context>"), .codex).isEmpty)
        #expect(parse(message("user", "input_text", "# AGENTS.md instructions for /x"), .codex).isEmpty)
        #expect(parse(message("developer", "input_text", "rules"), .codex).isEmpty)
        #expect(parse(message("assistant", "output_text", "Done"), .codex) == [TranscriptEntry(.assistant, "Done")])
        #expect(parse(Rows.codex(["type": "reasoning", "summary": []]), .codex).isEmpty)
        let call = Rows.codex(["type": "function_call", "name": "exec_command", "arguments": #"{"cmd":"git status"}"#])
        #expect(parse(call, .codex) == [TranscriptEntry(.toolCall(name: "exec_command"), "git status")])
        let patch = Rows.codex(["type": "custom_tool_call", "name": "apply_patch", "input": "*** Begin Patch\n*** Update File: a"])
        #expect(parse(patch, .codex) == [TranscriptEntry(.toolCall(name: "apply_patch"), "*** Begin Patch")])
        let output = Rows.codex(["type": "function_call_output", "output": "On branch main"])
        #expect(parse(output, .codex) == [TranscriptEntry(.toolResult, "On branch main")])
        #expect(parse(Rows.json(["type": "event_msg", "payload": ["type": "task_complete"]]), .codex).isEmpty)
    }
}

/// A temporary home with `.claude` / `.codex` folders.
private struct FakeHome {
    let url: URL

    init() {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("atoll-home-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    @discardableResult
    func write(_ path: String, _ text: String) -> URL {
        let file = url.appendingPathComponent(path)
        try! FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try! text.write(to: file, atomically: true, encoding: .utf8)
        return file
    }

    func remove() { try? FileManager.default.removeItem(at: url) }
}

@Suite("Transcript locator")
struct TranscriptLocatorTests {
    @Test("Claude Code: the pid's session file gives the id, whose transcript is in the cwd's project folder")
    func claudePid() throws {
        let home = FakeHome()
        defer { home.remove() }
        home.write(".claude/sessions/4242.json", Rows.json([
            "pid": 4242, "sessionId": "abc-1", "cwd": "/Users/me/my.app", "startedAt": 1_000_000_500,
        ]))
        let file = home.write(".claude/projects/-Users-me-my-app/abc-1.jsonl", "")
        // The process started half a second before the file says: the same process, whatever cwd the agent reports.
        let same = TranscriptLocator(home: home.url) { _ in Date(timeIntervalSince1970: 1_000_000) }
        #expect(same.locate(tool: .claudeCode, hint: SessionHint(pid: 4242), cwd: "/Users/me/my.app") == file)
        #expect(same.locate(tool: .claudeCode, hint: SessionHint(pid: 4242), cwd: "/Users/me/terminal-cwd") == file)
        // A reused pid: this process started long after the file's.
        let reused = TranscriptLocator(home: home.url) { _ in Date(timeIntervalSince1970: 2_000_000) }
        #expect(reused.locate(tool: .claudeCode, hint: SessionHint(pid: 4242), cwd: "/Users/me/my.app") == nil)
        // No start time: the cwd decides.
        let unknown = TranscriptLocator(home: home.url) { _ in nil }
        #expect(unknown.locate(tool: .claudeCode, hint: SessionHint(pid: 4242), cwd: "/Users/me/my.app") == file)
        #expect(unknown.locate(tool: .claudeCode, hint: SessionHint(pid: 4242), cwd: "/Users/me/other") == nil)
        #expect(same.locate(tool: .claudeCode, hint: SessionHint(pid: 1), cwd: "/Users/me/my.app") == nil)
    }

    @Test("a running process's start time is read; a missing one has none")
    func startTime() throws {
        let start = try #require(ProcessInspector.startTime(getpid()))
        #expect(start <= Date())
        #expect(ProcessInspector.startTime(99_999) == nil)
    }

    @Test("Claude Code: a session id from the source, found in any project folder; explicit paths win; ids aren't paths")
    func claudeID() {
        let home = FakeHome()
        defer { home.remove() }
        let file = home.write(".claude/projects/-elsewhere/s-2.jsonl", "")
        let locator = TranscriptLocator(home: home.url)
        #expect(locator.locate(tool: .claudeCode, hint: SessionHint(sessionID: "s-2"), cwd: "/x") == file)
        let explicit = home.write("given.jsonl", "")
        #expect(locator.locate(tool: .claudeCode, hint: SessionHint(sessionID: "s-2", transcriptPath: explicit.path), cwd: "/x") == explicit)
        #expect(locator.locate(tool: .claudeCode, hint: SessionHint(sessionID: "../../etc/passwd"), cwd: "/x") == nil)
        #expect(locator.locate(tool: .generic, hint: SessionHint(sessionID: "s-2"), cwd: "/x") == nil)
    }

    @Test("Claude Code: a source id with no transcript (cmux's own cmux-… ids) falls back to the pid's session file")
    func claudeFallsBackToPid() {
        let home = FakeHome()
        defer { home.remove() }
        home.write(".claude/sessions/7.json", Rows.json(["sessionId": "real-1", "cwd": "/w", "startedAt": 1_000_000_000]))
        let file = home.write(".claude/projects/-w/real-1.jsonl", "")
        let locator = TranscriptLocator(home: home.url) { _ in Date(timeIntervalSince1970: 1_000_000) }
        #expect(locator.locate(tool: .claudeCode, hint: SessionHint(pid: 7, sessionID: "cmux-fee"), cwd: "/w") == file)
    }

    @Test("Codex: by session id in the dated rollout folders; with only a pid there is no certain link")
    func codex() {
        let home = FakeHome()
        defer { home.remove() }
        home.write(".codex/sessions/2026/10/01/rollout-2026-10-01T09-00-00-other.jsonl", "")
        let file = home.write(".codex/sessions/2026/11/18/rollout-2026-11-18T10-00-00-019f-aa.jsonl", "")
        let locator = TranscriptLocator(home: home.url)
        #expect(locator.locate(tool: .codex, hint: SessionHint(sessionID: "019f-aa"), cwd: "/x") == file)
        #expect(TranscriptLocator(home: home.url) { _ in nil } openFiles: { _ in [] }
            .locate(tool: .codex, hint: SessionHint(pid: 99), cwd: "/x") == nil)
    }

    @Test("Codex: with no usable id, the rollout file its process has open; files elsewhere don't count")
    func codexOpenFile() throws {
        let home = FakeHome()
        defer { home.remove() }
        let rollout = home.write(".codex/sessions/2026/11/18/rollout-2026-11-18T18-08-22-abc.jsonl", "")
        let locator = TranscriptLocator(home: home.url, processStart: { _ in nil }) { _ in
            ["/dev/null", home.url.appendingPathComponent(".codex/other.jsonl").path, rollout.path]
        }
        #expect(locator.locate(tool: .codex, hint: SessionHint(pid: 5, sessionID: "cmux-feed"), cwd: "/x")?.path == rollout.path)
        let none = TranscriptLocator(home: home.url, processStart: { _ in nil }) { _ in ["/tmp/rollout-x.jsonl"] }
        #expect(none.locate(tool: .codex, hint: SessionHint(pid: 5), cwd: "/x") == nil)
        #expect(locator.locate(tool: .claudeCode, hint: SessionHint(pid: 5), cwd: "/x") == nil)
    }

    @Test("a process's open files are listed")
    func openFiles() throws {
        let home = FakeHome()
        defer { home.remove() }
        let file = home.write("open.jsonl", "x")
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        let paths = ProcessInspector.openFiles(getpid()).map { ($0 as NSString).standardizingPath }
        #expect(paths.contains { $0.hasSuffix("/open.jsonl") })
    }

    @Test("session labels from cmux / herdr become the hint")
    func labels() {
        let hint = SessionHint(labels: [SessionHint.idLabel: "s", "other": "x"], pid: 7)
        #expect(hint == SessionHint(pid: 7, sessionID: "s"))
        #expect(HerdrCLIAdapter.sessionLabels(["kind": "path", "value": "/t.jsonl", "agent": "claude", "source": "x"])
            == [SessionHint.pathLabel: "/t.jsonl"])
        #expect(HerdrCLIAdapter.sessionLabels(["kind": "id", "value": "abc"]) == [SessionHint.idLabel: "abc"])
        #expect(HerdrCLIAdapter.sessionLabels(nil).isEmpty)
    }
}

@Suite("Transcript reader")
struct TranscriptReaderTests {
    @Test("only appended bytes are parsed; an unfinished last line waits; a shorter file starts over")
    func incremental() async throws {
        let home = FakeHome()
        defer { home.remove() }
        let file = home.write("t.jsonl", Rows.claudeUser("one") + "\n" + String(Rows.claudeUser("two").prefix(10)))
        let reader = TranscriptReader()
        let first = try #require(await reader.read(address: "a", url: file, format: .claudeCode))
        #expect(first.entries == [TranscriptEntry(.user, "one")])
        try (Rows.claudeUser("one") + "\n" + Rows.claudeUser("two") + "\n").write(to: file, atomically: false, encoding: .utf8)
        let second = try #require(await reader.read(address: "a", url: file, format: .claudeCode))
        #expect(second.entries.map(\.text) == ["one", "two"], "\(second)")
        #expect(second.version > first.version)
        try (Rows.claudeUser("new") + "\n").write(to: file, atomically: false, encoding: .utf8)
        let third = try #require(await reader.read(address: "a", url: file, format: .claudeCode))
        #expect(third.entries.map(\.text) == ["new"])
    }

    @Test("a long file is read from its tail, skipping the line the window starts in; old entries are dropped")
    func tail() async throws {
        let home = FakeHome()
        defer { home.remove() }
        let lines = (0..<50).map { Rows.claudeUser("message \($0)") }
        let file = home.write("t.jsonl", lines.joined(separator: "\n") + "\n")
        let reader = TranscriptReader(window: UInt64(lines[0].utf8.count * 10 + 5), maxEntries: 6)
        let snapshot = try #require(await reader.read(address: "a", url: file, format: .claudeCode))
        #expect(snapshot.startsMidway)
        #expect(snapshot.entries.count == 6)
        #expect(snapshot.entries.last?.text == "message 49")
        #expect(await reader.read(address: "a", url: home.url.appendingPathComponent("missing.jsonl"), format: .claudeCode) == nil)
    }
}

@Suite("Transcript rendering")
struct TranscriptRenderingTests {
    func pieces(_ rendered: (text: String, runs: [StyledRun])) -> [String: TermStyle] {
        Dictionary(rendered.runs.map { ((rendered.text as NSString).substring(with: $0.range), $0.style) }, uniquingKeysWith: { a, _ in a })
    }

    @Test("Claude Code's screen shape: ❯ prompts, ⏺ replies and tool calls, ⎿ results under their call")
    func layout() {
        let snapshot = TranscriptSnapshot(path: "/t", entries: [
            TranscriptEntry(.user, "fix it\nplease"),
            TranscriptEntry(.assistant, "On it."),
            TranscriptEntry(.toolCall(name: "Bash"), "ls"),
            TranscriptEntry(.toolResult, "a\nb"),
        ], version: 1, startsMidway: true)
        let rendered = TranscriptRendering.render(snapshot)
        #expect(rendered.text == """
        … earlier messages not shown
        ❯ fix it
          please

        ⏺ On it.

        ⏺ Bash(ls)
          ⎿  a
             b
        """)
        let styles = pieces(rendered)
        #expect(styles["❯ fix it"] == OutputStyling.accent)
        #expect(styles["Bash"] == OutputStyling.bold)
        #expect(styles["  ⎿  a"] == OutputStyling.muted)
    }

    @Test("parallel tool calls: each result goes under its own call, not under the last one")
    func parallelCalls() {
        let snapshot = TranscriptSnapshot(path: "/t", entries: [
            TranscriptEntry(.toolCall(name: "Read"), "a", id: "1"),
            TranscriptEntry(.toolCall(name: "Read"), "b", id: "2"),
            TranscriptEntry(.toolResult, "A", id: "1"),
            TranscriptEntry(.toolResult, "B", id: "2"),
            TranscriptEntry(.toolResult, "orphan", id: "gone"),
        ], version: 1)
        #expect(TranscriptRendering.render(snapshot).text == """
        ⏺ Read(a)
          ⎿  A

        ⏺ Read(b)
          ⎿  B
          ⎿  orphan
        """)
    }

    @Test("reply markdown: markers dropped, styles kept; fences, lists, quotes and tables")
    func markdown() {
        let text = "## Plan\nUse `swift test` and **never** skip.\n- see Sources/App.swift:3\n> note\n| a | b |\n|---|---|\n```swift\nlet x = 1\n```"
        let rendered = TranscriptRendering.render(TranscriptSnapshot(path: "/t", entries: [TranscriptEntry(.assistant, text)], version: 1))
        #expect(rendered.text == """
        ⏺ Plan
          Use swift test and never skip.
          - see Sources/App.swift:3
          │ note
          | a | b |
          |---|---|
          ```swift
          let x = 1
          ```
        """)
        let styles = pieces(rendered)
        #expect(styles["Plan"] == OutputStyling.bold)
        #expect(styles["swift test"] == OutputStyling.code)
        #expect(styles["never"] == OutputStyling.bold)
        #expect(styles["-"] == OutputStyling.listMarker)
        #expect(styles["Sources/App.swift:3"] == OutputStyling.path)
        #expect(styles["let x = 1"] == OutputStyling.code)
        #expect(styles["```swift"] == OutputStyling.muted)
        #expect(styles["---"] == OutputStyling.muted)
    }
}

@MainActor
@Suite("Transcript in the panel")
struct TranscriptPanelTests {
    func waitForTranscript(_ h: Harness, tries: Int = 200) async -> TranscriptSnapshot? {
        for _ in 0..<tries {
            if let transcript = h.store.panel?.transcript { return transcript }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return nil
    }

    @Test("the open panel reads the agent's transcript found through its session label")
    func panelReads() async throws {
        let home = FakeHome()
        defer { home.remove() }
        home.write(".claude/projects/-x/s-1.jsonl", Rows.claudeUser("hello") + "\n")
        let h = Harness()
        h.store.transcriptLocator = TranscriptLocator(home: home.url)
        var info = term("t1", "idle")
        info.labels[SessionHint.idLabel] = "s-1"
        h.connect([info])
        h.store.openPanel("t1")
        let transcript = try #require(await waitForTranscript(h))
        #expect(transcript.entries == [TranscriptEntry(.user, "hello")])
    }

    @Test("while the panel is open the transcript is read again on a timer, with no status change; closing stops it")
    func polls() async throws {
        let home = FakeHome()
        defer { home.remove() }
        let file = home.write(".claude/projects/-x/s-1.jsonl", Rows.claudeUser("one") + "\n")
        let h = Harness()
        h.store.transcriptLocator = TranscriptLocator(home: home.url)
        var info = term("t1", "idle")
        info.labels[SessionHint.idLabel] = "s-1"
        h.connect([info])
        h.store.openPanel("t1")
        _ = try #require(await waitForTranscript(h))
        try (Rows.claudeUser("one") + "\n" + Rows.claudeUser("two") + "\n").write(to: file, atomically: false, encoding: .utf8)
        h.scheduler.advance(by: 2)
        var entries: [TranscriptEntry] = []
        for _ in 0..<200 {
            entries = h.store.panel?.transcript?.entries ?? []
            if entries.count == 2 { break }
            try? await Task.sleep(for: .milliseconds(5))
        }
        #expect(entries.map(\.text) == ["one", "two"])
        h.store.closePanel()
        h.scheduler.advance(by: 2)
        #expect(h.store.panel == nil)
    }

    @Test("no certain link: no transcript, the terminal output stays")
    func noLink() async {
        let h = Harness()
        h.connect([term("t1", "idle")])
        h.store.openPanel("t1")
        await settle()
        #expect(await waitForTranscript(h, tries: 20) == nil)
        #expect(h.store.panel?.output?.text == "hello")
    }

    @Test("a turn ending in Idle (tools that report it) also reads once more; leaving another state doesn't")
    func settleOnIdle() async {
        let h = Harness()
        h.connect([term("t1", "working"), term("t2", "idle")])
        h.store.openPanel("t1")
        await settle()
        func panelReads() -> Int { h.client.commands.filter { $0 == .read("t1", 200) }.count }
        h.status("t1", "idle", seq: 11)
        h.scheduler.advance(by: 1.5)
        await settle()
        #expect(panelReads() == 3)
        h.status("t1", "blocked", kind: "permission", seq: 12)
        h.scheduler.advance(by: 1.5)
        await settle()
        #expect(panelReads() == 4)
    }

    @Test("a turn ending in the open panel reads once more after the settle delay")
    func settleReread() async {
        let h = Harness()
        h.connect([term("t1", "working")])
        h.store.openPanel("t1")
        await settle()
        // Panel reads only (the turn's final message is read on its own, with fewer lines).
        func panelReads() -> Int { h.client.commands.filter { $0 == .read("t1", 200) }.count }
        h.status("t1", "done", seq: 11)
        await settle()
        #expect(panelReads() == 2)
        h.scheduler.advance(by: 1.4)
        await settle()
        #expect(panelReads() == 2)
        h.scheduler.advance(by: 0.1)
        await settle()
        #expect(panelReads() == 3)
    }
}
