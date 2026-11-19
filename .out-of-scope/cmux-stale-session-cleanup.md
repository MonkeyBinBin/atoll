# cmux：清除從沒結束的 session 與相關快取

`CmuxSessions` 不主動清除沒有送 `SessionEnd` 就消失的 session（Claude Code crash、`kill -9`、關掉 surface 時 hook 沒跑完），也不清除已結束 session id 的記錄（`endedIDs`）。`CmuxAdapter` 的 `ownership` cache（pid → 是否屬於 herdr）同樣只增不減。這是刻意的選擇。

## Why this is out of scope

這些資料已經有自然的上限，累積的量小到可以忽略：

- `CmuxAdapter.runStream` 每次重新連上 `cmux events` stream，都會把 `sessions`（含 `endedIDs`）整個重建。累積範圍只有一次 stream 連線期間，cmux 重開或 stream 斷線都會歸零。
- 畫面行為不受影響。adapter 的 `include`（`CmuxAdapter.currentTerminals`）會用 `ProcessInspector.isAlive` 濾掉已結束的 pid，殘留的 session 不會變成畫面上的 agent。
- 2026-11-19 量測 cmux 保留的事件歷史（11-04 至 11-19，約 15 天、10 次 boot）：總共 24 個 session、19 個 pid，其中從沒送 `SessionEnd` 的只有 4 個。一次連線頂多累積幾十筆，每 3 秒 tick 走過幾十筆 dictionary，記憶體約幾 KB。`ownership` 每個 pid 只存一個 `Bool`。

真的要清除，得付出兩個代價：

- `CmuxSessions` 是 pure、deterministic 的（測試完全靠餵事件），要清除已不在的程序，就得讓它接收存活判斷，或開放外部移除 session 的方法，增加和 adapter 的耦合。
- `endedIDs` 是用來擋 cmux 晚到的重複 hook，避免已結束的 session 復活、蓋過接手的新 session（ticket 62）。清得太早會讓這個問題回來，清除時機要另外設計和測試。

用這些複雜度與回歸風險換幾 KB 記憶體不划算。如果之後量測發現 session 數量大到每次 publish 的成本明顯可見（例如一次連線累積到上千筆），再重新評估。

## Prior requests

- ticket 63：「cmux 從沒結束的 session 與相關快取不會被清除」（由 ticket 62 的 code review 提出）
