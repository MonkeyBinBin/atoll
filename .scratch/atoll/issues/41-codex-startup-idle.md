# 41: Codex 啟動時的 Idle 不當成回合結束

**What to build:** Codex 一啟動，herdr 就回報 Idle → Working → Idle（Working 只有約 1 秒），還把它算成第一個回合（`turn: 1`）。Atoll 把這段 Working → Idle 當成「停下來的回合」：冒 Idle 泡泡、今日時間軸多一筆沒有內容的 Idle（ticket 38 實測）、「這次跑完時通知我」會被它觸發、還會讀一次畫面與算一次 git 變更量。使用者什麼都還沒做，這些都是雜訊。

**Blocked by:** —

**Status:** resolved

**實測（Codex 0.167.2，`hc events` 加時間戳，兩次）：** 狀態出現（Idle）約在前景程式切成 codex 後 1.2 秒；0.2–0.3 秒後轉 Working；再 0.9–1.3 秒轉 Idle；接著 `turn` 事件 `turn: 1`。從狀態出現到回到 Idle 共 1.1–1.5 秒。

- [x] 判斷：agent 的狀態出現後（status 從無到有，或換了 app）3 秒內開始的 Working，若在狀態出現後 10 秒內轉成 Idle，而且這是狀態出現後的第一段 Working，就視為啟動，不是回合結束。其他情況照舊（例如晚於 3 秒才開始的 Working、超過 10 秒才結束、結束在 Done／Error、或已經有過一段 Working）
- [x] 處理：這次 Working → Idle 對外與對內都當成「第一次看到」（`onTransition` 與 store 內部的 transition 處理都以前一個狀態為 nil 處理），所以不冒泡泡、不通知、不記時間軸、不觸發「這次跑完時通知我」、不送排隊訊息、不讀畫面；那段 Working 開始時已經起算的 git 基準直接作廢，不產生變更量
- [x] 同一個 terminal 裡 Codex 退出再重開（status 清掉後又出現）會重新起算
- [x] 時間門檻放在 `AgentStore.Timing`
- [x] 測試放在 AtollCore，fake client：啟動的 Working → Idle 不冒泡泡、不記時間軸、不觸發通知我、不讀畫面、沒有變更量；Working 晚於 3 秒開始照舊；Idle 晚於 10 秒才到照舊；啟動後結束在 Done 照舊；第二段 Working → Idle 照舊；退出再重開重新起算
- [x] 實作後用真的 Codex 啟動確認不冒泡泡、時間軸沒有多一筆

**Out of scope:** 改變其他工具或其他時間點的 Working → Idle 規則、修改 herdr 的回合計數。

## Comments

- 2026-11-12（agent）：`AgentStore` 的 `Record` 多記 `statusAppearedAt`（status 從無到有或換 app 時）、`workedSinceAppeared`、`startupWorking`；`trackStartup` 在每個 status 事件更新它們：狀態出現後的第一段 Working 若在 `Timing.startupWorkingWithin`（3 秒）內開始就標成啟動中，轉回 Idle 時若仍在 `startupSettleWithin`（10 秒）內就是啟動收尾。status 清掉時歸零，所以 Codex 退回 shell 再重開會重新起算。snapshot 或 `created` 帶著既有狀態進來的 agent 沒有出現時間，不會被當成啟動。啟動收尾那次 transition 以 `from: nil` 交給 `onTransition` 與 store 內部所有 transition 處理（現有規則都把第一次看到當成沒有變化），並作廢那段 Working 開始時起算的 git 基準（`openTurns` 取消、generation 加一）。
- 2026-11-12（agent）：測試：`StartupSettleTests` 6 個（啟動收尾不冒泡泡、不記時間軸、不觸發通知我且保持待命、不讀畫面、不算變更量；Working 晚於 3 秒照舊；Idle 晚於 10 秒照舊；結束在 Done 照舊；第二段 Working → Idle 照舊；退出再重開重新起算），全套 392 個通過。實機（dev-run + 在 shell 裡啟動 Codex 0.167.2）：啟動期間約每 0.9 秒抓一次泡泡，8 次都沒有，Today 窗格是空的；之後送一個真正的回合，Today 照常記一筆 Done 與最後一句話。
- 2026-11-12（agent）：code review 後修正：判斷原本不分工具，Claude Code 帶著很短的問題啟動、3 秒內開始 Working 又在 10 秒內以 Idle 結束時，這個真的回合會被吞掉，和 Out of scope 衝突；改成只對 Codex（`AgentTool.from(app:) == .codex`）生效，新增測試（共 7 個，全套 393 個通過）。另外 `trackStartup` 改名 `observeStartup`、transition 區塊改用 `from` 避免遮蔽 `before`、抽出 `discardOpenTurn`（Error 分支共用）。已知限制：herdr CLI 來源是輪詢比對，新 pane 第一次被輪詢到時已經帶著 Codex 的狀態（走 `created`）就沒有出現時間，啟動雜訊照舊（cmux 也走 `created`，不受這條規則影響）；使用者若在那 1 秒的 Working 裡排了訊息，要等下一個回合結束才送出。

