# 38: 今日時間軸

**What to build:** 一個「Today」視圖，把每個 agent 今天每個回合結束的時間、狀態、最後一句話與變更量排成時間線。離開一陣子回來，不用逐一打開面板就能知道誰做了什麼、哪些還沒看。資料都已經有：回合結束的判斷（ticket 24 的 `turnEnded`）、最後一句話（`Agent.lastWords`，ticket 35）、變更量（`ChangeSummary`，ticket 28），只差收集與呈現。

**Blocked by:** —

**Status:** resolved

**隱私決策（已確認採用提案）：** ticket 35 規定最後一句話「下一個回合開始就丟棄」，時間線要保留它就得放寬。提案：時間線只存在記憶體，Atoll 結束、日期換日或按「Clear」就丟棄，不寫入磁碟、不放進通知；每筆的文字沿用 ticket 35 的截斷（最多 2 行、每行 200 字）；Settings 可關閉時間線（關閉時不收集）。spec 第 65 條與 README 隱私段落需一併更新。

- [x] 收集：每次 live transition 判定回合結束（Done／Idle from Working／Exited，以及 Error）記一筆：時間、agent 顯示名稱與工具、專案名、結束狀態、`lastWords`（回合結束當下沒有的話，等 ticket 35 的畫面讀取回來後補上同一筆，不另起一筆）、`ChangeSummary` 的文字（git 算完後補上）。Needs you 不記（它不是回合結束）
- [x] 上限：只保留今天（本機時間 00:00 起）的紀錄，最多 200 筆，超過丟最舊的；換日時清空
- [x] agent 被移除或退出後，它的紀錄保留在時間線上（標示已不在），點了不打開面板
- [x] 顯示：選單列加「Today…」與清單底列加一個入口，打開一個視窗（或動態島的新模式，實作時擇一並說明理由）：依時間倒序，每筆一列「14:32 · Claude Code · atoll · Done · +120 −30 · 最後一句話」；可依 agent 篩選；點了打開該 agent 的面板
- [x] 「未看」標記：回合結束後使用者還沒打開過該 agent 面板的紀錄加一個點，打開面板後清掉（只在記憶體）；視窗標題顯示未看數
- [x] 規則（收集、補欄位、上限、換日、未看）放在 AtollCore，fake client 測試：回合結束記一筆、最後一句話晚到補在同一筆、變更量晚到補上、Needs you 不記、上限與換日、移除後保留、打開面板清除未看、關閉時不收集

**Out of scope:** 寫入磁碟或跨 Atoll 重啟保留、匯出、跨天瀏覽、統計圖表、用模型摘要一天的工作。

## Comments

- 2026-11-12：使用者確認採用上述隱私提案（只存在記憶體、Atoll 結束／換日／Clear 即丟棄、不寫磁碟不進通知、沿用 ticket 35 截斷、Settings 可關閉），改為 ready-for-agent。
- 2026-11-12（agent）：AtollCore 新增 `TodayTimeline`／`TimelineEntry`（只在記憶體）。`AgentStore` 在 live transition 時：Done／Exited／從 Working／Starting 轉 Idle（同 `turnEnded`）與 Error 記一筆，Working／Starting／Needs you 關掉該 agent「還開著的那一筆」。同一個回合只有一筆：開著的那筆還在時，Done → Idle → Exited 的收尾與重連後再看到 Done 都不另起一筆，只有之後轉 Error 才會再記。開著的那筆在每次 rebuild 補上晚到的欄位：`lastWords`（status msg 或畫面讀取，用 `TurnFinalMessage` 截成最多 2 行、每行 200 字）與 `ChangeSummary.text`，只補空的欄位，所以下一個回合把 agent 的 `lastWords` 清掉後，時間線上的那句話還在；agent 不在清單上就關掉，同一個 address 之後的新 agent 另起一筆。最多 200 筆（丟最舊的），記錄時丟掉今天 00:00 以前的，另排一個本機午夜的計時器在沒有新事件時清空（`store.calendar` 可注入）。未看：記錄時該 agent 的面板正開著就算看過，`openPanel` 把該 agent 的紀錄全標成看過。`timelineEnabled` 關掉時清空且不收集，`clearTimeline()` 給 Clear 用。rebuild 只在時間線真的有變時才寫回，避免每次 rebuild 都觸發畫面更新。
- 2026-11-12（agent）：UI：選擇做成獨立視窗（`TodayView`，比照 Settings 視窗），不做動態島的新模式：每列要放時間、名稱、狀態、變更量、最後一句話，還要篩選，動態島面板（480pt 寬）放不下，而且這是離開一陣子回來才看的東西，不需要貼著動態島。入口是選單列的「Today…」與清單底列的「Today」按鈕（有未看時顯示數字）。視窗依時間倒序，每列：未看點、`HH:mm · Codex · cx ·` 狀態圖示與文字（狀態色是為深色動態島調的，在淺色視窗只給圖示上色）、變更量、已不在的標「Gone」並停用，第二行是最後一句話（最多 2 行，help 全文）。有 agent 篩選與 Clear；視窗標題「Today · N unseen」。點一列會顯示動態島並打開該 agent 的面板（同通知點擊的路徑）。Settings 加「Today timeline (in memory, cleared at midnight)」開關（預設開）。spec 第 65 條與 README 隱私段落已更新，README 加一段功能說明。DebugHook 加 `today`（打開視窗並截圖、標題寫進 today.txt）。
- 2026-11-12（agent）：測試：`TimelineTests` 11 個（回合結束記一筆、Needs you 不記且收尾只算一筆、Error 與停成 Idle 都記、重連不重記、最後一句話晚到補在同一筆且下個回合後仍在、status msg 截斷、變更量晚到補上、移除後保留且同 address 新 agent 另起一筆、上限 200、午夜清空、未看與打開面板清除、關閉時不收集與 Clear），全套 380 個通過。實機（dev-run + `hc` 跑 Codex 0.167.2）：兩個回合後視窗列出兩筆、各有最後一句話、標題「Today · 2 unseen」；打開該 agent 面板後標題變回「Today」；面板開著時結束的第三回合沒有未看點；移除該 terminal 後三筆都還在、變灰並標示 Gone。測試目錄是沒有 commit 的 git repo，所以沒有變更量可顯示，變更量只由單元測試涵蓋。沒有實機測的：點視窗裡的一列打開面板（合成點擊只能送到動態島視窗；這一列和 debug 的 `panel` 指令走同一個 `model.openPanel`）、午夜清空、篩選選單。
- 2026-11-12（agent）：code review 後修正：(1) 下一個回合的 status msg（例如 Needs you 的等待原因）不再補進上一筆：rebuild 補欄位跑在關閉那筆之前，改成只在 agent 還停在 Done／Idle／Exited 時才補；(2) 沒經過 Working 的新回合（Idle → Done）原本會漏記：每筆記下回合結束當下的 `turn`（herdr 在 Done 之後才把它加一），開著的那筆 `turn` 不同就是新回合，另起一筆；補欄位時 agent 的 `turn` 已經超過那筆的 `turn + 1` 就不補；(3) Error 一律獨立一筆、只帶來源的 status msg，不再複製同回合 Done 的最後一句話與變更量，也不接手晚到的欄位（轉 Error 時 store 本來就會作廢那回合的 git 與畫面讀取）；(4) 換日：`calendar` 改 `Calendar.autoupdatingCurrent`，app 收到 `NSCalendarDayChanged`、`NSSystemTimeZoneDidChange`、喚醒時呼叫 `rollOverTimeline()`，補上睡過午夜計時器晚到的情況；(5)「已不在」改成紀錄上的 `gone` 旗標：agent 結束（退出，或來源清掉狀態，例如 Codex 退回 shell；斷線不算）或離開清單就設上，之後同一個 address 有新 agent 也不會恢復，不必等退出後在清單上停留的 15 秒；(6) 時間線沒有變化時不寫回（開著的那筆才關、有未看才標記、沒有紀錄就略過補欄位）；terminal 有自訂名稱時列上補上專案名。新增測試 6 個，共 17 個，全套 386 個通過。實機重測：Codex 回合後列出 Done 與最後一句話；Codex 退出回 shell 後該 agent 的紀錄立即標 Gone（修正前要等它離開清單）。
- 2026-11-12（agent）：保留但沒有在 ticket 裡要求的：關閉時也清空既有紀錄（隱私上較保守，spec 第 65 條已寫明）、清單底列按鈕顯示未看數、README 功能段落、DebugHook `today`。已知行為：Codex 啟動時回報 Working 後轉 Idle，會被記成一筆沒有最後一句話的「Idle」（和泡泡、通知用的是同一條「從 Working 轉 Idle 就是停下來的回合」規則，泡泡也會冒）；沒處理，因為分辨不出它和使用者第一個回合被中斷的情況。
- 2026-11-12（agent）：依使用者要求，Today 從獨立視窗改成動態島的窗格（`IslandModel.Mode.today`），比照清單與啟動表單：選單列「Today…」會顯示動態島並打開它，清單底列的「Today」也是；`Esc` 或標題列的清單鍵回到清單，釘選鈕可以保持展開。標題列有「Today」、未看數、agent 篩選、Clear；列表最高 420pt 可捲動，每列是一張卡片（hover 變亮），點了打開該 agent 的面板，Gone 的卡片變淡且點了沒反應。在深色動態島上，狀態文字恢復用狀態色。獨立視窗、`.atollShowToday` 通知與視窗標題的未看數都拿掉了。實機：清單 → Today 顯示兩筆與「2 unseen」，點一列打開面板，回到 Today 時未看點已清掉，`Esc` 回清單。
- 2026-11-12（agent）：依使用者要求，收合的動態島右翼加一顆 Today 按鈕（`TodayToggleButton`，排在「＋」與清單之間，`IslandLayout.buttonsWidth` 改成 3 顆）：點了打開 Today 窗格，已打開時再點收起，help 與無障礙標籤帶未看數。圖示是 12×12 的時鐘（奶油色鐘面、teal 指針、刻度），和 list／launch 一樣由 `.scratch/atoll/art/final/make_sprites.py` 產生 `today`／`today_open`（打開時上移 1px、指針變黃）；重跑腳本只有 `ui.png`／`ui.json` 改變。實機：收合狀態三顆按鈕並排，點時鐘展開 Today 窗格且圖示切成展開版。

