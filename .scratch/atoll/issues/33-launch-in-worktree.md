# 33: 用獨立 git worktree 啟動 agent

**What to build:** 啟動表單（ticket 13）在選定的目錄是 git repo 時，多一個「New worktree」選項：先建立新的 `git worktree`，再在那裡啟動 agent。共用 working tree 警示（ticket 29）目前只能提醒，本 ticket 提供對應的解法，警示上也加一個入口。

**Blocked by:** —

**Status:** ready-for-agent

- [ ] 表單：目錄是 git repo（`git rev-parse --show-toplevel` 成功）時才顯示「New worktree」開關，預設關閉。打開時顯示 branch 名稱欄位（預設由顯示名稱或任務前幾個字轉成 slug，加上 `atoll/` 前綴，可編輯）與建立位置
- [ ] 建立位置固定在 repo 外面的同層目錄：`<repo 上層>/<repo 名稱>.worktrees/<slug>`，避免 worktree 出現在原 working tree 裡被 git status 或檔案監看看到。目錄已存在就在名稱後加數字
- [ ] 建立：`git worktree add -b <branch> <path> HEAD`。branch 已存在時顯示錯誤，請使用者改名，不自動覆寫或 checkout 既有 branch
- [ ] 這是 Atoll 第一個會寫入 repo 的 git 指令：沿用 `ProcessGitRunner` 的 hardening（含停用 hooks，所以 `post-checkout` 不會執行），逾時放寬（例如 30 秒，大 repo checkout 會久）；失敗時顯示 git 的錯誤訊息，不啟動 agent
- [ ] 送出前的確認摘要改成「工具 · worktree 路徑（branch）· 任務前 60 字」，並提示「從 HEAD `<short sha>` 建立，未 commit 的修改不會帶過去」（原 repo 有未 commit 修改時才顯示）
- [ ] 啟動狀態機在前面多一個「Creating worktree…」階段，之後照 ticket 13 的 Launched／unconfirmed／failed；worktree 建好但啟動失敗時，worktree 保留，訊息裡顯示它的路徑
- [ ] 新路徑寫入最近目錄清單
- [ ] 共用 working tree 警示（清單、hover card、面板標題列）旁加「Launch in new worktree」，打開啟動表單並預填同一個專案、工具，「New worktree」為開啟。不動既有的 agent
- [ ] 路徑與 branch slug 的產生規則（非 ASCII、空白、重名加數字）、指令組裝放在 AtollCore，用可替換的 runner 測試；`RealGitTests` 新增在暫存 repo 真的建立 worktree 並確認 hooks 沒執行

**Out of scope:** 刪除或清理 worktree（spec 不做移除）、merge 回主 branch、搬移既有 agent 到新 worktree、依 repo 自訂建立位置、建立後安裝依賴。

## Comments
