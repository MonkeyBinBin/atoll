# OPTIONAL. Not needed for Herdr, the herdr CLI/TUI or cmux: the island reads those directly.
# Atoll: run agent CLIs from any other terminal (Ghostty, iTerm, Terminal, VS Code…) inside
# herdr-core, so the island can show, message, interrupt and open them.
#
#   source /path/to/atoll/scripts/shell/atoll.zsh   # in ~/.zshrc
#
# `hc run` stays attached to this terminal like ssh; the agent keeps running in herdr-core if
# the window closes (reopen it from the island with "Open in Herdr").
# They also run as usual where another tool already integrates the agent and the island reads it
# directly: herdr-core terminals (HC_TERMINAL_ID, e.g. Herdr), cmux (CMUX_SURFACE_ID) and the
# herdr CLI/TUI (HERDR_PANE_ID).
#
# The terminal app is detected from __CFBundleIdentifier (set by macOS for app-launched shells,
# e.g. com.cmuxterm.app in cmux), else TERM_PROGRAM. Override it if detection is wrong:
#   export ATOLL_ORIGIN=com.cmuxterm.app

_atoll_run() {
  local cmd=$1; shift
  if [[ -n $HC_TERMINAL_ID || -n $CMUX_SURFACE_ID || -n $HERDR_PANE_ID ]] || ! command -v hc >/dev/null 2>&1; then
    command "$cmd" "$@"
    return
  fi
  # The app this terminal belongs to, so the island can switch back to it.
  local origin=${ATOLL_ORIGIN:-${HERDR_ISLAND_ORIGIN:-${__CFBundleIdentifier:-$TERM_PROGRAM}}}
  local -a labels
  [[ -n $origin ]] && labels=(--label "atoll.origin=$origin")
  hc run --no-notify "${labels[@]}" -- "$cmd" "$@"
}

claude() { _atoll_run claude "$@"; }
codex() { _atoll_run codex "$@"; }
