# Spec: Atoll（P0）

> 2026-11-10 由 Herdr Agent Island 改名為 Atoll：產品已同時整合 herdr-app、herdr CLI 與 cmux，不再只服務 Herdr。app 為 `Atoll.app`（bundle id `local.atoll`，首次啟動會搬移舊 `local.herdr-island` 的設定），模組為 `Atoll`／`AtollCore`，label 前綴為 `atoll.`（仍讀取舊的 `island.origin`）。

Status: ready-for-agent

## Problem Statement

我同時在 Herdr 裡跑多個 AI agent（Claude Code、Codex）。要知道哪個 agent 在工作、哪個卡在等我回覆、哪個出錯，只能切到 Herdr 視窗逐一查看。agent 等待輸入時我常常沒發現，任務因此停擺；要回一句話或中斷跑偏的 agent，也得離開手上的工作、找到對應 pane 再操作，容易送錯對象。

## Solution

一個自用的 macOS 常駐程式，在螢幕頂部（與瀏海融合）顯示像素風「動態島」：每個 agent 一個小角色，用動作、圖示與文字呈現狀態，需要注意的 agent 永遠釘在最顯眼的位置。點角色就展開該 agent 的互動面板，可以看近期輸出、傳送訊息、回答等待中的問題、中斷目前任務，或切回 Herdr 接手。也能直接從動態島透過 Herdr 啟動新 agent。所有資料只與本機 herdr-core 溝通；連線中斷或狀態不明時明確顯示「狀態未知」，不讓我誤以為資料是即時的。

## User Stories

### 監看

1. As a 多 agent 工程師, I want 每個 agent 在動態島上都有自己的像素角色, so that 我不用切視窗就能一眼看到所有 agent
2. As a 多 agent 工程師, I want 角色外觀代表工具（Claude Code／Codex／通用）, so that 我能分辨是哪種 agent
3. As a 多 agent 工程師, I want 每個 agent 在 session 存續期間有固定的個體色, so that 我能記住「黃色那隻是 project-x 的 Codex」
4. As a 多 agent 工程師, I want 等待使用者與錯誤狀態的角色釘在左翼且永遠可見, so that 需要我處理的 agent 不會被捲出視野
5. As a 多 agent 工程師, I want 其餘角色依優先級排列並可橫向捲動, so that agent 很多時仍能全部看到
6. As a 多 agent 工程師, I want 有 agent 等待或出錯時，動態島旁出現一行短文字（例如「Codex · project-x 在等你」）, so that 不靠動畫也知道誰需要我
7. As a 使用者, I want 每個狀態除了動畫還有圖示或文字, so that 色弱或關閉動畫時仍能辨識
8. As a 使用者, I want `blocked` 依 kind 顯示不同圖示（question／permission／auth）, so that 我知道 agent 是在問問題、要權限還是要登入
9. As a 使用者, I want Herdr 斷線時動態島變灰並顯示最後更新時間, so that 我不會把過期資料當成即時狀態
10. As a 使用者, I want 超過 heartbeat 期限沒收到資料時，所有 agent 轉為「狀態未知」, so that 介面不會猜測狀態
11. As a 使用者, I want 沒有 agent 時動態島縮成最小膠囊, so that 它不佔空間
12. As a 使用者, I want 有瀏海的螢幕上動態島與瀏海融合、往兩翼延伸, so that 它看起來是系統的一部分
13. As a 使用者, I want 沒有瀏海的螢幕上動態島是頂部置中的浮動膠囊, so that 外接螢幕也能用
14. As a 使用者, I want 只看到有回報 agent 狀態的 terminal, so that 一般 shell 與 dev server 不會干擾
15. As a 使用者, I want 設定中有開關可以顯示未回報狀態的 terminal（以「狀態未知」呈現）, so that 不回報狀態的 agent 也能被看到
16. As a 使用者, I want 每個 agent 顯示「最近狀態變化」時間, so that 我知道它多久沒動靜
17. As a 使用者, I want 打開過的已完成 agent 從慶祝動畫轉為安靜待機, so that 已看過的完成不再吸引注意

### 清單

18. As a 使用者, I want 點動態島上角色以外的區域展開 agent 清單, so that 我能看到每個 agent 的詳細資訊
19. As a 使用者, I want 清單卡片顯示名稱、工具、狀態與持續時間、專案目錄、最近狀態變化、是否等待我, so that 不用打開面板就能判斷
20. As a 使用者, I want 清單依優先級排序（等待使用者 > 錯誤 > 狀態未知 > 執行中 > 完成／閒置）, so that 最需要處理的在最上面
21. As a 使用者, I want 已退出的 session 收在清單底部, so that 不會與正在工作的 agent 混淆
22. As a 使用者, I want 按 `Esc` 逐層收回（面板 → 清單 → 收合）, so that 用鍵盤就能離開

### 互動

23. As a 使用者, I want 點某個角色直接打開該 agent 的互動面板, so that 一步就能處理它
24. As a 使用者, I want 互動面板固定標示目標（例如「傳送給 Codex · project-x」）, so that 我不會送錯 agent
25. As a 使用者, I want 打開面板時看到該 agent 的近期終端機輸出與擷取時間, so that 我知道它目前在做什麼
26. As a 使用者, I want agent 狀態或 turn 變化時輸出自動刷新，也能手動刷新, so that 我看到的內容是最新的
27. As a 使用者, I want agent 在 working／blocked 時面板標示「僅目前畫面」, so that 我知道看不到更早的歷史
28. As a 使用者, I want 對選定的 agent 輸入文字並傳送, so that 我能補充指示或追問
29. As a 使用者, I want agent 問問題（`blocked: question`）時直接用文字回答, so that 不用切回 Herdr
30. As a 使用者, I want agent 要權限（`blocked: permission`）時看到畫面擷取與一排按鍵（`1 2 3`、`y n`、Enter、Esc）, so that 我能直接選擇選項
31. As a 使用者, I want agent 需要登入（`blocked: auth`）時只提供切回 Herdr, so that 敏感流程在完整終端機裡處理
32. As a 使用者, I want 送出後看到「等待中／已送達／agent 已開始處理／已送出但無法確認／失敗」的明確狀態, so that 我知道訊息是否真的到了
33. As a 使用者, I want 我正在打字時送出顯示「等待中」, so that 我理解 Herdr 正在等我停手
34. As a 使用者, I want 送出失敗時看到錯誤原因與提示，並能手動重送, so that 我能修正後再試
35. As a 使用者, I want 程式永遠不自動重送, so that 指示不會被重複執行
36. As a 使用者, I want 按「中斷目前任務」並在 1.5 秒內再按一次確認, so that agent 跑偏時能快速停下，又不會誤觸
37. As a 使用者, I want 中斷後看到一次性的結果回饋（stopped／exited／still_working／unknown）, so that 我知道中斷是否生效
38. As a 使用者, I want 介面上不出現「結束 session」, so that 我不會把中斷誤當成刪除
39. As a 使用者, I want 一鍵切回 Herdr 並聚焦到該 agent 的 pane, so that 我能接手完整終端機操作
40. As a 使用者, I want 互動面板一次只開一個 agent，切換時替換內容, so that 不會有多個輸入框混淆目標

### 啟動

41. As a 使用者, I want 從動態島打開啟動表單, so that 不用切到 Herdr 就能開新 agent
42. As a 使用者, I want 從內建的 Claude Code、Codex 與 herdr-core templates 中選擇, so that 能用我習慣的工具與預設任務
43. As a 使用者, I want 從最近用過的目錄清單或 Finder 挑選工作目錄, so that 快速選對專案
44. As a 使用者, I want 輸入初始任務與可選的顯示名稱, so that agent 一啟動就開始工作
45. As a 使用者, I want 送出前固定看到「工具 · 目錄 · 初始指示前 60 字」摘要, so that 不會送錯專案
46. As a 使用者, I want 新 agent 開在預設 space（可在表單更改）, so that 它出現在 Herdr GUI 裡且能切回
47. As a 使用者, I want 看到「啟動中 → 啟動成功」或「已建立，未確認任務開始」或「啟動失敗」, so that 不會在任務沒開始時被告知成功
48. As a 使用者, I want Herdr GUI 沒開時啟動與切回按鈕停用並說明原因, so that 我知道為什麼不能用

### 鍵盤與通知

49. As a 使用者, I want 用全域快捷鍵（預設 `⌥⌘A`，可改）展開清單, so that 不用碰滑鼠
50. As a 使用者, I want 另一個全域快捷鍵直接打開最早開始等待的 agent, so that 處理等待只要一鍵
51. As a 使用者, I want 在清單用 `↑↓` 選擇、`Enter` 打開、`⌘1`–`⌘9` 直接跳到第 N 個, so that 鍵盤就能完成所有操作
52. As a 使用者, I want agent 等待使用者或出錯時收到 macOS 通知, so that 我在別的 app 裡也不會錯過
53. As a 使用者, I want 完成通知預設關閉，可依 agent 或專案打開, so that 通知不會太吵
54. As a 使用者, I want 通知內容只顯示「工具 · 專案名」, so that 畫面輸出不會出現在通知中心
55. As a 使用者, I want 點通知直接打開該 agent 的互動面板, so that 不用再找一次

### 設定與常駐

56. As a 使用者, I want menu bar icon 顯示等待數量 badge, so that 動態島隱藏時也知道有 agent 在等
57. As a 使用者, I want 從 menu bar 開關動態島、打開設定、結束程式, so that 能控制常駐行為
58. As a 使用者, I want 設定中看到 Herdr 連線狀態並能重新連線, so that 斷線時能自行恢復
59. As a 使用者, I want 程式啟動時檢查 `hc` 版本並在不相容時提示, so that 協定變動時不會默默壞掉
60. As a 使用者, I want 獨立開關通知與動畫, so that 依情境調整干擾程度
61. As a 使用者, I want 開啟系統「減少動態效果」或程式內關閉動畫時角色改為靜止首幀, so that 不受動畫干擾仍可辨識狀態
62. As a 使用者, I want core 重啟或暫時離線後自動重連並重新同步, so that 不需要手動處理
63. As a 使用者, I want 程式閒置時 CPU 與記憶體佔用很低, so that 它可以一直常駐

### 隱私

64. As a 使用者, I want 程式只與本機的 herdr-core、herdr CLI 與 cmux 溝通, so that prompt 與終端機輸出不會離開本機
65. As a 使用者, I want 近期輸出只在面板開著時存在記憶體中、關閉即丟棄, so that 沒有殘留的本機快取

### 美術

66. As a 使用者, I want 角色是同一族群的小機器人，用頭型剪影區分工具, so that 整體風格一致又能辨識
67. As a 使用者, I want 色盤是高明度、適合黑底的自訂 16 色, so that 角色在黑色膠囊上清楚可讀
68. As a 使用者, I want 個體色與狀態色互不重疊, so that 不會把「黃色個體」誤認成「等待中」
69. As a 使用者, I want 每個狀態有對應的動畫（啟動、工作、等待、完成、閒置、錯誤、中斷、退出、未知）, so that 角色的動作就能傳達狀態
70. As a 使用者, I want 動畫只在狀態變化與互動時明顯播放，平常只有輕微呼吸, so that 動態島不會持續閃動干擾我
71. As a 使用者, I want 先看到風格探索 board 再決定方向, so that 量產前就確認視覺走向

## Implementation Decisions

### 平台與技術

- 自用工具，不做 notarization、onboarding、診斷匯出。
- Swift + SwiftUI，視窗使用 AppKit `NSPanel`（無邊框、不搶焦點、層級高於 menu bar），最低 macOS 15。
- menu bar icon 只負責彙總 badge、開關動態島、設定、結束；所有 agent 操作集中在動態島展開面板。

### 介面語言

- 所有 UI 文字（動態島、清單、面板、表單、menu bar、設定、通知）使用英文。本 spec 其他段落以中文描述的狀態與文案，實作時一律採用下表的英文字串。

| 用途 | 英文字串 |
| --- | --- |
| 狀態：啟動中／執行中／等待使用者／完成／閒置／錯誤／已退出／狀態未知 | Starting / Working / Needs you / Done / Idle / Error / Exited / Unknown |
| blocked kind | Question / Permission / Sign-in required |
| 中斷回饋 | Interrupted · stopped／exited／still working／unknown |
| 收合態提示 | Codex · project-x needs you |
| 斷線 | Herdr offline · Last updated hh:mm |
| 面板目標 | Send to Codex · project-x |
| 送出狀態 | Waiting for you to stop typing… / Delivered / Agent started / Sent · unconfirmed / Failed |
| 輸出區 | Fetched at hh:mm:ss / Screen only / Refresh |
| 切回 | Open in Herdr |
| 中斷按鈕 | Interrupt current task → Press again to confirm |
| 啟動狀態 | Starting… / Launched / Created · task start unconfirmed / Launch failed |
| 最近活動 | Last status change |
| GUI 未開 | Herdr app isn't running |

### Herdr 整合邊界

- 主要後端是 herdr-core（目前 `hc` 0.1.19），另外直接讀取 herdr CLI／TUI（`herdr` 0.9.x）與 cmux 自己整合的 agent（ticket 19–21）。三者都不需要改 shell 設定。herdr-core 的說明：直接連 core 的 Unix socket，走 JSON-RPC 2.0（一行一則訊息），不 spawn `hc` CLI。協定處於 preview（generation 1，只增不減），因此所有 RPC 包在薄 adapter 後面，啟動時以 `rpc.discover`／版本檢查相容性。
- Herdr GUI（`herdr-app`）擁有 space／tab；啟動與聚焦走 `herdr-app` 的公開指令（`do tab.new`、`do agent.focus`）。GUI 沒開時這兩項停用，其餘功能照常。
- 一般終端機（Ghostty、cmux、iTerm 等）啟動的 agent：經 `scripts/shell/atoll.zsh` 的包裝函式改以 `hc run` 執行，仍只透過 herdr-core 整合（ticket 18）；來源 app 記在 label `atoll.origin`。
- herdr CLI／TUI：socket `~/.config/herdr/herdr.sock`，狀態來自 `agent.list`（約 2 秒輪詢＋pane 事件即時刷新），位址 `herdr:<terminal_id>`（ticket 20）。
- cmux：以 `cmux events` 的 `agent.hook.*` 事件推得每個 session 的狀態，位址 `cmux:<session_id>`；cmux 沒開時不呼叫任何 cmux 指令。從 cmux surface 啟動的程序（例如 herdr server）會繼承 `CMUX_SURFACE_ID`，其 session 若屬於 herdr／herdr-core（環境有 `HERDR_PANE_ID`／`HC_TERMINAL_ID`）就不在 cmux 來源重複顯示（ticket 21）。
- Herdr mods 不在整合範圍（mods 只能畫在 Herdr 視窗內，不滿足需求）。

### 模組

- **HerdrClient（介面）**：對 Herdr 的全部依賴。能力包括：訂閱事件串流（snapshot、`created / lost / restarted / finished / removed / status / turn / title / labels / foreground`、15 秒 heartbeat、`missed` 後重給 snapshot）、讀取輸出、傳送文字、傳送按鍵、中斷、啟動（`tab.new`）、聚焦（`agent.focus`）、版本檢查。回傳 Herdr 的結構化結果與 `{kind, message, hint}` 錯誤，不做 UI 判斷。
- **CoreRPCAdapter**：HerdrClient 的實作，負責 socket 連線、JSON-RPC 編解碼、自動重連、以及呼叫 `herdr-app` 指令。
- **AgentStore（領域核心）**：吃 HerdrClient 的事件與指令結果，產出 UI 要的 agent 清單與狀態。負責狀態對映、過濾、優先級排序、過期判定、送出狀態機、啟動狀態機、本機「已確認」標記、個體色指派。這是唯一有業務邏輯的模組。
- **IslandUI**：動態島視窗、收合態角色列、清單、互動面板、啟動表單、menu bar；只讀 AgentStore 的狀態並轉發使用者意圖。
- **SpritePlayer**：讀取 sprite sheet + JSON，依狀態播放 loop／one-shot，整數倍 nearest-neighbor 縮放，尊重減少動態效果設定。
- **Notifier**：把 AgentStore 的狀態轉換映射成 macOS 通知，點擊後導向指定 agent。

### 狀態對映

使用者可見狀態由 AgentStore 依下表決定：

| 使用者可見狀態 | 來源 |
| --- | --- |
| 啟動中 | 已送出 launch，尚未收到該 terminal 的第一個 status |
| 執行中 | `status.state = working` |
| 等待使用者 | `status.state = blocked`，附 `kind`（question／permission／auth） |
| 完成 | `status.state = done` |
| 閒置 | `status.state = idle` |
| 錯誤 | `status.state = error` |
| 已退出 | terminal `state = finished` |
| 狀態未知 | socket 斷線、超過 heartbeat 期限未收資料，或 terminal 從未回報 status |

- 「已中斷」不是持續狀態：只是 `interrupt` 結果（stopped／exited／still_working／unknown）的一次性回饋，之後回到 Herdr 的實際狀態。
- `done` 與 `idle` 沿用 Herdr 語意；在動態島打開該 agent 的面板時，AgentStore 只在本機記「已確認」（角色由慶祝轉待機），不寫回 Herdr。
- 不從畫面文字推測狀態；沒有新輸出不代表完成。
- 優先級：等待使用者 > 錯誤 > 狀態未知 > 執行中 > 完成 > 閒置 > 已退出。同級內等待使用者依「開始等待時間」由早到晚。
- 預設只顯示有回報 `status.app` 的 terminal；設定開關打開時其餘 terminal 以「狀態未知」顯示。
- 「最近狀態變化」= AgentStore 本機記錄的最後一個 `status`／`turn`／`foreground` 事件時間（core 沒有輸出活動時間欄位）。
- 個體色在 terminal 第一次出現時指派，session 存續期間不變，不因排序改變。

### 送出語意

- 狀態機：`等待中`（Herdr 等待人類停止打字，最長約 60 秒）→ `已送達`（RPC 成功回傳）→ `agent 已開始處理`（`started = true`）或 `已送出，無法確認`（`started = null`）；任何一步出錯 → `失敗`（顯示 `error.kind` 與 `hint`）。
- 永不自動重送；失敗後只提供手動重送。
- `blocked: question` 用文字傳送並帶 force（Herdr 預設拒絕送給 blocked 的程式）；`blocked: permission` 只送按鍵；`blocked: auth` 不提供輸入。
- 不針對各工具解析選單，permission 只提供通用按鍵排。

### 啟動語意

- 選單：內建 Claude Code（`claude`）、Codex（`codex --no-daemon`），加上 core templates（`~/.config/herdr-core/templates/*.md`）自動讀取。
- 經 `herdr-app do tab.new` 在預設 space 建立（表單可改），附 cwd、argv、初始任務。
- 狀態機：`啟動中` → 回傳 terminal 且 30 秒內收到 `working` → `啟動成功`；拿到 terminal 但逾時 → `已建立，未確認任務開始`（附切回 Herdr）；指令失敗 → `啟動失敗`。

### 中斷

- 按鈕名固定「中斷目前任務」，第一次按下變為「再按一次確認」，1.5 秒內再按才呼叫 interrupt。
- 「結束 session」、kill、rm 不出現在 MVP UI。

### 動態島版面

- 有瀏海：黑色膠囊與瀏海融合往兩翼延伸；左翼放釘住的需注意角色與提示文字，右翼放其餘角色並可橫向捲動、兩端淡出。兩翼寬度分開計算。
- 無瀏海：頂部置中的浮動膠囊，同樣的左右分區邏輯。
- 0 個 agent：最小膠囊加一個待機角色。
- 斷線：膠囊轉灰，顯示「Herdr 離線 · 最後更新 hh:mm」，角色保留並標為狀態未知。
- 點角色 → 直接展開該 agent 的互動面板；點其他區域 → 展開清單。
- 互動面板與啟動表單都是動態島往下展開的面板（約 480pt 寬、高度隨內容），一次只開一個 agent。

### 近期輸出

- 面板打開時讀取 200 行；之後收到該 agent 的 `status`／`turn` 事件自動刷新；可手動刷新；標示擷取時間；Herdr 回傳只有畫面時標示「僅目前畫面」。
- 不做本機快取，面板關閉即丟棄。

### 鍵盤

- 全域快捷鍵：`⌥⌘A` 展開清單；第二組快捷鍵打開最早開始等待的 agent。兩者皆可改。
- 清單內：`↑↓` 選擇、`Enter` 打開面板、`⌘1`–`⌘9` 直接跳到第 N 個、`Esc` 逐層返回。

### 通知

- 預設：等待使用者、錯誤會通知；完成預設關閉，可依 agent／專案打開；執行中永不通知。
- 內容只含「工具 · 專案名」，不含輸出。點擊打開該 agent 的互動面板。

### 美術系統

- 製作流程：Codex imagegen 做風格探索與角色設計稿；最終 sprite 以原生 16×16 重繪或量化後人工修圖，鎖定色盤；pixelfx（MIT）離線產出特效層（問號氣泡、訊息飛出、慶祝）。不採用 `hatch-pet` 的 atlas 格式，只參考其狀態分類與 QA 流程。
- 尺寸：角色原生 16×16；收合態 1 像素 = 1pt，展開面板 2×；一律整數倍 nearest-neighbor。
- 風格：自訂約 16 色高明度色盤、純黑底；輪廓用深色調彩色線或亮邊而非黑線；預留一組個體識別色，避開狀態色（錯誤紅、等待黃）。
- 角色：同一小機器人族群，Claude Code／Codex／通用三種頭型剪影；個體色只上在配件區（圍巾、天線）；不使用官方吉祥物或 logo。
- 文字與控件使用系統原生（SF Pro／SF Mono），像素只用於角色、狀態圖示與少量點綴。
- 資源格式（app 唯一接受的格式）：透明 PNG sprite sheet + Aseprite 風格 JSON（frame rect、duration、loop／one-shot、fps、pivot）。P0 的程式化占位角色也用同一格式。
- 動畫清單（每種外觀約 30 幀）：

| 狀態 | 動畫 | 幀數 | 播放 |
| --- | --- | --- | --- |
| 啟動中 | 生成 | 4 | 一次 |
| 執行中 | 工作 | 4–6 | 循環 |
| 等待使用者 | 舉手 + 依 kind 的圖示氣泡 | 4 | 循環 |
| 完成 | 小慶祝 | 6 | 一次，之後轉待機 |
| 閒置 | 慢速呼吸 | 2–4 | 循環 |
| 錯誤 | 錯誤反應 | 4 | 一次，停在最後一幀 |
| 中斷回饋 | 停下 | 3 | 一次 |
| 已退出 | 變暗睡覺 | 1 | 靜止 |
| 狀態未知 | 灰階 + 「?」 | 1 | 靜止 |

- 減少動態效果：所有狀態改用第 0 幀靜止。
- 定案流程：先產出風格探索 board（3 個方向 × 3 種外觀的 idle 幀，原生 16×16 加放大預覽），選定方向後再量產。

### 開工前要先驗證的事實

以下 4 項已於 2026-11-10 對 `hc` 0.1.19 ＋ Herdr app 0.1.14 驗證（ticket 04），可用 `HERDR_CONTRACT=1 swift test --filter Contract` 重跑協定部分：

1. **Codex 會回報 OSC 7501**：`codex --no-daemon` 啟動後 `reported = true`、`status = {app: "codex", state: "idle"}`。Codex 與 Claude Code 同樣走一般狀態路徑。（附帶：core 的 PATH 不含 nvm，`terminal.run` 直接以 argv `codex` 啟動會 `spawn_failed`；本 app 的啟動走 `herdr-app do tab.new`，不受影響，見第 3 點。）
2. **`herdr-app do agent.focus` 不會把 Herdr 視窗帶到前景**：只切到該 tab／pane（`herdr-app status` 的 `agent` 改變，前景 app 不變）。`Open in Herdr` 因此在 focus 後另外 activate Herdr app（bundle id `dev.herdr.app`）。
3. **`herdr-app do tab.new` 不回報初始任務是否被處理**：立即回傳 `{space, tab, terminal}`。實測 terminal 的 argv 為 `/bin/zsh -lic '"$@"; exec "$0" -li' /bin/zsh <argv…> <task>`：tab.new 自己以 login＋interactive shell 包裝（nvm／PATH 會載入），並把 task 當成程式的最後一個參數傳入（`claude "<task>"`），`first_message` 為 null。因此內建工具直接用 argv `claude`／`codex --no-daemon`，不可再自行包 shell（會把 task 吃掉）。啟動成功判定維持「拿到 terminal 且 30 秒內收到 `working`」；實測 Claude Code 約 3 秒內 Launched。
4. **「已看過」寫回：未確認，P0 不依賴**：live terminal 帶有 label `herdr.seen`，其值等於該 terminal 的 `turn`，推測是 Herdr app 寫入的「已看過」標記（可能經 `terminal.label`），但未觀察到寫入過程。P0 的「已確認」只存本機，不呼叫任何寫回指令。

實作中確定的協定細節：

- 不需 `hello` 即可呼叫 RPC；訂閱後的 plain 連線只收通知，指令各自開短連線（`terminal.send` 可能等使用者停止打字數秒）。
- 事件格式 `{"method":"event","params":{"seq","terminal","type","data"}}`；`status` 事件帶完整 `status`（可為 null），`turn` 事件為 `{state, turn}`，`created` 帶完整 terminal；heartbeat 為 `{"method":"heartbeat","params":{"seq"}}`。快速連續的狀態可能被合併，不保證每次轉換都有事件，因此以 snapshot／created 的資料為底。
- OSC 7501 格式：`ESC ] 7501 ; state=<s>:kind=<k>:app=<a>:msg=<m> BEL`。
- live 且曾回報、但 `status` 變為 null（例如 agent 退回 shell）→ 狀態未知。
- 啟動前就已 finished、從未在本次 session 看過 `app` 的 terminal 預設不顯示（設定「Show terminals without status」打開時以 Exited 顯示）。

## Testing Decisions

- **好的測試**：只透過模組的公開介面驗證外部可見行為（AgentStore 輸出的清單、狀態、排序、送出／啟動狀態、發出的 HerdrClient 指令），不檢查內部資料結構或私有方法。重構內部實作不應讓測試失敗。
- **主 seam：HerdrClient**。AgentStore 以可注入事件序列與指令結果的 fake HerdrClient 測試。涵蓋：
  - 每一列狀態對映（含 blocked kind、finished、從未回報、斷線、heartbeat 逾時、`missed` 後 snapshot 重建）
  - 「已中斷」只作一次性回饋，之後回到實際狀態
  - 優先級排序與同級排序、釘選規則
  - `status.app` 過濾與設定開關
  - 個體色在排序變動後不變
  - 送出狀態機各路徑（started true／null、各種錯誤 kind、等待人類停止打字），且確認從不自動重送
  - blocked kind 決定可用的回覆方式（文字＋force／按鍵／只能切回）
  - 啟動狀態機（成功、逾時、失敗、GUI 未開時停用）
  - 中斷需二次確認才發出指令
  - 本機「已確認」標記不會呼叫任何寫回 Herdr 的指令
  - 通知觸發規則（哪些轉換會通知、內容不含輸出）
- **補充：CoreRPCAdapter 契約測試**。對本機真實 herdr-core 執行，驗證 schema 與欄位、事件順序、錯誤格式符合預期，並用來確認「開工前要先驗證的事實」。預設不跑，手動觸發（需要 core 執行中）；只做唯讀操作與自己建立、自己清除的測試 terminal。
- **不做自動化測試**：SwiftUI 版面、動態島視窗定位、動畫播放。靠 dogfood 與逐幀檢查。
- Prior art：新 repo，尚無既有測試；以 Swift Testing 建立第一批測試作為後續範本。

## Out of Scope

- 遠端／多機器 Herdr 管理（`hc machine`）
- 任務歷史搜尋、標籤、收藏、依專案分組、父子 agent 關係視覺化
- 封存已完成 session、近期輸出本機快取、快取保留設定（P1）
- 結束／kill／移除 session、清除輸出或歷史
- 自訂角色、色盤、動畫與動態島配置
- 解析各 agent 工具的原生選單或對話 UI
- notarization、對外發佈、onboarding、遙測、診斷匯出
- Herdr mods
- 依畫面文字推測 agent 狀態

## Further Notes

- 原始需求文件為 PRD v0.1；本 spec 依其後的釐清結果覆寫了部分內容：中斷移入 P0、收合態改為每個 agent 一個角色、像素角色改為原生 16×16 系統。
- 整合線（HerdrClient／AgentStore／UI）與美術線（風格探索 → 角色 → 動畫）可平行；整合線先用程式化占位 sprite。
- herdr-core 協定為 preview 狀態，版本升級後應重跑 adapter 契約測試。
- 參考資料：herdr-core README、docs/commands.md、OpenRPC schema（`hc schema`）；pixelfx（github.com/patch-gg/pixelfx）。
