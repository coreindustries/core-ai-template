#!/usr/bin/env bash
# pr-monitor.test.sh - pr-monitor.sh against a FAKE gh and a stub pr-watch.sh (no network).
# The mktemp directory is left for the OS temp cleaner; the test never deletes anything.
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "$0")" && pwd)"
BOARD_DIR="$(cd "$TESTS_DIR/.." && pwd)"
TMP="$(mktemp -d)"

mkdir -p "$TMP/board" "$TMP/bin"
cp "$BOARD_DIR/pr-monitor.sh" "$TMP/board/pr-monitor.sh"
# Stub: PR 7 needs action, every other PR is quiet.
cat > "$TMP/board/pr-watch.sh" <<'STUB'
#!/usr/bin/env bash
echo "noise for $1"
[ "$1" = "7" ] && echo "ACTION pr=7 event=check-failed"
exit 0
STUB
cat > "$TMP/bin/gh" <<'STUB'
#!/usr/bin/env bash
if [ "${FAKE_GH_FAIL:-0}" = 1 ]; then exit 1; fi
printf '7\n8\n'
STUB
chmod +x "$TMP/bin/gh"

fail=0
check() { if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1: expected [$2] got [$3]"; fail=1; fi; }

out="$(PATH="$TMP/bin:$PATH" bash "$TMP/board/pr-monitor.sh" --once 2>&1)"
check "emits only ACTION lines" "ACTION pr=7 event=check-failed" "$out"

out="$(FAKE_GH_FAIL=1 PATH="$TMP/bin:$PATH" bash "$TMP/board/pr-monitor.sh" --once 2>&1)"
case "$out" in *"WARN could not list open PRs"*) echo "PASS warns when gh fails" ;; *) echo "FAIL warn: $out"; fail=1 ;; esac

bash "$TMP/board/pr-monitor.sh" --bogus >/dev/null 2>&1
check "unknown arg exits 2" "2" "$?"

exit "$fail"
