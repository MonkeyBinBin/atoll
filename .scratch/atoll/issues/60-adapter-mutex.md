# 60: adapter 的共享狀態改用 `Mutex`，拿掉 `@unchecked Sendable`

**What to build:** `CoreRPCAdapter`、`CmuxAdapter`、`HerdrCLIAdapter`、`LineSocket`，以及 App 層的 `SpriteSheet`，都標成 `@unchecked Sendable`，用 `NSLock` 手動 `lock()`／`unlock()` 保護跨 thread 的欄位。哪些欄位該上鎖只靠人記得，compiler 不檢查，而且已經有漏掉的地方：
- `CmuxAdapter`：reader thread 送 heartbeat 時在鎖外讀 `seq`，ticker thread 卻透過 `publishChanges()` → `nextSeq()` 在鎖內寫它。這是真的跨 thread data race。
- `HerdrCLIAdapter.pollLoop`：在鎖外讀寫 `seq`（heartbeat、離線判斷、`seq = max(seq, 1)`），`nextSeq()` 卻在鎖內寫。目前只有 poll thread 會碰 `seq`，所以只是上鎖不一致，還不是 race。
- `LineSocket`：`readLine()` 讀寫 `buffer` 完全不上鎖，靠的是「只有一個讀取 thread」這個默契。

把每個 class 受保護的欄位收進一個 `State` struct，用 `Synchronization.Mutex` 包起來（部署目標是 macOS 15，可以直接用），存取一律走 `withLock`，再把 `@unchecked Sendable` 改成一般的 `Sendable`，交給 compiler 檢查。

**Blocked by:** —

**Status:** resolved

- [x] `CoreRPCAdapter`、`CmuxAdapter`、`HerdrCLIAdapter`、`LineSocket`、`SpriteSheet` 不再有 `NSLock`，也不再標 `@unchecked Sendable`；受保護的欄位只能透過 `Mutex.withLock` 存取
- [x] 鎖住期間做的事跟原本一樣，不擴大：`emit`、`isCurrent`、`nextSeq`、socket／process 的 I/O、`ProcessInspector` 的查詢、`LineSocket.readLine` 的阻塞 `read()` 都留在鎖外；`subscriptionLoop` 的 `defer` 仍是先 `close()` 再清 `currentSocket`
- [x] 上述兩個 `seq` 的地方改成在鎖內讀寫
- [x] `DemoClient`：可變欄位本來就是 `@MainActor`，試著拿掉 `@unchecked`；compiler 不接受就維持原狀並記錄原因
- [x] 不新增 `nonisolated(unsafe)` 或新的 unchecked box；`grep -rnE '@unchecked Sendable|nonisolated\(unsafe\)' Sources | wc -l` 從 13 往下降
- [x] 新增 `LineSocket` 測試：一個 thread 卡在 `readLine()` 時，另一個 thread 呼叫 `shutdown()`，`readLine()` 要在時限內回傳 nil
- [x] `make check` 通過、無新 warning；`HERDR_CONTRACT=1 swift test --filter Contract`（真的 herdr-core）改動前後都通過
- [x] 本 issue 檔末尾記錄做了什麼、留了什麼

**Out of scope:**
- 包 `Any` 的 `UncheckedBox`／`UncheckedParams`／`UncheckedResult`（`[String: Any]` 本身不是 `Sendable`）
- `IslandModel` 的 `NSFont` static、`IslandController` 的 `nonisolated(unsafe) let unsafeEvent`
- 統一三個 adapter 的 lifecycle：`CoreRPCAdapter` 只在真的開 thread 時遞增 generation，`CmuxAdapter`／`HerdrCLIAdapter` 每次 `start()` 都遞增。所以在執行中再呼叫一次 `start()`，現有的 loop 會退出，卻不會開新的。目前只會呼叫一次，所以沒有影響；照原樣搬過去，要不要修另外決定
- 改用 actor 或 Swift Concurrency 重寫 thread 模型

## Comments

- 2026-11-18（agent）：完成。`CoreRPCAdapter`、`CmuxAdapter`、`HerdrCLIAdapter` 各自把受保護的欄位收進 private `State` struct，存在 `let shared = Mutex(State())`，原本的 `lock()`／`unlock()` 區塊一對一改成 `shared.withLock`；三者都從 `@unchecked Sendable` 改成 `Sendable`，compiler 接受。`CmuxAdapter` 原本的 `state` 欄位改名 `sessions`，避免跟 Mutex 撞名。鎖住期間做的事沒有擴大：`emit`、`isCurrent`、`nextSeq` 仍在鎖外呼叫；`ownedByHerdr` 維持「查 cache → 鎖外 `ProcessInspector.belongsToHerdr` → 寫回」三段；`currentTerminals` 只在鎖內 copy sessions；`frameSeq` 改在上鎖前算；`subscriptionLoop` 的 `defer` 仍是先 `close()` 再清 `currentSocket`。`seq` 的兩處：Cmux 的 heartbeat 改讀 `currentSeq`（鎖內讀）；HerdrCLI 的 heartbeat 在寫 `lastAgents` 的同一個 `withLock` 裡讀，離線判斷與 `seq = max(seq, 1)` 合成一個 `withLock`，判斷規則不變。HerdrCLI 的 `wake` 從未重新指派，改成 `let` 放在 `State` 外。`LineSocket`：`buffer` 與 `closed` 各自是 `Mutex`，`readLine()` 只在取出整行與 append 時上鎖，阻塞的 `read()` 不持鎖；`shutdown()`／`close()` 照舊在鎖內呼叫系統呼叫，避免 close 與 shutdown 交錯時打到被重複使用的 fd。`SpriteSheet`：兩個 cache 收進 `Mutex<Caches>`，`frame()` 跟原本一樣整段在鎖內，包括第一次 recolor，避免兩個 thread 重複計算。`DemoClient` 直接拿掉 `@unchecked`，compiler 接受，因為可變欄位都是 `@MainActor`。`grep -rnE '@unchecked Sendable|nonisolated\(unsafe\)' Sources` 從 13 降到 7，剩下的都是 Out of scope 列的項目；`Sources/` 已無 `NSLock`。
- 2026-11-18（agent）：測試：新增 `LineSocketTests` 2 個，用真的 Unix socket server 驗證兩件事：卡在 `readLine()` 時另一個 thread `shutdown()` 會在 2 秒內回 nil；一行拆成兩次送達時能正確組回，一次回一行，EOF 回 nil。`make check`：`AtollCoreTests` 524 個 + `AtollTests` 14 個通過，debug／release 皆 0 warning。`HERDR_CONTRACT=1 swift test --filter Contract`（本機真的 herdr-core）改動前後都通過（4 個）。`--sanitize=thread` 跑 Contract、LineSocket、Cmux、HerdrCLI、Connection、MultiSource 共 48 個，沒有 data race 回報；但 Cmux／HerdrCLI 的測試主要是解析邏輯，TSan 實際碰到 thread 的只有 contract 與 `LineSocket` 測試。實機：build 安裝後，新版能正常 quit 再重開，沒有卡在 `stop()`。未實機驗證：cmux 與 herdr CLI 來源的連線、Reconnect、關掉再開後的離線與恢復。
