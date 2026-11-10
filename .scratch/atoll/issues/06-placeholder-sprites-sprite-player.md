# 06: 占位 sprite＋SpritePlayer

**What to build:** 動態島上的圓點換成像素角色：以最終資源格式（透明 PNG sprite sheet + Aseprite 風格 JSON）程式化產生 Claude Code、Codex、通用三種外觀的占位 sprite，`SpritePlayer` 依狀態播放 loop 或 one-shot 動畫。每個 agent 首次出現時指派個體色，session 存續期間不變。設定中可關閉動畫，系統「減少動態效果」開啟時改用各狀態第 0 幀。

**Blocked by:** 01, 03

**Status:** resolved

- [x] 占位 sprite 涵蓋 spec 動畫表的每個狀態，三種外觀可一眼區分
- [x] `SpritePlayer` 讀取 JSON 的 frame rect、duration、loop／one-shot；one-shot 播完停在指定幀或轉入下一狀態（Done → Idle 待機）
- [x] 一律整數倍 nearest-neighbor 縮放，收合態 1 像素 = 1pt
- [x] 個體色只上在配件區，排序變動後顏色不變（有 fake client 測試）
- [x] 設定的動畫開關與系統減少動態效果都會讓角色改為靜止首幀
- [x] 每個角色旁或可及性標籤上有英文狀態文字，不只靠動畫

## Comments

- 2026-11-10（agent）：`scripts/make_placeholder_sprites.py` 產生最終格式的占位 sprite（PNG sheet＋Aseprite 風格 JSON，`accessoryKey` #FF00FF 在載入時換成個體色）。`SpriteView` 支援 loop／one-shot／next（Done→idle）／hold，整數倍 nearest-neighbor；動畫開關與減少動態效果 → 第 0 幀。收合態播放 4 秒後降為 1Hz 呼吸（spec 70，閒置 CPU 約 1%）。
