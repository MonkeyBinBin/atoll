import AtollCore
import SwiftUI

extension View {
    /// `/` (and Codex `$`) completion for a text box: suggestions under it; ↑↓ Tab Return Esc arrive
    /// through the island's key monitor while they show. `onSubmit` runs when Return lands on a
    /// command that is already typed in full, so `/clear` + Return sends like the CLI.
    func commandCompletion(
        model: IslandModel, draft: Binding<String>, focused: Bool, tool: AgentTool, cwd: String?,
        onSubmit: (() -> Void)? = nil
    ) -> some View {
        modifier(CommandCompletionModifier(model: model, draft: draft, focused: focused, tool: tool, cwd: cwd, onSubmit: onSubmit))
    }
}

private struct CommandCompletionModifier: ViewModifier {
    let model: IslandModel
    @Binding var draft: String
    let focused: Bool
    let tool: AgentTool
    let cwd: String?
    let onSubmit: (() -> Void)?

    @State private var completion = CommandCompletion()

    private struct CatalogKey: Hashable {
        var tool: AgentTool
        var cwd: String?
    }

    func body(content: Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            content
            if focused, completion.isActive {
                CommandSuggestionList(completion: completion, onPick: pick)
            }
        }
        .task(id: CatalogKey(tool: tool, cwd: cwd)) {
            let (tool, cwd) = (tool, cwd)
            let commands = await Task.detached(priority: .userInitiated) {
                SlashCommandCatalog.load(tool: tool, cwd: cwd)
            }.value
            completion.commands = commands
            completion.update(draft: draft)
            sync()
        }
        .onChange(of: draft) { _, text in
            completion.update(draft: text)
            sync()
        }
        .onChange(of: focused) { sync() }
        .onChange(of: model.completionKeyRequest) { _, request in
            guard let request, focused, completion.isActive else { return }
            handle(request.key)
        }
        .onDisappear { model.completionActive = false }
    }

    private func handle(_ key: IslandModel.CompletionKey) {
        switch key {
        case .previous: completion.move(-1)
        case .next: completion.move(1)
        case .complete: apply(nil)
        case .accept:
            if completion.isExact(draft), let onSubmit {
                completion.dismiss(draft: draft)
                sync()
                onSubmit()
            } else {
                apply(nil)
            }
        case .dismiss:
            completion.dismiss(draft: draft)
            sync()
        }
    }

    private func pick(_ command: SlashCommand) {
        apply(command)
    }

    private func apply(_ command: SlashCommand?) {
        if let text = completion.complete(draft, with: command) { draft = text }
    }

    private func sync() {
        let active = focused && completion.isActive
        if model.completionActive != active { model.completionActive = active }
    }
}

/// The suggestion rows: token, argument hint, where it comes from, and the description.
struct CommandSuggestionList: View {
    let completion: CommandCompletion
    let onPick: (SlashCommand) -> Void

    static let rowHeight: CGFloat = 34
    static let visibleRows = 6

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(completion.suggestions.enumerated()), id: \.element.id) { index, command in
                        row(command, selected: index == completion.selection)
                            .id(command.id)
                            .onTapGesture { onPick(command) }
                    }
                }
            }
            .scrollIndicators(.automatic)
            .frame(height: CGFloat(min(completion.suggestions.count, Self.visibleRows)) * Self.rowHeight)
            .onChange(of: completion.selection) { _, _ in
                if let id = completion.selected?.id { proxy.scrollTo(id) }
            }
        }
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.06)))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func row(_ command: SlashCommand, selected: Bool) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(command.token)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .layoutPriority(1)
                if let hint = command.argumentHint {
                    Text(hint)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Text(Self.sourceLabel(command.source))
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .fixedSize()
            }
            if let description = command.description {
                Text(description)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, minHeight: Self.rowHeight, maxHeight: Self.rowHeight, alignment: .leading)
        .background(selected ? Color.white.opacity(0.12) : Color.clear)
        .contentShape(Rectangle())
        .help(command.description ?? command.token)
    }

    static func sourceLabel(_ source: SlashCommand.Source) -> String {
        switch source {
        case .builtIn: "built-in"
        case .personal: "user"
        case .project: "project"
        case .plugin: "plugin"
        }
    }
}
