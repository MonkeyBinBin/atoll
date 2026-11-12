# 40: 面板輸出搜尋

**What to build:** 在面板的終端機輸出裡用 `⌘F` 搜尋並高亮符合的文字。面板只顯示畫面最後 200 行，想找「剛剛哪個測試失敗」「那個錯誤訊息」目前只能用眼睛捲。只搜尋已經讀進來的輸出，不額外讀取。

**Blocked by:** —

**Status:** resolved

- [x] `⌘F`（面板模式）在輸出區上方打開一列搜尋框並聚焦；由 `IslandController` 的 key monitor 攔下（同 `⌘⇧1`–`5`、`⌥↩` 的做法），不讓它落到回覆輸入框
- [x] 不分大小寫的子字串比對；所有符合處高亮，目前這一個用較強的顏色並捲到可見；搜尋框旁顯示「3 / 12」，沒有結果顯示「No matches」
- [x] `↩` 下一個、`⇧↩` 上一個（到底循環）；`Esc` 先關搜尋列並把焦點還給回覆輸入框，再按一次才照舊返回清單（`model.escape()` 的優先順序要調整）
- [x] 搜尋的是畫面上顯示的文字：「Messages only」打開時搜尋過濾後的內容，切換時重新比對；輸出自動刷新時保留關鍵字並重新比對，目前位置盡量停在同一行附近
- [x] 切到變更檢視（ticket 32）時搜尋列隱藏；換 agent 或關閉面板時清掉關鍵字（只在記憶體）（變更檢視的部分只用程式邏輯確認，見 Comments）
- [x] `TerminalOutputView` 是 `NSTextView`：高亮用 temporary attributes 或 text storage 的背景色，不改動文字本身；比對規則（找出所有範圍、上一個／下一個、刷新後重新定位）放成可測的純函式，單元測試：大小寫、多個符合、循環、沒有結果、文字變長後重新定位、空關鍵字
- [x] 實機確認：長輸出捲動到符合處、Messages only 切換、自動刷新時不跳回頂端

**Out of scope:** 正規表示式、搜尋更早的歷史（超出已讀進來的部分）、跨 agent 搜尋、在 diff 檢視裡搜尋。

## Comments

- 2026-11-12（agent）：AtollCore 新增 `OutputSearch`（值型別，只在記憶體）：`setQuery` 用 `NSString.range(of:options: .caseInsensitive)` 找出所有 `NSRange`（UTF-16，text view 直接用），新關鍵字從最後一個符合處開始（離最新輸出最近）；`step(forward:)` 循環；`update(text:)` 重新比對並定位：先找「同一行內容、同一行內第幾個」的符合處（行內容去掉換行，原本在最後一行的也對得上），有多個取行號最接近的，找不到就取行號最接近的符合處；`counter` 給「3 / 12」／「No matches」／空關鍵字 nil。
- 2026-11-12（agent）：UI：`IslandModel.outputSearch`（nil = 搜尋列關閉）、`searchFieldFocused`、`searchFocusRequest`／`replyFocusRequest`；`mode` 離開或換到別的面板時清掉。`IslandController` 的 key monitor 攔 `⌘F`（變更檢視中不開），搜尋框有焦點時把 `↩`／`⇧↩` 變成下一個／上一個；`escape()` 在面板模式下先關搜尋列（變更檢視中搜尋列隱藏，Esc 照舊）並把焦點還給回覆框。`AgentPanelView` 在輸出區上方放搜尋列（放大鏡、輸入框、計數、上下鍵、關閉），輸出區用 `.onChange(of: text, initial: true)` 把顯示中的文字餵給搜尋（刷新、Messages only 切換、從變更檢視切回來都會重新比對）；只有搜尋已經比對到同一份文字時才傳高亮，避免刷新瞬間範圍錯位。`TerminalOutputView` 用 layout manager 的 temporary attributes 畫背景色（全部淡黃、目前橘色），有目前符合處時不再釘到底部，改成 `scrollRangeToVisible`。DebugHook 加 `cmdf`／`chars`／`ret`／`sret`／`esckey`，snapshot 資訊多印搜尋狀態。README 補一段。
- 2026-11-12（agent）：測試：`OutputSearchTests` 7 個（大小寫與多個符合、沒有結果與空關鍵字、循環、刷新後停在同一行、行不見了取最近、重複行與行內第幾個、最後一行在輸出變長後），全套 368 個通過。實機（dev-run + `hc` 跑 Codex 印 120 行、每 37 行一個 FAIL）：`⌘F` 打開並聚焦、打 fail 顯示 4 / 4 並捲到最新的 line 111、`↩` 循環到第一個再到 line 37（捲上去）、`⇧↩` 往回；關掉 Messages only 後仍停在 line 37；釘住面板讓 Codex 再跑一個會輸出的回合，刷新期間與結束後都停在 line 111（最上面一行捲出 200 行視窗後由 4 / 6 變 3 / 7），沒有跳回頂端；Esc 第一次關搜尋列、清掉高亮、游標回到回覆框，第二次回清單；換 agent 再回來關鍵字已清掉。變更檢視只用程式邏輯確認（搜尋列在 `terminalOutput` 裡，變更檢視時整段不顯示，`openSearch` 也擋掉），沒有實機切換。
- 2026-11-12（agent）：code review 後修正：(1) 搜尋框用輸入法（注音、拼音）按 `↩` 選字時不再被當成「下一個」，field editor 有 marked text 就交給輸入框；(2) 捲動：搜尋中（有關鍵字）不釘底部；只有使用者打字或上下一個（`IslandModel.searchScrollRequest`）才主動捲到目前符合處；刷新時只有目前符合處原本就在畫面內才跟著它（新文字的高亮下一輪才到，用 coordinator 記住要不要跟），所以手動捲走後刷新不會被拉回去，也不會先跳到底部再跳回來；(3) `↩` 攔截加上 `canSearch`，變更檢視中不會被吃掉；(4) 行號改用 `NSString.lineRange` 逐行走，`\r\n` 不再算錯（新增 CRLF 測試，共 8 個）；抽出 `canSearch`／`resetSearch`。實機重測：上一個捲到 line 74，Codex 跑出新輸出、刷新期間與結束後都停在 line 74（3 / 5 → 3 / 6）。沒有實機測的：手動捲走後刷新不被拉回、輸入法選字（合成按鍵做不到）。已知行為：Needs you 自動切到下一個 agent 時，搜尋會跟著換 agent 一起清掉。

