# 47: 抽出共用的 process runner

**What to build:** AtollCore 有四份各自手寫的 Process + timeout：`ChangeSummary.execute`、`CmuxAdapter.run`、`CoreRPCAdapter.run`、`AgentCLI.run`。只有 `AgentCLI.run` 處理了「login shell 的背景子程序（如 gitstatusd）握著 stdout，讀到 EOF 會卡住」：它把 stdout 寫到暫存檔而不是 pipe，並用 terminationHandler + semaphore 做真正有效的 timeout。抽出一個共用 runner，讓四處行為一致；順便把 `CoreRPCAdapter.loginShell()` 移到跟 shell 環境相關的位置（目前只因 `AgentCLIDetector` 要用才從 `private` 改成 internal）。

**Status:** ready-for-agent

- [ ] 一個共用 runner：executable、arguments、cwd（可選）、timeout；回傳 exit status 與 stdout（必要時 stderr）；逾時終止並回報；不因子程序握著輸出而阻塞
- [ ] 四處改用它，行為不變（`ChangeSummary` 的 hardened git 環境、`CoreRPCAdapter.run` 的 async／錯誤型別照舊）
- [ ] `loginShell()` 移出 `CoreRPCAdapter`，`hcRunArguments` 與 `AgentCLIDetector` 都改用新位置
- [ ] 有測試；跑真實程序的測試照 `ATOLL_PROCESS_TESTS=1` 的方式手動開啟

**Out of scope:** 改變任何呼叫端的對外行為或錯誤訊息。

## Comments
