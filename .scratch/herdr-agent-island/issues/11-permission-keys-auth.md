# 11: Permission 按鍵排與 auth 路徑

**What to build:** agent 處於 `blocked: permission` 時，互動面板顯示目前畫面擷取與一排通用按鍵（`1` `2` `3` `y` `n` `Enter` `Esc`），點擊即透過 `hc keys` 送到目標 agent，並顯示送出結果。`blocked: auth` 時只顯示 `Sign-in required` 與 `Open in Herdr`，不提供任何輸入。

**Blocked by:** 10

**Status:** ready-for-agent

- [ ] permission 時顯示畫面擷取與按鍵排，每個按鍵都明確屬於目前目標 agent
- [ ] 按鍵送出結果（成功／錯誤 kind）有回饋，不自動重送
- [ ] auth 時沒有任何輸入控件
- [ ] blocked kind → 可用回覆方式的對應有 fake client 測試
