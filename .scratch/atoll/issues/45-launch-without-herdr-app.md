# 45: Herdr app 沒開也能啟動 agent，並可開新 space

**What to build:** 啟動表單在 Herdr app 關閉時整個不能用（Launch 停用、Space 只剩 Selected space），也沒辦法開一個自訂名稱的新 space。Herdr app 會把 space／tab 寫成 herdr-core terminal 的 label，app 關掉後還在；帶這些 label 用 `hc run` 起的 terminal，app 打開時就出現在那個 space。用這點讓表單在 app 關閉時照常啟動，並加上「New space…」。

**Blocked by:** 42, 43

**Status:** resolved

- [x] app 關閉時 Launch 可用：改走 `hc run --bg --keep --no-parent`，帶 `herdr.space`／`herdr.tab` label（每次一個新 tab）；一般 argv 照 `tab.new` 的方式經 login shell 執行、task 當最後一個參數，template 由 core 送 task
- [x] app 關閉時的 Space 清單：上次 `herdr-app ls` 的快取（存 UserDefaults）加上 live terminal 的 label，名稱以 `where` label 為準；「Selected space」改成「Last selected space」，取快取裡 app 最後顯示的 space，沒有就第一個，都沒有就開新 space
- [x] Space 選單加「New space…」與名稱欄位：app 開著時用 `herdr-app do space.new`；app 關閉時產生新 space id，名稱記在 pending 清單（存 UserDefaults），app 打開讀到該 space 後 `space.rename`，失敗下次重讀再試，launch 失敗則丟掉
- [x] 規則放在 AtollCore（`HerdrLabels`、`CoreRPCAdapter.hcRunArguments`、`AgentStore.launch`／`launchSpaces`），有測試

**Out of scope:** app 關閉時清單依 space 分段、自動喚起 Herdr app、`space.new` 帶 terminal 名稱（Herdr 不收）。

## Comments

- 2026-11-12（agent）：實測（Herdr 0.1.15）：app 關閉時用 label 起的 terminal，重開後出現在既有 space 的新 tab，以及新 space（名稱依資料夾）；id 不需要 `sp`／`tb` + hex 格式；`space.rename` 後 `where` 立即更新；app 關閉時 `herdr-app` 不會自動啟動 app（socket refused）。`hc run` 的 login shell 包裝實跑確認 task 以最後一個參數送達、結束後留下 shell。
- 2026-11-12（agent）：測試：`OfflineLaunchTests`、`HerdrLabelsTests`；原「app 沒開 → 拒絕」改為走 core；全套 420 個通過。表單 UI 未在 app 關閉狀態下實測。
- 2026-11-12（agent）：review 後修正：app 關閉時新建、尚未被 app 命名的 space 在選單顯示 pending 名稱（否則資料夾名），不再顯示 id；pending 名稱改在 launch 成功後才記，worktree 失敗不留；app 打開讀 spaces 時，丟掉既沒顯示、也沒有 live terminal 帶該 label 的名稱（等 core snapshot 到了才判斷）。表單的 Space 改用 `LaunchSpaceChoice`（selected／existing／new），request 由 `LaunchRequest(…optionID:space:newSpaceName:)` 在 AtollCore 組出；app 開著選 New space 時 Name 欄位停用並標示不適用；Settings 的 Default space 補上 app 關閉時的說明。全套 424 個通過。未處理：Recent／⌘R 不記住「New space…」。
