import AppKit
import AtollCore
import SwiftUI

/// The panel's view of a finished turn's changes: files with +/−, each expandable into its diff.
/// Shown in place of the terminal output; the code it holds is dropped with the panel.
struct ChangesView: View {
    let changes: PanelChanges
    let store: AgentStore
    let font: NSFont
    let height: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Group {
                switch changes.files {
                case .loading:
                    placeholder { ProgressView().controlSize(.small) }
                case .failed:
                    placeholder { Text("Couldn't load changes").foregroundStyle(.secondary) }
                case .loaded(let files) where files.isEmpty:
                    placeholder { Text("No changes left in the working tree").foregroundStyle(.secondary) }
                case .loaded(let files):
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(files) { file in
                                fileRow(file)
                                if changes.expanded.contains(file.path) {
                                    diffView(changes.diffs[file.path], file: file)
                                }
                            }
                        }
                        .padding(6)
                    }
                }
            }
            .frame(height: height)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.05)))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            HStack(spacing: 8) {
                Text(changes.summary.label)
                    .help(changes.summary.help)
                Spacer()
                Button("Back to output") { store.hideChanges() }
                    .buttonStyle(.borderless)
            }
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
        }
    }

    private func placeholder(@ViewBuilder _ content: () -> some View) -> some View {
        content()
            .font(.system(size: 12))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func fileRow(_ file: ChangedFile) -> some View {
        HStack(spacing: 6) {
            Image(systemName: changes.expanded.contains(file.path) ? "chevron.down" : "chevron.right")
                .font(.system(size: 9, weight: .semibold))
                .frame(width: 10)
                .opacity(file.hasDiff ? 1 : 0)
            kindBadge(file.kind)
            Text(pathLabel(file))
                .font(.system(size: 11, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.head)
                .help(pathLabel(file))
            Spacer(minLength: 6)
            counts(file)
            if let url = file.fileURL(in: changes.summary.toplevel) {
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    Image(systemName: "arrow.up.forward.square")
                }
                .buttonStyle(.borderless)
                .help("Open in editor")
            }
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 4)
        .background(RoundedRectangle(cornerRadius: 5).fill(Color.white.opacity(changes.expanded.contains(file.path) ? 0.06 : 0)))
        .contentShape(Rectangle())
        .onTapGesture { store.toggleDiff(file) }
    }

    private func pathLabel(_ file: ChangedFile) -> String {
        if case .renamed(let from) = file.kind { return "\(from) → \(file.path)" }
        return file.path
    }

    @ViewBuilder
    private func kindBadge(_ kind: ChangedFile.Kind) -> some View {
        let (letter, color): (String, Color) = switch kind {
        case .modified: ("M", .secondary)
        case .added: ("A", PixelPalette.done.color)
        case .deleted: ("D", PixelPalette.error.color)
        case .renamed: ("R", PixelPalette.waiting.color)
        case .untracked: ("N", PixelPalette.done.color)
        }
        Text(letter)
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .foregroundStyle(color)
            .frame(width: 12)
            .help(Self.kindName(kind))
    }

    private static func kindName(_ kind: ChangedFile.Kind) -> String {
        switch kind {
        case .modified: "Modified"
        case .added: "Added"
        case .deleted: "Deleted"
        case .renamed: "Renamed"
        case .untracked: "New, untracked"
        }
    }

    @ViewBuilder
    private func counts(_ file: ChangedFile) -> some View {
        if file.kind == .untracked {
            Text("new").foregroundStyle(.secondary)
                .font(.system(size: 10))
        } else if file.isBinary {
            Text("binary").foregroundStyle(.secondary)
                .font(.system(size: 10))
        } else {
            HStack(spacing: 4) {
                Text("+\(file.insertions ?? 0)").foregroundStyle(PixelPalette.done.color)
                Text("−\(file.deletions ?? 0)").foregroundStyle(PixelPalette.error.color)
            }
            .font(.system(size: 10, design: .monospaced))
        }
    }

    @ViewBuilder
    private func diffView(_ state: PanelChanges.Load<FileDiff>?, file: ChangedFile) -> some View {
        switch state {
        case .loaded(let diff):
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(diff.lines.enumerated()), id: \.offset) { _, line in
                    Text(line.isEmpty ? " " : line)
                        .font(Font(font))
                        .foregroundStyle(Self.color(for: line))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Self.background(for: line))
                }
                if diff.omitted > 0 {
                    HStack(spacing: 6) {
                        Text("… \(diff.omitted) more lines")
                        if let url = file.fileURL(in: changes.summary.toplevel) {
                            Button("Open in editor") { NSWorkspace.shared.open(url) }
                                .buttonStyle(.borderless)
                        }
                    }
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
                }
            }
            .textSelection(.enabled)
            .padding(.leading, 22)
            .padding(.vertical, 4)
        case .failed:
            Text("Couldn't load the diff")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .padding(.leading, 22)
        case .loading, nil:
            ProgressView().controlSize(.mini).padding(.leading, 22)
        }
    }

    private static func color(for line: String) -> Color {
        if line.hasPrefix("+") { return PixelPalette.done.color }
        if line.hasPrefix("-") { return PixelPalette.error.color.opacity(0.95) }
        if line.hasPrefix("@@") { return Color(red: 0.55, green: 0.75, blue: 1) }
        return .primary.opacity(0.8)
    }

    private static func background(for line: String) -> Color {
        if line.hasPrefix("+") { return PixelPalette.done.color.opacity(0.08) }
        if line.hasPrefix("-") { return PixelPalette.error.color.opacity(0.08) }
        return .clear
    }
}
