import Foundation
import Testing
@testable import AtollCore

/// Screens captured while agents worked (Claude Code 2.1.322 with statusline mods, Codex 0.167.0, via `hc read`);
/// only the long temp path is shortened.
enum WorkingScreens {
    static let rule = String(repeating: "─", count: 200)

    static let claudeWorking = [
        "",
        "⏺ 結論是 herdr-core 沒有任何活動時間戳，hc events 也只送狀態事件，所以改用 ticket 寫的輪詢方案。接下來我先抓 Working 中的真實畫面當 fixture，Claude 用這個 session，Codex 另開一個。 · summary",
        "",
        "⏺ Ticket 36 調查中：hc events 無輸出事件，接著查 herdr-core 文件 · 4s",
        "  ⎿  $ F=/tmp/f36; mkdir -p $F; hc read t5c --lines 40 > $F/claude-w1.txt; /bin/sleep 4; hc read t5c --lines 40 > $F/claude-w2.txt; diff $F/claude-w1.txt",
        "     $F/claude-w2.txt | head -20; tail -12 $F/claude-… (4s)",
        "     (ctrl+b to run in background)",
        "",
        "⠀⠀⠄⠈⢁⣀⣏⣁⠀⠀⠀⠀  ⢀⡤⠤⣄           ⢀⣀⣀",
        "⢀⢁⣤⣶⠾⣿⡿⢿⣶⠶⣤⡀ ⠒⠋  ⠈⠹⣄⣀⡤⠴⠋⠙⠒⠒⠒⠚⠉ ⠈⠙⠲⠤⣄⣠⠤⣄⣀⣀  ⣀⡴ \u{e0b6} \u{f017}  1m 18s \u{e0b4} \u{e0b6} \u{f120}  \u{e0b4}",
        "⠈⠈⠛⠿⠶⠿⠷⠾⠿⠶⠛⠁       ⠈⠁                   ⠈⠉⠉⠁",
        "                                                                                                                                                                                                                                                                  [-]",
        "\u{e0b6} esc \u{f04d} stop \u{e0b4} \u{e0b6} ^B \u{f0c5} bg \u{e0b4} \u{e0b6} ^X⏎ \u{f0cb} queue \u{e0b4} \u{e0b6} ^⏎ \u{f0e7} now \u{e0b4} \u{e0b6} ^O \u{f1ea} log \u{e0b4}",
        "",
        rule,
        "❯",
        rule,
        "  Opus 5.5 medium │ \u{f07b} atoll \u{e0a0} main │ context ●●●○○○○○○○  31% used 310k / 1.0M · cache hit 99%",
        "  5h ●●○○○○○○○○  16% used · resets 5:00pm (in 2h30m) │ 7d ●●●●○○○○○○  41% used · resets nov 16 8:00am (in 3d 17h)",
        "  ⏵⏵ auto mode on · 1 shell · ← 1 agent",
    ].joined(separator: "\n")

    static let codexThinking = [
        "",
        "",
        "› <hc from=\"t5c\">Think step by step privately about the prime factorization of 9991 * 8633, then give only the final factorization. Do not run any commands.</hc>",
        "",
        "",
        "• Working (1s • esc to interrupt)",
        "",
        "",
        "› Ask Codex to do anything",
        "",
        "  GPT-5.6-Sol medium · /tmp/f36 · granular · Context 4% used · 5h 99% left · weekly 92% left",
        "  ← for agents · ? for shortcuts",
    ].joined(separator: "\n")

    static func replacing(_ screen: String, _ pairs: [(String, String)]) -> String {
        pairs.reduce(screen) { $0.replacingOccurrences(of: $1.0, with: $1.1) }
    }
}

@Suite("No output: screen fingerprint")
struct OutputFingerprintTests {
    @Test("Claude Code: ticking timers, statusline art and the status rows below the box don't count as output")
    func claudeVolatileIgnored() {
        let later = WorkingScreens.replacing(WorkingScreens.claudeWorking, [
            ("1m 18s", "1m 52s"), ("… (4s)", "… (37s)"), ("文件 · 4s", "文件 · 37s"),
            ("⠀⠀⠄⠈⢁⣀⣏⣁⠀⠀⠀⠀  ⢀⡤⠤⣄", "⢀⠐⠀⠀⢀⣀⣏⣁⠀⠀⠀⠀          ⢀⣠⣄⣀"),
            ("31% used 310k", "33% used 331k"), ("16% used", "17% used"),
        ])
        #expect(later != WorkingScreens.claudeWorking)
        #expect(OutputFilter.activityFingerprint(later, tool: .claudeCode)
            == OutputFilter.activityFingerprint(WorkingScreens.claudeWorking, tool: .claudeCode))
    }

    @Test("Claude Code: the blinking ⏺ of a running tool row doesn't count")
    func claudeBlinkIgnored() {
        let blinkOff = WorkingScreens.replacing(WorkingScreens.claudeWorking, [("⏺ Ticket 36", "  Ticket 36")])
        #expect(OutputFilter.activityFingerprint(blinkOff, tool: .claudeCode)
            == OutputFilter.activityFingerprint(WorkingScreens.claudeWorking, tool: .claudeCode))
    }

    @Test("Claude Code: a running tool row's title, which Claude Code rewrites into a summary every so often, doesn't count")
    func claudeToolTitleIgnored() {
        let retitled = WorkingScreens.replacing(WorkingScreens.claudeWorking, [
            ("⏺ Ticket 36 調查中：hc events 無輸出事件，接著查 herdr-core 文件 · 4s", "  Running 1 shell command…"),
        ])
        #expect(OutputFilter.activityFingerprint(retitled, tool: .claudeCode)
            == OutputFilter.activityFingerprint(WorkingScreens.claudeWorking, tool: .claudeCode))
    }

    @Test("Claude Code: a new output row counts")
    func claudeOutputCounts() {
        let later = WorkingScreens.replacing(WorkingScreens.claudeWorking, [
            ("     (ctrl+b to run in background)", "     Compiling Atoll…\n     (ctrl+b to run in background)"),
        ])
        #expect(OutputFilter.activityFingerprint(later, tool: .claudeCode)
            != OutputFilter.activityFingerprint(WorkingScreens.claudeWorking, tool: .claudeCode))
    }

    @Test("Codex: the Working (Ns • esc to interrupt) row doesn't count; the reply does")
    func codexWorkingRow() {
        let base = OutputFilter.activityFingerprint(WorkingScreens.codexThinking, tool: .codex)
        let later = WorkingScreens.replacing(WorkingScreens.codexThinking, [("(1s •", "(47s •"), ("4% used", "5% used")])
        #expect(OutputFilter.activityFingerprint(later, tool: .codex) == base)
        let replied = WorkingScreens.replacing(WorkingScreens.codexThinking, [("• Working (1s • esc to interrupt)", "• 89 × 97² × 103")])
        #expect(OutputFilter.activityFingerprint(replied, tool: .codex) != base)
    }

    @Test("generic tools: elapsed-time and token counters are ignored, other text isn't")
    func generic() {
        let a = OutputFilter.activityFingerprint("building… 12s · 900 tokens\nstep 3", tool: .generic)
        #expect(OutputFilter.activityFingerprint("building… 1m 40s · 12,345 tokens\nstep 3", tool: .generic) == a)
        #expect(OutputFilter.activityFingerprint("building… 1m40s · 1.2k tokens\nstep 3", tool: .generic) == a)
        #expect(OutputFilter.activityFingerprint("building… 12s · 900 tokens\nstep 4", tool: .generic) != a)
    }

    @Test("Codex: a reply that mentions esc to interrupt is still output")
    func codexReplyMentioningEsc() {
        let base = OutputFilter.activityFingerprint(WorkingScreens.codexThinking, tool: .codex)
        let replied = WorkingScreens.replacing(WorkingScreens.codexThinking, [("• Working (1s • esc to interrupt)", "• Press esc to interrupt a running turn.")])
        #expect(OutputFilter.activityFingerprint(replied, tool: .codex) != base)
    }
}

@MainActor
@Suite("No output: store")
struct NoOutputStoreTests {
    func harness(_ terminals: [TerminalInfo] = [term("t1", "working")]) -> Harness {
        let h = Harness()
        h.client.readResult = .success(ReadOutput(text: WorkingScreens.claudeWorking, how: "screen"))
        h.connect(terminals)
        return h
    }

    func checks(_ h: Harness) -> Int {
        let lines = h.store.timing.outputCheckLines
        return h.client.commands.filter { if case .read(_, let n) = $0 { n == lines } else { false } }.count
    }

    /// Runs the scheduler in 6 s steps (with heartbeats, so the source stays live), letting each read land.
    func run(_ h: Harness, minutes: Int) async {
        for _ in 0..<(minutes * 10) {
            h.client.emit(.heartbeat(seq: 10))
            h.scheduler.advance(by: 6)
            await settle()
        }
    }

    @Test("an unchanged screen past the threshold is marked, counted from the first check")
    func unchangedMarked() async {
        let h = harness()
        await run(h, minutes: 11)
        #expect(h.store.agent("t1")?.noOutputSince == nil)
        await run(h, minutes: 2)
        let since = h.store.agent("t1")?.noOutputSince
        #expect(since != nil)
        #expect(checks(h) >= 6)
    }

    @Test("spinners and timers ticking don't count as output")
    func tickingIgnored() async {
        let h = harness()
        for minute in 0..<14 {
            let later = WorkingScreens.replacing(WorkingScreens.claudeWorking, [("1m 18s", "\(minute)m 5s"), ("… (4s)", "… (\(minute)s)")])
            h.client.readResult = .success(ReadOutput(text: later, how: "screen"))
            await run(h, minutes: 1)
        }
        #expect(h.store.agent("t1")?.noOutputSince != nil)
    }

    @Test("new output clears the mark and restarts the count")
    func changeClears() async {
        let h = harness()
        await run(h, minutes: 14)
        #expect(h.store.agent("t1")?.noOutputSince != nil)
        h.client.readResult = .success(ReadOutput(text: WorkingScreens.codexThinking, how: "screen"))
        await run(h, minutes: 3)
        #expect(h.store.agent("t1")?.noOutputSince == nil)
    }

    @Test("leaving Working clears it at once and stops checking")
    func leavingClears() async {
        let h = harness()
        await run(h, minutes: 14)
        h.status("t1", "done", seq: 11)
        #expect(h.store.agent("t1")?.noOutputSince == nil)
        let before = checks(h)
        await run(h, minutes: 5)
        #expect(checks(h) == before)
        h.status("t1", "working", seq: 12)
        await run(h, minutes: 3)
        #expect(h.store.agent("t1")?.noOutputSince == nil)
    }

    @Test("one failed check changes nothing; consecutive failures hide the mark; neither resets the count")
    func failures() async {
        let h = harness()
        await run(h, minutes: 14)
        let since = h.store.agent("t1")?.noOutputSince
        #expect(since != nil)
        h.client.readResult = .failure(.unavailable("gone"))
        await run(h, minutes: 2)
        #expect(h.store.agent("t1")?.noOutputSince == since)
        await run(h, minutes: 2)
        #expect(h.store.agent("t1")?.noOutputSince == nil)
        h.client.readResult = .success(ReadOutput(text: WorkingScreens.claudeWorking, how: "screen"))
        await run(h, minutes: 3)
        #expect(h.store.agent("t1")?.noOutputSince == since)
    }

    @Test("a read that never answers doesn't stop the checks for good")
    func hungReadRecovers() async {
        let h = harness()
        h.client.holdRead = true
        await run(h, minutes: 3)
        let stuck = checks(h)
        #expect(stuck == 1)
        await run(h, minutes: 6)
        #expect(checks(h) > stuck)
        h.client.holdRead = false
        h.client.releaseRead()
    }

    @Test("many working agents: never more than the per-minute cap, intervals stretch instead")
    func throttled() async {
        let h = harness((1...30).map { term("t\($0)", "working") })
        var last = 0
        for _ in 0..<15 {
            await run(h, minutes: 1)
            let now = checks(h)
            #expect(now - last <= h.store.timing.outputChecksPerMinute)
            last = now
        }
        #expect(last > 0)
    }

    @Test("turned off: no checks at all")
    func off() async {
        let h = harness()
        h.store.noOutputThreshold = nil
        await run(h, minutes: 15)
        #expect(checks(h) == 0)
        #expect(h.store.agent("t1")?.noOutputSince == nil)
    }
}
