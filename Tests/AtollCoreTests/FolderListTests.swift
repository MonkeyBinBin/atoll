import Testing
@testable import AtollCore

@Suite("Folder list: pinned and recent folders")
struct FolderListTests {
    @Test("using a folder moves it first; at most 10 unpinned")
    func remember() {
        var list = FolderList(pinned: [], recent: [])
        for i in 0..<12 { list = list.remembering("/f\(i)") }
        list = list.remembering("/f5")
        #expect(list.recent.count == 10)
        #expect(list.recent.first == "/f5")
        #expect(!list.recent.contains("/f0"))
    }

    @Test("pinned folders don't count toward the limit and are never pushed out")
    func pinnedKept() {
        var list = FolderList(pinned: [], recent: []).remembering("/keep").pinning("/keep")
        for i in 0..<15 { list = list.remembering("/f\(i)") }
        #expect(list.recent.contains("/keep"))
        #expect(list.unpinnedRecent.count == 10)
        #expect(!list.unpinnedRecent.contains("/keep"))
    }

    @Test("a pinned folder used last is still the last used")
    func lastUsedPinned() {
        let list = FolderList(pinned: [], recent: ["/a", "/b"]).pinning("/b").remembering("/b")
        #expect(list.recent.first == "/b")
        #expect(list.unpinnedRecent == ["/a"])
    }

    @Test("unpinning trims back to the limit")
    func unpin() {
        var list = FolderList(pinned: [], recent: []).remembering("/p").pinning("/p")
        for i in 0..<10 { list = list.remembering("/f\(i)") }
        list = list.unpinning("/p")
        #expect(list.pinned.isEmpty)
        #expect(list.recent.count == 10)
        #expect(!list.recent.contains("/p")) // the oldest unpinned
    }

    @Test("clear keeps pinned; forget removes from both")
    func clearAndForget() {
        let list = FolderList(pinned: ["/p"], recent: ["/a", "/p", "/b"])
        #expect(list.clearingRecent() == FolderList(pinned: ["/p"], recent: ["/p"]))
        #expect(list.forgetting("/p") == FolderList(pinned: [], recent: ["/a", "/b"]))
    }

    @Test("pinned folders reorder; no-op at the ends")
    func move() {
        let list = FolderList(pinned: ["/a", "/b", "/c"], recent: [])
        #expect(list.movingPinned("/c", by: -1).pinned == ["/a", "/c", "/b"])
        #expect(list.movingPinned("/a", by: -1) == list)
        #expect(list.pinning("/a") == list)
    }
}
