import Foundation
import Testing
@testable import AtollCore

/// Claude Code 2.1.323 `AskUserQuestion` screens, recorded in cmux (ticket 54); the right-hand pane trimmed.
enum QuestionScreens {
    static let rule = String(repeating: "─", count: 80)

    static let single = [
        "❯ 用 AskUserQuestion 工具問我一個單選題（multiSelect false）：午餐要吃什麼，三個選項",
        "🎯",
        rule,
        " ☐ 午餐",
        "",
        "午餐要吃什麼？",
        "",
        "❯ 1. 麵",
        "     湯麵或乾麵都行，出餐快，吃起來方便。",
        "  2. 飯",
        "     便當或燴飯，份量足，比較耐餓。",
        "  3. 粥",
        "     清淡好消化，適合想吃輕鬆一點的時候。",
        "  4. Type something.",
        rule,
        "  5. Chat about this",
        "",
        "Enter to select · ↑/↓ to navigate · Esc to cancel",
    ].joined(separator: "\n")

    static let multiSelect = [
        "🎯",
        rule,
        "←  ☐ 飲料  ✔ Submit  →",
        "",
        "飲料要哪些？（可複選）",
        "",
        "❯ 1. [ ] 紅茶",
        "         香氣濃、口感醇厚，配飯很搭。",
        "  2. [ ] 綠茶",
        "         清爽解膩，喝起來比較沒負擔。",
        "  3. [ ] 咖啡",
        "         提神醒腦，適合下午想專心的時候。",
        "  4. [ ] Type something",
        rule,
        "  5. Chat about this",
    ].joined(separator: "\n")

    static let tabs = [
        "🎯",
        rule,
        "←  ☐ 午餐  ☐ 飲料  ✔ Submit  →",
        "",
        "午餐要吃麵還是飯？",
        "",
        "❯ 1. 麵",
        "     湯麵或乾麵，出餐快，吃起來方便。",
        "  2. 飯",
        "     便當或燴飯，份量足，比較耐餓。",
        "  3. Type something.",
        rule,
        "  4. Chat about this",
    ].joined(separator: "\n")

    /// cmux returns a side panel drawn right of the conversation on every row (here, a statusline mod's).
    static func withSidePanel(_ screen: String, column: Int = 163) -> String {
        screen.components(separatedBy: "\n").map { line in
            let width = line.reduce(0) { $0 + OutputFilter.cellWidth($1) }
            return line + String(repeating: " ", count: max(column - width, 0)) + "│ SPELL BOOK  12.1s │"
        }.joined(separator: "\n")
    }
}

@Suite("Question choices: extraction")
struct QuestionChoicesExtractionTests {
    typealias Option = QuestionChoices.Option

    @Test("one single-select question: its options with their detail line and number key, free-text rows dropped")
    func single() {
        let choices = QuestionChoices.extract(from: QuestionScreens.single, tool: .claudeCode, kind: .question)
        #expect(choices?.options == [
            Option(label: "麵", detail: "湯麵或乾麵都行，出餐快，吃起來方便。", key: "1"),
            Option(label: "飯", detail: "便當或燴飯，份量足，比較耐餓。", key: "2"),
            Option(label: "粥", detail: "清淡好消化，適合想吃輕鬆一點的時候。", key: "3"),
        ])
    }

    @Test("a side panel on every row (cmux) doesn't leak into the options or hide the rule before the free-text rows")
    func sidePanel() {
        let choices = QuestionChoices.extract(from: QuestionScreens.withSidePanel(QuestionScreens.single), tool: .claudeCode, kind: .question)
        #expect(choices?.options.map(\.label) == ["麵", "飯", "粥"])
        #expect(choices?.options.first?.detail == "湯麵或乾麵都行，出餐快，吃起來方便。")
    }

    @Test("multiSelect and several questions (the ← tabs → header) aren't offered: a number key wouldn't answer them")
    func notSingle() {
        #expect(QuestionChoices.extract(from: QuestionScreens.multiSelect, tool: .claudeCode, kind: .question) == nil)
        #expect(QuestionChoices.extract(from: QuestionScreens.tabs, tool: .claudeCode, kind: .question) == nil)
    }
}

@MainActor
@Suite("Question choices: answering from the list")
struct QuestionResponseTests {
    func waiting(_ screen: String = QuestionScreens.single) async -> Harness {
        let h = Harness()
        h.client.readResult = .success(ReadOutput(text: screen, how: "screen"))
        h.connect([term("t1", "working", app: "claude-code")])
        h.status("t1", "blocked", app: "claude-code", kind: "question", seq: 11)
        h.scheduler.advance(by: h.store.timing.previewDelay)
        await settle()
        return h
    }

    var keys: (Harness) -> [[String]] = { h in
        h.client.commands.compactMap { if case .keys(_, let keys) = $0 { keys } else { nil } }
    }

    @Test("a recognized question: picking an option sends its number once and reports it by label")
    func pick() async throws {
        let h = await waiting()
        let agent = try #require(h.store.agent("t1"))
        let rice = try #require(agent.questionChoices?.options[1])
        #expect(agent.permissionChoices == nil)
        h.store.respond(.option(rice), to: "t1", episode: agent.waitingSince)
        await settle()
        #expect(keys(h) == [["2"]])
        #expect(h.store.permissionResponses["t1"] == .sent(.option(rice)))
        #expect(h.store.permissionResponses["t1"]?.label == "飯 sent")
    }

    @Test("a new question since the user looked: nothing sent, \"No longer waiting\"")
    func newEpisode() async throws {
        let h = await waiting()
        let seen = try #require(h.store.agent("t1"))
        let rice = try #require(seen.questionChoices?.options[1])
        h.status("t1", "working", seq: 12)
        h.scheduler.advance(by: 1)
        h.status("t1", "blocked", kind: "question", seq: 13)
        h.scheduler.advance(by: h.store.timing.previewDelay)
        await settle()
        h.store.respond(.option(rice), to: "t1", episode: seen.waitingSince)
        await settle()
        #expect(keys(h).isEmpty)
        #expect(h.store.permissionResponses["t1"] == .noLongerWaiting)
    }
}
