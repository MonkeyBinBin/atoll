import Foundation
import Testing
@testable import AtollCore

/// Screens captured at the end of real turns (Claude Code 2.1.322, Codex 0.167.0, through herdr-core's `hc`);
/// only the long temp path is shortened. `claudeTool` is assembled from Claude Code's tool-call rows.
enum FinalScreens {
    static let rule = String(repeating: "─", count: 200)

    static let claudeShort = [
        "",
        "❯ Explain in exactly three short lines what a hash map is. No tools.",
        "",
        "⏺ A hash map stores key-value pairs and uses a hash function to convert each key into an index in an internal array.",
        "  Lookup, insert, and delete take average O(1) time because the key maps directly to its bucket instead of being searched for.",
        "  Collisions, where two keys map to the same index, are handled by chaining or open addressing, and resizing keeps performance steady as the map grows.",
        "",
        "✻ Baked for 3s · done 下午2:13",
        "",
        "",
        rule,
        "❯",
        rule,
        "  Haiku 5.5 medium │  f35 │ context ●○○○○○○○○○   5% used 50.6k / 1.0M · cache hit 54%",
        "  5h ●○○○○○○○○○  13% used · resets 5:00pm (in 2h45m) │ 7d ●●●●○○○○○○  41% used · resets nov 16 8:00am (in 3d 17h)",
        "  ⏵⏵ auto mode on (shift+tab to cycle) · ← 1 agent",
    ].joined(separator: "\n")

    static let claudeLong = [
        "",
        "❯ <hc from=\"t5c\">Now list 12 famous hash map implementations, one per line, each with a one-sentence description. No tools.</hc>",
        "",
        "⏺ 1. Java HashMap: a bucket-based hash table that turns long collision chains into balanced trees to limit worst-case lookup time.",
        "  2. Java ConcurrentHashMap: a thread-safe hash map that uses fine-grained locking and atomic operations so many threads can read and write at once.",
        "  3. Python dict: an insertion-ordered hash table with a compact layout that keeps entries in a dense array and indexes them with a sparse table.",
        "  4. C++ std::unordered_map: the standard library's chained hash table, which stores elements in buckets and rehashes when the load factor grows too high.",
        "  5. Abseil flat_hash_map (SwissTable): an open-addressing table that probes groups of control bytes, using SIMD instructions to check many slots at once.",
        "  6. Rust HashMap: the standard library map built on the hashbrown SwissTable implementation and using SipHash by default to resist hash-flooding attacks.",
        "  7. Go map: a built-in hash table that randomizes iteration order on purpose so programs can't depend on it.",
        "  8. JavaScript Map: an ECMAScript collection that preserves insertion order and compares keys by SameValueZero.",
        "  9. Redis dict: a hash table that resizes incrementally by spreading the rehashing work across many operations, so no single command stalls.",
        "  10. .NET Dictionary<TKey, TValue>: a chained hash table that stores entries in one array and uses a separate bucket array to index them.",
        "  11. PHP HashTable: an ordered hash table that the engine uses for both PHP arrays and object properties.",
        "  12. Ruby Hash: an insertion-ordered hash table, implemented in C in st.c, that has been the standard Hash since Ruby 1.9.",
        "",
        "✻ Worked for 9s · done 下午2:14",
        "",
        "",
        rule,
        "❯",
        rule,
        "  Haiku 5.5 medium │  f35 │ context ●○○○○○○○○○   7% used 69.3k / 1.0M · cache hit 65%",
        "  5h ●○○○○○○○○○  13% used · resets 5:00pm (in 2h44m) │ 7d ●●●●○○○○○○  41% used · resets nov 16 8:00am (in 3d 17h)",
        "  ⏵⏵ auto mode on (shift+tab to cycle) · ← 1 agent",
    ].joined(separator: "\n")

    static let codexShort = [
        "",
        "› Explain in exactly three short lines what a hash map is. Do not run any commands.",
        "",
        "",
        "• A hash map stores key–value pairs.",
        "  A hash function maps each key to a storage location.",
        "  Average lookup, insertion, and deletion take O(1) time.",
        "",
        "  Worked for 5s • 2:14 PM",
        "",
        "",
        "›",
        "",
        "",
        "  GPT-5.6-Sol medium · /tmp/f35 · granular · Context 3% used · 5h 100% left · weekly 92% left",
    ].joined(separator: "\n")

    static let codexLong = [
        "",
        "› <hc from=\"t5c\">Now list 12 famous hash map implementations, one per line, each with a one-sentence description. Do not run any commands.</hc>",
        "",
        "",
        "• Java HashMap — A general-purpose, non-thread-safe hash table with separate chaining and tree bins.",
        "  Java ConcurrentHashMap — A thread-safe hash map optimized for concurrent reads and updates.",
        "  C++ std::unordered_map — The standard library’s hash-based associative container with unique keys.",
        "  Python dict — A compact, insertion-ordered hash map used throughout the Python language.",
        "  JavaScript Map — An insertion-ordered key–value collection supporting keys of any type.",
        "  Go map — A built-in hash map type with runtime-managed storage and growth.",
        "  Rust std::collections::HashMap — A generic hash map using keyed hashing for denial-of-service resistance.",
        "  C# Dictionary<TKey,TValue> — .NET’s general-purpose generic hash table for unique keys.",
        "  Ruby Hash — An insertion-ordered key–value collection supporting arbitrary objects as keys.",
        "  PHP associative array — An ordered hash table that serves as both a map and an array.",
        "  GLib GHashTable — A configurable C hash table supporting custom hash and equality functions.",
        "  Abseil flat_hash_map — A high-performance C++ open-addressing hash map based on Swiss tables.",
        "",
        "  Worked for 6s • 2:14 PM",
        "",
        "",
        "› Ask Codex to do anything",
        "",
        "  GPT-5.6-Sol medium · /tmp/f35 · granular · Context 3% used · 5h 100% left · weekly 92% left",
        "  ← for agents · ? for shortcuts",
    ].joined(separator: "\n")

    static let codexTool = [
        "",
        "› <hc from=\"t5c\">Run the command: ls. After it runs, end your turn immediately without writing any text at all.</hc>",
        "",
        "",
        "• 我會執行 ls，完成後不再輸出文字。",
        "",
        "• Explored",
        "  └ List ls",
        "    + Show details",
        "",
        "  Worked for 8s • 2:15 PM",
        "",
        "",
        "› Ask Codex to do anything",
        "",
        "  GPT-5.6-Sol medium · /tmp/f35 · granular · Context 3% used · 5h 99% left · weekly 92% left",
        "  ← for agents · ? for shortcuts",
    ].joined(separator: "\n")

    static let codexTip = [
        "",
        "› <hc from=\"t5c\">In two short lines, say what a binary heap is. Do not run any commands.</hc>",
        "",
        "",
        "• A binary heap is a complete binary tree that maintains a min-heap or max-heap ordering.",
        "  It supports O(log n) insertion and removal, with O(1) access to the root.",
        "  └ Tip: Paste an image with Ctrl+V to attach it to your next message.",
        "",
        "  Worked for 2s • 2:20 PM",
        "",
        "",
        "› Ask Codex to do anything",
        "",
        "  GPT-5.6-Sol medium · /tmp/f35 · granular · Context 3% used · 5h 99% left · weekly 92% left",
        "  ← for agents · ? for shortcuts",
    ].joined(separator: "\n")

    static let claudeTool = [
        "",
        "❯ List the files here.",
        "",
        "⏺ I'll list the files.",
        "",
        "⏺ Bash(ls)",
        "  ⎿  a.txt",
        "     notes.md",
        "",
        "✻ Worked for 4s · done 下午2:20",
        "",
        rule,
        "❯",
        rule,
        "  Haiku 5.5 medium │  f35 │ context ●○○○○○○○○○   7% used 71.4k / 1.0M · cache hit 87%",
    ].joined(separator: "\n")

    static let unknown = [
        "$ make",
        "cc -o app main.c",
        "$",
    ].joined(separator: "\n")
}

@Suite("Turn final message: extraction")
struct TurnFinalMessageTests {
    @Test("Claude Code: the last two lines of the last ⏺ reply")
    func claudeShort() {
        let message = TurnFinalMessage.extract(from: FinalScreens.claudeShort, tool: .claudeCode)
        #expect(message?.lines == [
            "Lookup, insert, and delete take average O(1) time because the key maps directly to its bucket instead of being searched for.",
            "Collisions, where two keys map to the same index, are handled by chaining or open addressing, and resizing keeps performance steady as the map grows.",
        ])
    }

    @Test("Claude Code: a long reply keeps only its last two lines")
    func claudeLong() {
        let message = TurnFinalMessage.extract(from: FinalScreens.claudeLong, tool: .claudeCode)
        #expect(message?.lines.count == 2)
        #expect(message?.lines.first?.hasPrefix("11. PHP HashTable") == true)
        #expect(message?.lines.last?.hasPrefix("12. Ruby Hash") == true)
    }

    @Test("Claude Code: a turn that ends on a tool call has no final message")
    func claudeTool() {
        #expect(TurnFinalMessage.extract(from: FinalScreens.claudeTool, tool: .claudeCode) == nil)
    }

    @Test("Codex: the last two lines of the last • reply, without the Worked-for row")
    func codexShort() {
        let message = TurnFinalMessage.extract(from: FinalScreens.codexShort, tool: .codex)
        #expect(message?.lines == [
            "A hash function maps each key to a storage location.",
            "Average lookup, insertion, and deletion take O(1) time.",
        ])
    }

    @Test("Codex: a long reply keeps only its last two lines")
    func codexLong() {
        let message = TurnFinalMessage.extract(from: FinalScreens.codexLong, tool: .codex)
        #expect(message?.lines == [
            "GLib GHashTable — A configurable C hash table supporting custom hash and equality functions.",
            "Abseil flat_hash_map — A high-performance C++ open-addressing hash map based on Swiss tables.",
        ])
    }

    @Test("Codex: a tip Codex appends under the reply (└ Tip: …) isn't part of it and doesn't make it a tool block")
    func codexTip() {
        let message = TurnFinalMessage.extract(from: FinalScreens.codexTip, tool: .codex)
        #expect(message?.lines == [
            "A binary heap is a complete binary tree that maintains a min-heap or max-heap ordering.",
            "It supports O(log n) insertion and removal, with O(1) access to the root.",
        ])
    }

    @Test("Codex: a turn that ends on a tool block (• Explored └ …) has no final message")
    func codexTool() {
        #expect(TurnFinalMessage.extract(from: FinalScreens.codexTool, tool: .codex) == nil)
    }

    @Test("unrecognized screens and generic tools give nothing")
    func unknown() {
        #expect(TurnFinalMessage.extract(from: FinalScreens.unknown, tool: .claudeCode) == nil)
        #expect(TurnFinalMessage.extract(from: FinalScreens.unknown, tool: .codex) == nil)
        #expect(TurnFinalMessage.extract(from: FinalScreens.claudeShort, tool: .generic) == nil)
    }

    @Test("without the tool's input box at the bottom the layout isn't trusted: nothing, not a status row")
    func noInputBox() {
        let claude = ["❯ go", "", "⏺ Partial reply still streaming", "  Haiku 5.5 medium │ f35 │ context 5% used"].joined(separator: "\n")
        #expect(TurnFinalMessage.extract(from: claude, tool: .claudeCode) == nil)
        let codex = ["• Reply", "  GPT-5.6-Sol medium · /tmp/f35 · Context 3% used"].joined(separator: "\n")
        #expect(TurnFinalMessage.extract(from: codex, tool: .codex) == nil)
    }

    @Test("each kept line is cut to the preview length")
    func cut() {
        let long = String(repeating: "x", count: 500)
        let screen = ["❯ go", "", "⏺ \(long)", "", FinalScreens.rule, "❯", FinalScreens.rule].joined(separator: "\n")
        let message = TurnFinalMessage.extract(from: screen, tool: .claudeCode)
        #expect(message?.lines.first?.count == TurnFinalMessage.maxLineLength)
        #expect(message?.lines.first?.hasSuffix("…") == true)
    }
}

@MainActor
@Suite("Turn final message: store")
struct TurnFinalMessageStoreTests {
    func harness(app: String = "codex") -> Harness {
        let h = Harness()
        h.connect([term("t1", "working", app: app)])
        h.client.readResult = .success(ReadOutput(text: FinalScreens.codexShort, how: "screen"))
        return h
    }

    func reads(_ h: Harness) -> Int {
        h.client.commands.filter { if case .read = $0 { true } else { false } }.count
    }

    @Test("a finished turn without a status message reads the screen once, after the delay")
    func readsOnce() async {
        let h = harness()
        h.status("t1", "done", app: "codex", seq: 11)
        #expect(reads(h) == 0)
        h.scheduler.advance(by: h.store.timing.previewDelay)
        await settle()
        #expect(reads(h) == 1)
        #expect(h.store.agent("t1")?.finalMessage?.lines.last == "Average lookup, insertion, and deletion take O(1) time.")
        // Nothing else re-reads it: later events in the same finished state don't.
        h.client.emit(.event(seq: 12, .title(terminal: "t1", title: "x")))
        h.scheduler.advance(by: 5)
        await settle()
        #expect(reads(h) == 1)
    }

    @Test("Idle straight from Working counts as a finished turn too")
    func idleFromWorking() async {
        let h = harness()
        h.status("t1", "idle", app: "codex", seq: 11)
        h.scheduler.advance(by: h.store.timing.previewDelay)
        await settle()
        #expect(h.store.agent("t1")?.finalMessage != nil)
    }

    @Test("the next turn drops it")
    func nextTurnClears() async {
        let h = harness()
        h.status("t1", "done", app: "codex", seq: 11)
        h.scheduler.advance(by: h.store.timing.previewDelay)
        await settle()
        h.status("t1", "working", app: "codex", seq: 12)
        #expect(h.store.agent("t1")?.finalMessage == nil)
    }

    @Test("a status message from the source wins: no screen read")
    func statusMessageWins() async {
        let h = harness(app: "claude-code")
        h.client.emit(.event(seq: 11, .status(terminal: "t1", status: CoreStatus(state: "done", app: "claude-code", kind: nil, msg: "all tests pass"), reported: true)))
        h.scheduler.advance(by: h.store.timing.previewDelay)
        await settle()
        #expect(reads(h) == 0)
        #expect(h.store.agent("t1")?.finalMessage == nil)
    }

    @Test("a failed read isn't retried and shows nothing")
    func failureNotRetried() async {
        let h = harness()
        h.client.readResult = .failure(.unavailable("gone"))
        h.status("t1", "done", app: "codex", seq: 11)
        h.scheduler.advance(by: h.store.timing.previewDelay)
        await settle()
        h.scheduler.advance(by: 10)
        await settle()
        #expect(reads(h) == 1)
        #expect(h.store.agent("t1")?.finalMessage == nil)
    }

    @Test("a new turn starting before the read lands keeps the stale result out")
    func staleReadDropped() async {
        let h = harness()
        h.client.holdRead = true
        h.status("t1", "done", app: "codex", seq: 11)
        h.scheduler.advance(by: h.store.timing.previewDelay)
        await settle()
        h.status("t1", "working", app: "codex", seq: 12)
        h.client.releaseRead()
        await settle()
        #expect(h.store.agent("t1")?.finalMessage == nil)
    }

    @Test("Done → Exited is the same turn settling: the message stays and the screen isn't read again")
    func exitAfterDoneKeeps() async {
        let h = harness()
        h.status("t1", "done", app: "codex", seq: 11)
        h.scheduler.advance(by: h.store.timing.previewDelay)
        await settle()
        let before = reads(h)
        h.client.emit(.event(seq: 12, .finished(terminal: "t1", exitCode: 0, reason: nil, finishedMs: nil)))
        h.scheduler.advance(by: h.store.timing.previewDelay)
        await settle()
        #expect(h.store.agent("t1")?.finalMessage != nil)
        #expect(reads(h) == before)
    }

    @Test("left the finished state before the delay ran out: no read")
    func leftBeforeDelay() async {
        let h = harness()
        h.status("t1", "done", app: "codex", seq: 11)
        h.status("t1", "error", app: "codex", seq: 12)
        h.scheduler.advance(by: h.store.timing.previewDelay)
        await settle()
        #expect(reads(h) == 0)
    }

    @Test("removed while the read is in flight and created again: the old read doesn't land on the new agent")
    func removedDuringRead() async {
        let h = harness()
        h.client.holdRead = true
        h.status("t1", "done", app: "codex", seq: 11)
        h.scheduler.advance(by: h.store.timing.previewDelay)
        await settle()
        h.client.emit(.event(seq: 12, .removed(terminal: "t1")))
        h.client.emit(.event(seq: 13, .created(term("t1", "done", app: "codex"))))
        h.client.releaseRead()
        await settle()
        #expect(h.store.agent("t1") != nil)
        #expect(h.store.agent("t1")?.finalMessage == nil)
    }

    @Test("lastWords: the source's summary first, else the final message")
    func lastWords() async {
        let h = harness()
        h.status("t1", "done", app: "codex", seq: 11)
        h.scheduler.advance(by: h.store.timing.previewDelay)
        await settle()
        #expect(h.store.agent("t1")?.lastWords?.hasSuffix("O(1) time.") == true)
        h.client.emit(.event(seq: 12, .status(terminal: "t1", status: CoreStatus(state: "done", app: "codex", msg: "summary"), reported: true)))
        #expect(h.store.agent("t1")?.lastWords == "summary")
    }

    @Test("a removed agent drops it")
    func removedClears() async {
        let h = harness()
        h.status("t1", "done", app: "codex", seq: 11)
        h.scheduler.advance(by: h.store.timing.previewDelay)
        await settle()
        h.client.emit(.event(seq: 12, .removed(terminal: "t1")))
        h.client.emit(.event(seq: 13, .created(term("t1", "done", app: "codex"))))
        #expect(h.store.agent("t1")?.finalMessage == nil)
    }
}
