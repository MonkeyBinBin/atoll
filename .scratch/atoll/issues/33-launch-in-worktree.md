# 33: 用獨立 git worktree 啟動 agent

**What to build:** 啟動表單（ticket 13）在選定的目錄是 git repo 時，多一個「New worktree」選項：先建立新的 `git worktree`，再在那裡啟動 agent。共用 working tree 警示（ticket 29）目前只能提醒，本 ticket 提供對應的解法，警示上也加一個入口。

**Blocked by:** —

**Status:** resolved

- [x] 表單：目錄是 git repo（`git rev-parse --show-toplevel` 成功）時才顯示「New worktree」開關，預設關閉。打開時顯示 branch 名稱欄位（預設由顯示名稱或任務前幾個字轉成 slug，加上 `atoll/` 前綴，可編輯）與建立位置
- [x] 建立位置固定在 repo 外面的同層目錄：`<repo 上層>/<repo 名稱>.worktrees/<slug>`，避免 worktree 出現在原 working tree 裡被 git status 或檔案監看看到。目錄已存在就在名稱後加數字
- [x] 建立：`git worktree add -b <branch> <path> HEAD`。branch 已存在時顯示錯誤，請使用者改名，不自動覆寫或 checkout 既有 branch
- [x] 這是 Atoll 第一個會寫入 repo 的 git 指令：沿用 `ProcessGitRunner` 的 hardening（含停用 hooks，所以 `post-checkout` 不會執行），逾時放寬（例如 30 秒，大 repo checkout 會久）；失敗時顯示 git 的錯誤訊息，不啟動 agent
- [x] 送出前的確認摘要改成「工具 · worktree 路徑（branch）· 任務前 60 字」，並提示「從 HEAD `<short sha>` 建立，未 commit 的修改不會帶過去」（原 repo 有未 commit 修改時才顯示）
- [x] 啟動狀態機在前面多一個「Creating worktree…」階段，之後照 ticket 13 的 Launched／unconfirmed／failed；worktree 建好但啟動失敗時，worktree 保留，訊息裡顯示它的路徑
- [x] 新路徑寫入最近目錄清單
- [x] 共用 working tree 警示（清單、hover card、面板標題列）旁加「Launch in new worktree」，打開啟動表單並預填同一個專案、工具，「New worktree」為開啟。不動既有的 agent
- [x] 路徑與 branch slug 的產生規則（非 ASCII、空白、重名加數字）、指令組裝放在 AtollCore，用可替換的 runner 測試；`RealGitTests` 新增在暫存 repo 真的建立 worktree 並確認 hooks 沒執行

**Out of scope:** 刪除或清理 worktree（spec 不做移除）、merge 回主 branch、搬移既有 agent 到新 worktree、依 repo 自訂建立位置、建立後安裝依賴。

## Comments

- 2026-11-12（agent）：AtollCore 新增 `Worktree.swift`：`WorktreeSource`（toplevel、HEAD、tracked 檔是否 dirty）、`WorktreePlan.make`（`<repo 上層>/<repo>.worktrees/<branch 最後一段的 slug>`，已存在就加 `-2`、`-3`；使用者選的是 repo 子目錄時，agent 在 worktree 的同一個子目錄啟動，比對時先解析 symlink）、`WorktreeNaming`（slug 只留 ASCII 英數與 `-`，最多 40 字，全中文時用 `agent`；預設 branch 由顯示名稱或任務前 5 個字組成，加 `atoll/`）、`WorktreeCreating` 與 `GitWorktreeCreator`。建立前先 `check-ref-format --branch`、確認 branch 不存在、目錄不存在，再 `git worktree add -b <branch> <path> <表單看到的 HEAD>`；沿用 `ProcessGitRunner` 的 hardening（hooks、fsmonitor、filter driver 都停用），建立用 30 秒逾時。
- 2026-11-12（agent）：`GitRunner` 新增 `runCapturing`（保留 exit status 與 stderr，協定有預設實作），`ProcessGitRunner` 改成另開 thread 讀 stderr，讓 worktree 失敗時能顯示 git 自己的錯誤訊息；`run` 的行為不變。`AgentStore.launch(_:worktree:)`：有 plan 時先進 `.creatingWorktree`（「Creating worktree…」），成功後把 `request.folder` 換成 worktree 裡的目錄再走原本的啟動狀態機；失敗是 `.failed(kind: "worktree_failed")` 且不啟動；worktree 建好但啟動失敗時 `launchWorktree` 保留路徑，表單顯示「Worktree kept at …」。`onWorktreeCreated` 把新路徑加進最近目錄。
- 2026-11-12（agent）：UI：表單偵測到 repo 才顯示「New worktree」，打開後有 Branch（自動跟著名稱／任務更新，手動改過就不再覆寫）與 Location；確認摘要改成「工具 · worktree 名稱（branch）· 任務」，另一行「From HEAD <sha>」，原 repo 有未 commit 修改時以警示色提醒不會帶過去。共用 working tree 警示在清單列與面板加「Launch in new worktree」（打開表單、預填專案與工具、勾選 New worktree，不動既有 agent）；hover card 是點擊穿透的，所以沒有按鈕。DebugHook 新增 `launchwt <folder>`。
- 2026-11-12（agent）：測試：命名與位置 5 組、git 指令 5 個（含 stderr 傳遞、branch 已存在時不寫入）、啟動狀態機 4 個、真 repo 1 個（從子目錄啟動、原 repo 有未 commit 修改、埋 `post-checkout` hook：worktree 內容是 HEAD 的版本、branch 正確、hook 沒執行、原 repo status 看不到 worktree、同名 branch 再建被拒、路徑自動加 `-2`），全套 293 個通過。dev-run 實測：對 scratchpad 的 repo 打開表單，branch 由任務帶出 `atoll/reply-with-the-word-hello`，摘要顯示 HEAD 與未 commit 警示；⌘↩ 後 worktree 建在 `repo32.worktrees/`、`git worktree list` 正確、Herdr 在 worktree 裡開了 Claude Code，狀態到 Launched 並完成回合。共用 working tree 警示旁的按鈕只有編譯確認，沒有實際造出兩個 agent 共用 tree 的情境點過。
