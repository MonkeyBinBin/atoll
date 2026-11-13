# 47: 抽出共用的 process runner

**What to build:** AtollCore 有四份各自手寫的 Process + timeout：`ChangeSummary.execute`、`CmuxAdapter.run`、`CoreRPCAdapter.run`、`AgentCLI.run`。只有 `AgentCLI.run` 處理了「login shell 的背景子程序（如 gitstatusd）握著 stdout，讀到 EOF 會卡住」：它把 stdout 寫到暫存檔而不是 pipe，並用 terminationHandler + semaphore 做真正有效的 timeout。抽出一個共用 runner，讓四處行為一致；順便把 `CoreRPCAdapter.loginShell()` 移到跟 shell 環境相關的位置（目前只因 `AgentCLIDetector` 要用才從 `private` 改成 internal）。

**Status:** resolved

- [x] 一個共用 runner：executable、arguments、~~cwd（可選）~~（未做，見 Comments）、timeout；回傳 exit status 與 stdout（必要時 stderr）；逾時終止並回報；不因子程序握著輸出而阻塞
- [x] 四處改用它，行為不變（`ChangeSummary` 的 hardened git 環境、`CoreRPCAdapter.run` 的 async／錯誤型別照舊）
- [x] `loginShell()` 移出 `CoreRPCAdapter`，`hcRunArguments` 與 `AgentCLIDetector` 都改用新位置
- [x] 有測試；跑真實程序的測試照 `ATOLL_PROCESS_TESTS=1` 的方式手動開啟

**Out of scope:** 改變任何呼叫端的對外行為或錯誤訊息。

## Comments

- 2026-11-13（agent）：新增 `ProcessRunner`（AtollCore，internal）：同步／async 兩個 `run`，`environment` 與 `timeout` 皆可選（nil = 不設限，cmux／herdr-app 維持原本沒有 timeout），回傳 `status`／`exited`／`stdout`／`stderr`，失敗為 `Failure.couldNotStart`／`.timedOut`；stdout、stderr 都寫暫存檔，stdin 為 `/dev/null`。四處改用它，`loginShell()` 移到 `ProcessRunner`。沒有加 cwd：四個呼叫端都不需要（git 用 `-C`）。`CmuxAdapter` 的 `events` 長駐串流仍用 pipe（邊跑邊讀，不在此範圍）。
- 2026-11-13（agent）：測試：先補 `ProcessCallersTests` 鎖住 herdr-app／hc 與 cmux 的錯誤對應（現有程式 9 個綠燈；「背景子程序握著輸出」1 個紅燈，舊實作卡滿 30 秒），再寫 `ProcessRunnerTests` 契約 8 個；git 路徑沿用既有的真實 git 測試。改完後全套 467 個通過，`ATOLL_PROCESS_TESTS=1` 全過（含原本的紅燈），`HERDR_CONTRACT=1` 契約 4 個通過。行為差異：herdr-app／hc／cmux 的 stdin 由繼承改為 `/dev/null`（GUI app 本來就是 `/dev/null`）。
- 2026-11-13（agent）：review 後修正。逾時改為 SIGTERM 後等 1 秒，仍未結束就 SIGKILL 並等到真的結束（舊 git 路徑會等，第一版沒等是退步），測試改為檢查 process 確實不在。無法啟動時拋出系統原本的 error（`Failure.couldNotStart` 拿掉），herdr-app 的 `app_command_failed` 訊息與 cmux 拋出的 error 與改版前一致。暫存檔建立失敗為 `Failure.noOutputFile`，`FileHandle` 開檔失敗時不再留下檔案。`Output` 加 `stdoutText`／`stderrText`／`errorText`；cmux 的 async 呼叫改用 async `run`；拿掉沒人用的 `qos:`（`ProcessGitRunner.runCapturing` 保留自己的 `.utility` 包裝，因為它在同一個 thread 上連跑兩個 git）。
- 2026-11-13（agent）：已知行為差異（皆為設計取捨）：stdin 改為 `/dev/null`；輸出改寫暫存檔，暫存目錄不可寫時三條路徑都會失敗（git 回 nil）；`AgentCLI` 偵測遇到非 UTF-8 輸出改為替換字元而非視為失敗。`cwd` 沒加：四個呼叫端都不需要。
