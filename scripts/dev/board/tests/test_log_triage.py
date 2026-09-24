"""Unit tests for scripts/dev/board/log-triage.py.

No network access, no real `gh` calls (a fake `gh` on PATH is used where a test
exercises the filing path), everything under a temp state/config directory.
Runnable directly: `python3 scripts/dev/board/tests/test_log_triage.py`
"""
import importlib.util
import json
import os
import pathlib
import subprocess
import sys
import tempfile
import unittest

HERE = pathlib.Path(__file__).resolve().parent
TOOL = HERE.parent / "log-triage.py"
spec = importlib.util.spec_from_file_location("log_triage", TOOL)
lt = importlib.util.module_from_spec(spec)
spec.loader.exec_module(lt)


# Fictional secret shapes built by concatenation, never written as a literal
# recognizable secret prefix in this source file (the repo's pre-commit hook
# blocks lines containing several vendor key prefixes verbatim, an AWS key id,
# a full SendGrid key, or a PEM header -- see scripts/precommit-secret-patterns.sh).
SECRET_LINES = {
    "sk-" + "ant-" + "api03-" + "A" * 90: "ANTHROPIC_KEY",
    "xox" + "b-" + "1111111111-2222222222-" + "b" * 24: "SLACK_BOT_TOKEN",
    "Authorization: Bearer " + "c" * 64: "BEARER_TOKEN",
    "gh" + "p_" + "d" * 36: "GITHUB_TOKEN",
    "postgresql://app_user:hunter2hunter2@db-host:5432/appdb": "URL_PASSWORD",
    "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxIn0.sig_part-123": "JWT",
    "AKIA" + "ABCDEFGHIJ0123456": "AWS_KEY_ID",
}


# Common credential-name shapes with SHORT values (well under the old 20-char
# floor). None of these are pre-commit-blocked literal prefixes.
# (full URL, scheme, secret, host-and-rest) — kept explicit rather than parsed
# back out of the URL, since ":" and "@" appear in more than one place.
URL_CREDENTIAL_LINES = [
    ("mysql://dbuser:" + "s3cr3t" + "@dbhost:3306/app", "mysql", "s3cr3t", "dbhost:3306/app"),
    ("redis://:" + "hunter2" + "@redis-host:6379", "redis", "hunter2", "redis-host:6379"),
    ("amqp://guest:" + "guestpw" + "@rabbit:5672/", "amqp", "guestpw", "rabbit:5672/"),
    ("mongodb://appuser:" + "m0ngoPW" + "@cluster0.example.net", "mongodb", "m0ngoPW", "cluster0.example.net"),
    ("https://svc-user:" + "httpsecret" + "@example.com/path", "https", "httpsecret", "example.com/path"),
]

SHORT_KV_CREDENTIAL_LINES = [
    "password=" + "hunter2",
    "password: " + "hunter2",
    "passwd=" + "abc123",
    "pwd=" + "abc123",
    "secret=" + "abc123",
    "token=" + "abc123",
    "api_key=" + "abc123",
    "apikey=" + "abc123",
    "access_token=" + "abc123",
    "refresh_token=" + "abc123",
    "client_secret=" + "abc123",
    "auth=" + "abc123",
    "private_key=" + "abc123",
]


class RedactTest(unittest.TestCase):
    def test_every_secret_shape_is_replaced(self):
        for line, label in SECRET_LINES.items():
            out = lt.redact(f"prefix {line} suffix")
            self.assertIn(f"[REDACTED:{label}]", out, line[:20])

    def test_url_userinfo_password_redacted_for_any_scheme(self):
        for line, scheme, secret, host in URL_CREDENTIAL_LINES:
            out = lt.redact(f"connecting to {line} now")
            self.assertNotIn(secret, out, line)
            self.assertIn(scheme + "://", out, line)
            self.assertIn(host, out, line)
            self.assertIn("[REDACTED", out, line)

    def test_short_key_value_credentials_are_redacted(self):
        for line in SHORT_KV_CREDENTIAL_LINES:
            key, _, value = line.partition("=") if "=" in line else line.partition(": ")
            out = lt.redact(f"config dump {line} trailing")
            self.assertNotIn(value.strip(), out, line)
            self.assertIn("[REDACTED", out, line)

    def test_authorization_basic_header_is_redacted(self):
        out = lt.redact("Authorization: Basic " + "dXNlcjpwYXNzd29yZA==")
        self.assertNotIn("dXNlcjpwYXNzd29yZA==", out)
        self.assertIn("[REDACTED", out)

    def test_authorization_any_value_is_redacted(self):
        out = lt.redact("Authorization: CustomScheme " + "opaque-value-123")
        self.assertNotIn("opaque-value-123", out)
        self.assertIn("[REDACTED", out)

    def test_standalone_basic_auth_value_is_redacted(self):
        out = lt.redact("saw header value Basic " + "dXNlcjpwYXNzd29yZA==" + " in request")
        self.assertNotIn("dXNlcjpwYXNzd29yZA==", out)
        self.assertIn("[REDACTED", out)

    def test_dash_style_credential_headers_are_redacted(self):
        for line, secret in (
            ("X-Api-Key: " + "9f8e7d6c5b4a", "9f8e7d6c5b4a"),
            ("X-Auth-Token: " + "abc123", "abc123"),
            ("X-Client-Secret: " + "xyz789", "xyz789"),
        ):
            out = lt.redact(line)
            self.assertNotIn(secret, out, line)
            self.assertIn("[REDACTED", out, line)

    def test_redact_secrets_only_handles_secret_shapes(self):
        out = lt.redact_secrets("token=" + "sk-" + "ant-" + "Z" * 40)
        self.assertNotIn("Z" * 20, out)
        # personal data is NOT touched by redact_secrets (only by redact)
        self.assertIn("jane.doe@example.com", lt.redact_secrets("contact jane.doe@example.com"))

    def test_secret_at_long_length_is_still_redacted(self):
        out = lt.redact("key=" + "sk-" + "ant-" + "Z" * 200)
        self.assertNotIn("Z" * 20, out)

    def test_personal_data(self):
        out = lt.redact("sent to jane.doe@example.com and +1 (555) 010-2233 "
                        "path /Users/u_4f2a/profile.md slack U0ABCDEF12")
        for leak in ("jane.doe", "555", "u_4f2a", "U0ABCDEF12"):
            self.assertNotIn(leak, out)
        self.assertIn("Users/<user>", out)

    def test_agent_written_text_is_dropped(self):
        out = lt.redact('[tools] tool_call failed: Provide a command to start. '
                        'raw_params={"id":"exec","args":{"cmd":"echo my private note"}}')
        self.assertNotIn("private note", out)
        self.assertIn("raw_params=<redacted:tool-args>", out)
        out2 = lt.redact('{"message":"please summarize my medical records for tomorrow","level":"warn"}')
        self.assertNotIn("medical", out2)

    def test_diagnostic_words_and_ip_survive_redact(self):
        for word in ("UNAUTHORIZED", "UNAVAILABLE", "WEBSOCKET", "WORKSPACE", "192.168.1.100",
                     "task-scheduler-fire-failed-retrying"):
            self.assertIn(word, lt.redact(f"[WARN] fetch failed {word} after retry"), word)

    def test_diagnostic_text_survives_untouched(self):
        line = "dispatch-notify: send-hook.js not found, skipping agent notification"
        self.assertEqual(lt.redact(line), line)

    def test_output_is_capped(self):
        self.assertLessEqual(len(lt.redact("x " * 1000)), lt.SAMPLE_MAX)


class ClassifyAndSignatureTest(unittest.TestCase):
    def test_level_detection_error_and_warn_tokens(self):
        for word in ("ERROR", "ERR", "FATAL", "CRITICAL", "PANIC"):
            self.assertEqual(lt.classify(f"[{word}] something broke")[0], "ERROR", word)
        for word in ("WARN", "WARNING"):
            self.assertEqual(lt.classify(f"[{word}] something is off")[0], "WARN", word)

    def test_lines_with_neither_are_ignored(self):
        level, _, _ = lt.classify("[INFO] server started on port 8080")
        self.assertIsNone(level)

    def test_json_line_with_level_and_msg_fields(self):
        line = json.dumps({"level": "error", "msg": "connection refused to backend"})
        level, msg, _ = lt.classify(line)
        self.assertEqual(level, "ERROR")
        self.assertEqual(msg, "connection refused to backend")

    def test_json_line_with_severity_and_message_fields(self):
        line = json.dumps({"severity": "warn", "message": "retrying request"})
        level, msg, _ = lt.classify(line)
        self.assertEqual(level, "WARN")
        self.assertEqual(msg, "retrying request")

    def test_source_extracted_from_bracket_prefix(self):
        _, _, source = lt.classify("[payments] ERROR charge failed")
        self.assertEqual(source, "payments")

    def test_level_bracket_itself_is_not_mistaken_for_a_source(self):
        _, _, source = lt.classify("[ERROR] fail for someone")
        self.assertIsNone(source)

    def test_signature_ignores_numbers_uuids_and_leading_timestamps(self):
        line1 = ("2024-01-02T03:04:05Z [ERROR] request 12345 failed for id="
                 "550e8400-e29b-41d4-a716-446655440000 after 3 retries")
        line2 = ("2024-06-07T08:09:10Z [ERROR] request 99999 failed for id="
                 "6ba7b810-9dad-11d1-80b4-00c04fd430c8 after 9 retries")
        sig1 = lt.signature(lt.redact(lt.classify(line1)[1]))
        sig2 = lt.signature(lt.redact(lt.classify(line2)[1]))
        self.assertEqual(sig1, sig2)
        id1 = __import__("hashlib").sha1(sig1.encode()).hexdigest()[:12]
        id2 = __import__("hashlib").sha1(sig2.encode()).hexdigest()[:12]
        self.assertEqual(id1, id2)

    def test_signature_still_differs_for_different_diagnostic_text(self):
        sig1 = lt.signature(lt.redact(lt.classify("[ERROR] disk full on /data")[1]))
        sig2 = lt.signature(lt.redact(lt.classify("[ERROR] connection refused")[1]))
        self.assertNotEqual(sig1, sig2)

    def test_hex_run_is_normalized(self):
        sig = lt.signature("commit deadbeefcafe0123 failed")
        self.assertIn("<hex>", sig)

    def test_ipv4_is_normalized(self):
        sig = lt.signature("connect to 10.0.0.42 failed")
        self.assertIn("<ip>", sig)

    def test_json_source_field_is_redacted(self):
        line = json.dumps({"level": "error", "msg": "boom", "component": "jane.doe@example.com"})
        _, _, source = lt.classify(line)
        self.assertNotIn("jane.doe", source or "")

    def test_build_digest_never_stores_raw_source(self):
        line = json.dumps({"level": "warn", "msg": "slow query", "logger": "token=" + "abc123xyz"})
        items, _ = lt.build_digest([line])
        self.assertTrue(items)
        for src in items[0]["sources"]:
            self.assertNotIn("abc123xyz", src)


def cap(env, phase, items, window):
    return {"env": env, "phase": phase, "window_min": window, "scanned": 100, "items": items}


def item(i, n, sig="warn thing happened", level="WARN"):
    return {"id": i, "level": level, "count": n, "sources": ["gateway"], "sig": sig, "sample": sig}


class AnalyseTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        lt.STATE = pathlib.Path(self.tmp.name)
        d = lt.rdir("abc1234")
        caps = [
            cap("staging", "before", [item("aaaaaaaaaaaa", 45), item("baselined000", 3)], 1440),
            cap("staging", "after", [item("aaaaaaaaaaaa", 2), item("newnewnewnew", 4, level="ERROR")], 30),
            cap("production", "before", [], 1440),
            cap("production", "after", [item("newnewnewnew", 1, level="ERROR")], 30),
        ]
        for c in caps:
            (d / f"{c['env']}-{c['phase']}.json").write_text(json.dumps(c))
        lt.load_baseline = lambda: {"baselined000": {"note": "proven benign"}}

    def tearDown(self):
        self.tmp.cleanup()

    def test_verdicts_including_unattributed_and_baselined(self):
        v = {r["id"]: r["verdict"] for r in lt.analyse("abc1234")}
        self.assertEqual(v, {"newnewnewnew": "RELEASE-SUSPECT",
                             "aaaaaaaaaaaa": "PRE-EXISTING",
                             "baselined000": "BASELINED"})

    def test_suspect_sorted_first_and_frequency_cells(self):
        rows = lt.analyse("abc1234")
        self.assertEqual(rows[0]["id"], "newnewnewnew")
        pre = next(r for r in rows if r["id"] == "aaaaaaaaaaaa")
        self.assertEqual(lt.freq_cell(pre, "staging", "before"), "45/1440m")
        self.assertEqual(lt.freq_cell(pre, "production", "after"), "0/30m")

    def test_no_before_capture_is_unattributed_not_suspect(self):
        d = lt.rdir("abc1234")
        (d / "preview-after.json").write_text(json.dumps(cap("preview", "after", [item("previewonly0", 3)], 30)))
        v = {r["id"]: r["verdict"] for r in lt.analyse("abc1234")}
        self.assertEqual(v["previewonly0"], "UNATTRIBUTED")

    def test_one_uncaptured_env_does_not_demote_a_measured_regression(self):
        d = lt.rdir("abc1234")
        (d / "preview-after.json").write_text(
            json.dumps(cap("preview", "after", [item("newnewnewnew", 7, level="ERROR")], 30)))
        v = {r["id"]: r["verdict"] for r in lt.analyse("abc1234")}
        self.assertEqual(v["newnewnewnew"], "RELEASE-SUSPECT")

    def test_suspect_needs_absence_in_every_before(self):
        d = lt.rdir("abc1234")
        (d / "preview-before.json").write_text(
            json.dumps(cap("preview", "before", [item("newnewnewnew", 1)], 1440)))
        v = {r["id"]: r["verdict"] for r in lt.analyse("abc1234")}
        self.assertEqual(v["newnewnewnew"], "PRE-EXISTING")


class ReleaseValidationTest(unittest.TestCase):
    def test_rejects_path_traversal(self):
        with self.assertRaises(SystemExit):
            lt.validate_release("../x")
        with self.assertRaises(SystemExit):
            lt.rdir("../x")

    def test_accepts_short_and_full_sha(self):
        self.assertEqual(lt.validate_release("abc1234"), "abc1234")
        self.assertEqual(lt.validate_release("a" * 40), "a" * 40)

    def test_env_name_validation(self):
        with self.assertRaises(SystemExit):
            lt.validate_env_name("Bad Name!")
        self.assertEqual(lt.validate_env_name("staging-2"), "staging-2")


def write_config(root: pathlib.Path, logs_cmd: str, since_before=1440, since_after=30) -> pathlib.Path:
    cfg = {
        "deploy": {
            "journalDir": "docs/deployments",
            "environments": [
                {"name": "staging", "logs": logs_cmd,
                 "logWindowBeforeMinutes": since_before, "logWindowAfterMinutes": since_after}
            ],
        },
        "logTriage": {"baselineFile": ".claude/log-baseline.json", "emitterPaths": ["src", "scripts"]},
    }
    p = root / "agent-lanes.json"
    p.write_text(json.dumps(cfg))
    return p


class CaptureNeverStoresRawTest(unittest.TestCase):
    def test_capture_writes_only_redacted_text(self):
        with tempfile.TemporaryDirectory() as t:
            root = pathlib.Path(t)
            fake_email = "jane.doe@example.com"
            fake_token = "sk-" + "ant-" + "Q" * 40
            logs_cmd = (
                "printf '%s\\n' "
                f"'[ERROR] fail for {fake_email} token {fake_token}'"
            )
            cfg = write_config(root, logs_cmd)
            state = root / "state"
            env = dict(os.environ, LANES_CONFIG=str(cfg), LOG_TRIAGE_STATE=str(state))
            out = subprocess.run(
                [sys.executable, str(TOOL), "capture", "after", "staging",
                 "--release", "abc1234", "--since-minutes", "5"],
                env=env, capture_output=True, text=True)
            self.assertEqual(out.returncode, 0, out.stderr)
            text = (state / "abc1234" / "staging-after.json").read_text()
            self.assertNotIn(fake_email, text)
            self.assertNotIn("Q" * 20, text)
            self.assertNotIn(fake_token, text)

    def test_failing_logs_command_exits_2_and_writes_nothing(self):
        with tempfile.TemporaryDirectory() as t:
            root = pathlib.Path(t)
            cfg = write_config(root, "exit 7")
            state = root / "state"
            env = dict(os.environ, LANES_CONFIG=str(cfg), LOG_TRIAGE_STATE=str(state))
            out = subprocess.run(
                [sys.executable, str(TOOL), "capture", "before", "staging", "--release", "abc1234"],
                env=env, capture_output=True, text=True)
            self.assertEqual(out.returncode, 2)
            self.assertIn("FAILED capture", out.stderr)
            self.assertFalse((state / "abc1234").exists() and
                             any((state / "abc1234").iterdir()) if (state / "abc1234").exists() else False)

    def test_failure_message_prints_only_stderr_not_raw_stdout(self):
        with tempfile.TemporaryDirectory() as t:
            root = pathlib.Path(t)
            logs_cmd = "printf '%s\\n' 'RAW-LOG-LINE-SHOULD-NOT-LEAK' >&1; printf boom-stderr >&2; exit 3"
            cfg = write_config(root, logs_cmd)
            state = root / "state"
            env = dict(os.environ, LANES_CONFIG=str(cfg), LOG_TRIAGE_STATE=str(state))
            out = subprocess.run(
                [sys.executable, str(TOOL), "capture", "before", "staging", "--release", "abc1234"],
                env=env, capture_output=True, text=True)
            self.assertEqual(out.returncode, 2)
            self.assertNotIn("RAW-LOG-LINE-SHOULD-NOT-LEAK", out.stderr)
            self.assertIn("boom-stderr", out.stderr)

    def test_failure_message_stderr_is_fully_redacted(self):
        with tempfile.TemporaryDirectory() as t:
            root = pathlib.Path(t)
            logs_cmd = "printf 'contact jane.doe@example.com token=%s' 'abc123xyz' >&2; exit 5"
            cfg = write_config(root, logs_cmd)
            state = root / "state"
            env = dict(os.environ, LANES_CONFIG=str(cfg), LOG_TRIAGE_STATE=str(state))
            out = subprocess.run(
                [sys.executable, str(TOOL), "capture", "before", "staging", "--release", "abc1234"],
                env=env, capture_output=True, text=True)
            self.assertEqual(out.returncode, 2)
            self.assertNotIn("jane.doe@example.com", out.stderr)
            self.assertNotIn("abc123xyz", out.stderr)

    def test_empty_logs_command_exits_2_naming_the_field(self):
        with tempfile.TemporaryDirectory() as t:
            root = pathlib.Path(t)
            cfg = write_config(root, "")
            state = root / "state"
            env = dict(os.environ, LANES_CONFIG=str(cfg), LOG_TRIAGE_STATE=str(state))
            out = subprocess.run(
                [sys.executable, str(TOOL), "capture", "before", "staging", "--release", "abc1234"],
                env=env, capture_output=True, text=True)
            self.assertEqual(out.returncode, 2)
            self.assertIn("logs", out.stderr)
            self.assertFalse((state / "abc1234").exists())


class FileDryRunTest(unittest.TestCase):
    def test_dry_run_plans_create_and_comment_without_calling_gh(self):
        with tempfile.TemporaryDirectory() as t:
            bindir = pathlib.Path(t) / "bin"
            bindir.mkdir()
            log = pathlib.Path(t) / "gh.log"
            gh = bindir / "gh"
            # existing issue only for the pre-existing signature
            gh.write_text("#!/bin/sh\necho \"$@\" >> " + str(log) + "\n"
                          "case \"$*\" in *comments*) ;; *state=all*) ;; api*) echo '77 aaaaaaaaaaaa';; esac\n")
            gh.chmod(0o755)
            state = pathlib.Path(t) / "s"
            env = dict(os.environ, PATH=f"{bindir}:{os.environ['PATH']}", LOG_TRIAGE_STATE=str(state))
            d = state / "def4567"
            d.mkdir(parents=True)
            (d / "staging-before.json").write_text(json.dumps(cap("staging", "before", [item("aaaaaaaaaaaa", 9)], 1440)))
            (d / "staging-after.json").write_text(
                json.dumps(cap("staging", "after", [item("aaaaaaaaaaaa", 1), item("bbbbbbbbbbbb", 2)], 30)))
            out = subprocess.run([sys.executable, str(TOOL), "file", "def4567"], env=env, capture_output=True, text=True)
            self.assertEqual(out.returncode, 0, out.stderr)
            self.assertRegex(out.stdout, r"comment\s+#77\s+1 signature")
            self.assertIn("create-P2", out.stdout)
            self.assertIn("dry run", out.stdout)
            calls = log.read_text() if log.exists() else ""
            self.assertNotIn("issue create", calls)
            self.assertNotIn("issue comment", calls)


class MutationCheckHelpersTest(unittest.TestCase):
    """Not a real test class -- see the report for how these were used to
    confirm the verdict logic and the redact-before-storage invariant are
    actually exercised by the suite above (both were manually broken and
    the affected test above was confirmed to fail, then restored)."""


if __name__ == "__main__":
    unittest.main()
