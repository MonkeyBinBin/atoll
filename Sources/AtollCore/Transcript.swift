import Foundation

/// One shown item of an agent's conversation, read from its session transcript (ticket 61).
public struct TranscriptEntry: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// What the user typed (a prompt, or a slash command).
        case user
        /// The agent's reply text (markdown).
        case assistant
        /// A tool call; `text` is a one-line summary of its input.
        case toolCall(name: String)
        /// A tool's output, shortened.
        case toolResult
        /// Local command output and similar side notes.
        case note
    }

    public var kind: Kind
    public var text: String
    /// Ties a tool result to its call (several calls can run before their results arrive).
    public var id: String?

    public init(_ kind: Kind, _ text: String, id: String? = nil) {
        self.kind = kind
        self.text = text
        self.id = id
    }
}

/// Which transcript layout a file uses.
public enum TranscriptFormat: Sendable {
    case claudeCode
    case codex
}

/// Turns transcript lines into entries. Both layouts are undocumented and change between versions, so only known
/// row types are read and everything else is skipped; nothing here throws. Thinking / reasoning is never shown.
public enum TranscriptParser {
    /// Longest text kept per entry (one line can hold a whole file or an image).
    static let textLimit = 20_000
    /// Tool output rows kept, and the longest row.
    static let resultLines = 4
    static let resultLineLimit = 200

    public static func entries(line: Data, format: TranscriptFormat) -> [TranscriptEntry] {
        guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { return [] }
        switch format {
        case .claudeCode: return claudeEntries(object)
        case .codex: return codexEntries(object)
        }
    }

    // MARK: Claude Code

    /// `user` / `assistant` rows only (other rows carry request copies with text blocks too); meta and
    /// side-chain (sub-agent) rows are skipped.
    static func claudeEntries(_ row: [String: Any]) -> [TranscriptEntry] {
        guard let type = row["type"] as? String, type == "user" || type == "assistant",
              (row["isMeta"] as? Bool) != true, (row["isSidechain"] as? Bool) != true,
              (row["isCompactSummary"] as? Bool) != true,
              let message = row["message"] as? [String: Any] else { return [] }
        if let text = message["content"] as? String {
            return type == "user" ? claudeUserText(text) : [TranscriptEntry(.assistant, capped(text))]
        }
        guard let blocks = message["content"] as? [[String: Any]] else { return [] }
        var entries: [TranscriptEntry] = []
        for block in blocks {
            switch (type, block["type"] as? String) {
            case ("user", "text"):
                entries += claudeUserText(block["text"] as? String ?? "")
            case ("user", "image"):
                entries.append(TranscriptEntry(.user, "[image]"))
            case ("user", "tool_result"):
                if let output = toolOutput(block["content"]) {
                    entries.append(TranscriptEntry(.toolResult, output, id: block["tool_use_id"] as? String))
                }
            case ("assistant", "text"):
                let text = (block["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty { entries.append(TranscriptEntry(.assistant, capped(text))) }
            case ("assistant", "tool_use"), ("assistant", "server_tool_use"):
                let name = block["name"] as? String ?? "tool"
                entries.append(TranscriptEntry(.toolCall(name: name), summary(block["input"]), id: block["id"] as? String))
            default:
                break
            }
        }
        return entries
    }

    /// Claude Code's own wrappers around text that isn't the user's: skipped.
    static let claudeSkippedTags = [
        "system-reminder", "local-command-caveat", "task-notification", "command-message", "user-prompt-submit-hook",
    ]

    /// A user text: a prompt, or one of Claude Code's wrappers. Slash commands show as typed, `!` commands and local
    /// command output as notes; reminders, caveats and task notifications aren't the user's and are skipped. Any other
    /// text starting with `<` (a message sent through `hc`, pasted content) is the user's and shows as is.
    static func claudeUserText(_ raw: String) -> [TranscriptEntry] {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return [] }
        guard text.hasPrefix("<") else { return [TranscriptEntry(.user, capped(text))] }
        if let name = tag("command-name", in: text) {
            let args = tag("command-args", in: text) ?? ""
            return [TranscriptEntry(.user, args.isEmpty ? name : "\(name) \(args)")]
        }
        if let command = tag("bash-input", in: text) { return [TranscriptEntry(.user, "! \(command)")] }
        for name in ["local-command-stdout", "bash-stdout"] {
            if let output = tag(name, in: text), let shortened = shortened(output) {
                return [TranscriptEntry(.note, shortened)]
            }
        }
        if claudeSkippedTags.contains(where: { text.hasPrefix("<\($0)") }) { return [] }
        // A message typed in through herdr-core (`hc send`, Atoll's reply box): `<hc from="t7">text</hc>`.
        if let inner = hcInner(text) { return inner.isEmpty ? [] : [TranscriptEntry(.user, capped(inner))] }
        return [TranscriptEntry(.user, capped(text))]
    }

    /// The text of `<hc from="t7">text</hc>`; nil unless the opening tag closes before the closing one.
    static func hcInner(_ text: String) -> String? {
        guard text.hasPrefix("<hc"), let close = text.range(of: "</hc>", options: .backwards), close.upperBound == text.endIndex,
              let open = text[..<close.lowerBound].firstIndex(of: ">") else { return nil }
        let name = text[text.index(text.startIndex, offsetBy: 3)..<open]
        guard name.isEmpty || name.first == " " else { return nil }
        return String(text[text.index(after: open)..<close.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The text inside `<name>…</name>`, trimmed; nil when the tag is missing.
    static func tag(_ name: String, in text: String) -> String? {
        guard let open = text.range(of: "<\(name)>"),
              let close = text.range(of: "</\(name)>", range: open.upperBound..<text.endIndex) else { return nil }
        return String(text[open.upperBound..<close.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Codex

    /// `response_item` rows: user / assistant messages and tool calls with their output. Developer messages and the
    /// context Codex injects as user text (environment, AGENTS.md, image markers) are skipped, as is reasoning.
    static func codexEntries(_ row: [String: Any]) -> [TranscriptEntry] {
        guard (row["type"] as? String) == "response_item", let payload = row["payload"] as? [String: Any] else { return [] }
        switch payload["type"] as? String {
        case "message":
            let role = payload["role"] as? String
            guard role == "user" || role == "assistant", let content = payload["content"] as? [[String: Any]] else { return [] }
            return content.compactMap { item in
                switch item["type"] as? String {
                case "input_text":
                    let text = (item["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    guard role == "user", !text.isEmpty, !codexInjected(text) else { return nil }
                    return TranscriptEntry(.user, capped(text))
                case "input_image":
                    return role == "user" ? TranscriptEntry(.user, "[image]") : nil
                case "output_text":
                    let text = (item["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    return role == "assistant" && !text.isEmpty ? TranscriptEntry(.assistant, capped(text)) : nil
                default:
                    return nil
                }
            }
        case "function_call":
            let arguments = (payload["arguments"] as? String).flatMap { $0.data(using: .utf8) }
                .flatMap { try? JSONSerialization.jsonObject(with: $0) }
            return [TranscriptEntry(.toolCall(name: payload["name"] as? String ?? "tool"), summary(arguments ?? payload["arguments"]),
                                    id: payload["call_id"] as? String)]
        case "custom_tool_call":
            return [TranscriptEntry(.toolCall(name: payload["name"] as? String ?? "tool"), summary(payload["input"]),
                                    id: payload["call_id"] as? String)]
        case "function_call_output", "custom_tool_call_output":
            return toolOutput(payload["output"]).map { [TranscriptEntry(.toolResult, $0, id: payload["call_id"] as? String)] } ?? []
        default:
            return []
        }
    }

    /// Context Codex adds as user text: the environment, AGENTS.md, and the markers around an attached image
    /// (`<image name=[Image #1]>` … `</image>`, each a text item of its own).
    static func codexInjected(_ text: String) -> Bool {
        if ["<environment_context>", "<user_instructions>", "# AGENTS.md instructions"].contains(where: { text.hasPrefix($0) }) {
            return true
        }
        return text == "</image>" || (text.hasPrefix("<image name=") && text.hasSuffix(">") && !text.contains("\n"))
    }

    // MARK: Helpers

    /// One line describing a tool input: the command, path, pattern or URL it acts on, else its first string.
    static func summary(_ input: Any?) -> String {
        let line: String
        if let text = input as? String {
            line = text
        } else if let object = input as? [String: Any] {
            let keys = ["command", "cmd", "file_path", "path", "pattern", "query", "url", "description", "prompt"]
            let value = keys.lazy.compactMap { key -> String? in
                if let string = object[key] as? String { return string }
                if let parts = object[key] as? [String] { return parts.joined(separator: " ") }
                return nil
            }.first
            line = value ?? object.values.lazy.compactMap { $0 as? String }.first ?? ""
        } else {
            line = ""
        }
        let first = line.split(separator: "\n", omittingEmptySubsequences: true).first.map(String.init) ?? ""
        return OutputFilter.cut(first.trimmingCharacters(in: .whitespaces), limit: 120)
    }

    /// A tool result's text (a string, or text blocks), shortened; nil when there is none.
    static func toolOutput(_ content: Any?) -> String? {
        let text: String
        if let string = content as? String {
            // Some Codex versions store `{"output": "...", "metadata": {...}}` as a string.
            if string.hasPrefix("{"), let data = string.data(using: .utf8),
               let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let output = object["output"] as? String {
                text = output
            } else {
                text = string
            }
        } else if let blocks = content as? [[String: Any]] {
            text = blocks.compactMap { $0["text"] as? String }.joined(separator: "\n")
        } else if let object = content as? [String: Any], let output = object["output"] as? String {
            text = output
        } else {
            return nil
        }
        return shortened(text)
    }

    /// The first few non-blank rows, each cut, with "…" when more were left out; nil when blank.
    static func shortened(_ text: String) -> String? {
        let rows = text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { OutputFilter.cut(String($0).trimmingCharacters(in: .whitespaces), limit: resultLineLimit) }
            .filter { !$0.isEmpty }
        guard !rows.isEmpty else { return nil }
        let kept = rows.prefix(resultLines).joined(separator: "\n")
        return rows.count > resultLines ? kept + "\n… +\(rows.count - resultLines) lines" : kept
    }

    static func capped(_ text: String) -> String {
        text.count > textLimit ? String(text.prefix(textLimit)) + "\n…" : text
    }
}
