# 36: Working 長時間沒有新輸出時提示

**What to build:** agent 停在 Working 很久、畫面卻一直沒有變化時，在清單列、hover card 與面板標題列標示「No output for 10m」。只陳述「畫面沒變」這個事實，不推測 agent 卡住或當掉（符合「誠實的狀態」原則）；用途是提醒使用者看一眼，例如它可能在等一個不會結束的指令。

**Blocked by:** —

**Status:** resolved

**待確認的前提：** herdr-core 事件串流（`status / turn / title / labels / foreground / finished …`）目前沒有「畫面有新輸出」的事件，herdr CLI 與 cmux 也沒有。實作的第一步是確認三個來源有沒有更便宜的訊號（例如 herdr-core 的 terminal 活動時間戳或 `hc events` 裡的輸出事件）；有的話改用它，下面的輪詢方案作廢。

- [x] 輪詢方案（沒有現成訊號時）：只對 Working 的 agent，每 2 分鐘 `read(terminal:lines:)` 讀一次畫面（行數小，例如 40），**只保留雜湊**，不保留內容；去掉 spinner、計時器、token 計數這類會一直跳動的列後再算雜湊（規則放在 `OutputFilter`），否則畫面永遠「有變化」
- [x] 雜湊連續相同超過門檻（預設 10 分鐘，Settings 可選 5／10／20 分鐘或關閉）就標示；畫面一變或離開 Working 立刻清掉並重新計時
- [x] 讀取失敗：這一次不算（不重設、不累計），連續失敗不顯示提示
- [x] 讀取次數有上限：同時 Working 的 agent 再多，每分鐘總讀取次數有上限（例如 10 次），超過就把間隔拉長，不擋住其他指令
- [x] 顯示：清單列與面板標題列在狀態字後加「· No output for 12m」（次要色，不用警示色），hover card 同；不發通知、不冒泡泡
- [x] 隱私：畫面內容只在算雜湊時短暫存在，不留在記憶體；spec 第 65 條與 README 的隱私段落註明「只保留雜湊」
- [x] 規則（雜湊前的過濾、門檻判斷、讀取節流）放在 AtollCore，fake client 測試：畫面不變超過門檻標示、spinner 跳動不算變化、畫面變化清除、離開 Working 清除、讀取失敗不重設、多個 agent 時的節流

**Out of scope:** 自動中斷或重送、判斷 agent 是否卡住、CPU／網路活動偵測、Needs you 等其他狀態的計時。

## Comments

- 2026-11-12（agent）：前提確認：herdr-core 的 terminal 資訊（`hc get`）沒有活動或輸出時間戳，`hc events` 在 agent 持續輸出時只送狀態類事件（實測 8 秒內只有 snapshot）；herdr CLI 的 list diff 與 cmux 的 `agent.hook.*` 也沒有輸出事件，所以採用輪詢方案。
- 2026-11-12（agent）：AtollCore：`OutputFilter.activityFingerprint`（FNV-1a）建在 `activityLines` 上：Claude Code 經 `claudeMessages`（去掉輸入框、狀態列、footer 的 spinner／提示／點字動畫），再去掉緊接在 `⎿` 上方的工具標題列；Codex 經 `codexMessages` 並去掉 `• Working (Ns • esc to interrupt)`（只認行首的 `Working (`，回覆裡提到 esc to interrupt 仍算輸出）；之後去掉 powerline 裝飾列與點字動畫列，把時間（`12s`、`1m 40s`、`1m40s`、`250ms`，相鄰的合併成一個）與 token 計數（`12,345 tokens`、`1.2k tokens`）換成 `#`，行首的 `⏺`／`•` 換成空白。`NoOutputWatch`（只存雜湊與時間）：新進 Working 的 agent 等滿一個間隔才第一次讀（短回合不讀），雜湊第一次出現的時間當起點，成功的讀取確認超過門檻才標示；讀取失敗不重設起點、也不算確認，單次失敗顯示不變，連續兩次失敗才隱藏；每次讀取有 ticket（entry id 加上第幾次），離開再回到 Working 或被放棄的讀取結果都作廢；超過兩個間隔沒回應的讀取視為失敗，之後照常排下一次。`AgentStore`：`noOutputThreshold`（nil 關閉，同時停止讀取）、`Timing.outputCheckInterval`（120 秒）／`outputCheckLines`（40）／`outputChecksPerMinute`（10）；每 `60 / 上限` 秒一個 tick，每個 tick 最多讀一個到期最久的 agent，所以不論多少 agent，每分鐘總讀取次數不超過上限，間隔自然拉長；讀取結果讓標示改變時才 rebuild。`Agent.noOutputSince`。
- 2026-11-12（agent）：UI：清單列、hover card、面板標題列在狀態後加「· No output for 12m」（次要色，help 說明畫面從幾點沒變）；Settings 新增「No output」區塊的「Mark no output after」（Off／5／10／20 分鐘，預設 10），說明文字的讀取間隔取自 `Timing`。
- 2026-11-12（agent）：測試：指紋 7 個（Claude 計時／點字動畫／輸入框下方狀態列不算、閃爍的 `⏺` 不算、工具標題被改寫不算、新輸出列算、Codex Working 列不算但回覆算、回覆提到 esc to interrupt 仍算、generic 的時間與 token 計數），store 8 個（不變超過門檻標示、spinner 與計時跳動不算、畫面變化清除、離開 Working 清除且停止讀取、單次失敗不變／連續失敗隱藏／都不重設、沒回應的讀取不會讓檢查永久停止、30 個 agent 時每分鐘不超過上限、關閉時完全不讀），全套 345 個通過。dev-run 實測（門檻暫設 1 分鐘）一開始一直沒標示，追出兩個真實畫面才有的變化：執行中工具列的 `⏺` 會閃爍，Claude Code 也會每兩分鐘左右把執行中的工具標題改寫成摘要；兩者都改成不計入、補上測試後，同一個長指令執行約 5 分鐘時清單顯示「Working · … · No output for 2m」。顯示的時間從第一次看到這個畫面的檢查算起，所以會比實際少最多一個檢查間隔。
