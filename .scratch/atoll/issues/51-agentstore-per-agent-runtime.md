# 51: AgentStore 的每個 agent 狀態收進單一結構

**What to build:** `AgentStore.swift`（約 1950 行）用約 30 個以 address 為 key 的 dictionary 存每個 agent 的狀態（`previews`、`choices`、`finalMessages`、`finalReads`、`finalTimers`、`reminderTimers`、`reminderEpisodes`、`openTurns`、`changeSummaries`、`toplevels`、`summaryGeneration`、`responseTimers`、`previewTimers`、`interruptTimers`、`feedbackTimers`、`endedTimers`…）。agent 消失時的清理散在 `rebuild()`、`dropFinalMessage`、`reconcile*` 等多處，新增欄位很容易漏清，殘留資料或 timer。把它們收進一個 per-agent 的 runtime 結構，移除時一處清掉；再視情況把 waiting preview／final message、reminder、change summary 拆成獨立的小 coordinator。

**Status:** resolved

- [x] 每個 agent 的暫存狀態與 timer 集中在一個結構，agent 移除時統一取消／丟棄
- [x] 對外 API（`AgentStore` 的 public 介面與 callback）不變，既有測試不改即通過
- [x] 加一個測試：agent 消失後，store 內沒有它的殘留狀態或排程中的 timer

**Out of scope:** 改變任何行為或 tunable；adapter 層。

## Comments

- 2026-11-13（agent）：TDD。先加 `AgentStore.residue(of:)`（internal，列出某 address 仍持有的狀態）與 `AgentRuntimeTests` 3 個（event 移除、snapshot 移除、送出途中 agent 消失），紅燈時殘留的是 `interruptStates`／`interruptTimers`／`feedbackTimers`／`interruptFeedback`、`acknowledged`、`responseTimers`／`permissionResponses`、`keyStates`、`sendStates`。
- 2026-11-13（agent）：`AgentStore.AgentRuntime`（`runtimes[address]`，與 `records` 並列，不放進 `Record`：事件處理會複製再寫回 record）收齊原本 19 個 private 字典：acknowledged、interrupt feedback、waiting preview／choices／episode、list response episode、reminder／reminded episode、open turn（git baseline task）、change summary、toplevel、summary generation、final message／read token。timer 統一放 `timers: [Timer: ScheduledAction]`，經 `schedule(_:for:after:)`／`cancel(_:for:)`，觸發後自動移除。`rebuild()` 開頭 `tearDownGone()`：record 不在的 runtime 取消所有 timer、cancel baseline task 後丟棄，並修剪 published 的 `sendStates`／`keyStates`／`permissionResponses`／`interruptStates`／`lastInterruptError`（原本靠被取消的 timer 清掉的）。晚到的 callback 一律 `runtimes[address]?.…` 不重建；`finishInterrupt`、`showNoLongerWaiting`、send／key 完成時 agent 已不在就不寫狀態（send 的 completion 照常呼叫）。summary generation 改用 store-wide 計數，避免同一 address 的新 agent 撞到舊結果。刻意留在外面：`colors`（session 內固定）、`timeline`、`.sending` 的 queued message（要等送出結果才回報 `onQueuedFailed`）、以 path／toplevel／source 為 key 的狀態。
- 2026-11-13（agent）：另加「timer 確實被取消」的測試：`FakeScheduler.liveCount`（未取消的排程數），t1 移除後與只有 t2 的對照組相同；把 `tearDown()` 註解掉時轉紅（6 vs 2）。store-wide summary generation 沒有專屬測試：`FakeProbe` 無法卡住 git 結果來重現「舊結果晚到」。全套 472 個通過（既有測試未改）。閒置 CPU 重量 0.2–0.6%，沒有退步。未做：把 preview／final message、reminder、change summary 拆成獨立 coordinator，這次集中在「狀態集中、移除一處清乾淨」；`AgentStore.swift` 行數沒變少（新增結構與說明），拆 coordinator 才會真正瘦身，要的話另開 ticket。
- 2026-11-13（agent）：code review 後補記。刻意的行為變更（Out of scope 寫「不改變任何行為」，以下是為了消除殘留而必要的例外）：agent 已不在時，`finishInterrupt`、`showNoLongerWaiting`、send／key 完成不再寫入狀態（send 的 completion 照常呼叫），原本是寫入後靠 timer 清掉；agent 移除時 `acknowledged` 與 `interruptFeedback` 一起丟棄，原本同一 address 重新出現時還在；summary generation 改 store-wide 計數；移除時修剪 5 個 published 字典（多一次 observable 寫入）。`runtimes` 改為 `@ObservationIgnored`：唯一外部讀取是 `Notifier.deliver` 呼叫 `isReadingWaitingScreen`（一次性讀取，完成靠 `onWaitingDetails`），不需要觀察，也避免每次 schedule／cancel 觸發 re-render。測試直接看內部（`residue(of:)`、`liveCount`）違反 spec「只透過公開介面驗證」，保留為刻意例外：殘留沒有對外可見的效果可驗，且本 ticket 的 AC 要求檢查；日後拆 coordinator 時需一併調整。尚未處理（review 指出、留待拆 coordinator 時一起做）：published 字典、`notifyWhenDone`、`spaceMisses`、`queuedMessages` 仍各自清理；「agent 已不在就不寫」的 guard 散在四處。
