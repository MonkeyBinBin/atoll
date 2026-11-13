import Foundation

/// The launch form's folders: pinned ones (in the user's order, never pushed out) and recent ones (newest
/// first). `recent` keeps every used folder, pinned or not, so its first entry is always the last one used;
/// only unpinned entries count toward the limit.
public struct FolderList: Equatable, Sendable {
    public static let limit = 10

    public var pinned: [String]
    public var recent: [String]

    public init(pinned: [String], recent: [String]) {
        self.pinned = pinned
        self.recent = recent
    }

    /// Recent folders that aren't pinned, as the Folder menu lists them under the pinned ones.
    public var unpinnedRecent: [String] { recent.filter { !pinned.contains($0) } }

    /// The folder was just used: it goes first in `recent`.
    public func remembering(_ path: String) -> FolderList {
        var list = self
        list.recent.removeAll { $0 == path }
        list.recent.insert(path, at: 0)
        return list.trimmed()
    }

    /// Pins at the end of the pinned list; no-op when already pinned.
    public func pinning(_ path: String) -> FolderList {
        guard !pinned.contains(path) else { return self }
        var list = self
        list.pinned.append(path)
        if !list.recent.contains(path) { list.recent.append(path) }
        return list
    }

    /// Back to an ordinary recent folder; drops the oldest unpinned one if that goes over the limit.
    public func unpinning(_ path: String) -> FolderList {
        var list = self
        list.pinned.removeAll { $0 == path }
        return list.trimmed()
    }

    /// Gone from both lists.
    public func forgetting(_ path: String) -> FolderList {
        FolderList(pinned: pinned.filter { $0 != path }, recent: recent.filter { $0 != path })
    }

    /// Clears the unpinned recent folders; pinned ones stay.
    public func clearingRecent() -> FolderList {
        FolderList(pinned: pinned, recent: recent.filter { pinned.contains($0) })
    }

    /// Moves a pinned folder one place up (-1) or down (+1); no-op at the ends.
    public func movingPinned(_ path: String, by offset: Int) -> FolderList {
        guard let index = pinned.firstIndex(of: path), pinned.indices.contains(index + offset) else { return self }
        var list = self
        list.pinned.swapAt(index, index + offset)
        return list
    }

    private func trimmed() -> FolderList {
        var unpinned = 0
        let kept = recent.filter { path in
            if pinned.contains(path) { return true }
            unpinned += 1
            return unpinned <= Self.limit
        }
        return FolderList(pinned: pinned, recent: kept)
    }
}
