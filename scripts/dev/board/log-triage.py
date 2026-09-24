#!/usr/bin/env python3
"""log-triage.py — deterministic before/after log triage for a deployed release.

Reads the shell command configured per environment in `.claude/agent-lanes.json`
(`deploy.environments[].logs`), runs it to capture that environment's raw log
output, and builds a redacted warn/error digest of it IN THIS PROCESS: no
external tool and no LLM ever reads a raw log line. Every line is redacted
(secrets first, then personal/free-text content) before anything is written to
disk or printed — only the redacted signature and a redacted sample are ever
stored.

    log-triage.py capture before|after <env> --release <rel> [--since-minutes N]
    log-triage.py report <rel> [--all]
    log-triage.py file   <rel> [--apply] [--max-new 15]

Verdicts (per signature, across every environment captured for the release):
  BASELINED        listed in the baseline file (logTriage.baselineFile); not filed
  RELEASE-SUSPECT  seen AFTER, in NO environment's BEFORE, and at least one
                   environment showing it has a BEFORE capture (so its absence
                   before is actually measured there, not just uncaptured)
  PRE-EXISTING     seen in some environment's BEFORE (the release did not introduce it)
  UNATTRIBUTED     seen AFTER only on environments with no BEFORE capture: cannot tell

Every non-baselined signature is filed: one already tracked (an open issue
carrying its `log-sig:<id>` marker) gets a frequency comment there; each
RELEASE-SUSPECT gets its own P2 `lane:bug` issue, up to --max-new; everything
else goes into one P3 rollup issue per release. This tool never baselines
anything itself: declaring a signature benign is a reviewed PR, not an
automatic outcome.

`file` is a dry run unless --apply is passed. State lives under
$LOG_TRIAGE_STATE (default ~/.local/state/agent-lanes/<repo>/log-triage/<release>/).
Config path can be overridden with $LANES_CONFIG (default .claude/agent-lanes.json).

A non-zero exit from the configured `logs` command is ALWAYS treated as a failed
capture — nothing is written to disk for that phase. This matters for pipelines
like `... | grep ERROR`, which exit 1 when grep finds nothing to match, even
though "no matching lines" may be a perfectly valid, successful outcome for that
command. If that's the case for your `logs` command, write it as
`... | grep ERROR || true` so "no matches" exits 0.
"""
import argparse
import hashlib
import json
import os
import pathlib
import re
import subprocess
import sys

REPO = pathlib.Path(__file__).resolve().parents[3]
SAMPLE_MAX = 220
SIGNATURE_MAX = 200
ENV_NAME_RE = re.compile(r"^[a-z0-9][a-z0-9-]*$")
RELEASE_RE = re.compile(r"^[0-9a-f]{7,40}$")

STATE = pathlib.Path(os.environ.get("LOG_TRIAGE_STATE") or
                      (pathlib.Path.home() / ".local/state/agent-lanes" / REPO.name / "log-triage"))

# --------------------------------------------------------------------------
# Redaction: one ordered pattern table. Specific patterns before generic ones,
# so a specific secret shape is labelled correctly before a generic fallback
# would otherwise swallow it. Secrets first, personal/free-text data second —
# redact_secrets() uses only the first half; redact() uses both.
# --------------------------------------------------------------------------
_SECRETS = [
    (r"(?<![A-Za-z0-9])sk-an[t]-[A-Za-z0-9_-]{20,}", "[REDACTED:ANTHROPIC_KEY]"),
    (r"(?<![A-Za-z0-9])sk-[A-Za-z0-9_-]{20,}", "[REDACTED:OPENAI_KEY]"),
    (r"hooks\.slack\.com/services/\S+", "hooks.slack.com/services/[REDACTED:SLACK_WEBHOOK]"),
    (r"(?i)([?&](?:token|key|sig|signature|access_token|auth|code)=)[^&\s\"']+", r"\1[REDACTED]"),
    (r"xox[b]-[0-9A-Za-z-]{20,}", "[REDACTED:SLACK_BOT_TOKEN]"),
    (r"xapp-[0-9A-Za-z-]{20,}", "[REDACTED:SLACK_APP_TOKEN]"),
    (r"xox[pa]-[0-9A-Za-z-]{20,}", "[REDACTED:SLACK_TOKEN]"),
    (r"shpat_[A-Za-z0-9]{20,}", "[REDACTED:SHOPIFY_TOKEN]"),
    (r"gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}", "[REDACTED:GITHUB_TOKEN]"),
    (r"AKIA[0-9A-Z]{16}", "[REDACTED:AWS_KEY_ID]"),
    (r"\b[0-9]{8,10}:[A-Za-z0-9_-]{35}\b", "[REDACTED:TELEGRAM_TOKEN]"),
    (r"eyJ[A-Za-z0-9_-]+\.eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+", "[REDACTED:JWT]"),
    (r"Bearer [A-Za-z0-9._-]{20,}", "Bearer [REDACTED:BEARER_TOKEN]"),
    # Authorization: <anything> — except "Bearer ..." (handled above, so its
    # specific label survives) and an already-redacted value. Catches Basic,
    # Digest, custom schemes, and any other header value verbatim.
    (r"(?i)(authorization\s*:)(?!\s*bearer\b)(?!\s*\[redacted)\s*.+", r"\1 [REDACTED:AUTH_HEADER]"),
    # any URL with userinfo, any scheme — mysql://, redis://:pass@, amqp://,
    # mongodb://, postgres(ql)://, https://, etc. Keeps scheme/user/host,
    # redacts only the password (the part between ":" and "@").
    (r"([a-zA-Z][a-zA-Z0-9+.-]*://)([^:@/\s]*):([^@\s]+)@", r"\1\2:[REDACTED:URL_PASSWORD]@"),
    (r"1//[A-Za-z0-9_-]{40,}", "[REDACTED:GOOGLE_REFRESH_TOKEN]"),
    # key=value / key: value credentials — no minimum length (a short password
    # is still a password). Redacts up to the next whitespace/quote/&/,.
    (r"(?i)(?<![A-Za-z0-9_-])(password|passwd|pwd|secret|api[_-]?key|apikey|"
     r"access[_-]?token|refresh[_-]?token|client[_-]?secret|auth[_-]?token|auth|"
     r"private[_-]?key|token)(\s*[:=]\s*[\"']?)[^\s\"'&,]+",
     r"\1\2[REDACTED:CREDENTIAL]"),
    # standalone "Basic <b64>" not already caught via an "Authorization:" prefix.
    (r"(?i)\bBasic\s+[A-Za-z0-9+/=]{6,}", "Basic [REDACTED:BASIC_AUTH]"),
    # "X-Api-Key:", "X-Auth-Token:", "X-Client-Secret:" and similar *-key/-token/-secret headers.
    (r"(?i)\b([\w-]*-(?:key|token|secret)\s*:\s*)\S+", r"\1[REDACTED:HEADER_CREDENTIAL]"),
    (r"\b[a-f0-9]{32,}\b", "[REDACTED:HEX_TOKEN]"),
]
# Personal data and free-form authored text: what a secret scanner alone misses.
_PERSONAL = [
    (r"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}", "<email>"),
    (r"(?<![\w.])\+?\d{0,3}[\s.-]?\(?\d{3}\)?[\s-]\d{3}[\s-]\d{4}(?![\w.])", "<phone>"),
    (r"(?i)\b(users|home)/[^/\s\"')]+", r"\1/<user>"),
    # Slack ids always carry a digit in position 2 (U0…, D0…, C0…); plain words like
    # UNAUTHORIZED or WEBSOCKET never do, so they survive
    (r"\b[UWDCG][0-9][A-Z0-9]{7,10}\b", "<slack-id>"),
    (r"(?i)\b((?:telegram|chat|user|sender|from|to)[_ ]?id[=: ]+)-?\d{5,}", r"\1<id>"),
    # everything after raw_params= is tool arguments an agent wrote, not a diagnostic
    (r"(raw_params=).*", r"\1<redacted:tool-args>"),
    # structural redaction of free-form text: (1) any long quoted run is someone's
    # words, not a diagnostic
    (r'"(?:[^"\\\n]|\\.){16,}"', '"<redacted:text>"'),
    (r"'(?:[^'\\\n]|\\.){16,}'", "'<redacted:text>'"),
    (r"“[^”\n]{16,}”", "“<redacted:text>”"),
    # (2) everything after a content label is content, to the end of the line
    (r"(?i)\b((?:text|message|msg|prompt|content|reply|body|query|input|subject|question)\s*[:=]\s*).{12,}$",
     r"\1<redacted:text>"),
]
_SECRET_SUBS = [(re.compile(p), r) for p, r in _SECRETS]
_SUBS = [(re.compile(p), r) for p, r in _SECRETS + _PERSONAL]


def redact_secrets(text: str) -> str:
    """Redact only secret-shaped content (used on stderr from a failed capture)."""
    s = text or ""
    for pat, rep in _SECRET_SUBS:
        s = pat.sub(rep, s)
    return s


def redact(text: str) -> str:
    """Redact secrets and personal/free-text content, then cap the result.

    This is the ONLY function that may turn raw log text into something safe to
    store or print. It must run before a line is ever written to disk."""
    s = text or ""
    for pat, rep in _SUBS:
        s = pat.sub(rep, s)
    return s[:SAMPLE_MAX]


# --------------------------------------------------------------------------
# Level detection and signature normalization — the digest this tool used to
# get from an external script, now built in code from raw log lines.
# --------------------------------------------------------------------------
_ERROR_TOKEN_RE = re.compile(r"\b(ERROR|ERR|FATAL|CRITICAL|PANIC)\b", re.IGNORECASE)
_WARN_TOKEN_RE = re.compile(r"\b(WARN|WARNING)\b", re.IGNORECASE)
_SOURCE_PREFIX_RE = re.compile(r"^\s*\[([\w][\w.:-]*)\]")
_SOURCE_LOGGER_RE = re.compile(r"\blogger=([\w][\w.:-]*)")
_LEADING_TS_RE = re.compile(
    r"^\[?(?:"
    r"\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:?\d{2})?"
    r"|\d{2}/[A-Za-z]{3}/\d{4}:\d{2}:\d{2}:\d{2}(?:\s[+-]\d{4})?"
    r"|[A-Za-z]{3}\s+\d{1,2}\s\d{2}:\d{2}:\d{2}(?:\s\d{4})?"
    r")\]?\s*"
)
_UUID_RE = re.compile(r"\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\b")
_HEX_RE = re.compile(r"\b[0-9a-fA-F]{8,}\b")
_IPV4_RE = re.compile(r"\b(?:\d{1,3}\.){3}\d{1,3}\b")
_NUM_RE = re.compile(r"\d+")


def _level_from_text(text: str):
    if _ERROR_TOKEN_RE.search(text):
        return "ERROR"
    if _WARN_TOKEN_RE.search(text):
        return "WARN"
    return None


def _extract_source(text: str):
    m = _SOURCE_PREFIX_RE.match(text)
    if m and not _level_from_text(m.group(1)):
        return m.group(1)
    m = _SOURCE_LOGGER_RE.search(text)
    return m.group(1) if m else None


def classify(line: str):
    """Return (level, message, source) for one raw log line; level is None to ignore it.

    Handles a JSON object carrying a level/severity field and a msg/message field
    (structured logging), and a plain-text line carrying a level keyword anywhere
    (bracketed like "[WARN]" or free-standing like "ERROR:"). Anything else is
    ignored — this tool only triages warnings and errors."""
    text = (line or "").rstrip("\n")
    stripped = text.strip()
    if stripped[:1] == "{":
        try:
            data = json.loads(stripped)
        except ValueError:
            data = None
        if isinstance(data, dict):
            msg = data.get("msg", data.get("message"))
            if msg is not None:
                level_raw = data.get("level", data.get("severity"))
                level = _level_from_text(str(level_raw)) if level_raw else None
                if level is None:
                    level = _level_from_text(str(msg))
                source = data.get("component") or data.get("logger") or _extract_source(str(msg))
                # source is attacker-controlled log content same as msg — it is stored
                # and posted to GitHub issues (issue_body's "sources:" line), so it must
                # be redacted here too, not just the message.
                return level, str(msg), redact(source) if source else source
    source = _extract_source(text)
    return _level_from_text(text), text, redact(source) if source else source


def signature(text: str) -> str:
    """Normalize already-redacted text into a stable signature for grouping."""
    s = (text or "").strip()
    s = _LEADING_TS_RE.sub("", s, count=1)
    s = _UUID_RE.sub("<uuid>", s)
    s = _HEX_RE.sub("<hex>", s)
    s = _IPV4_RE.sub("<ip>", s)
    s = _NUM_RE.sub("<n>", s)
    s = re.sub(r"\s+", " ", s).strip()
    return s[:SIGNATURE_MAX]


def build_digest(lines) -> tuple:
    """Turn raw log lines into a redacted, aggregated digest. Raw text never
    leaves this function: only `redact()`'s output is kept in the returned items."""
    agg = {}
    scanned = 0
    for raw in lines:
        if not raw.strip():
            continue
        scanned += 1
        level, msg, source = classify(raw)
        if level is None:
            continue
        redacted = redact(msg)          # REDACT FIRST —
        sig = signature(redacted)       # — then normalize the redacted text
        sid = hashlib.sha1(sig.encode("utf-8")).hexdigest()[:12]
        e = agg.setdefault(sid, {"id": sid, "level": level, "count": 0,
                                  "sources": set(), "sig": sig, "sample": redacted})
        e["count"] += 1
        if source:
            e["sources"].add(source)
    items = [
        {"id": e["id"], "level": e["level"], "count": e["count"],
         "sources": sorted(e["sources"])[:6], "sig": e["sig"], "sample": e["sample"]}
        for e in agg.values()
    ]
    return items, scanned


# --------------------------------------------------------------------------
# Config
# --------------------------------------------------------------------------
def config_path() -> pathlib.Path:
    override = os.environ.get("LANES_CONFIG")
    return pathlib.Path(override) if override else (REPO / ".claude/agent-lanes.json")


def load_config() -> dict:
    p = config_path()
    try:
        return json.loads(p.read_text())
    except OSError as err:
        raise SystemExit(f"[log-triage] FAILED: cannot read config {p}: {err}")
    except ValueError as err:
        raise SystemExit(f"[log-triage] FAILED: {p} is not valid JSON: {err}")


def find_env(config: dict, name: str) -> dict:
    envs = (config.get("deploy") or {}).get("environments") or []
    for e in envs:
        if e.get("name") == name:
            return e
    names = ", ".join(e.get("name", "?") for e in envs) or "(none configured)"
    raise SystemExit(f"[log-triage] FAILED: environment {name!r} not found in "
                      f"deploy.environments (configured: {names})")


def load_baseline() -> dict:
    config = load_config()
    rel = (config.get("logTriage") or {}).get("baselineFile") or ".claude/log-baseline.json"
    p = REPO / rel
    try:
        return json.loads(p.read_text()).get("known", {})
    except OSError as err:
        raise SystemExit(f"[log-triage] FAILED: cannot read baseline {p}: {err}")
    except ValueError as err:
        raise SystemExit(f"[log-triage] FAILED: {p} is not valid JSON: {err}")


def validate_env_name(name: str) -> str:
    if not ENV_NAME_RE.match(name or ""):
        raise SystemExit(f"[log-triage] FAILED: invalid environment name {name!r} "
                          f"(must match {ENV_NAME_RE.pattern})")
    return name


def validate_release(release: str) -> str:
    if not RELEASE_RE.match(release or ""):
        raise SystemExit(f"[log-triage] FAILED: invalid release id {release!r} "
                          f"(must match {RELEASE_RE.pattern})")
    return release


def rdir(release: str) -> pathlib.Path:
    validate_release(release)
    d = STATE / release
    d.mkdir(parents=True, exist_ok=True)
    return d


# --------------------------------------------------------------------------
# capture
# --------------------------------------------------------------------------
def run_capture(env_name: str, phase: str, release: str, since_minutes: int) -> int:
    validate_env_name(env_name)
    validate_release(release)
    config = load_config()
    entry = find_env(config, env_name)
    default_since = entry.get("logWindowBeforeMinutes" if phase == "before" else "logWindowAfterMinutes")
    since = since_minutes or default_since or (1440 if phase == "before" else 30)
    cmd_template = entry.get("logs")
    if not cmd_template or not str(cmd_template).strip():
        print(f"[log-triage] FAILED capture {phase} {env_name}: "
              f"deploy.environments[name={env_name!r}].logs is empty or missing in "
              f"{config_path()}; set it to a shell command that prints raw log lines to stdout",
              file=sys.stderr)
        return 2
    cmd = str(cmd_template).replace("{since_minutes}", str(int(since))).replace("{env}", env_name)
    try:
        proc = subprocess.run(["bash", "-c", cmd], cwd=REPO, capture_output=True, text=True, timeout=1200)
    except subprocess.TimeoutExpired as err:
        print(f"[log-triage] FAILED capture {phase} {env_name}: command timed out: "
              f"{redact_secrets(str(err))[:1500]}", file=sys.stderr)
        return 2
    if proc.returncode != 0:
        # STDOUT is raw, unredacted log output — never print it, even truncated.
        # Only stderr (the command's own diagnostic output, not log content) is
        # shown, and it still goes through the full redact() (not just
        # redact_secrets()): stderr can echo back log lines too (e.g. a shell
        # trace of the failing pipeline), so personal/free-text content must be
        # stripped from it exactly as it would be from a successful capture.
        print(f"[log-triage] FAILED capture {phase} {env_name}: logs command exited "
              f"{proc.returncode}. A non-zero exit is always treated as a failed capture — "
              f"e.g. a `... | grep ERROR` pipeline exits 1 when nothing matches, so write "
              f"`grep ... || true` if \"no matches\" is a valid, successful outcome.\n"
              f"stderr: {redact(proc.stderr or '')[:1500] or '(empty)'}",
              file=sys.stderr)
        return 2
    items, scanned = build_digest(proc.stdout.splitlines())
    data = {"env": env_name, "phase": phase, "window_min": since, "scanned": scanned, "items": items}
    out = rdir(release) / f"{env_name}-{phase}.json"
    out.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n")
    lv = {}
    for e in items:
        lv[e["level"]] = lv.get(e["level"], 0) + e["count"]
    print(f"[log-triage] {phase} {env_name}: {len(items)} signature(s) {json.dumps(lv)} "
          f"over {since}m, scanned={scanned} -> {out}")
    return 0


def cmd_capture(a) -> int:
    return run_capture(a.env, a.phase, a.release, a.since_minutes)


# --------------------------------------------------------------------------
# analyse / report
# --------------------------------------------------------------------------
def load_release(release: str) -> dict:
    caps = {}
    for f in sorted(rdir(release).glob("*-*.json")):
        d = json.loads(f.read_text())
        caps[(d["env"], d["phase"])] = d
    if not caps:
        raise SystemExit(f"[log-triage] no captures for {release} under {STATE / release}")
    return caps


def analyse(release: str) -> list:
    caps, known = load_release(release), load_baseline()
    envs = sorted({e for e, _ in caps})
    sigs = {}
    for (env, phase), d in caps.items():
        for e in d["items"]:
            s = sigs.setdefault(e["id"], {**{k: e[k] for k in ("id", "level", "sig", "sample")},
                                          "sources": set(), "counts": {}})
            s["sources"].update(e["sources"])
            s["counts"][(env, phase)] = e["count"]
    rows = []
    for s in sigs.values():
        in_before = any(p == "before" and n for (e, p), n in s["counts"].items())
        after_envs = {e for (e, p), n in s["counts"].items() if p == "after" and n}
        # measured on at least ONE environment that has a BEFORE; un-captured
        # environments only add "not captured" cells, they must never demote a
        # measured regression
        measured = any((e, "before") in caps for e in after_envs)
        if s["id"] in known:
            verdict = "BASELINED"
        elif in_before:
            verdict = "PRE-EXISTING"
        elif measured:
            verdict = "RELEASE-SUSPECT"
        else:
            verdict = "UNATTRIBUTED"
        s.update(verdict=verdict, envs=envs, sources=sorted(s["sources"]),
                  windows={k: caps[k]["window_min"] for k in caps})
        rows.append(s)
    order = {"RELEASE-SUSPECT": 0, "UNATTRIBUTED": 1, "PRE-EXISTING": 2, "BASELINED": 3}
    rows.sort(key=lambda r: (order[r["verdict"]], r["level"] != "ERROR",
                             -sum(r["counts"].values())))
    return rows


def freq_cell(r, env, phase):
    if (env, phase) not in r["windows"]:
        return "not captured"
    return f"{r['counts'].get((env, phase), 0)}/{r['windows'][(env, phase)]}m"


def literal(r) -> str:
    """Longest placeholder-free literal run of the (redacted) signature."""
    parts = re.split(r"<[a-z-]+(?::[a-z-]+)?>|\[REDACTED:[A-Z_]+\]", r["sig"])
    runs = [m for p in parts for m in re.findall(r"[A-Za-z][A-Za-z .,:'_/-]{15,}", p)]
    return max(runs or [""], key=len).strip()


def emitter(r) -> str:
    frag = literal(r)
    if not frag:
        return "unknown (no literal fragment to search)"
    config = load_config()
    paths = (config.get("logTriage") or {}).get("emitterPaths") or ["src", "scripts"]
    p = subprocess.run(["git", "-C", str(REPO), "grep", "-n", "-F", frag, "--", *paths],
                       capture_output=True, text=True)
    hits = [h for h in p.stdout.splitlines()
            if not re.search(r"(^|/)tests?/|\.test\.|_test\.|test_", h.split(":", 1)[0])]
    return ":".join(hits[0].split(":", 2)[:2]) if hits else "not in this repo — likely a dependency"


def journal_history(r) -> str:
    frag = literal(r)
    config = load_config()
    journal_dir = REPO / ((config.get("deploy") or {}).get("journalDir") or "docs/deployments")
    if not frag or not journal_dir.is_dir():
        return "n/a (no literal fragment to search)"
    p = subprocess.run(["grep", "-rlF", frag[:60], str(journal_dir)], capture_output=True, text=True)
    return str(len(p.stdout.splitlines()))


def cmd_report(a) -> int:
    rows = analyse(a.release)
    envs = rows[0]["envs"] if rows else []
    print("| verdict | level | id | signature | " + " | ".join(f"{e} before / after" for e in envs) + " |")
    print("|---|---|---|---|" + "---|" * len(envs))
    for r in rows:
        if r["verdict"] == "BASELINED" and not a.all:
            continue
        cells = " | ".join(f"{freq_cell(r, e, 'before')} / {freq_cell(r, e, 'after')}" for e in envs)
        print(f"| {r['verdict']} | {r['level']} | `{r['id']}` | {r['sig'][:90].replace('|', '/')} | {cells} |")
    n = {v: sum(1 for r in rows if r["verdict"] == v)
         for v in ("RELEASE-SUSPECT", "UNATTRIBUTED", "PRE-EXISTING", "BASELINED")}
    print(f"\n[log-triage] {a.release}: {json.dumps(n)}")
    return 1 if n["RELEASE-SUSPECT"] else 0


# --------------------------------------------------------------------------
# file (GitHub issue filing)
# --------------------------------------------------------------------------
def release_marker(release: str) -> str:
    """Written into every body and comment this tool posts for a release; its
    presence anywhere on an issue means that release is already reported there."""
    return f"log-triage release `{release}`"


def issue_body(r, release) -> str:
    rows = "\n".join(f"| {e} | {freq_cell(r, e, 'before')} | {freq_cell(r, e, 'after')} |" for e in r["envs"])
    why = {"RELEASE-SUSPECT": "seen AFTER the deploy and in NO environment's BEFORE capture",
           "UNATTRIBUTED": "seen AFTER the deploy on an environment with no BEFORE capture, "
                           "so the release cannot be ruled in or out",
           "PRE-EXISTING": "already present BEFORE the deploy"}[r["verdict"]]
    return f"""<!-- log-sig:{r['id']} -->
Filed by `scripts/dev/board/log-triage.py` (deterministic, no LLM; text redacted in code), {release_marker(release)}.

**Signature** ({r['level']}, `{r['id']}`), sources: {', '.join(r['sources']) or '?'}
```
{r['sig']}
```
**Verdict:** {r['verdict']}: {why}.

**Frequency** (count / capture window):

| environment | before | after |
|---|---|---|
{rows}

**Sample (redacted):**
```
{r['sample']}
```
**Emitter:** {emitter(r)}
**Journal history:** {journal_history(r)} earlier deployment journal(s) contain its literal text.

To close: fix the emitter or its cause. If it is proven benign, add it to the baseline file
(`logTriage.baselineFile` in `.claude/agent-lanes.json`) with a note saying why, in a reviewed PR.
"""


def gh(*args, input_text=None) -> subprocess.CompletedProcess:
    return subprocess.run(["gh", *args], capture_output=True, text=True, input=input_text)


def open_markers() -> dict:
    """{sig id: issue number} for every open issue carrying a log-sig marker.
    One paginated REST call: per-signature search hits the GraphQL rate limit."""
    # every open issue, not just label log-triage: a human-split issue that carries the
    # marker must be found too, or the tool re-files it
    p = gh("api", "-X", "GET", "repos/{owner}/{repo}/issues", "-f", "state=open",
           "-f", "per_page=100", "--paginate",
           "--jq", '.[] | select(.pull_request == null) | "\\(.number) '
                   '\\([(.body // "") | scan("log-sig:([0-9a-f]{12})")[]] | join(","))"')
    if p.returncode != 0:
        raise SystemExit(f"[log-triage] FAILED: listing log-triage issues: {p.stderr.strip()[:300]}")
    found = {}
    for line in p.stdout.splitlines():
        num, _, ids = line.partition(" ")
        for sig_id in filter(None, ids.split(",")):
            found.setdefault(sig_id, num)
    return found


def rollup_body(rows, release) -> str:
    """One P3 issue per release for every non-suspect signature nobody tracks yet.
    Each row carries its log-sig marker, so a later release comments here instead of re-filing."""
    envs = rows[0]["envs"] if rows else []
    head = "| verdict | level | id | signature | emitter | journals | " + \
           " | ".join(f"{e} before / after" for e in envs) + " |"
    sep = "|---|---|---|---|---|---|" + "---|" * len(envs)
    lines = [head, sep]
    for r in rows:
        cells = " | ".join(f"{freq_cell(r, e, 'before')} / {freq_cell(r, e, 'after')}" for e in envs)
        lines.append(f"| {r['verdict']} | {r['level']} | `{r['id']}` | "
                     f"{r['sig'][:110].replace('|', '/')} | {emitter(r)} | {journal_history(r)} | {cells} |")
    markers = "\n".join(f"<!-- log-sig:{r['id']} -->" for r in rows)
    return f"""{markers}
Filed by `scripts/dev/board/log-triage.py` (deterministic, no LLM; text redacted in code), {release_marker(release)}.

Warn/error signatures that were **not introduced by this release** (PRE-EXISTING), or that
could not be attributed because an environment had no BEFORE capture (UNATTRIBUTED), and that
no open issue tracks yet. Counts are `count / capture window`.

{chr(10).join(lines)}

To work one: split it into its own `lane:bug` issue that carries its `log-sig:<id>` marker (the
tool then comments there instead of here), fix the emitter or cause, or prove it benign and add
it to the baseline file with a note, in a reviewed PR.
"""


def already_reported(num: str, marker: str) -> bool:
    # the issue BODY counts too: an issue this tool created for the release carries the
    # marker there, and a re-run must not comment on its own fresh issue
    for path, jq in ((f"repos/{{owner}}/{{repo}}/issues/{num}", ".body // \"\""),
                     (f"repos/{{owner}}/{{repo}}/issues/{num}/comments", ".[].body")):
        p = gh("api", path, "--paginate", "--jq", jq)
        if p.returncode != 0:
            raise SystemExit(f"[log-triage] FAILED: reading #{num}: {p.stderr.strip()[:300]}")
        if marker in p.stdout:
            return True
    return False


def find_rollup(release: str):
    title = f"[log-triage] {release}:"
    p = gh("api", "-X", "GET", "repos/{owner}/{repo}/issues", "-f", "state=all",
           "-f", "labels=log-triage", "-f", "per_page=100", "--paginate",
           "--jq", '.[] | "\\(.number)\\t\\(.title)"')
    if p.returncode != 0:
        raise SystemExit(f"[log-triage] FAILED: listing rollups: {p.stderr.strip()[:300]}")
    for line in p.stdout.splitlines():
        num, _, t = line.partition("\t")
        if t.startswith(title):
            return num
    return None


def cmd_file(a) -> int:
    rows = [r for r in analyse(a.release) if r["verdict"] != "BASELINED"]
    markers = open_markers()
    tracked, suspects, rollup = {}, [], []
    for r in rows:
        if r["id"] in markers:
            tracked.setdefault(markers[r["id"]], []).append(r)
        elif r["verdict"] == "RELEASE-SUSPECT":
            suspects.append(r)
        else:
            rollup.append(r)
    rollup = suspects[a.max_new:] + rollup   # overflow is filed in the rollup, never dropped
    marker = release_marker(a.release)
    plan = []
    for num, rs in tracked.items():
        if already_reported(num, marker):
            print(f"   already  #{num:>5}  reported for {a.release}; not commenting again")
            continue
        plan.append(("comment", num, rs))
    plan += [("create-P2", None, [r]) for r in suspects[:a.max_new]]
    if rollup:
        existing = find_rollup(a.release)
        plan += [("exists", existing, rollup)] if existing else [("rollup-P3", None, rollup)]
    for kind, num, rs in plan:
        what = f"#{num}" if num else ""
        print(f"{kind:>10} {what:>6}  {len(rs)} signature(s): " + ", ".join(r["id"] for r in rs[:6])
              + (" ..." if len(rs) > 6 else ""))
    if not a.apply:
        print("\n[log-triage] dry run: pass --apply to file.")
        return 0
    gh("label", "create", "log-triage", "--color", "BFD4F2",
       "--description", "Filed by scripts/dev/board/log-triage.py", "--force")
    common = ["--label", "bug", "--label", "lane:bug", "--label", "state:backlog", "--label", "log-triage"]
    for kind, num, rs in plan:
        if kind == "exists":
            print(f"  rollup for {a.release} already filed as #{num}; not re-filing")
            continue
        if kind == "comment":
            body = f"Seen again ({marker}):\n\n" + "\n\n---\n\n".join(issue_body(r, a.release) for r in rs)
            p = gh("issue", "comment", num, "--body-file", "-", input_text=body)
        elif kind == "create-P2":
            r = rs[0]
            p = gh("issue", "create", "--title", f"[log-triage] {r['level']} {r['sig'][:80]}",
                   "--label", "P2", *common, "--body-file", "-", input_text=issue_body(r, a.release))
        else:
            p = gh("issue", "create", "--title",
                   f"[log-triage] {a.release}: {len(rs)} pre-existing/unattributed warn/error signatures (rollup)",
                   "--label", "P3", *common, "--body-file", "-", input_text=rollup_body(rs, a.release))
        if p.returncode != 0:
            print(f"[log-triage] FAILED {kind} {num or ''}: {p.stderr.strip()[:300]}", file=sys.stderr)
            return 2
        print(f"  {kind} -> {p.stdout.strip()}")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(prog="log-triage.py", description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    c = sub.add_parser("capture")
    c.add_argument("phase", choices=["before", "after"])
    c.add_argument("env")
    c.add_argument("--release", required=True)
    c.add_argument("--since-minutes", type=int)
    r = sub.add_parser("report")
    r.add_argument("release")
    r.add_argument("--all", action="store_true")
    f = sub.add_parser("file")
    f.add_argument("release")
    f.add_argument("--apply", action="store_true")
    f.add_argument("--max-new", type=int, default=15)
    a = ap.parse_args()
    validate_release(a.release)
    if a.cmd == "capture":
        validate_env_name(a.env)
    return {"capture": cmd_capture, "report": cmd_report, "file": cmd_file}[a.cmd](a)


if __name__ == "__main__":
    sys.exit(main())
