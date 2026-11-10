# 16: 全狀態動畫定稿

**What to build:** 以 15 的定稿為基礎，替三種外觀製作 spec 動畫表中的全部狀態動畫（每種外觀約 30 幀），逐幀 QA 後以最終資源格式輸出，替換 06 的占位 sprite，動態島上直接看到正式角色。

**Blocked by:** 06, 15

**Status:** resolved

- [x] 每個狀態的幀數與播放方式符合 spec 動畫表
- [x] 循環動畫首尾銜接順暢；one-shot 結束幀符合規格（Done 轉待機、Error 停在最後一幀）
- [x] 每個狀態的第 0 幀單獨看也能辨識狀態（供減少動態效果使用）
- [x] 1× 與 2× 整數縮放下像素清晰
- [x] 以最終格式輸出並替換占位資源，`SpritePlayer` 不需改動

## Comments

- 2026-11-10（agent）：`art/final/make_sprites.py` 產出三種外觀全部 9 個 tag（每種 33 幀），直接替換 `Sources/HerdrIsland/Resources/Sprites/` 的占位資源，`SpriteView` 格式不變。逐幀 QA：`art/final/qa-all-tags@8x.png`；needs_you 的舉手第一版被 Claude 寬頭遮住，已改為舉過頭頂。
