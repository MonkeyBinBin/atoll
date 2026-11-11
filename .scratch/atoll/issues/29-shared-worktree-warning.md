# 29: 多個 agent 共用同一個 working tree 時警示

**What to build:** 兩個以上的 agent 同時在同一個 git working tree 裡活動時，在清單、hover card 與面板標示共用風險，提醒改用各自的 worktree。同時跑多個 agent 時，最大的損失是彼此覆蓋檔案或把對方的變更 commit 進去，事前提醒比事後處理衝突便宜得多。

**Blocked by:** —

**Status:** resolved

- [x] 分組：對每個 agent 的 `projectPath` 跑 `git rev-parse --show-toplevel`，toplevel 相同才算共用。不同的 `git worktree` 有不同的 toplevel，不會被誤判；非 git 目錄不參與判斷
- [x] 結果依 `projectPath` 快取，只在 `projectPath` 改變或 agent 新增時重新計算，不輪詢
- [x] 「活動中」是指 Starting、Working、Needs you、Error。同一組裡有兩個以上的 agent 活動中才警示；Done／Idle／Exited 的 agent 不算，避免開著不用的 session 一直觸發警示
- [x] 不聲稱是哪個 agent 改了哪些檔案：同一個 working tree 的 `git status` 是共用的，無法歸屬。警示只陳述事實：「與 Codex · project-x 共用 working tree」
- [x] 顯示：清單列與 hover card 加圖示與文字（不能只靠顏色）；面板標題列列出同組的其他 agent。第二個 agent 開始活動時冒一次泡泡，同一組持續共用期間不再重複
- [x] Settings 可以關閉
- [x] 分組與「何時警示、何時再冒泡泡」的規則放在 AtollCore，git 執行透過可替換的 runner（若 ticket 28 先做了，就共用它的 `GitProbe`），並有測試：同 tree 兩個活動中、worktree 不同不警示、一個活動一個 Idle 不警示、非 git 目錄、泡泡只冒一次

**Out of scope:** 自動建立 worktree、阻止 agent 啟動、偵測不同 worktree 之間的檔案衝突、Launch 表單的 worktree 選項（另開 ticket）。

## Comments

- 2026-11-11（agent）：`GitProbe` 新增 `WorkingTreeProbing`（`toplevel(in:)`，沿用 ticket 28 的 hardened `ProcessGitRunner`）。`AgentStore.treeProbe` 為 nil 時不跑 git；`rebuild()` 裡的 `markSharedTrees` 依專案路徑快取 toplevel（`""` 代表不是 repo），沒看過的路徑在背景查一次，結果回來再 rebuild；快取只保留目前 agent 用到的路徑，所以 agent 換目錄（foreground cwd 事件）會查新路徑。同一個 toplevel、沒有 Exited 的 agent 為一組，其中活動中（`AgentState.isActiveInTree`：Starting／Working／Needs you／Error）的有兩個以上時，各自的 `Agent.sharedTreeWith` 填入其他活動中 agent 的 address。
- 2026-11-11（agent）：泡泡規則：`sharedAnnounced[toplevel]` 記錄已經涵蓋過的 agent。組內活動中的 agent 有沒被涵蓋的，就對其中 `stateSince` 最新的那個（剛開始的）呼叫 `onSharedTree`，並把全部活動中的加入已涵蓋；整組（非 Exited 的成員）少於兩個時清掉，下次重新冒。所以同一對 agent 輪流開始、結束回合不會重複冒（ticket 寫的「持續共用期間不再重複」，這裡以「同一組成員」為準，而不是「同時活動中」，避免每個回合都冒一次）。限制：Atoll 啟動時已經有兩個活動中的 agent 共用 tree，會冒一次泡泡。`AgentBubble` 新增 `kind`（`.state`／`.sharedTree`）與 `stillApplies(to:)`；shared-tree 泡泡不算緊急，agent 不再共用時就收掉，內容是「Shared working tree · with 工具 · 專案名」，`BubbleRules` 的隱私註解已同步更新。ticket 28 的「shared tree」改為優先用這裡的分組，Atoll 啟動後還沒開始過回合的 agent 也算進去。
- 2026-11-11（agent）：測試：`SharedTreeTests` 10 個（同 tree 子目錄、不同 worktree、不活動的不算、非 repo、每個路徑只查一次與換目錄、只冒一次、第三個加入與重新開始、關閉、與 ticket 28 的連動、泡泡 kind），全套 195 個通過。dev-run 實測：暫存 repo 裡 A（repo 根目錄，Working）、B（`sub/`，Idle → Working）、C（`git worktree`，Working）：A、B 的清單列與 B 的面板標題列顯示「Shares working tree with …」，C 沒有；B 轉為 Working 時冒出「Shared working tree · with Claude Code · repo28」。hover card 只有編譯確認，沒有截圖驗證。

