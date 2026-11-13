## Agent skills

### Issue tracker

Issues live as local markdown files under `.scratch/`. See `docs/agents/issue-tracker.md`.

### Triage labels

Default five-role vocabulary (`needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`), recorded as a `Status:` line in each issue file. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: root `GLOSSARY.md` + `docs/adr/`. See `docs/agents/domain.md`.

## Build & install

「重新 build 並且安裝」= 覆蓋安裝到 `/Applications/Atoll.app`：

1. `./scripts/build-app.sh`（release、ad-hoc 簽章 → `build/Atoll.app`）
2. `osascript -e 'quit app id "local.atoll"'`，等約 2 秒，用 `pgrep -f /Applications/Atoll.app` 確認已結束
3. `ditto build/Atoll.app /Applications/Atoll.app && codesign -v /Applications/Atoll.app && open /Applications/Atoll.app`

不要用 `rm -rf /Applications/Atoll.app` + `pkill`，會被權限層擋下。設定存在 UserDefaults（`local.atoll`），重裝後保留。osascript 沒有 Accessibility 權限，無法點 Settings／選單 UI 驗證，請使用者目視確認。
