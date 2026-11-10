# 02: 色盤＋風格探索 board

**What to build:** 用 Codex imagegen（`codex exec`）探索角色風格，整理出 3 個風格方向，每個方向都有 Claude Code、Codex、通用三種外觀的 idle 幀，全部是原生 16×16 像素並附放大預覽，讓使用者在量產前選定視覺走向。依 spec 的美術系統：同一小機器人族群、頭型剪影區分工具、黑底高明度自訂色盤、彩色輪廓、不使用官方吉祥物或 logo。

**Blocked by:** None (can start immediately)

**Status:** ready-for-agent

- [ ] 3 個風格方向，各自附約 16 色的候選色盤
- [ ] 每個方向 × 3 種外觀的 idle 幀，原生 16×16、對齊像素格（非 AI 生成的模糊縮圖），附 8× nearest-neighbor 放大預覽
- [ ] 每個方向附一張黑底預覽，模擬動態島尺寸（1 像素 = 1pt）
- [ ] imagegen 原始產出與整理後的 16×16 版本都保存在 `.scratch/herdr-agent-island/art/`
- [ ] 使用者選定方向，選擇與理由記錄在 art 目錄的說明檔
