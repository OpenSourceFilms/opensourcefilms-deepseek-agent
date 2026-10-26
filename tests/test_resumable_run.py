"""Offline subprocess regressions for historical resumable_run.sh.

Only Bash and temporary files are used; never start DeepSeek or network calls.
"""
from __future__ import annotations

from pathlib import Path
import hashlib
import shutil
import subprocess
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]


class ResumableRunTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="ds_resumable_synthetic_")
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.script = self.root / "resumable_run.sh"
        shutil.copy2(ROOT / "resumable_run.sh", self.script)
        self.job = self.root / "job"
        self.units = self.root / "units.txt"

    def run_units(self, values, command='printf "%s" "{UNIT}"'):
        self.units.write_text("".join(v + "\n" for v in values), encoding="utf-8")
        return subprocess.run(
            ["bash", str(self.script), str(self.job), str(self.units), command],
            cwd=self.root, capture_output=True, text=True, timeout=12,
        )

    def test_ordinary_units_keep_legacy_checkpoint_names_and_resume(self):
        first = self.run_units(["media_001", "media_002"])
        self.assertEqual(first.returncode, 0, first.stdout + first.stderr)
        self.assertEqual((self.job / "out/media_001.out").read_text(), "media_001")
        again = self.run_units(["media_001", "media_002"], command='exit 91; printf "%s" "{UNIT}"')
        self.assertEqual(again.returncode, 0, again.stdout + again.stderr)
        self.assertIn("skipped=2", again.stdout)
        self.assertEqual((self.job / "out/media_002.out").read_text(), "media_002")

    def test_shell_metacharacters_are_data_not_executable_shell_source(self):
        marker = self.root / "this-must-not-exist"
        unit = "$(touch " + str(marker) + ")"
        result = self.run_units([unit])
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse(marker.exists())
        results = list((self.job / "out").glob("*.out"))
        self.assertEqual(len(results), 1)
        self.assertEqual(results[0].read_text(), unit)

    def test_colliding_legacy_sanitizations_have_distinct_outputs(self):
        units = ["shoot/A 1", "shoot?A 1", "shoot_A_1"]
        result = self.run_units(units)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        outputs = sorted((self.job / "out").glob("*.out"))
        self.assertEqual(len(outputs), 3)
        self.assertEqual({f.read_text() for f in outputs}, set(units))

    def test_generated_complex_id_cannot_alias_literal_simple_unit(self):
        complex_id = "a/b"
        digest = hashlib.sha256(complex_id.encode()).hexdigest()[:16]
        colliding_simple_id = f"a_b-{digest}"
        result = self.run_units([complex_id, colliding_simple_id])
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual((self.job / "out" / f"~{colliding_simple_id}.out").read_text(),
                         complex_id)
        self.assertEqual((self.job / "out" / f"{colliding_simple_id}.out").read_text(),
                         colliding_simple_id)
        self.assertIn("ran=2", result.stdout)

    def test_competing_directory_at_publication_is_not_success(self):
        self.units.write_text("race\n", encoding="utf-8")
        cmd = 'sleep 0.4; printf "%s" "{UNIT}"'
        proc = subprocess.Popen(
            ["bash", str(self.script), str(self.job), str(self.units), cmd],
            cwd=self.root, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            text=True,
        )
        outdir = self.job / "out"
        deadline = time.monotonic() + 5
        while not list(outdir.glob(".race.*")) and time.monotonic() < deadline:
            time.sleep(0.01)
        self.assertTrue(list(outdir.glob(".race.*")), "command never started")
        rival_directory = outdir / "race.out"
        rival_directory.mkdir()
        stdout, stderr = proc.communicate(timeout=8)
        self.assertNotEqual(proc.returncode, 0, stdout + stderr)
        self.assertIn("failed=1", stdout)
        self.assertEqual(list(rival_directory.iterdir()), [])
        self.assertEqual(list(outdir.glob(".race.*")), [])

    def test_failed_or_empty_commands_are_not_checkpoints(self):
        failed = self.run_units(["failed"], command="printf partial; exit 5")
        self.assertNotEqual(failed.returncode, 0)
        self.assertFalse((self.job / "out/failed.out").exists())
        empty = self.run_units(["failed"], command="true")
        self.assertNotEqual(empty.returncode, 0)
        self.assertFalse((self.job / "out/failed.out").exists())
        ok = self.run_units(["failed"])
        self.assertEqual(ok.returncode, 0, ok.stderr)
        self.assertEqual((self.job / "out/failed.out").read_text(), "failed")

    def test_existing_symlinked_checkpoint_is_not_followed(self):
        outdir = self.job / "out"
        outdir.mkdir(parents=True)
        external = self.root / "external"
        external.write_bytes(b"existing data")
        (outdir / "safe.out").symlink_to(external)
        result = self.run_units(["safe"])
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(external.read_bytes(), b"existing data")
        self.assertTrue((outdir / "safe.out").is_symlink())

    def test_racing_publication_never_overwrites_competitor(self):
        self.units.write_text("race\n", encoding="utf-8")
        cmd = 'sleep 0.4; printf "%s" "{UNIT}"'
        proc = subprocess.Popen(
            ["bash", str(self.script), str(self.job), str(self.units), cmd],
            cwd=self.root, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            text=True,
        )
        outdir = self.job / "out"
        deadline = time.monotonic() + 5
        while not list(outdir.glob(".race.*")) and time.monotonic() < deadline:
            time.sleep(0.01)
        self.assertTrue(list(outdir.glob(".race.*")), "command never started")
        competitor = outdir / "race.out"
        competitor.write_bytes(b"other-job-won")
        stdout, stderr = proc.communicate(timeout=8)
        self.assertNotEqual(proc.returncode, 0, stdout + stderr)
        self.assertEqual(competitor.read_bytes(), b"other-job-won")
        self.assertEqual(list(outdir.glob(".race.*")), [])

    def test_template_without_placeholder_is_refused(self):
        result = self.run_units(["one"], command='printf "unexpected"')
        self.assertEqual(result.returncode, 2)
        self.assertFalse((self.job / "out/one.out").exists())

    def test_missing_arguments_give_usage_error(self):
        result = subprocess.run(
            ["bash", str(self.script)], capture_output=True, text=True,
            cwd=self.root, timeout=10,
        )
        self.assertEqual(result.returncode, 2)
        self.assertIn("usage:", result.stderr)


if __name__ == "__main__":
    unittest.main()
