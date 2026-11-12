import AtollCore
import SwiftUI

struct IslandView: View {
    @Bindable var model: IslandModel
    @Environment(AppSettings.self) private var settings

    var body: some View {
        let layout = model.layout
        let hasNotch = model.geometry?.hasNotch ?? false
        let expanded = model.isExpanded
        let offline = !model.store.isLive
        let width = expanded ? model.expandedWidth(layout) : layout.collapsedWidth
        VStack(spacing: 0) {
            topRow(layout: layout, width: width, expanded: expanded)
                .frame(height: layout.height)
            if expanded {
                expandedContent
                    .frame(width: width)
                    .background(
                        GeometryReader { proxy in
                            Color.clear
                                .onAppear { model.expandedContentHeight = proxy.size.height }
                                .onChange(of: proxy.size.height) { _, h in model.expandedContentHeight = h }
                        }
                    )
                    .transition(.opacity)
            }
        }
        .frame(width: width, alignment: .top)
        .background(
            IslandBackground(
                layout: layout, width: width, expanded: expanded, offline: offline,
                urgency: model.store.agents.first(where: { $0.state.needsAttention })?.state,
                islets: islets(layout),
                decorations: settings.decorations, animate: settings.animationsEnabled
            )
        )
        .clipShape(IslandShape(topRadius: hasNotch ? 0 : layout.height / 2, bottomRadius: expanded ? 18 : (hasNotch ? 10 : layout.height / 2)))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.colorScheme, .dark)
        .animation(.snappy(duration: 0.18), value: expanded)
    }

    private func islets(_ layout: IslandLayout) -> [Islet] {
        (layout.pinned + layout.others).compactMap { agent in
            model.characterAnchors[agent.address].map { Islet(midX: $0.midX, feetY: $0.maxY, state: agent.state) }
        }
    }

    // MARK: Top row (the collapsed island)

    @ViewBuilder
    private func topRow(layout: IslandLayout, width: CGFloat, expanded: Bool) -> some View {
        let side = expanded ? (width - layout.centerWidth) / 2 : nil
        HStack(spacing: 0) {
            leftWing(layout)
                .padding(.leading, expanded ? 0 : layout.endInset)
                .frame(width: side ?? layout.leftWidth, alignment: .trailing)
            Color.clear.frame(width: layout.centerWidth)
            HStack(spacing: 0) {
                rightWing(layout)
                    .frame(maxWidth: .infinity, alignment: .leading)
                LaunchToggleButton(model: model)
                    .frame(width: IslandLayout.buttonWidth)
                TodayToggleButton(model: model)
                    .frame(width: IslandLayout.buttonWidth)
                ListToggleButton(model: model)
                    .frame(width: IslandLayout.buttonWidth)
            }
            .padding(.trailing, expanded ? 8 : layout.endInset)
            .frame(width: side ?? layout.rightWidth, alignment: .leading)
        }
        .contentShape(Rectangle())
        .onTapGesture { model.toggleList() }
    }

    private func leftWing(_ layout: IslandLayout) -> some View {
        HStack(spacing: 6) {
            if let hint = layout.hint {
                Text(hint)
                    .font(Font(IslandLayout.hintFont))
                    .foregroundStyle(model.store.isLive ? AgentState.needsYou(.unspecified).color : Color(white: 0.75))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .accessibilityLabel(hint)
            }
            ForEach(layout.pinned) { agent in
                CharacterButton(agent: agent, model: model)
            }
        }
        .padding(.horizontal, IslandLayout.padding)
        .frame(maxHeight: .infinity)
    }

    @ViewBuilder
    private func rightWing(_ layout: IslandLayout) -> some View {
        if let label = layout.spaceLabel {
            HStack(spacing: 0) {
                Text(label)
                    .font(Font(IslandLayout.spaceFont))
                    .foregroundStyle(Color(white: 0.7))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.leading, IslandLayout.padding)
                    .help("Showing one Herdr space · change it in the list (Tab)")
                    .accessibilityLabel("Space \(label)")
                if !layout.others.isEmpty {
                    if layout.rightScrolls {
                        ScrollView(.horizontal, showsIndicators: false) { othersRow(layout) }
                    } else {
                        othersRow(layout)
                    }
                }
            }
            .frame(maxHeight: .infinity)
        } else if model.store.agents.isEmpty && model.store.isLive {
            PixelIconView(tag: "empty")
                .frame(width: 18, height: 18)
                .padding(.horizontal, IslandLayout.padding + 2)
                .frame(maxHeight: .infinity)
                .accessibilityLabel("No agents")
        } else if layout.rightScrolls {
            ScrollView(.horizontal, showsIndicators: false) {
                othersRow(layout)
            }
            .mask(
                LinearGradient(stops: [
                    .init(color: .clear, location: 0), .init(color: .black, location: 0.08),
                    .init(color: .black, location: 0.92), .init(color: .clear, location: 1),
                ], startPoint: .leading, endPoint: .trailing)
            )
        } else {
            othersRow(layout)
        }
    }

    private func othersRow(_ layout: IslandLayout) -> some View {
        HStack(spacing: 6) {
            ForEach(layout.others) { agent in
                CharacterButton(agent: agent, model: model)
            }
        }
        .padding(.horizontal, IslandLayout.padding)
        .frame(maxHeight: .infinity)
    }

    // MARK: Expanded

    @ViewBuilder
    private var expandedContent: some View {
        switch model.mode {
        case .collapsed:
            EmptyView()
        case .list:
            AgentListView(model: model)
        case .panel(let address):
            if let agent = model.store.agent(address) {
                AgentPanelView(model: model, agent: agent)
                    .id(address)
            } else {
                AgentListView(model: model)
            }
        case .launch:
            LaunchFormView(model: model)
        case .today:
            TodayView(model: model)
        }
    }
}

/// Opens / closes the agent list; highlighted while the list is shown.
struct ListToggleButton: View {
    let model: IslandModel
    @State private var hovered = false

    var body: some View {
        let open = model.mode == .list
        PixelIconView(tag: open ? "list_open" : "list")
            .opacity(open || hovered ? 1 : 0.7)
            .frame(width: 18, height: 18)
            .contentShape(Rectangle())
            .onTapGesture {
                model.hover = nil
                if open { model.collapse() } else { model.showList() }
            }
            .onHover { hovered = $0 }
            .accessibilityElement()
            .accessibilityLabel(open ? "Hide agent list" : "Show agent list")
            .accessibilityAddTraits(.isButton)
    }
}

/// Opens / closes the launch form straight from the island; highlighted while it is shown.
struct LaunchToggleButton: View {
    let model: IslandModel
    @State private var hovered = false

    var body: some View {
        let open = model.mode == .launch
        PixelIconView(tag: open ? "launch_open" : "launch")
            .opacity(open || hovered ? 1 : 0.7)
            .frame(width: 18, height: 18)
            .contentShape(Rectangle())
            .onTapGesture {
                model.hover = nil
                if open { model.collapse() } else { model.openLaunch() }
            }
            .onHover { hovered = $0 }
            .accessibilityElement()
            .accessibilityLabel(open ? "Close launch form" : "Launch agent")
            .accessibilityAddTraits(.isButton)
    }
}

/// Opens / closes the Today pane straight from the island; highlighted while it is shown.
struct TodayToggleButton: View {
    let model: IslandModel
    @State private var hovered = false

    var body: some View {
        let open = model.mode == .today
        let unseen = model.store.timeline.unseenCount
        PixelIconView(tag: open ? "today_open" : "today")
            .opacity(open || hovered ? 1 : 0.7)
            .frame(width: 18, height: 18)
            .contentShape(Rectangle())
            .onTapGesture {
                model.hover = nil
                if open { model.collapse() } else { model.openToday() }
            }
            .onHover { hovered = $0 }
            .help(unseen > 0 ? "Today · \(unseen) unseen" : "Today")
            .accessibilityElement()
            .accessibilityLabel(open ? "Close Today" : unseen > 0 ? "Today, \(unseen) unseen" : "Today")
            .accessibilityAddTraits(.isButton)
    }
}

/// One pixel character in the collapsed row. Click → that agent's panel.
struct CharacterButton: View {
    let agent: Agent
    let model: IslandModel
    @Environment(AppSettings.self) private var settings
    @State private var frame: CGRect = .zero

    var body: some View {
        AgentSprite(agent: agent, store: model.store, settleAfter: model.isExpanded ? nil : 4)
        .frame(width: 16, height: 16)
        .contentShape(Rectangle())
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: {
            frame = $0
            if model.characterAnchors[agent.address] != $0 { model.characterAnchors[agent.address] = $0 }
        }
        .onDisappear {
            // Moving between wings recreates the button; don't wipe the anchor the new one already wrote.
            if model.characterAnchors[agent.address] == frame { model.characterAnchors[agent.address] = nil }
        }
        .onTapGesture {
            model.hover = nil
            model.openPanel(agent.address)
        }
        // A native tooltip never shows for a non-activating panel in a background app,
        // so hovering shows our own info card under the character instead.
        .onHover { inside in
            if inside {
                model.hover = IslandModel.Hover(address: agent.address, anchor: frame)
            } else if model.hover?.address == agent.address {
                model.hover = nil
            }
        }
        .accessibilityElement()
        .accessibilityLabel("\(agent.displayName), \(agent.state.fullLabel)")
        .accessibilityAddTraits(.isButton)
    }
}

/// Flat top (flush with the screen edge / notch), rounded bottom.
struct IslandShape: Shape {
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set {
            topRadius = newValue.first
            bottomRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let t = min(topRadius, rect.height / 2, rect.width / 2)
        let b = min(bottomRadius, rect.height / 2, rect.width / 2)
        var p = Path()
        p.move(to: CGPoint(x: rect.minX + t, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - t, y: rect.minY))
        p.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.minY), tangent2End: CGPoint(x: rect.maxX, y: rect.minY + t), radius: t)
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - b))
        p.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.maxY), tangent2End: CGPoint(x: rect.maxX - b, y: rect.maxY), radius: b)
        p.addLine(to: CGPoint(x: rect.minX + b, y: rect.maxY))
        p.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.maxY), tangent2End: CGPoint(x: rect.minX, y: rect.maxY - b), radius: b)
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + t))
        p.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.minY), tangent2End: CGPoint(x: rect.minX + t, y: rect.minY), radius: t)
        p.closeSubpath()
        return p
    }
}
