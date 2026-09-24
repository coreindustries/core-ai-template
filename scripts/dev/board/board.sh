#!/usr/bin/env bash
# board.sh — deterministic GitHub-Issues coordination CLI for the bugfix/
# feature/release-manager agent lanes. GitHub Issues are the single source of
# truth for coordinated work; the repetitive coordination is done by this TOOL,
# not by model calls that rediscover state.
#
# Every subcommand shells `gh` (never a hand-rolled REST client) so this
# stays in lockstep with whatever `gh` itself supports, and every subcommand
# is stdin/stdout/exit-code shaped so scripts/dev/board/tests/board.test.sh
# can drive it against a fake `gh`/`curl`/`sleep` on PATH with no network
# calls. Portability: macOS bash 3.2 (no `declare -A`, no GNU-only date/sed
# flags) + Linux.
#
# Project settings come from .claude/agent-lanes.json (lanes-config.sh).
#
# Label taxonomy (.claude/skills/_shared/agent-protocol.md §2; created by
# `board.sh init-labels`):
#   lane:bug | lane:feature | lane:release   — which agent lane owns the issue
#   P0..P3                                    — priority
#   state:backlog|implementing|built|deployed|verifying|blocked|dropped|done
#   agent:<NAME>                              — current claimant (0 or 1)
#   needs-deploy                              — merged PR not yet on a deployed environment
#
# Usage: scripts/dev/board/board.sh <subcommand> [args...]
# Run `board.sh help` for the full command list.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
# gh-checks.sh owns the EXIT trap (cleans up GH_CHECKS_MODE_FILE) — if this
# script ever adds its own EXIT trap, chain `rm -f "$GH_CHECKS_MODE_FILE"`
# into it instead of replacing it.
. "$SCRIPT_DIR/gh-checks.sh"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib.sh"

DEFAULT_BRANCH="$(lanes_cfg '.defaultBranch' main)"

VALID_STATES="backlog implementing built deployed verifying done blocked dropped"
VALID_LANES="bug feature release"

# ---------------------------------------------------------------------------
# init-labels [--dry-run]
# ---------------------------------------------------------------------------
cmd_init_labels() {
  require_gh; require_jq
  local dry_run=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --dry-run) dry_run=1; shift ;;
      *) die "init-labels: unknown arg $1" ;;
    esac
  done

  local existing
  existing="$(gh label list --limit 200 --json name --jq '.[].name')"

  # The taxonomy has one source: the "Agent lanes" section of .github/labels.yml
  # (labels-sync keeps it current after merge; this bootstraps a fresh repo).
  # Emitted as name|color|description — '|' because label names contain ':'.
  # agent:<NAME> labels are created on demand by `claim` / `pr-own`.
  local labels_file="${BOARD_LABELS_FILE:-$LANES_REPO_ROOT/.github/labels.yml}"
  [ -f "$labels_file" ] || die "init-labels: $labels_file not found"
  local defs
  defs="$(awk '
    /^# -+ Agent lanes -+$/ { on = 1; next }
    on && /^# -+/ { if (name != "") print name "|" color "|" desc; exit }
    !on { next }
    /^- name:/ {
      if (name != "") print name "|" color "|" desc
      name = $0; sub(/^- name:[ \t]*/, "", name); gsub(/"/, "", name); color = ""; desc = ""
    }
    /^  color:/ { color = $0; sub(/^  color:[ \t]*/, "", color); gsub(/"/, "", color) }
    /^  description:/ { desc = $0; sub(/^  description:[ \t]*/, "", desc); gsub(/^"|"$/, "", desc) }
  ' "$labels_file")"
  [ -n "$defs" ] || die "init-labels: no '# ---------- Agent lanes ----------' section in $labels_file"

  local line name color desc
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    name="${line%%|*}"
    local rest="${line#*|}"
    color="${rest%%|*}"
    desc="${rest#*|}"

    if printf '%s\n' "$existing" | grep -qxF "$name"; then
      echo "exists: $name"
      continue
    fi

    if [ "$dry_run" = "1" ]; then
      echo "gh label create \"$name\" --color \"$color\" --description \"$desc\""
      continue
    fi

    if gh label create "$name" --color "$color" --description "$desc" >/dev/null 2>&1; then
      echo "created: $name"
    else
      echo "init-labels SKIPPED creating '$name': gh label create failed (likely a concurrent creation) — verify by hand with 'gh label list'" >&2
    fi
  done <<EOF
$defs
EOF

  echo "note: per-agent labels agent:<NAME> are created on demand by 'claim', not here"
}

# ---------------------------------------------------------------------------
# list [--lane bug|feature|release] [--state <s>] [--agent <NAME>] [--unclaimed] [--json]
# ---------------------------------------------------------------------------
cmd_list() {
  require_gh; require_jq
  local lane="" state="" agent="" unclaimed=0 as_json=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --lane) lane="$2"; shift 2 ;;
      --state) state="$2"; shift 2 ;;
      --agent) agent="$2"; shift 2 ;;
      --unclaimed) unclaimed=1; shift ;;
      --json) as_json=1; shift ;;
      *) die "list: unknown arg $1" ;;
    esac
  done

  local label_args=()
  [ -n "$lane" ] && label_args+=(--label "lane:${lane}")
  [ -n "$state" ] && label_args+=(--label "state:${state}")
  [ -n "$agent" ] && label_args+=(--label "agent:${agent}")

  local raw
  raw="$(gh issue list --state open --limit 200 --json number,title,labels,createdAt,url "${label_args[@]}")"

  # Default view is "any lane:* label" — always required client-side. When
  # --lane was passed, gh's own --label filter already guarantees this, so
  # the check is a harmless no-op in that case rather than a special case.
  local filtered
  filtered="$(printf '%s' "$raw" | jq -c --argjson unclaimed "$unclaimed" '
    map(select(
      ((.labels | map(.name)) as $l | ($l | map(startswith("lane:")) | any))
      and
      ( if $unclaimed == 1
        then ((.labels | map(.name) | map(startswith("agent:")) | any) | not)
        else true end )
    ))
  ')"

  if [ "$as_json" = "1" ]; then
    printf '%s\n' "$filtered"
    return
  fi

  printf '%s' "$filtered" | jq -r '
    def prio: (.labels | map(.name) | map(select(test("^P[0-3]$"))))[0] // "-";
    def lanename: (.labels | map(.name) | map(select(startswith("lane:"))) | map(sub("^lane:";"")))[0] // "-";
    def statename: (.labels | map(.name) | map(select(startswith("state:"))) | map(sub("^state:";"")))[0] // "-";
    def claimant: (.labels | map(.name) | map(select(startswith("agent:"))) | map(sub("^agent:";"")))[0] // "-";
    def prioweight: (prio | if . == "-" then 9 else (.[1:] | tonumber) end);
    sort_by(prioweight, .createdAt)
    | .[]
    | [ ("#" + (.number|tostring)), prio, lanename, statename, claimant,
        (((now - (.createdAt | fromdateiso8601)) / 86400 | floor | tostring) + "d"),
        (.title | if length > 60 then .[0:57] + "..." else . end) ]
    | @tsv
  ' | render_table
}

# ---------------------------------------------------------------------------
# next --lane bug|feature --agent <NAME>
# ---------------------------------------------------------------------------
cmd_next() {
  require_gh; require_jq
  local lane="" agent=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --lane) lane="$2"; shift 2 ;;
      --agent) agent="$2"; shift 2 ;;
      *) die "next: unknown arg $1" ;;
    esac
  done
  [ -n "$lane" ] || die "next: --lane is required"
  [ -n "$agent" ] || die "next: --agent is required"

  local raw
  raw="$(gh issue list --state open --label "lane:${lane}" --limit 200 --json number,title,labels,createdAt,url)"

  local pick
  pick="$(printf '%s' "$raw" | jq -c '
    map(select( ((.labels | map(.name)) | map(startswith("agent:")) | any) | not ))
    | map(. + { _p: ( ((.labels | map(.name)) | map(select(test("^P[0-3]$"))))[0] // "P9" ) })
    | sort_by(._p, .createdAt)
    | .[0] // empty
  ')"

  if [ -z "$pick" ]; then
    echo "next: no unclaimed open issue in lane:${lane}" >&2
    exit 3
  fi

  local num title url
  num="$(printf '%s' "$pick" | jq -r '.number')"
  title="$(printf '%s' "$pick" | jq -r '.title')"
  url="$(printf '%s' "$pick" | jq -r '.url')"

  cmd_claim "$num" "$agent"

  echo "#${num}  ${title}"
  echo "$url"
}

# ---------------------------------------------------------------------------
# claim <issue> <NAME>
# ---------------------------------------------------------------------------
cmd_claim() {
  require_gh; require_jq
  local issue="${1:-}" name="${2:-}"
  [ -n "$issue" ] && [ -n "$name" ] || die "claim: usage: claim <issue> <NAME>"

  local labels other
  labels="$(gh issue view "$issue" --json labels --jq '.labels[].name')"
  other="$(printf '%s\n' "$labels" | grep '^agent:' | grep -vx "agent:${name}" || true)"
  if [ -n "$other" ]; then
    echo "claim: issue #${issue} already has label(s): $(printf '%s' "$other" | tr '\n' ' ')" >&2
    exit 5
  fi

  if ! gh label list --limit 200 --json name --jq '.[].name' | grep -qxF "agent:${name}"; then
    gh label create "agent:${name}" --color "ededed" --description "Claimed by agent ${name}" >/dev/null 2>&1 \
      || echo "claim: label create for agent:${name} failed (likely already exists under a race) — continuing" >&2
  fi

  gh issue edit "$issue" --add-label "agent:${name}" >/dev/null

  local ts
  ts="$(now_iso)"
  gh issue comment "$issue" --body "claim: ${name} ${ts}" >/dev/null

  sleep 3

  local comments winner
  comments="$(gh issue view "$issue" --json comments)"
  winner="$(printf '%s' "$comments" | jq -r --arg me "$name" --arg myts "$ts" '
    [ .comments[].body
      | capture("^(?<kind>claim|release): (?<name>\\S+) (?<ts>\\S+)")?
    ]
    | map(select(. != null)) as $events
    | ($events | map(select(.kind=="claim" and .name != $me and .ts < $myts))) as $earlier
    | ($events | map(select(.kind=="release"))) as $releases
    | ( $earlier
        | map(select(
            . as $c
            | ($releases | map(select(.name == $c.name and .ts > $c.ts)) | length) == 0
          ))
        | sort_by(.ts)
        | .[0].name // empty
      )
  ')"

  if [ -n "$winner" ]; then
    gh issue edit "$issue" --remove-label "agent:${name}" >/dev/null \
      || echo "claim: remove-label agent:${name} on #${issue} failed after losing the race — check by hand" >&2
    gh issue comment "$issue" --body "claim-lost: ${name} to ${winner}" >/dev/null
    echo "claim: #${issue} lost the race to ${winner}" >&2
    exit 4
  fi

  echo "claimed: #${issue} as ${name}"
}

# ---------------------------------------------------------------------------
# release <issue> <NAME> [--reason ...]
# ---------------------------------------------------------------------------
cmd_release() {
  require_gh
  local issue="${1:-}" name="${2:-}"
  [ -n "$issue" ] && [ -n "$name" ] || die "release: usage: release <issue> <NAME> [--reason ...]"
  shift 2
  local reason=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --reason) reason="$2"; shift 2 ;;
      *) shift ;;
    esac
  done

  gh issue edit "$issue" --remove-label "agent:${name}" >/dev/null 2>&1 \
    || echo "release: remove-label agent:${name} on #${issue} failed (label may already be absent) — continuing" >&2

  local ts
  ts="$(now_iso)"
  gh issue comment "$issue" --body "release: ${name} ${ts} ${reason}" >/dev/null
  echo "released: #${issue} by ${name}"
}

# ---------------------------------------------------------------------------
# state <issue> <new-state>
# ---------------------------------------------------------------------------
cmd_state() {
  require_gh; require_jq
  local issue="${1:-}" new="${2:-}"
  [ -n "$issue" ] && [ -n "$new" ] || die "state: usage: state <issue> <new-state>"

  local ok=0 s
  for s in $VALID_STATES; do [ "$s" = "$new" ] && ok=1; done
  [ "$ok" = "1" ] || die "state: invalid state '${new}' — must be one of: ${VALID_STATES}"

  local labels old
  labels="$(gh issue view "$issue" --json labels --jq '.labels[].name')"
  old="$(printf '%s\n' "$labels" | grep '^state:' | head -1 || true)"
  old="${old#state:}"
  [ -n "$old" ] || old="none"

  local args=(--add-label "state:${new}")
  local lbl
  while IFS= read -r lbl; do
    [ -z "$lbl" ] && continue
    args+=(--remove-label "$lbl")
  done <<EOF
$(printf '%s\n' "$labels" | grep '^state:' || true)
EOF

  gh issue edit "$issue" "${args[@]}" >/dev/null
  gh issue comment "$issue" --body "state: ${old} -> ${new}" >/dev/null
  echo "#${issue}: state ${old} -> ${new}"
}

# ---------------------------------------------------------------------------
# handoff <issue> --file <md>
# ---------------------------------------------------------------------------
cmd_handoff() {
  require_gh
  local issue="${1:-}"; shift || true
  local file=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --file) [ $# -ge 2 ] || die "handoff: --file requires a value — usage: handoff <issue> --file <md>"; file="$2"; shift 2 ;;
      *) shift ;;
    esac
  done
  [ -n "$issue" ] && [ -n "$file" ] || die "handoff: usage: handoff <issue> --file <md>"
  [ -f "$file" ] || die "handoff: file not found: ${file}"

  local tmp
  tmp="$(mktemp)"
  { printf 'handoff:\n'; cat "$file"; } > "$tmp"
  gh issue comment "$issue" --body-file "$tmp" >/dev/null
  rm -f "$tmp"
  echo "handoff posted: #${issue}"
}

# ---------------------------------------------------------------------------
# show <issue> [issue-fetch.sh options] — issue text + downloaded screenshots
# watch --agent <NAME> [--lane bug|feature] [...] — issue events for Monitor
#
# Both `exec` into a child script and never return to this process — bash
# does NOT run EXIT traps on a successful exec (the process image is simply
# replaced, it never takes the normal exit path), so gh-checks.sh's own
# `trap 'rm -f "$GH_CHECKS_MODE_FILE"' EXIT` would never fire here and the
# sentinel file (when gh-checks.sh actually created one — see its header)
# would leak on every `show`/`watch` invocation. Clean it up ourselves first.
# ---------------------------------------------------------------------------
cmd_show() { rm -f "$GH_CHECKS_MODE_FILE"; exec bash "$SCRIPT_DIR/issue-fetch.sh" "$@"; }
cmd_watch() { rm -f "$GH_CHECKS_MODE_FILE"; exec bash "$SCRIPT_DIR/issue-watch.sh" "$@"; }

# ---------------------------------------------------------------------------
# comment <issue> --file <md> — a progress note (no prefix; use handoff for
# a resumable handoff and state for label transitions)
# ---------------------------------------------------------------------------
cmd_comment() {
  require_gh
  local issue="${1:-}"; shift || true
  local file=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --file) [ $# -ge 2 ] || die "comment: --file requires a value — usage: comment <issue> --file <md>"; file="$2"; shift 2 ;;
      *) die "comment: unknown arg $1 — usage: comment <issue> --file <md>" ;;
    esac
  done
  [ -n "$issue" ] && [ -n "$file" ] || die "comment: usage: comment <issue> --file <md>"
  [ -s "$file" ] || die "comment: file missing or empty: ${file}"
  gh issue comment "$issue" --body-file "$file" >/dev/null
  echo "commented: #${issue}"
}

# ---------------------------------------------------------------------------
# checkout <issue> <NAME> [--worktree] — claim (if not already ours), move to
# state:implementing (if not already), print the issue with screenshots, and
# optionally cut <worktreeDir>/<issue>-<slug> on a fresh origin/<defaultBranch> branch.
# Every step it skips says so; any failure stops it.
# ---------------------------------------------------------------------------
cmd_checkout() {
  require_gh; require_jq
  local issue="${1:-}" name="${2:-}"
  [ -n "$issue" ] && [ -n "$name" ] || die "checkout: usage: checkout <issue> <NAME> [--worktree]"
  shift 2
  local want_wt=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --worktree) want_wt=1; shift ;;
      *) die "checkout: unknown arg $1" ;;
    esac
  done

  local meta labels title
  meta="$(gh issue view "$issue" --json title,labels,state)" || die "checkout: gh issue view #${issue} failed" 2
  [ "$(printf '%s' "$meta" | jq -r .state)" = "OPEN" ] || die "checkout: #${issue} is not open"
  labels="$(printf '%s' "$meta" | jq -r '.labels[].name')"
  title="$(printf '%s' "$meta" | jq -r .title)"

  if printf '%s\n' "$labels" | grep -qx "agent:${name}"; then
    echo "checkout: #${issue} already claimed by ${name} — claim skipped"
  else
    cmd_claim "$issue" "$name"
  fi
  if printf '%s\n' "$labels" | grep -qx "state:implementing"; then
    echo "checkout: #${issue} already state:implementing — state change skipped"
  else
    cmd_state "$issue" implementing
  fi

  if [ "$want_wt" = "1" ]; then
    local common main_root prefix slug branch wt
    # BOARD_MAIN_ROOT overrides repo discovery — the test harness's only way
    # to point this at a disposable temp repo instead of the real checkout
    # `$SCRIPT_DIR` always resolves to (git -C "$SCRIPT_DIR" ... would
    # otherwise always answer about THIS repo, no matter what the caller is
    # actually testing).
    if [ -n "${BOARD_MAIN_ROOT:-}" ]; then
      main_root="$BOARD_MAIN_ROOT"
    else
      common="$(git -C "$SCRIPT_DIR" rev-parse --path-format=absolute --git-common-dir)" \
        || die "checkout: cannot locate the repository's git dir"
      main_root="$(dirname "$common")"
    fi
    git -C "$main_root" rev-parse --git-dir >/dev/null 2>&1 \
      || die "checkout: BOARD_MAIN_ROOT/$main_root is not a git repository"
    case "$labels" in
      *lane:feature*) prefix=feat ;;
      *lane:bug*) prefix=fix ;;
      *) prefix=chore ;;
    esac
    slug="$(printf '%s' "$title" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed -e 's/^-//' -e 's/-$//' | cut -c1-40 | sed 's/-$//')"
    [ -n "$slug" ] || slug="issue"
    branch="${prefix}/${issue}-${slug}"
    wt="${main_root}/$(lanes_cfg '.worktreeDir' .worktrees)/${issue}-${slug}"

    # Clear stale worktree administrative entries (e.g. a directory removed
    # by wt-clean.sh without going through `git worktree remove`) before
    # deciding whether to add.
    git -C "$main_root" worktree prune

    if [ -e "$wt" ]; then
      echo "checkout: worktree already exists: ${wt} — creation skipped"
    elif git -C "$main_root" show-ref --verify --quiet "refs/heads/${branch}"; then
      # A prior checkout already cut this branch (and it survived a later
      # wt-clean, which removes the WORKTREE but leaves the branch —
      # deliberately, as evidence of the work) — `worktree add -b` would
      # fail forever with "branch already exists". Reuse it instead.
      git -C "$main_root" worktree add -q "$wt" "$branch" \
        || die "checkout: git worktree add ${wt} (existing branch ${branch}) failed"
      echo "checkout: worktree ${wt} reusing existing branch ${branch}"
    else
      git -C "$main_root" fetch -q origin "$DEFAULT_BRANCH" || die "checkout: git fetch origin ${DEFAULT_BRANCH} failed"
      git -C "$main_root" worktree add -q -b "$branch" "$wt" "origin/${DEFAULT_BRANCH}" \
        || die "checkout: git worktree add ${wt} (${branch}) failed"
      echo "checkout: worktree ${wt} on ${branch} (from origin/${DEFAULT_BRANCH})"
    fi
  fi

  bash "$SCRIPT_DIR/issue-fetch.sh" "$issue"
}

# ---------------------------------------------------------------------------
# deploy-queue [--json]
# ---------------------------------------------------------------------------
cmd_deploy_queue() {
  require_gh; require_jq
  local as_json=0
  for a in "$@"; do [ "$a" = "--json" ] && as_json=1; done

  local since
  since="$(date -u -v-14d +%Y-%m-%d 2>/dev/null || date -u -d '-14 days' +%Y-%m-%d)"

  local raw
  raw="$(gh pr list --state merged --label needs-deploy --limit 100 \
    --search "merged:>=${since}" \
    --json number,title,mergeCommit,mergedAt,body)"

  local out
  out="$(printf '%s' "$raw" | jq -c '
    map({
      number, title, mergedAt,
      mergeSha: (.mergeCommit.oid // null),
      hasRealProof: ((.body // "") | test("## Real Proof"))
    })
  ')"

  if [ "$as_json" = "1" ]; then
    printf '%s\n' "$out"
    return
  fi

  printf '%s' "$out" | jq -r '
    .[] | [ ("#" + (.number|tostring)),
            ((.mergeSha // "-") | .[0:8]),
            (if .hasRealProof then "proof-ok" else "NO-PROOF" end),
            .title ]
    | @tsv
  ' | render_table
}

# ---------------------------------------------------------------------------
# render --out <file.html> [--hash-file <path>]
#
# --hash-file: after writing --out, hash the rendered content EXCLUDING the
# `<!-- generated-at: ... -->` stamp line (the only thing in the output that
# varies run-to-run when the underlying issue data hasn't changed), compare
# against the previous hash in the file, print UNCHANGED/CHANGED, and update
# the file on CHANGED. Lets a caller (e.g. a cron/CI regeneration step) know
# whether the board actually moved without diffing two full HTML documents
# whose timestamp line always differs.
# ---------------------------------------------------------------------------
cmd_render() {
  require_gh; require_jq
  local out="" hash_file=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --out) out="$2"; shift 2 ;;
      --hash-file) hash_file="$2"; shift 2 ;;
      *) die "render: unknown arg $1" ;;
    esac
  done
  [ -n "$out" ] || die "render: --out <file.html> is required"

  local raw data_json
  raw="$(gh issue list --state open --limit 200 --json number,title,labels,url,createdAt)"
  data_json="$(printf '%s' "$raw" | jq -c '
    map({
      number, title, url, createdAt,
      priority: ((.labels|map(.name)|map(select(test("^P[0-3]$"))))[0] // null),
      lane: ((.labels|map(.name)|map(select(startswith("lane:")))|map(sub("^lane:";"")))[0] // null),
      state: ((.labels|map(.name)|map(select(startswith("state:")))|map(sub("^state:";"")))[0] // null),
      claimant: ((.labels|map(.name)|map(select(startswith("agent:")))|map(sub("^agent:";"")))[0] // null)
    })
    | map(select(.lane != null))
  ')"

  {
    printf '<!doctype html>\n'
    printf '<!-- generated-at: %s -->\n' "$(now_iso)"
    # Title comes from config; strip anything that is markup or a sed delimiter.
    local board_title
    board_title="$(lanes_cfg '.boardTitle' 'Agent Work Board' | tr -d '<>&"|\\')"
    sed "s|__BOARD_TITLE__|${board_title}|g" <<'HTML_HEAD'
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>__BOARD_TITLE__</title>
<style>
  :root { color-scheme: light dark; --bg:#fff; --fg:#111; --card:#f5f5f5; --border:#ddd; --accent:#5319e7; }
  @media (prefers-color-scheme: dark) {
    :root { --bg:#0e0e10; --fg:#eee; --card:#1c1c1e; --border:#333; --accent:#a78bfa; }
  }
  * { box-sizing: border-box; }
  body { margin:0; background:var(--bg); color:var(--fg); font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif; }
  h1 { padding:1rem; margin:0; font-size:1.1rem; }
  .lanes { display:flex; flex-direction:column; gap:1rem; padding:0 1rem 1rem; }
  .lane { border:1px solid var(--border); border-radius:8px; overflow:hidden; }
  .lane h2 { margin:0; padding:.5rem .75rem; background:var(--card); font-size:.95rem; border-bottom:1px solid var(--border); }
  .cols { display:grid; grid-template-columns:repeat(auto-fit,minmax(160px,1fr)); gap:.5rem; padding:.5rem; }
  .col h3 { font-size:.7rem; text-transform:uppercase; opacity:.6; margin:.25rem 0; letter-spacing:.04em; }
  .card { border:1px solid var(--border); border-radius:6px; padding:.4rem .5rem; margin-bottom:.4rem; font-size:.8rem; background:var(--bg); }
  .card a { color:var(--accent); text-decoration:none; font-weight:600; }
  .meta { opacity:.65; font-size:.7rem; margin-top:.15rem; }
  @media (max-width: 480px) { .cols { grid-template-columns: 1fr; } }
</style>
</head>
<body>
<h1>__BOARD_TITLE__</h1>
<div id="root" class="lanes"></div>
<script id="board-data" type="application/json">
HTML_HEAD
    printf '%s' "$data_json"
    cat <<'HTML_TAIL'
</script>
<script>
(function () {
  var data = JSON.parse(document.getElementById('board-data').textContent);
  var lanes = ['bug', 'feature', 'release'];
  var states = ['backlog', 'implementing', 'built', 'deployed', 'verifying', 'blocked'];
  var root = document.getElementById('root');
  lanes.forEach(function (lane) {
    var items = data.filter(function (d) { return d.lane === lane; });
    var laneEl = document.createElement('div');
    laneEl.className = 'lane';
    var h2 = document.createElement('h2');
    h2.textContent = 'lane:' + lane + ' (' + items.length + ')';
    laneEl.appendChild(h2);
    var cols = document.createElement('div');
    cols.className = 'cols';
    states.forEach(function (state) {
      var col = document.createElement('div');
      col.className = 'col';
      var h3 = document.createElement('h3');
      h3.textContent = state;
      col.appendChild(h3);
      items.filter(function (d) { return d.state === state; }).forEach(function (d) {
        var card = document.createElement('div');
        card.className = 'card';
        var a = document.createElement('a');
        a.href = d.url;
        a.target = '_blank';
        a.rel = 'noopener';
        a.textContent = '#' + d.number + (d.priority ? (' ' + d.priority) : '');
        card.appendChild(a);
        var t = document.createElement('div');
        t.textContent = d.title;
        card.appendChild(t);
        var m = document.createElement('div');
        m.className = 'meta';
        m.textContent = d.claimant ? ('claimed: ' + d.claimant) : 'unclaimed';
        card.appendChild(m);
        col.appendChild(card);
      });
      cols.appendChild(col);
    });
    laneEl.appendChild(cols);
    root.appendChild(laneEl);
  });
})();
</script>
</body>
</html>
HTML_TAIL
  } > "$out"

  echo "render: wrote ${out}"

  if [ -n "$hash_file" ]; then
    local content hash old_hash
    # Strip the generated-at stamp before hashing — see the comment block
    # above this function for why.
    content="$(grep -v '^<!-- generated-at:' "$out")"
    if command -v shasum >/dev/null 2>&1; then
      hash="$(printf '%s' "$content" | shasum -a 256 | awk '{print $1}')"
    elif command -v sha256sum >/dev/null 2>&1; then
      hash="$(printf '%s' "$content" | sha256sum | awk '{print $1}')"
    else
      die "render: neither shasum nor sha256sum found on PATH — cannot compute --hash-file" 2
    fi

    old_hash=""
    [ -f "$hash_file" ] && old_hash="$(cat "$hash_file")"

    if [ "$hash" = "$old_hash" ]; then
      echo "UNCHANGED"
    else
      printf '%s\n' "$hash" > "$hash_file"
      echo "CHANGED"
    fi
  fi
}

# ---------------------------------------------------------------------------
# project-sync — sync a GitHub Projects (v2) board deterministically from
# issue labels (lane:*, state:*, P0-P3, agent:*). This is `render`'s live
# counterpart: render produces a static HTML snapshot from a `gh issue list`
# read; project-sync WRITES the same label taxonomy into a real GitHub
# Project so it's filterable/sortable/groupable in GitHub's own UI, with no
# second taxonomy invented here (see the label-taxonomy comment at the top
# of this file).
#
# The JSON shapes parsed below (`gh project view/list/field-list/item-add
# --format json`) follow the `gh` manual. Before relying on this, run
# `project-sync --self-check` with a project-scoped token: it prints the real
# JSON keys, so checking the shapes is one `board.sh` call.
# ---------------------------------------------------------------------------
_project_sync_field_id() {
  # $1=fields_json $2=field-name
  printf '%s' "$1" | jq -r --arg n "$2" '(.fields // [])[] | select(.name==$n) | .id' | head -1
}

_project_sync_option_id() {
  # $1=fields_json $2=field-name $3=option-name
  printf '%s' "$1" | jq -r --arg n "$2" --arg o "$3" \
    '(.fields // [])[] | select(.name==$n) | (.options // [])[] | select(.name==$o) | .id' | head -1
}

# _project_sync_status_for_state <state> — maps state:* onto the built-in Status
# field, the board's visible column. Left alone, GitHub's own project workflows
# set it (PR merged -> Done -> Auto-close issue) regardless of state.
_project_sync_status_for_state() {
  case "$1" in
    backlog) printf 'Todo' ;;
    implementing|built|deployed|verifying|blocked) printf 'In Progress' ;;
    done|dropped) printf 'Done' ;;
    *) printf '' ;;
  esac
}

# _project_sync_apply_select <item_id> <project_id> <fields_json> <field> <value> <issue_num> <project_num>
# Prints exactly one of: skip-empty | ok | warn | error (stdout, last line) —
# the caller dispatches on it. All human-readable detail goes to stderr.
_project_sync_apply_select() {
  local item_id="$1" project_id="$2" fields_json="$3" field="$4" value="$5" num="$6" pnum="$7"
  [ -n "$value" ] || { echo "skip-empty"; return 0; }
  local fid oid
  fid="$(_project_sync_field_id "$fields_json" "$field")"
  if [ -z "$fid" ]; then
    echo "project-sync: WARN #${num} field '${field}' does not exist on project #${pnum} — value '${value}' not set (run project-sync once without --issue to create missing fields)" >&2
    echo "warn"; return 0
  fi
  oid="$(_project_sync_option_id "$fields_json" "$field" "$value")"
  if [ -z "$oid" ]; then
    echo "project-sync: WARN #${num} field '${field}' on project #${pnum} has no option '${value}' — leaving unset. gh CLI cannot add an option to an existing single-select field; add it by hand in the Projects UI." >&2
    echo "warn"; return 0
  fi
  if gh project item-edit --id "$item_id" --project-id "$project_id" --field-id "$fid" --single-select-option-id "$oid" >/dev/null 2>&1; then
    echo "ok"
  else
    echo "project-sync: ERROR #${num} item-edit field '${field}'='${value}' failed on project #${pnum}" >&2
    echo "error"
  fi
}

# project-sync --self-check [--owner o] [--number N] [--issue n]
_project_sync_self_check() {
  local owner="$1" number="$2" issue="$3"
  require_gh; require_jq
  echo "== gh project field-list --format json (top-level keys) =="
  local fj
  fj="$(gh project field-list "$number" --owner "$owner" --format json --limit 100)" \
    || die "project-sync --self-check: gh project field-list failed for project #${number}" 2
  printf 'top-level: %s\n' "$(printf '%s' "$fj" | jq -c 'keys')"
  printf 'field[0] keys: %s\n' "$(printf '%s' "$fj" | jq -c '((.fields // [])[0] // {}) | keys')"
  printf 'single-select option[0] keys: %s\n' "$(printf '%s' "$fj" | jq -c \
    '(((.fields // [])[] | select(.options != null) | .options)[0] // {}) | keys')"

  if [ -n "$issue" ]; then
    local url
    url="$(gh issue view "$issue" --json url --jq '.url' 2>/dev/null || true)"
    if [ -n "$url" ]; then
      echo "== gh project item-add --format json (keys, issue #${issue}) =="
      local ij
      ij="$(gh project item-add "$number" --owner "$owner" --url "$url" --format json)" \
        || die "project-sync --self-check: gh project item-add failed for issue #${issue}" 2
      printf 'item keys: %s\n' "$(printf '%s' "$ij" | jq -c 'keys')"
    else
      echo "project-sync --self-check: could not resolve a URL for issue #${issue} — skipping item-add probe" >&2
    fi
  else
    echo "(pass --issue <n> to also probe gh project item-add's JSON keys)"
  fi
}

# project-sync [--owner o] [--title t] [--number N] [--issue n] [--create] [--dry-run] [--self-check]
cmd_project_sync() {
  require_gh; require_jq
  local owner="" title="" number="" only_issue="" create=0 dry_run=0 self_check=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --owner) owner="$2"; shift 2 ;;
      --title) title="$2"; shift 2 ;;
      --number) number="$2"; shift 2 ;;
      --issue) only_issue="$2"; shift 2 ;;
      --create) create=1; shift ;;
      --dry-run) dry_run=1; shift ;;
      --self-check) self_check=1; shift ;;
      *) die "project-sync: unknown arg $1" ;;
    esac
  done
  [ -n "$owner" ] || owner="${BOARD_PROJECT_OWNER:-$(lanes_cfg '.projectBoard.owner' '')}"
  [ -n "$owner" ] || owner="$(gh repo view --json owner --jq '.owner.login' 2>/dev/null || true)"
  [ -n "$owner" ] || die "project-sync: no owner — pass --owner, set projectBoard.owner in .claude/agent-lanes.json, or run inside a repo gh can identify"
  [ -n "$number" ] || number="${BOARD_PROJECT_NUMBER:-}"
  [ -n "$title" ] || title="$(lanes_cfg '.projectBoard.title' 'Agent Work Board')"

  # ---- resolve project number/id ---------------------------------------
  local project_id=""
  if [ -n "$number" ]; then
    local view_json
    view_json="$(gh project view "$number" --owner "$owner" --format json 2>&1)" \
      || die "project-sync: project #${number} not found for owner ${owner} (gh project view failed: ${view_json}) — check --owner/--number" 2
    project_id="$(printf '%s' "$view_json" | jq -r '.id // empty')"
    [ -n "$project_id" ] || die "project-sync: gh project view for #${number} returned no id — response: ${view_json}" 2
  else
    local list_json found_number found_id
    list_json="$(gh project list --owner "$owner" --format json --limit 100 2>&1)" \
      || die "project-sync: gh project list failed for owner ${owner}: ${list_json}" 2
    found_number="$(printf '%s' "$list_json" | jq -r --arg t "$title" '(.projects // [])[] | select(.title==$t) | .number' | head -1)"
    found_id="$(printf '%s' "$list_json" | jq -r --arg t "$title" '(.projects // [])[] | select(.title==$t) | .id' | head -1)"

    if [ -z "$found_number" ]; then
      if [ "$create" != "1" ]; then
        die "project-sync: no project titled '${title}' found for owner ${owner} — pass --create to create one, or --number/BOARD_PROJECT_NUMBER to target an existing project" 2
      fi
      if [ "$dry_run" = "1" ]; then
        echo "WOULD-CREATE project '${title}' for owner ${owner}"
        return 0
      fi
      local create_json repo_nwo
      create_json="$(gh project create --owner "$owner" --title "$title" --format json)" \
        || die "project-sync: gh project create failed for owner ${owner} title '${title}'" 2
      number="$(printf '%s' "$create_json" | jq -r '.number // empty')"
      project_id="$(printf '%s' "$create_json" | jq -r '.id // empty')"
      [ -n "$number" ] && [ -n "$project_id" ] \
        || die "project-sync: gh project create returned no number/id — response: ${create_json}" 2
      repo_nwo="$(gh repo view --json nameWithOwner --jq '.nameWithOwner' 2>/dev/null || true)"
      if [ -n "$repo_nwo" ]; then
        gh project link "$number" --owner "$owner" --repo "$repo_nwo" >/dev/null 2>&1 \
          || echo "project-sync: WARN link project #${number} to repo ${repo_nwo} failed — link it manually: gh project link ${number} --owner ${owner} --repo ${repo_nwo}" >&2
      else
        echo "project-sync: WARN could not resolve this repo's nameWithOwner — link project #${number} manually: gh project link ${number} --owner ${owner} --repo <owner/repo>" >&2
      fi
      echo "created: project #${number} '${title}' for owner ${owner}"
    else
      number="$found_number"
      project_id="$found_id"
    fi
  fi

  if [ "$self_check" = "1" ]; then
    _project_sync_self_check "$owner" "$number" "$only_issue"
    return
  fi

  # ---- ensure fields exist ----------------------------------------------
  local fields_json
  fields_json="$(gh project field-list "$number" --owner "$owner" --format json --limit 100 2>&1)" \
    || die "project-sync: gh project field-list failed for project #${number}: ${fields_json}" 2

  # name|type|csv-options (csv empty for TEXT)
  local field_defs="Lane|SINGLE_SELECT|bug,feature,release
State|SINGLE_SELECT|backlog,implementing,built,deployed,verifying,blocked,done,dropped
Priority|SINGLE_SELECT|P0,P1,P2,P3
Agent|TEXT|"

  local line fname ftype fopts existing_id opt refetch_fields=0
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    fname="${line%%|*}"
    local rest="${line#*|}"
    ftype="${rest%%|*}"
    fopts="${rest#*|}"

    existing_id="$(_project_sync_field_id "$fields_json" "$fname")"
    if [ -z "$existing_id" ]; then
      if [ "$dry_run" = "1" ]; then
        echo "WOULD-CREATE field '${fname}' (${ftype})"
        continue
      fi
      if [ "$ftype" = "SINGLE_SELECT" ]; then
        if gh project field-create "$number" --owner "$owner" --name "$fname" \
             --data-type SINGLE_SELECT --single-select-options "$fopts" --format json >/dev/null 2>&1; then
          echo "created field: ${fname}"
          refetch_fields=1
        else
          echo "project-sync: ERROR field-create '${fname}' failed on project #${number} — create it manually in the Projects UI (single select: ${fopts})" >&2
        fi
      else
        if gh project field-create "$number" --owner "$owner" --name "$fname" \
             --data-type TEXT --format json >/dev/null 2>&1; then
          echo "created field: ${fname}"
          refetch_fields=1
        else
          echo "project-sync: ERROR field-create '${fname}' failed on project #${number} — create it manually in the Projects UI (text field)" >&2
        fi
      fi
      continue
    fi

    if [ "$ftype" = "SINGLE_SELECT" ] && [ -n "$fopts" ]; then
      local ifs_old="$IFS"
      IFS=','
      for opt in $fopts; do
        if [ -z "$(_project_sync_option_id "$fields_json" "$fname" "$opt")" ]; then
          echo "project-sync: WARN field '${fname}' on project #${number} is missing option '${opt}' — gh CLI cannot add an option to an existing single-select field; add it by hand: project #${number} settings > '${fname}' field > add option '${opt}'" >&2
        fi
      done
      IFS="$ifs_old"
    fi
  done <<EOF
$field_defs
EOF

  if [ "$refetch_fields" = "1" ]; then
    fields_json="$(gh project field-list "$number" --owner "$owner" --format json --limit 100 2>&1)" \
      || die "project-sync: gh project field-list (refetch after field-create) failed for project #${number}: ${fields_json}" 2
  fi

  # ---- gather issues ------------------------------------------------------
  local issues_json
  if [ -n "$only_issue" ]; then
    local one
    one="$(gh issue view "$only_issue" --json number,title,labels,url,state 2>&1)" \
      || die "project-sync: gh issue view #${only_issue} failed: ${one}" 2
    issues_json="$(printf '%s' "$one" | jq -c '[.]')"
  else
    local open_json closed_json since
    open_json="$(gh issue list --state open --limit 200 --json number,title,labels,url,state 2>&1)" \
      || die "project-sync: gh issue list (open) failed: ${open_json}" 2
    since="$(date -u -v-7d +%Y-%m-%d 2>/dev/null || date -u -d '-7 days' +%Y-%m-%d)"
    if closed_json="$(gh issue list --state closed --search "closed:>=${since}" --limit 200 --json number,title,labels,url,state 2>&1)"; then
      :
    else
      echo "project-sync: WARN gh issue list (closed, last 7d) failed — recently-closed issues will not be synced this run: ${closed_json}" >&2
      closed_json="[]"
    fi
    printf '%s' "$closed_json" | jq -e . >/dev/null 2>&1 || closed_json="[]"

    issues_json="$(jq -nc --argjson a "$open_json" --argjson b "$closed_json" '
      ($a + $b)
      | unique_by(.number)
      | map(select((.labels|map(.name)) as $l | ($l | map(startswith("lane:")) | any)))
    ')"
  fi

  # ---- per-issue sync -------------------------------------------------
  local synced=0 warned=0 had_error=0
  local n i=0
  n="$(printf '%s' "$issues_json" | jq 'length')"
  while [ "$i" -lt "$n" ]; do
    local issue_line num url is_closed lane state priority agent issue_warns=0
    issue_line="$(printf '%s' "$issues_json" | jq -c --argjson i "$i" '.[$i]')"
    num="$(printf '%s' "$issue_line" | jq -r '.number')"
    url="$(printf '%s' "$issue_line" | jq -r '.url')"
    is_closed="$(printf '%s' "$issue_line" | jq -r '(.state=="CLOSED")')"
    lane="$(printf '%s' "$issue_line" | jq -r '(.labels|map(.name)|map(select(startswith("lane:")))|map(sub("^lane:";"")))[0] // empty')"
    state="$(printf '%s' "$issue_line" | jq -r '(.labels|map(.name)|map(select(startswith("state:")))|map(sub("^state:";"")))[0] // empty')"
    priority="$(printf '%s' "$issue_line" | jq -r '(.labels|map(.name)|map(select(test("^P[0-3]$"))))[0] // empty')"
    agent="$(printf '%s' "$issue_line" | jq -r '(.labels|map(.name)|map(select(startswith("agent:")))|map(sub("^agent:";"")))[0] // empty')"

    # Closed with no explicit state:done/dropped label -> treat as done.
    if [ "$is_closed" = "true" ] && [ -z "$state" ]; then
      state="done"
    fi

    # --issue mode targets exactly one issue by number; when its last lane:*
    # label has been removed, leaving it synced with Lane unset would just
    # sit there unfiled forever (nothing else re-visits it). Archive it off
    # the active board instead — this branch is intentionally scoped to
    # --issue mode only: a bulk sync run still WARNs (below) rather than mass
    # -archiving every no-lane issue it happens to see.
    if [ -n "$only_issue" ] && [ -z "$lane" ]; then
      if [ "$dry_run" = "1" ]; then
        echo "WOULD-ARCHIVE #${num} (no lane)"
        synced=$((synced + 1))
        i=$((i + 1))
        continue
      fi
      local arch_item_json arch_item_id
      if arch_item_json="$(gh project item-add "$number" --owner "$owner" --url "$url" --format json 2>&1)"; then
        arch_item_id="$(printf '%s' "$arch_item_json" | jq -r '.id // empty' 2>/dev/null)"
      else
        echo "project-sync: ERROR item-add for #${num} failed on project #${number}: ${arch_item_json}" >&2
        had_error=1
        i=$((i + 1))
        continue
      fi
      if [ -z "$arch_item_id" ]; then
        echo "project-sync: ERROR item-add for #${num} returned no item id — response: ${arch_item_json}" >&2
        had_error=1
        i=$((i + 1))
        continue
      fi
      if gh project item-archive "$number" --owner "$owner" --id "$arch_item_id" >/dev/null 2>&1; then
        echo "ARCHIVED #${num} (no lane)"
        synced=$((synced + 1))
      else
        echo "project-sync: ERROR item-archive for #${num} failed on project #${number}" >&2
        had_error=1
      fi
      i=$((i + 1))
      continue
    fi

    [ -n "$lane" ] || { echo "project-sync: WARN #${num} has no lane:* label — Lane not set" >&2; issue_warns=$((issue_warns + 1)); }
    [ -n "$state" ] || { echo "project-sync: WARN #${num} has no state:* label — State not set" >&2; issue_warns=$((issue_warns + 1)); }
    [ -n "$priority" ] || { echo "project-sync: WARN #${num} has no P0-P3 label — Priority not set" >&2; issue_warns=$((issue_warns + 1)); }

    if [ "$dry_run" = "1" ]; then
      echo "WOULD-SYNC #${num} lane=${lane:--} state=${state:--} p=${priority:--} agent=${agent:--}"
      warned=$((warned + issue_warns))
      synced=$((synced + 1))
      i=$((i + 1))
      continue
    fi

    local item_json item_id
    if item_json="$(gh project item-add "$number" --owner "$owner" --url "$url" --format json 2>&1)"; then
      :
    else
      echo "project-sync: ERROR item-add for #${num} failed on project #${number}: ${item_json}" >&2
      had_error=1
      i=$((i + 1))
      continue
    fi
    item_id="$(printf '%s' "$item_json" | jq -r '.id // empty' 2>/dev/null)"
    if [ -z "$item_id" ]; then
      echo "project-sync: ERROR item-add for #${num} returned no item id — response: ${item_json}" >&2
      had_error=1
      i=$((i + 1))
      continue
    fi

    local res
    res="$(_project_sync_apply_select "$item_id" "$project_id" "$fields_json" "Lane" "$lane" "$num" "$number")"
    case "$res" in warn) warned=$((warned + 1)) ;; error) had_error=1 ;; esac
    res="$(_project_sync_apply_select "$item_id" "$project_id" "$fields_json" "State" "$state" "$num" "$number")"
    case "$res" in warn) warned=$((warned + 1)) ;; error) had_error=1 ;; esac
    local status
    status="$(_project_sync_status_for_state "$state")"
    res="$(_project_sync_apply_select "$item_id" "$project_id" "$fields_json" "Status" "$status" "$num" "$number")"
    case "$res" in warn) warned=$((warned + 1)) ;; error) had_error=1 ;; esac
    res="$(_project_sync_apply_select "$item_id" "$project_id" "$fields_json" "Priority" "$priority" "$num" "$number")"
    case "$res" in warn) warned=$((warned + 1)) ;; error) had_error=1 ;; esac

    local agent_fid agent_err
    agent_fid="$(_project_sync_field_id "$fields_json" "Agent")"
    if [ -z "$agent_fid" ]; then
      echo "project-sync: WARN #${num} field 'Agent' does not exist on project #${number} — claimant not set" >&2
      warned=$((warned + 1))
    else
      # gh rejects an empty --text ("no changes to make"); unclaimed issues must --clear.
      if [ -n "$agent" ]; then
        agent_err="$(gh project item-edit --id "$item_id" --project-id "$project_id" --field-id "$agent_fid" --text "$agent" 2>&1 >/dev/null)"
      else
        agent_err="$(gh project item-edit --id "$item_id" --project-id "$project_id" --field-id "$agent_fid" --clear 2>&1 >/dev/null)"
      fi
      if [ $? -ne 0 ]; then
        echo "project-sync: ERROR #${num} item-edit field 'Agent'='${agent}' failed on project #${number}: ${agent_err}" >&2
        had_error=1
      fi
    fi

    warned=$((warned + issue_warns))
    echo "SYNCED #${num} lane=${lane:--} state=${state:--} p=${priority:--} agent=${agent:--}"
    synced=$((synced + 1))
    i=$((i + 1))
  done

  echo "SUMMARY synced=${synced} warned=${warned}"
  [ "$had_error" != "1" ] || exit 2
}

# ---------------------------------------------------------------------------
# prd_frontmatter_field <file> <field> — shared helper for prd-scan/file-feature
# ---------------------------------------------------------------------------
prd_frontmatter_field() {
  awk -v field="$2" '
    NR==1 && $0 != "---" { exit }
    NR==1 { infm=1; next }
    infm && $0 == "---" { exit }
    infm && $0 ~ ("^" field ":") {
      sub("^" field ":[[:space:]]*", "")
      gsub(/^"|"$/, "")
      print
      exit
    }
  ' "$1"
}

prd_id_for() {
  local file="$1" id
  id="$(prd_frontmatter_field "$file" "$(lanes_cfg '.prd.idField' prd_id)")"
  if [ -z "$id" ]; then
    id="$(basename "$file" .md)"
  fi
  printf '%s' "$id"
}

# FR ids are normalized to FR<N>: FR-6 and FR6 name the same requirement.
prd_fr_ids() {
  grep -Eo "$(lanes_cfg '.prd.frPattern' 'FR-?[0-9]+')" "$1" 2>/dev/null | sed -E 's/FR-?/FR/' | sort -u
}

# ---------------------------------------------------------------------------
# prd-scan [--json] [--prd <file>]
#
# Canonical FR tracking token: `[<prd_id> FR<N>]`, where <prd_id> is the
# PRD's frontmatter `prd_id` field (or the filename stem if absent) and
# `FR<N>` has any dash stripped (FR-6 and FR6 both normalize to FR6). A
# GitHub issue/PR title or body containing this literal bracketed token is
# considered "tracks this requirement". This does NOT decide whether the
# requirement is actually developed (that needs code reading) — only
# whether a tracking issue/PR exists for it.
# ---------------------------------------------------------------------------
cmd_prd_scan() {
  require_gh; require_jq
  local as_json=0 only_file=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --json) as_json=1; shift ;;
      --prd) only_file="$2"; shift 2 ;;
      *) die "prd-scan: unknown arg $1" ;;
    esac
  done

  local repo_root
  repo_root="$LANES_REPO_ROOT"

  local results="[]"
  local f base status prd_id title frs fr token hits pr_hits tracked entry

  local file_list
  if [ -n "$only_file" ]; then
    file_list="$only_file"
  else
    local prd_glob
    prd_glob="$(lanes_cfg '.prd.glob' 'prd/[0-9]*.md')"
    # Unquoted on purpose: the configured glob must expand.
    # shellcheck disable=SC2086
    file_list="$(cd "$repo_root" && ls -d $prd_glob 2>/dev/null | sed "s|^|${repo_root}/|" || true)"
  fi

  for f in $file_list; do
    [ -f "$f" ] || continue
    base="$(basename "$f")"
    case "$base" in _*) continue ;; esac

    status="$(prd_frontmatter_field "$f" status)"
    case "$(printf '%s' "$status" | tr '[:upper:]' '[:lower:]')" in
      *deprecated*|*superseded*|*dropped*|*cancelled*|*canceled*) continue ;;
    esac

    prd_id="$(prd_id_for "$f")"
    title="$(prd_frontmatter_field "$f" title)"
    frs="$(prd_fr_ids "$f")"
    [ -n "$frs" ] || continue

    for fr in $frs; do
      token="[${prd_id} ${fr}]"

      hits="$(gh issue list --state all --search "\"${token}\" in:title,body" --limit 5 --json number,title,url,state 2>&1)" \
        || { echo "prd-scan SKIPPED issue search for token ${token}: gh issue list failed — treating as untracked (verify by hand)" >&2; hits="[]"; }
      pr_hits="$(gh pr list --state all --search "\"${token}\"" --limit 5 --json number,title,url,state 2>&1)" \
        || { echo "prd-scan SKIPPED PR search for token ${token}: gh pr list failed — treating as none found" >&2; pr_hits="[]"; }

      printf '%s' "$hits" | jq -e . >/dev/null 2>&1 || hits="[]"
      printf '%s' "$pr_hits" | jq -e . >/dev/null 2>&1 || pr_hits="[]"

      tracked="false"
      [ "$(printf '%s' "$hits" | jq 'length')" -gt 0 ] && tracked="true"

      entry="$(jq -nc --arg prd "$base" --arg prd_id "$prd_id" --arg title "$title" --arg fr "$fr" \
        --arg token "$token" --argjson tracked "$tracked" --argjson issues "$hits" --argjson prs "$pr_hits" \
        '{prd:$prd, prd_id:$prd_id, title:$title, fr:$fr, token:$token, tracked:$tracked, issues:$issues, prs:$prs}')"
      results="$(printf '%s' "$results" | jq -c --argjson e "$entry" '. + [$e]')"
    done
  done

  if [ "$as_json" = "1" ]; then
    printf '%s\n' "$results"
    return
  fi

  printf '%s' "$results" | jq -r '.[] | select(.tracked==false) | "\(.token)  \(.title)"'
  local n
  n="$(printf '%s' "$results" | jq '[.[] | select(.tracked==false)] | length')"
  echo ""
  echo "untracked FR candidates: ${n}"
  echo "(does NOT mean undeveloped — verify top candidates against code/PRs before filing)"
}

# ---------------------------------------------------------------------------
# file-feature --prd <file> --fr <id> --priority P1 --title "..." --body-file <md>
# ---------------------------------------------------------------------------
cmd_file_feature() {
  require_gh; require_jq
  local prd="" fr="" priority="" title="" body_file=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --prd) prd="$2"; shift 2 ;;
      --fr) fr="$2"; shift 2 ;;
      --priority) priority="$2"; shift 2 ;;
      --title) title="$2"; shift 2 ;;
      --body-file) body_file="$2"; shift 2 ;;
      *) die "file-feature: unknown arg $1" ;;
    esac
  done
  [ -n "$prd" ] && [ -n "$fr" ] && [ -n "$priority" ] && [ -n "$title" ] && [ -n "$body_file" ] \
    || die "file-feature: --prd --fr --priority --title --body-file are all required"
  [ -f "$body_file" ] || die "file-feature: body file not found: ${body_file}"

  local prd_id fr_norm token existing
  prd_id="$(prd_id_for "$prd")"
  fr_norm="$(printf '%s' "$fr" | sed -E 's/^FR-?/FR/')"
  token="[${prd_id} ${fr_norm}]"

  existing="$(gh issue list --state all --search "\"${token}\" in:title,body" --limit 5 --json number,title,url)"
  if [ "$(printf '%s' "$existing" | jq 'length')" -gt 0 ]; then
    echo "file-feature: token ${token} already tracked: $(printf '%s' "$existing" | jq -r '.[0] | "#\(.number) \(.url)"')" >&2
    exit 5
  fi

  gh issue create \
    --title "${token} ${title}" \
    --body-file "$body_file" \
    --label "lane:feature" \
    --label "$priority" \
    --label "state:backlog"
}

# ---------------------------------------------------------------------------
# pr-status <pr> [--json]
# ---------------------------------------------------------------------------
cmd_pr_status() {
  require_gh; require_jq
  local pr="${1:-}"; shift || true
  local as_json=0
  for a in "$@"; do [ "$a" = "--json" ] && as_json=1; done
  [ -n "$pr" ] || die "pr-status: usage: pr-status <pr> [--json]"

  local view
  view="$(gh_checks pr view "$pr" --json number,isDraft,mergeable,mergeStateStatus,reviewDecision,baseRefName,headRefOid,statusCheckRollup)"

  local base head behind
  base="$(printf '%s' "$view" | jq -r '.baseRefName')"
  head="$(printf '%s' "$view" | jq -r '.headRefOid')"
  behind="$(gh api "repos/{owner}/{repo}/compare/${base}...${head}" --jq '.behind_by' 2>/dev/null)" \
    || { echo "pr-status: compare API failed for #${pr} — behind-main count unavailable" >&2; behind=""; }
  [ -n "$behind" ] || behind="null"

  local buckets
  buckets="$(printf '%s' "$view" | jq -c '
    (.statusCheckRollup // [])
    | group_by(.conclusion // .status // "PENDING")
    | map({key: (.[0].conclusion // .[0].status // "PENDING"), count: length})
  ')"

  local failing
  failing="$(printf '%s' "$view" | jq -r '
    (.statusCheckRollup // [])[]
    | select((.conclusion // "") == "FAILURE")
    | [.name, (.detailsUrl // "")] | @tsv
  ')"

  local failing_report="" name details_url job_id err_line
  if [ -n "$failing" ]; then
    while IFS=$'\t' read -r name details_url; do
      [ -z "$name" ] && continue
      job_id="$(printf '%s' "$details_url" | grep -Eo '[0-9]+$' || true)"
      err_line=""
      if [ -n "$job_id" ]; then
        err_line="$(gh run view --job "$job_id" --log-failed 2>/dev/null \
          | grep -Ei 'FAIL|Error|error:|✖|not ok|##\[error\]' | head -1 || true)"
      fi
      failing_report="${failing_report}${name}: ${err_line:-<no matching log line found>}
"
    done <<EOF
$failing
EOF
  fi

  if [ "$as_json" = "1" ]; then
    jq -nc --argjson view "$view" \
      --argjson behind "$behind" \
      --argjson buckets "$buckets" \
      --arg failing "$failing_report" \
      '{number: $view.number, isDraft: $view.isDraft, mergeable: $view.mergeable,
        mergeStateStatus: $view.mergeStateStatus, reviewDecision: $view.reviewDecision,
        behindMain: $behind, checkBuckets: $buckets, failing: $failing}'
    return
  fi

  echo "#${pr} draft=$(printf '%s' "$view" | jq -r '.isDraft') mergeable=$(printf '%s' "$view" | jq -r '.mergeable') mergeState=$(printf '%s' "$view" | jq -r '.mergeStateStatus') review=$(printf '%s' "$view" | jq -r '.reviewDecision // "-"') behindMain=${behind}"
  echo "checks: $(printf '%s' "$buckets" | jq -r 'map("\(.key)=\(.count)") | join(" ")')"
  if [ -n "$failing_report" ]; then
    echo "failing jobs:"
    printf '%s' "$failing_report" | sed 's/^/  /'
  fi
}

# ---------------------------------------------------------------------------
# pr-update <pr>
# ---------------------------------------------------------------------------
cmd_pr_update() {
  require_gh; require_jq
  local pr="${1:-}"
  [ -n "$pr" ] || die "pr-update: usage: pr-update <pr>"

  gh pr update-branch "$pr" >/dev/null
  sleep 2
  local head
  head="$(gh pr view "$pr" --json headRefOid --jq '.headRefOid')"
  echo "pr-update: #${pr} new head: ${head}"
}

# ---------------------------------------------------------------------------
# pr-own <pr> <NAME>
# ---------------------------------------------------------------------------
cmd_pr_own() {
  require_gh; require_jq
  local pr="${1:-}" name="${2:-}"
  [ -n "$pr" ] && [ -n "$name" ] || die "pr-own: usage: pr-own <pr> <NAME>"

  local labels other
  labels="$(gh pr view "$pr" --json labels --jq '.labels[].name')"
  other="$(printf '%s\n' "$labels" | grep '^agent:' | grep -vx "agent:${name}" || true)"
  if [ -n "$other" ]; then
    echo "pr-own: PR #${pr} already has label(s): $(printf '%s' "$other" | tr '\n' ' ')" >&2
    exit 5
  fi

  if ! gh label list --limit 200 --json name --jq '.[].name' | grep -qxF "agent:${name}"; then
    gh label create "agent:${name}" --color "ededed" --description "Claimed by agent ${name}" >/dev/null 2>&1 \
      || echo "pr-own: label create for agent:${name} failed (likely already exists under a race) — continuing" >&2
  fi

  gh pr edit "$pr" --add-label "agent:${name}" >/dev/null

  local ts
  ts="$(now_iso)"
  gh pr comment "$pr" --body "pr-own: ${name} ${ts}" >/dev/null

  echo "pr-owned: #${pr} as ${name}"
}

# ---------------------------------------------------------------------------
# my-prs <NAME> [--json]
# ---------------------------------------------------------------------------
cmd_my_prs() {
  require_gh; require_jq
  local name="${1:-}"; shift || true
  local as_json=0
  for a in "$@"; do [ "$a" = "--json" ] && as_json=1; done
  [ -n "$name" ] || die "my-prs: usage: my-prs <NAME> [--json]"

  local raw
  raw="$(gh_checks pr list --state open --label "agent:${name}" --limit 200 \
    --json number,isDraft,mergeStateStatus,statusCheckRollup,title)"

  if [ "$as_json" = "1" ]; then
    printf '%s\n' "$raw"
    return
  fi

  printf '%s' "$raw" | jq -r '
    def checkbucket:
      ((.statusCheckRollup // []) | map(.conclusion // .status // "PENDING")) as $c
      | if ($c | length) == 0 then "none"
        elif ($c | map(select(. == "FAILURE" or . == "TIMED_OUT" or . == "CANCELLED" or . == "ACTION_REQUIRED" or . == "STARTUP_FAILURE")) | length) > 0 then "failing"
        elif ($c | map(select(. != "SUCCESS" and . != "NEUTRAL" and . != "SKIPPED")) | length) > 0 then "pending"
        else "green" end;
    .[] | [ ("#" + (.number|tostring)), .isDraft, .mergeStateStatus, checkbucket,
            (.title | if length > 60 then .[0:57] + "..." else . end) ]
    | @tsv
  ' | render_table
}

# ---------------------------------------------------------------------------
# reconcile-age --workflow <file.yml> [--max-hours 3]
#
# A scheduled reconcile that silently stops firing is invisible: nothing runs,
# so nothing fails. (GitHub disables schedules after 60 days without repo
# activity, and a schedule on a runner label nobody serves never starts.)
# This checks the newest SUCCESSFUL `schedule` run and prints one of:
#   OK <age>h        newest scheduled success is within --max-hours
#   STALE <age>h     older than --max-hours                     (exit 1)
#   NONE             no successful scheduled run on record       (exit 1)
# Callers surface the non-OK line; they do not swallow it.
# ---------------------------------------------------------------------------
cmd_reconcile_age() {
  require_gh; require_jq
  local workflow="" max_hours=3
  while [ $# -gt 0 ]; do
    case "$1" in
      --workflow) workflow="$2"; shift 2 ;;
      --max-hours) max_hours="$2"; shift 2 ;;
      *) die "reconcile-age: unknown arg $1" ;;
    esac
  done
  [ -n "$workflow" ] || die "reconcile-age: --workflow <file.yml> is required"
  case "$max_hours" in ''|*[!0-9]*) die "reconcile-age: --max-hours must be a whole number" ;; esac

  local runs
  runs="$(gh run list --workflow "$workflow" --event schedule --status success --limit 1 --json createdAt)" \
    || die "reconcile-age: gh run list failed for ${workflow}" 2
  local created
  created="$(printf '%s' "$runs" | jq -r '.[0].createdAt // empty')"
  if [ -z "$created" ]; then
    echo "NONE no successful scheduled run of ${workflow} on record"
    exit 1
  fi
  local age_h
  age_h="$(jq -nr --arg c "$created" '((now - ($c | fromdateiso8601)) / 3600) | floor')"
  if [ "$age_h" -gt "$max_hours" ]; then
    echo "STALE ${age_h}h since the last successful scheduled run of ${workflow} (max ${max_hours}h)"
    exit 1
  fi
  echo "OK ${age_h}h since the last successful scheduled run of ${workflow}"
}

# ---------------------------------------------------------------------------
usage() {
  cat <<'EOF'
board.sh — deterministic GitHub-Issues coordination CLI

  init-labels [--dry-run]
  list [--lane bug|feature|release] [--state <s>] [--agent <NAME>] [--unclaimed] [--json]
  next --lane bug|feature --agent <NAME>
  claim <issue> <NAME>
  release <issue> <NAME> [--reason ...]
  state <issue> <new-state>
  handoff <issue> --file <md>
  comment <issue> --file <md>
  show <issue> [--out DIR] [--no-comments]     (text + screenshots, via issue-fetch.sh)
  watch --agent <NAME> [--lane bug|feature]    (issue events for Monitor, via issue-watch.sh)
  checkout <issue> <NAME> [--worktree]         (claim + implementing + show [+ worktree])
  deploy-queue [--json]
  render --out <file.html> [--hash-file <path>]
  project-sync [--owner org] [--title "Agent Work Board"] [--number N] [--issue <n>] [--create] [--dry-run] [--self-check]
  prd-scan [--json] [--prd <file>]
  file-feature --prd <file> --fr <id> --priority P1 --title "..." --body-file <md>
  pr-status <pr> [--json]
  pr-update <pr>
  pr-own <pr> <NAME>
  my-prs <NAME> [--json]
  reconcile-age --workflow <file.yml> [--max-hours 3]
  help

Config: .claude/agent-lanes.json. See scripts/dev/board/README.md and
.claude/skills/_shared/agent-protocol.md.
EOF
}

main() {
  [ $# -ge 1 ] || { usage; exit 2; }
  local cmd="$1"; shift
  case "$cmd" in
    init-labels) cmd_init_labels "$@" ;;
    list) cmd_list "$@" ;;
    next) cmd_next "$@" ;;
    claim) cmd_claim "$@" ;;
    release) cmd_release "$@" ;;
    state) cmd_state "$@" ;;
    handoff) cmd_handoff "$@" ;;
    comment) cmd_comment "$@" ;;
    show) cmd_show "$@" ;;
    watch) cmd_watch "$@" ;;
    checkout) cmd_checkout "$@" ;;
    deploy-queue) cmd_deploy_queue "$@" ;;
    render) cmd_render "$@" ;;
    project-sync) cmd_project_sync "$@" ;;
    prd-scan) cmd_prd_scan "$@" ;;
    file-feature) cmd_file_feature "$@" ;;
    pr-status) cmd_pr_status "$@" ;;
    pr-update) cmd_pr_update "$@" ;;
    pr-own) cmd_pr_own "$@" ;;
    my-prs) cmd_my_prs "$@" ;;
    reconcile-age) cmd_reconcile_age "$@" ;;
    help|-h|--help) usage ;;
    *) die "unknown subcommand '${cmd}' — run 'board.sh help'" ;;
  esac
}

# Allow sourcing (e.g. from the test harness) without executing main.
if [ "${BOARD_SH_SOURCED:-0}" != "1" ]; then
  main "$@"
fi
