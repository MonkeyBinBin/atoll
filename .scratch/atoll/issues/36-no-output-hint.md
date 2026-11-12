# 36: Working 長時間沒有新輸出時提示

**What to build:** agent 停在 Working 很久、畫面卻一直沒有變化時，在清單列、hover card 與面板標題列標示「No output for 10m」。只陳述「畫面沒變」這個事實，不推測 agent 卡住或當掉（符合「誠實的狀態」原則）；用途是提醒使用者看一眼，例如它可能在等一個不會結束的指令。

**Blocked by:** —

**Status:** ready-for-agent

**待確認的前提：** herdr-core 事件串流（`status / turn / title / labels / foreground / finished …`）目前沒有「畫面有新輸出」的事件，herdr CLI 與 cmux 也沒有。實作的第一步是確認三個來源有沒有更便宜的訊號（例如 herdr-core 的 terminal 活動時間戳或 `hc events` 裡的輸出事件）；有的話改用它，下面的輪詢方案作廢。

- [ ] 輪詢方案（沒有現成訊號時）：只對 Working 的 agent，每 2 分鐘 `read(terminal:lines:)` 讀一次畫面（行數小，例如 40），**只保留雜湊**，不保留內容；去掉 spinner、計時器、token 計數這類會一直跳動的列後再算雜湊（規則放在 `OutputFilter`），否則畫面永遠「有變化」
- [ ] 雜湊連續相同超過門檻（預設 10 分鐘，Settings 可選 5／10／20 分鐘或關閉）就標示；畫面一變或離開 Working 立刻清掉並重新計時
- [ ] 讀取失敗：這一次不算（不重設、不累計），連續失敗不顯示提示
- [ ] 讀取次數有上限：同時 Working 的 agent 再多，每分鐘總讀取次數有上限（例如 10 次），超過就把間隔拉長，不擋住其他指令
- [ ] 顯示：清單列與面板標題列在狀態字後加「· No output for 12m」（次要色，不用警示色），hover card 同；不發通知、不冒泡泡
- [ ] 隱私：畫面內容只在算雜湊時短暫存在，不留在記憶體；spec 第 65 條與 README 的隱私段落註明「只保留雜湊」
- [ ] 規則（雜湊前的過濾、門檻判斷、讀取節流）放在 AtollCore，fake client 測試：畫面不變超過門檻標示、spinner 跳動不算變化、畫面變化清除、離開 Working 清除、讀取失敗不重設、多個 agent 時的節流

**Out of scope:** 自動中斷或重送、判斷 agent 是否卡住、CPU／網路活動偵測、Needs you 等其他狀態的計時。

## Comments
