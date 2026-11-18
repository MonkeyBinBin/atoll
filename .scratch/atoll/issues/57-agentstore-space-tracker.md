# 57: AgentStore 拆出 Herdr spaces 的 tracker

**What to build:** 52 拆完四個 tracker 後，`AgentStore.swift` 仍有 1818 行。其中 Herdr spaces（ticket 42、45）的狀態與規則是邊界最清楚的一塊：它以 space／source 為 key，不是 per-agent，52 特地把它列為 out of scope。現在它的欄位散在 store 的三個地方：published state（`spaces`、`cachedSpaces`、`pendingSpaceNames`）、private 的刷新機制（`spaceTimer`、`spaceRefreshing`、`spaceRefreshAgain`、`spaceGeneration`、`renamingSpaces`、`spaceMisses`），還有 `herdrAppRunning` 的 `didSet` 和 `rebuild()` 裡的 space 對應。把它們收進一個獨立的 AtollCore 型別，store 只負責轉發與在 rebuild 時查詢。

**Blocked by:** —

**Status:** needs-triage

- [ ] 一個 `@MainActor` 的 AtollCore 型別（命名比照既有的 `*Tracker`，例如 `SpaceTracker`），持有：目前的 spaces、cached spaces、pending space names、rename 進行中的 id、刷新 timer 與 generation（含「刷新中再要一次」的合併）、已觸發過一次刷新的未對應 terminal（現在的 `spaceMisses`）
- [ ] 搬過去的規則與現行完全相同：
  - Herdr app 開啟時立刻刷新一次，之後每 `spaceRefreshInterval` 刷新；app 關閉時作廢進行中的讀取並清空 `spaces`
  - 讀取失敗時保留上一次的結果；只在內容有變時才寫入並通知重建
  - `applyPendingSpaceNames`：rename 成功才移除，失敗留到下次讀取再試；snapshot 還沒到時不判定孤兒 space
  - `launchSpaces()` 的 `launchSpacesTimeout` 競速，加上 offline fallback（`HerdrLabels.spaces`）
  - herdr-core 的 agent 第一次沒對應到 space 時觸發一次刷新
- [ ] 依賴用注入的：`HerdrClient` 的 `spaces()`／`renameSpace`、`IslandScheduler`、兩個 tunable，以及 store 提供的 closure：primary source 目前的 terminals、primary snapshot 是否已到、重建。tracker 不回頭依賴 `AgentStore`
- [ ] `AgentStore` 的 public API 不變（`spaces`、`cachedSpaces`、`onSpacesCached`、`pendingSpaceNames`、`onPendingSpaceNamesChanged`、`refreshSpaces()`、`launchSpaces()`、`herdrAppRunning`），App 層不需修改；tracker 設成 `@ObservationIgnored` 時，`spaces` 等 published 屬性的觀察行為要維持（SwiftUI 仍會在 spaces 改變時重繪）
- [ ] agent 消失時的清理仍走 `forget` 那張表，`spaceMisses` 那一行改呼叫 tracker 的移除
- [ ] tracker 有自己的測試 suite（放在 `TrackerTests` 或新檔），用既有 fakes 驗證：刷新合併、app 關閉後晚到的結果被丟掉、讀取失敗保留舊值、rename 失敗會重試、孤兒 pending name 被丟棄、`launchSpaces` 逾時回 offline spaces
- [ ] 既有測試不改即通過（`SpaceTests`、`OfflineLaunchTests`、`LaunchHistoryTests` 等）；`swift build --build-tests` 無新 warning
- [ ] 本 issue 檔末尾記錄做了什麼、留了什麼，以及 `AgentStore.swift` 行數變化

**Out of scope:**
- 改變任何行為、tunable、callback 時機
- `SpaceGrouping`（清單分段）與 App 層的 space 篩選
- queued message 與 auto-advance：兩者都跟 send 路徑、`panel`、`agent(_:)` 查詢綁在一起，單獨拆出來只會多一層轉發。等 send／keys／interrupt 一起重整時再看
- adapter 層
