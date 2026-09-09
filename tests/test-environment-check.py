import copy
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("environment_check", ROOT / "scripts/environment-check.py")
checker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(checker)


def healthy(argv, root):
    versions = {"git": "git version 2.50.1 (Apple Git-155)",
                "bash": "GNU bash, version 3.2.57(1)-release",
                "node": "v25.8.0", sys.executable: "Python 3.12.14"}
    return "ok", "pmai-node-hooks-ok" if "-e" in argv else versions[argv[0]]


class EnvironmentTests(unittest.TestCase):
    def test_version_boundaries_include_major_only_constraints(self):
        for actual, rule, expected in [
            ("v25.8.0", ">=24,<25", False), ("v24.1.0", ">=24,<25", True),
            ("Python 3.13.0", ">=3.10,<3.13", False),
            ("Python 3.9.6", ">=3.10", False),
            ("git version 2.30.0.windows.1", ">=2.30", True),
            ("GNU bash, version 3.2.57(1)-release", ">=3.2", True),
            ("Python 3.15.0", ">=3.10", True),
            ("unknown", ">=3.10", False),
        ]:
            with self.subTest(actual=actual, rule=rule):
                self.assertEqual(checker.satisfies(actual, rule), expected)

    def test_bad_constraints_never_get_ignored(self):
        for rule in ["", ">=", ">=3.10,garbage", ">=3.10,", ">=3.10trailing", "3.10"]:
            with self.subTest(rule=rule), self.assertRaises(ValueError):
                checker.satisfies("Python 3.12.0", rule)

    def test_unknown_profile_rejected(self):
        with self.assertRaises(ValueError):
            checker.snapshot(ROOT, "hosst")

    def test_manifest_validation_rejects_disabled_checks_and_dead_fields(self):
        original = checker.load_manifest(ROOT)
        invalid = []
        for key, value in [("schema_version", True), ("profiles", {}), ("requirements", {})]:
            candidate = copy.deepcopy(original)
            candidate[key] = value
            invalid.append(candidate)
        candidate = copy.deepcopy(original)
        candidate["profiles"]["host"].remove("node")
        invalid.append(candidate)
        candidate = copy.deepcopy(original)
        candidate["requirements"]["git"]["version"] = ">=2.30,typo"
        invalid.append(candidate)
        candidate = copy.deepcopy(original)
        candidate["policy"] = {"ignored": True}
        invalid.append(candidate)
        for candidate in invalid:
            with self.subTest(candidate=candidate), patch.object(Path, "read_text", return_value=json.dumps(candidate)):
                with self.assertRaises(ValueError):
                    checker.load_manifest(ROOT)

    def test_host_passes_without_optional_tools_and_no_artificial_upper_bound(self):
        with patch.object(checker, "run", side_effect=healthy) as run:
            result = checker.snapshot(ROOT, "host")
        self.assertEqual(result["status"], "pass")
        self.assertEqual(len(run.call_args_list), 5)
        self.assertEqual({c["name"] for c in result["checks"]}, checker.TOOLS)

    def test_core_does_not_probe_node_or_optional_tools(self):
        with patch.object(checker, "run", side_effect=healthy) as run:
            result = checker.snapshot(ROOT, "core")
        self.assertEqual(result["status"], "pass")
        self.assertEqual(len(run.call_args_list), 3)

    def test_missing_failed_unknown_and_old_tools_block_with_remedy(self):
        for code, output in [("missing", ""), ("timeout", ""), ("command_failed", "v25.0.0"),
                             ("ok", "secret=must-not-appear"), ("ok", "Python 3.9.6")]:
            def probe(argv, root):
                return (code, output) if argv[0] == sys.executable else healthy(argv, root)
            with self.subTest(code=code, output=output), patch.object(checker, "run", side_effect=probe):
                result = checker.snapshot(ROOT, "host")
                self.assertEqual(result["status"], "fail")
                self.assertTrue(result["checks"][0]["remedy"])
                self.assertNotIn("secret", json.dumps(result))

    def test_node_capability_failure_blocks_even_with_new_version(self):
        def probe(argv, root):
            return ("ok", "") if "-e" in argv else healthy(argv, root)
        with patch.object(checker, "run", side_effect=probe):
            result = checker.snapshot(ROOT, "host")
        self.assertEqual(result["status"], "fail")
        self.assertEqual(result["checks"][-1]["code"], "capability_failed")

    def test_snapshot_digest_covers_requirements_and_checks(self):
        with patch.object(checker, "run", side_effect=healthy):
            first = checker.snapshot(ROOT, "host")
            second = checker.snapshot(ROOT, "host")
        self.assertEqual(first, second)
        claimed = first.pop("snapshot_digest")
        self.assertEqual(claimed, checker.digest(first))
        first["checks"][0]["status"] = "fail"
        self.assertNotEqual(claimed, checker.digest(first))

    def test_probe_timeout_is_bounded(self):
        with patch.object(checker.subprocess, "run", side_effect=subprocess.TimeoutExpired("node", 3)) as run:
            self.assertEqual(checker.run(["node", "--version"], ROOT), ("timeout", ""))
        self.assertEqual(run.call_args.kwargs["timeout"], 3)

    def test_invalid_manifest_cli_returns_json_failure_without_traceback(self):
        with tempfile.TemporaryDirectory() as directory:
            result = subprocess.run([sys.executable, str(ROOT / "scripts/environment-check.py"),
                                     "check", "--root", directory, "--json"], capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(json.loads(result.stdout)["code"], "manifest_invalid")
        self.assertNotIn("Traceback", result.stderr)

    def test_target_manifest_owns_requirements_not_caller_checkout(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "config").mkdir()
            manifest = checker.load_manifest(ROOT)
            manifest["requirements"]["git"]["version"] = ">=999"
            (root / "config/runtime-manifest.json").write_text(json.dumps(manifest))
            with patch.object(checker, "run", side_effect=healthy):
                result = checker.snapshot(root, "core")
            self.assertEqual(result["status"], "fail")
            self.assertEqual(result["checks"][1]["code"], "unsupported_version")

    def test_real_node_rejects_empty_or_invalid_hook_sources(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "config").mkdir()
            (root / "hooks").mkdir()
            (root / "config/runtime-manifest.json").write_text(json.dumps(checker.load_manifest(ROOT)))
            for source in [None, "const = ;", "const value = 1;"]:
                if source is not None:
                    (root / "hooks/probe.cjs").write_text(source)
                result = checker.snapshot(root, "host")
                self.assertEqual(result["checks"][-1]["status"], "pass" if source == "const value = 1;" else "fail")


if __name__ == "__main__":
    unittest.main()
