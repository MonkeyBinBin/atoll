#!/usr/bin/env bash
# Claude Code Stop hook: run the project's quality gate before Claude ends its turn.
# Needs jq or python3 to read the hook input and write JSON output.
CHECK_CMD="make check"

input=$(cat)

json_get() { # $1 = key
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$input" | jq -r --arg k "$1" '.[$k] // empty' 2>/dev/null
  else
    printf '%s' "$input" | python3 -c 'import json,sys
try: v = json.load(sys.stdin).get(sys.argv[1])
except Exception: v = None
print("" if v is None else str(v).lower() if isinstance(v, bool) else v)' "$1" 2>/dev/null
  fi
}

emit() { # $1 = key, $2 = message
  if command -v jq >/dev/null 2>&1; then
    jq -n --arg k "$1" --arg v "$2" '{($k): $v} + (if $k == "reason" then {decision: "block"} else {} end)'
  else
    python3 -c 'import json,sys
k, v = sys.argv[1], sys.argv[2]
out = {k: v}
if k == "reason": out["decision"] = "block"
print(json.dumps(out))' "$1" "$2"
  fi
}

# Follow Claude into worktrees: prefer the input's cwd over CLAUDE_PROJECT_DIR.
dir=$(json_get cwd)
top=$(git -C "${dir:-${CLAUDE_PROJECT_DIR:-.}}" rev-parse --show-toplevel 2>/dev/null) ||
  top=$(git -C "${CLAUDE_PROJECT_DIR:-.}" rev-parse --show-toplevel 2>/dev/null) ||
  exit 0 # Not a git repository: the gate is skipped.
cd "$top" || exit 0

# Clean working tree: nothing to check.
[ -z "$(git status --porcelain 2>/dev/null)" ] && exit 0

# Skip when this exact tree already got a result (passed, or failed and was reported).
state="$(git rev-parse --absolute-git-dir)/quality-gate.last"
fingerprint=$(
  {
    git rev-parse HEAD 2>/dev/null
    git diff HEAD 2>/dev/null
    git ls-files -o --exclude-standard -z | xargs -0 shasum 2>/dev/null
  } | shasum | cut -d' ' -f1
)
[ -f "$state" ] && [ "$(cut -d' ' -f2 "$state")" = "$fingerprint" ] && exit 0

if out=$(CI=1 bash -c "$CHECK_CMD" 2>&1); then
  echo "pass $fingerprint" >"$state"
  exit 0
fi
echo "fail $fingerprint" >"$state"

# Cap what goes back into context: last 60 lines, 400 chars per line, 8000 bytes total.
tail_out=$(printf '%s\n' "$out" | tail -n 60 | cut -c1-400 | tail -c 8000)

if [ "$(json_get stop_hook_active)" = "true" ]; then
  # Claude already continued once because of this hook: tell the user instead of looping.
  emit systemMessage "Quality gate still failing after one fix attempt. Run \`$CHECK_CMD\` to see the errors."
else
  emit reason "Quality gate failed (\`$CHECK_CMD\`). Fix these before finishing:
$tail_out"
fi
exit 0
