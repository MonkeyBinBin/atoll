# 67: 在 Settings 自訂啟動選單的 agent CLI

**What to build:** 啟動選單只偵測寫死在 `AgentCLI.catalog` 的 CLI，使用者裝了未收錄的 CLI（例如 PR #14 之前的 Antigravity CLI）就不會出現，每支援一個 CLI 都要改 code、發版。讓使用者在 Settings 自己加 CLI：

- command、選單標題
- 怎麼帶首個 prompt：最後一個參數 / 指定 flag / 不支援（對應 `TaskPassing`），以及 #66 的子指令前綴
- 選填的 OSC 7501 app word（`appWords`），讓「Launch in new worktree」能預選同一工具
- 選填的 `--help` 特徵字串（`helpSignature`），給名稱通用的 command

自訂項目與 catalog 一起走 `AgentCLIDetector` 偵測，存在 UserDefaults（`local.atoll`）。command 與 catalog 重複時以哪邊為準要決定。

現有的替代方式是寫 herdr-core template（啟動選單會列 `hc templates`），但 template 沒有 `taskPassing`，task 一律接在最後。

**Blocked by:** 66

**Status:** needs-triage
