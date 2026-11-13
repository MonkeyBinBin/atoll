import AppKit
import AtollCore
import SwiftUI

struct AgentPanelView: View {
    @Bindable var model: IslandModel
    let agent: Agent
    @Environment(AppSettings.self) private var settings
    @State private var draft = ""
    @State private var focusError: HerdrError?
    @FocusState private var inputFocused: Bool
    @FocusState private var searchFocused: Bool
    @State private var headerHovered = false

    private var store: AgentStore { model.store }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            outputSection
            replySection
            footer
        }
        .padding(14)
        .onAppear {
            inputFocused = agent.replyMode.isText || agent.replyMode == .textAndKeys
            model.panelHasDraft = false
            takePrefill()
        }
        .onChange(of: model.draftPrefill[agent.address]) { _, _ in takePrefill() }
        .onChange(of: model.queueRequest) { _, _ in queueDraft() }
        .onChange(of: agent.address) { _, _ in
            queuedExpanded = false
            replaceToken = nil
        }
        .onChange(of: model.quickReplyRequest) { _, request in
            guard let request, agent.replyMode.isText || agent.replyMode == .textAndKeys,
                  settings.quickReplies.indices.contains(request.index) else { return }
            sendQuickReply(settings.quickReplies[request.index])
        }
        .onChange(of: draft) { _, text in
            model.panelHasDraft = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        .onChange(of: model.searchFocusRequest) { _, _ in
            model.outputSearch?.update(text: outputText(store.panel))
            searchFocused = true
        }
        .onChange(of: model.replyFocusRequest) { _, _ in
            if agent.replyMode.isText || agent.replyMode == .textAndKeys { inputFocused = true }
        }
        .onChange(of: searchFocused) { _, focused in model.searchFieldFocused = focused }
    }

    private func takePrefill() {
        guard let text = model.draftPrefill.removeValue(forKey: agent.address) else { return }
        // Never overwrite what the user is typing: the returned text goes above it.
        draft = draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? text : text + "\n" + draft
    }

    // MARK: Header

    /// One-shot "notify me when this turn finishes"; shown as always-on when Settings already covers Done.
    @ViewBuilder
    private var doneBell: some View {
        let always = settings.doneNotifyAgents.contains(agent.address) || settings.doneNotifyProjects.contains(agent.projectPath)
        let armed = store.notifyWhenDone.contains(agent.address)
        Button {
            store.toggleNotifyWhenDone(agent.address)
        } label: {
            Image(systemName: always ? "bell.badge.fill" : armed ? "bell.fill" : "bell")
                .foregroundStyle(always || armed ? AnyShapeStyle(PixelPalette.done.color) : AnyShapeStyle(.secondary))
        }
        .buttonStyle(.borderless)
        .disabled(always)
        .help(always
            ? "Always notifies on Done (set in Settings)"
            : armed ? "Will notify when this turn finishes · click to cancel" : "Notify me when this turn finishes")
    }

    /// Other agents still waiting (⌘] jumps to the next), or a short All clear once none are.
    @ViewBuilder
    private var queueBadge: some View {
        let others = store.agents.filter { $0.state.isNeedsYou && $0.address != agent.address }.count
        if others > 0 {
            Button {
                model.openNextWaiting()
            } label: {
                Label("\(others) more waiting", systemImage: AgentState.needsYou(.unspecified).symbol)
            }
            .buttonStyle(.borderless)
            .font(.system(size: 11))
            .foregroundStyle(AgentState.needsYou(.unspecified).color)
            .help("Next waiting agent (⌘])")
        } else if model.allClear {
            Label("All clear", systemImage: "checkmark.circle")
                .font(.system(size: 11))
                .foregroundStyle(PixelPalette.done.color)
                .transition(.opacity)
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            AgentSprite(agent: agent, store: store, scale: 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(targetLabel)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    HStack(spacing: 4) {
                        Image(systemName: agent.state.symbol)
                        Text("\(agent.state.fullLabel) · \(Format.duration(since: agent.stateSince, now: context.date))")
                        NoOutputLabel(since: agent.noOutputSince, now: context.date)
                        Text("· Last status change \(Format.ago(agent.lastStatusChange, now: context.date))")
                            .foregroundStyle(.secondary)
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(agent.state.color)
                }
                if let summary = agent.changeSummary {
                    if store.changeInspector != nil, !summary.isEmpty {
                        Button {
                            if store.panel?.changes == nil { store.showChanges() } else { store.hideChanges() }
                        } label: {
                            HStack(spacing: 4) {
                                ChangeSummaryLabel(summary: summary)
                                Image(systemName: store.panel?.changes == nil ? "chevron.right" : "chevron.down")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .help(store.panel?.changes == nil ? "Show the changed files and diffs" : "Back to the terminal output")
                    } else {
                        ChangeSummaryLabel(summary: summary)
                    }
                }
                SharedTreeLabel(agent: agent, store: store, lineLimit: 2) { model.openLaunchInWorktree(for: agent) }
            }
            Spacer()
            queueBadge
            if headerHovered {
                Label("Click to collapse", systemImage: "chevron.up")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            }
            PinButton(model: model)
            doneBell
            Button {
                model.escape()
            } label: {
                Image(systemName: "list.bullet")
            }
            .buttonStyle(.borderless)
            .help("Back to agent list (esc)")
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(headerHovered ? 0.07 : 0))
        )
        .padding(.horizontal, -6)
        .padding(.vertical, -4)
        // The whole info row collapses the island in one click.
        .contentShape(Rectangle())
        .onTapGesture {
            if headerHovered { NSCursor.pop() }
            headerHovered = false
            model.collapse()
        }
        .onHover { inside in
            guard inside != headerHovered else { return }
            withAnimation(.easeOut(duration: 0.12)) { headerHovered = inside }
            if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
        .help("Collapse to the island")
    }

    private var targetLabel: String {
        switch agent.replyMode {
        case .text(force: true), .textAndKeys: "Answer \(agent.displayName)"
        default: "Send to \(agent.displayName)"
        }
    }

    // MARK: Output

    @ViewBuilder
    private var outputSection: some View {
        if let changes = store.panel?.changes {
            ChangesView(
                changes: changes,
                store: store,
                font: TerminalFont.font(family: settings.outputFontFamily, size: settings.outputFontSize),
                height: settings.largePanel ? 460 : 220
            )
        } else {
            terminalOutput
        }
    }

    private var terminalOutput: some View {
        let panel = store.panel
        let text = outputText(panel)
        // Highlights only once the search has matched this very text (it catches up right after a refresh).
        let search = model.outputSearch.flatMap { $0.text == text ? $0 : nil }
        return VStack(alignment: .leading, spacing: 4) {
            if model.outputSearch != nil { searchRow }
            TerminalOutputView(
                text: text,
                font: TerminalFont.font(family: settings.outputFontFamily, size: settings.outputFontSize),
                wrap: settings.wrapOutput,
                highlights: search?.matches ?? [],
                current: search?.current,
                searching: model.outputSearch?.query.isEmpty == false,
                scrollRequest: model.searchScrollRequest
            )
            .frame(height: settings.largePanel ? 460 : 220)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.05)))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            // Refreshed output, Messages only flipped, or back from the changes view: match the text as shown.
            .onChange(of: text, initial: true) { _, text in model.outputSearch?.update(text: text) }
            HStack(spacing: 8) {
                if let fetched = panel?.fetchedAt {
                    Text("Fetched at \(Format.clockSeconds.string(from: fetched))")
                }
                if panel?.output?.isScreenOnly == true || agent.state == .working || agent.state.isNeedsYou {
                    Text("Screen only")
                        .padding(.horizontal, 5)
                        .background(Capsule().strokeBorder(Color.secondary.opacity(0.6)))
                }
                if let error = panel?.error {
                    Text("Couldn't read output: \(error.message)")
                        .foregroundStyle(PixelPalette.error.color)
                        .lineLimit(1)
                }
                Spacer()
                if panel?.isLoading == true {
                    ProgressView().controlSize(.mini)
                }
                Toggle("Messages only", isOn: Binding(get: { settings.messagesOnly }, set: { settings.messagesOnly = $0 }))
                    .toggleStyle(.checkbox)
                    .controlSize(.mini)
                    .help("Hide the input box, status lines and mod rows")
                Toggle("Wrap", isOn: Binding(get: { settings.wrapOutput }, set: { settings.wrapOverride = $0 }))
                    .toggleStyle(.checkbox)
                    .controlSize(.mini)
                    .help("Wrap long lines instead of scrolling sideways")
                Button { settings.adjustFontSize(-1) } label: { Image(systemName: "textformat.size.smaller") }
                    .buttonStyle(.borderless)
                    .help("Smaller text (⌘-)")
                Button { settings.adjustFontSize(1) } label: { Image(systemName: "textformat.size.larger") }
                    .buttonStyle(.borderless)
                    .help("Larger text (⌘+)")
                Button {
                    settings.largePanel.toggle()
                } label: {
                    Image(systemName: settings.largePanel ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                }
                .buttonStyle(.borderless)
                .help(settings.largePanel ? "Smaller panel" : "Larger panel")
                Button("Refresh") { store.refreshPanelOutput() }
                    .buttonStyle(.borderless)
            }
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
        }
    }

    /// ⌘F row: ↩ / ⇧↩ (through the key monitor) step through matches, Esc closes it.
    private var searchRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Find in output", text: Binding(
                get: { model.outputSearch?.query ?? "" },
                set: { model.setSearchQuery($0) }
            ))
            .textFieldStyle(.plain)
            .focused($searchFocused)
            if let counter = model.outputSearch?.counter {
                Text(counter)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            let hasMatches = model.outputSearch?.current != nil
            Button { model.stepSearch(forward: false) } label: { Image(systemName: "chevron.up") }
                .buttonStyle(.borderless)
                .disabled(!hasMatches)
                .help("Previous match (⇧↩)")
            Button { model.stepSearch(forward: true) } label: { Image(systemName: "chevron.down") }
                .buttonStyle(.borderless)
                .disabled(!hasMatches)
                .help("Next match (↩)")
            Button { model.closeSearch() } label: { Image(systemName: "xmark.circle.fill") }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Close search (esc)")
        }
        .font(.system(size: 11))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.08)))
    }

    private func outputText(_ panel: PanelState?) -> String {
        guard let output = panel?.output else { return panel?.isLoading == true ? "Loading…" : "" }
        let text = settings.messagesOnly
            ? OutputFilter.messages(output.text, tool: agent.tool, app: agent.app)
            : OutputFilter.clean(output.text)
        return text.split(separator: "\n", omittingEmptySubsequences: false).suffix(200).joined(separator: "\n")
    }

    // MARK: Reply

    @ViewBuilder
    private var replySection: some View {
        switch agent.replyMode {
        case .text(let force):
            textReply(force: force)
        case .keys:
            keyRow
        case .textAndKeys:
            // Blocked, kind unknown: it may be a question (type) or a prompt (press a key).
            VStack(alignment: .leading, spacing: 10) {
                keyRow
                textReply(force: true)
            }
        case .openInHerdrOnly:
            HStack(spacing: 8) {
                Image(systemName: "lock.fill").foregroundStyle(PixelPalette.waiting.color)
                Text("Sign-in required — finish it in the full terminal.")
                    .font(.system(size: 12))
                Spacer()
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.05)))
        case .none:
            Text("This session has exited.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }

    private func textReply(force: Bool) -> some View {
        let state = store.sendStates[agent.address]
        let inFlight = state?.isInFlight == true
        return VStack(alignment: .leading, spacing: 6) {
            queuedRow
            HStack(alignment: .bottom, spacing: 8) {
                TextField(force ? "Answer \(agent.displayName)…" : "Message \(agent.displayName)…", text: $draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .lineLimit(1...5)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.08)))
                    .focused($inputFocused)
                    .onSubmit(submit)
                    .disabled(inFlight)
                if canQueue {
                    // ⌥↩ comes through the key monitor (`queueRequest`), not a keyboard shortcut.
                    Button(replacePending ? "Replace queued?" : "Queue ⌥↩", action: queueDraft)
                        .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .help(replacePending
                            ? "Click again to replace the queued message"
                            : "Send this when the current turn ends (Done or Idle), not now")
                }
                Button(force ? "Answer" : "Send", action: submit)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(inFlight || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .commandCompletion(
                model: model, draft: $draft, focused: inputFocused,
                tool: agent.tool, cwd: agent.projectPath, onSubmit: submit
            )
            if let choices = agent.questionChoices {
                QuestionButtons(agent: agent, choices: choices, store: store)
            }
            quickReplyRow(disabled: inFlight)
            sendStatus(state)
        }
    }

    @ViewBuilder
    private func sendStatus(_ state: SendState?) -> some View {
        if let state {
            HStack(spacing: 6) {
                switch state {
                case .waiting:
                    ProgressView().controlSize(.mini)
                    Text(state.label)
                case .failed(let error):
                    Image(systemName: "xmark.octagon.fill").foregroundStyle(PixelPalette.error.color)
                    Text("\(state.label) · \(error.kind): \(error.message)\(error.hint.map { " — \($0)" } ?? "")")
                        .lineLimit(2)
                    Spacer()
                    Button("Resend") { resend() }
                        .buttonStyle(.borderless)
                        .disabled(lastSent.isEmpty)
                case .started:
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(PixelPalette.done.color)
                    Text(state.label)
                case .delivered, .unconfirmed:
                    Image(systemName: "checkmark").foregroundStyle(.secondary)
                    Text(state.label)
                }
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
        }
    }

    @State private var lastSent = ""
    /// Set by a first Queue press while a message is already queued; a second press within 4 s replaces it.
    @State private var replaceToken: UUID?
    @State private var queuedExpanded = false

    private var replacePending: Bool { replaceToken != nil }
    private var canQueue: Bool { store.canQueue(agent.address) }

    private func queueDraft() {
        guard canQueue, !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if store.queuedMessages[agent.address] != nil, !replacePending {
            let token = UUID()
            replaceToken = token
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                if replaceToken == token { replaceToken = nil }
            }
            return
        }
        replaceToken = nil
        if store.queue(draft, for: agent.address) { draft = "" }
    }

    /// The queued message (one line, click to expand) with its actions, or a note on what became of it.
    @ViewBuilder
    private var queuedRow: some View {
        if let queued = store.queuedMessages[agent.address] {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: queued.status.symbol)
                    .foregroundStyle(queued.status.color)
                VStack(alignment: .leading, spacing: 2) {
                    Text(queued.status.title)
                        .foregroundStyle(.secondary)
                    Text(queued.text)
                        .lineLimit(queuedExpanded ? 8 : 1)
                        .truncationMode(.tail)
                        .onTapGesture { queuedExpanded.toggle() }
                        .help(queuedExpanded ? "Click to collapse" : "Click to show it all")
                }
                Spacer(minLength: 4)
                if queued.status == .held {
                    Button("Send now") { store.sendQueuedNow(agent.address) }
                        .buttonStyle(.borderless)
                        .disabled(!store.canSendQueuedNow(agent.address))
                        .help(store.canSendQueuedNow(agent.address)
                            ? "Send it now" : "It would answer the dialog the agent is waiting on")
                }
                if queued.status != .sending {
                    Button("Edit") {
                        if let text = store.editQueued(agent.address) {
                            draft = text
                            inputFocused = true
                        }
                    }
                    .buttonStyle(.borderless)
                    .help("Back into the reply box; no longer queued")
                    Button("Cancel") { store.cancelQueued(agent.address) }
                        .buttonStyle(.borderless)
                }
            }
            .font(.system(size: 11))
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.05)))
        } else if let notice = store.queueNotices[agent.address] {
            Label(notice == .dropped ? "Queued message dropped · the agent exited"
                  : "Queued message not sent · another message was still sending; it's back in the box",
                  systemImage: "xmark.circle")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    /// Canned replies: click sends, ⌥-click puts the text in the reply box to edit.
    @ViewBuilder
    private func quickReplyRow(disabled: Bool) -> some View {
        let replies = settings.quickReplies
        if !replies.isEmpty {
            HStack(spacing: 6) {
                ForEach(Array(replies.enumerated()), id: \.offset) { index, text in
                    Button {
                        if NSEvent.modifierFlags.contains(.option) {
                            draft = text
                            inputFocused = true
                        } else {
                            sendQuickReply(text)
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(Format.chipTitle(text)).lineLimit(1)
                            Text("⌘⇧\(index + 1)").foregroundStyle(.tertiary)
                        }
                        .font(.system(size: 11))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.white.opacity(0.08)))
                    }
                    .buttonStyle(.plain)
                    .disabled(disabled)
                    .help("\(text) — click to send, ⌥-click to edit first")
                }
                Spacer(minLength: 0)
            }
        }
    }

    /// Same path as the reply box, but leaves the draft alone.
    private func sendQuickReply(_ text: String) {
        guard store.sendStates[agent.address]?.isInFlight != true else { return }
        lastSent = text
        store.send(text, to: agent.address)
    }

    private func submit() {
        let text = draft
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              store.sendStates[agent.address]?.isInFlight != true else { return }
        lastSent = text
        store.send(text, to: agent.address)
        draft = ""
    }

    /// Manual resend only — the app never resends on its own.
    private func resend() {
        guard !lastSent.isEmpty else { return }
        store.send(lastSent, to: agent.address)
    }

    private var keyRow: some View {
        let state = store.keyStates[agent.address]
        let sending: Bool = if case .sending = state { true } else { false }
        return VStack(alignment: .leading, spacing: 6) {
            Text("Press a key in \(agent.displayName)")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                ForEach(AgentStore.permissionKeys, id: \.self) { key in
                    Button(Self.keyTitle(key)) { store.pressKey(key, on: agent.address) }
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .disabled(sending)
                }
            }
            if let state {
                HStack(spacing: 6) {
                    switch state {
                    case .sending(let key):
                        ProgressView().controlSize(.mini)
                        Text("Sending \(Self.keyTitle(key))…")
                    case .sent(let key):
                        Image(systemName: "checkmark").foregroundStyle(PixelPalette.done.color)
                        Text("Sent \(Self.keyTitle(key))")
                    case .failed(let key, let error):
                        Image(systemName: "xmark.octagon.fill").foregroundStyle(PixelPalette.error.color)
                        Text("Failed \(Self.keyTitle(key)) · \(error.kind): \(error.message)\(error.hint.map { " — \($0)" } ?? "")")
                            .lineLimit(2)
                    }
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            }
        }
    }

    static func keyTitle(_ key: String) -> String {
        switch key {
        case "enter": "Enter"
        case "esc": "Esc"
        default: key
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 10) {
            if agent.state != .exited {
                let interrupt = store.interruptState(agent.address)
                Button {
                    store.pressInterrupt(agent.address)
                } label: {
                    Label(interrupt.label, systemImage: "stop.circle")
                }
                .tint(interrupt == .confirming ? PixelPalette.error.color : nil)
                .foregroundStyle(interrupt == .confirming ? PixelPalette.error.color : .primary)
                .disabled(interrupt == .interrupting)
            }
            if let outcome = agent.interruptFeedback {
                Text("Interrupted · \(outcome.label)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            }
            Spacer()
            if let origin = agent.origin.map(OriginApp.init(origin:)), origin.canActivate {
                // Started from a terminal outside Herdr: jump back to it.
                Button {
                    model.collapse()
                    origin.activate()
                } label: {
                    Label("Switch to \(origin.name)", systemImage: "macwindow")
                }
                .help("Back to the \(origin.name) window this agent runs in (if it's still open)")
            }
            VStack(alignment: .trailing, spacing: 2) {
                let open = OpenTarget(agent.source)
                let blocked = agent.source == .core && !store.herdrAppRunning
                Button {
                    Task { focusError = await store.openInHerdr(agent.address) }
                } label: {
                    Label(open.title, systemImage: "arrow.up.forward.app")
                }
                .disabled(blocked)
                .help(open.help)
                if agent.source == .herdrCLI, focusError == nil {
                    Text("Switches the pane inside herdr")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                if blocked {
                    Text("Herdr app isn't running")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                } else if let focusError {
                    Text(focusError.message)
                        .font(.system(size: 10))
                        .foregroundStyle(PixelPalette.error.color)
                        .lineLimit(1)
                }
            }
        }
        .font(.system(size: 12))
    }
}

extension ReplyMode {
    var isText: Bool {
        if case .text = self { return true }
        return false
    }
}

/// Where "Open in …" takes an agent, per source.
struct OpenTarget {
    let title: String
    let help: String

    init(_ source: AgentSource) {
        switch source.id {
        case AgentSource.herdrCLI.id:
            title = "Open in herdr"
            help = "Focus this agent's pane inside herdr. Switch to the terminal running herdr to see it."
        case AgentSource.cmux.id:
            title = "Open in cmux"
            help = "Bring cmux forward on this agent's tab."
        default:
            title = "Open in Herdr"
            help = "Show this agent in the Herdr app."
        }
    }
}
