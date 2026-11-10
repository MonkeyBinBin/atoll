# 10: 傳送訊息與回答 question

**What to build:** 在互動面板對目標 agent 輸入文字並傳送。送出狀態依 spec 狀態機顯示：`Waiting for you to stop typing…` → `Delivered` → `Agent started` 或 `Sent · unconfirmed`；出錯則 `Failed` 並顯示錯誤 kind 與 hint，可手動重送。程式永遠不自動重送。agent 處於 `blocked: question` 時，同一個輸入框用 force 送出作為回答。

**Blocked by:** 09

**Status:** ready-for-agent

- [ ] 輸入框與送出按鈕旁固定顯示目標 agent
- [ ] 送出狀態機各路徑都有 fake client 測試：started true／null、各錯誤 kind、等待人類停止打字
- [ ] 任何失敗都不會被顯示為成功，也不會自動重送
- [ ] `blocked: question` 時以 force 送出；其他 blocked kind 不顯示文字輸入
- [ ] 送出期間防止重複點擊造成重複傳送
