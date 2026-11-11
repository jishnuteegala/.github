import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[2] / "actions" / "dist-manifest" / "manifest.py"

# sha256 of b"a\n" and b"b\n"
A = "87428fc522803d31065e7bce3cf03fe475096631e5e07bbd7a0fde60c4cf25c7"
B = "0263829989b6fd954f72baaf2fc64bc2e2f01d692d4de72986ea808f6e99813f"
FILES = {"index.html": b"a\n", "assets/app.js": b"b\n", "Z.txt": b"a\n"}
MANIFEST = f"{A}  Z.txt\n{B}  assets/app.js\n{A}  index.html\n"


class DistManifest(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)
        self.dist = self.root / "dist"
        for name, data in FILES.items():
            (self.dist / name).parent.mkdir(parents=True, exist_ok=True)
            (self.dist / name).write_bytes(data)
        self.summary = self.root / "summary.md"
        self.ci = self.root / "ci.sha256"
        self.ci.write_text(MANIFEST, encoding="utf-8")

    def run_script(self, *args):
        env = {**os.environ, "GITHUB_STEP_SUMMARY": str(self.summary)}
        return subprocess.run(
            [sys.executable, str(SCRIPT), *map(str, args)], capture_output=True, text=True, env=env
        )

    def test_write_lists_every_file_sorted_by_path(self):
        out = self.root / "out.sha256"
        self.assertEqual(self.run_script("write", self.dist, out).returncode, 0)
        self.assertEqual(out.read_bytes(), MANIFEST.encode())

    def test_write_fails_without_files(self):
        (self.root / "empty").mkdir()
        for dist in (self.root / "empty", self.root / "missing"):
            result = self.run_script("write", dist, self.root / "out.sha256")
            self.assertEqual(result.returncode, 1, dist)
            self.assertIn("::error::", result.stdout)

    def test_compare_passes_on_identical_build(self):
        result = self.run_script("compare", self.dist, self.ci)
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertIn("matches the CI build", self.summary.read_text(encoding="utf-8"))

    def test_compare_fails_on_changed_file(self):
        (self.dist / "assets/app.js").write_bytes(b"c\n")
        result = self.run_script("compare", self.dist, self.ci)
        self.assertEqual(result.returncode, 1)
        self.assertIn("changed: assets/app.js", result.stdout)

    def test_compare_fails_on_missing_or_extra_file(self):
        (self.dist / "index.html").unlink()
        (self.dist / "extra.js").write_bytes(b"a\n")
        result = self.run_script("compare", self.dist, self.ci)
        self.assertEqual(result.returncode, 1)
        self.assertIn("only in CI: index.html", result.stdout)
        self.assertIn("only in this build: extra.js", result.stdout)

    def test_compare_warns_and_passes_without_ci_manifest(self):
        result = self.run_script("compare", self.dist, self.root / "absent.sha256")
        self.assertEqual(result.returncode, 0)
        self.assertIn("::warning::", result.stdout)
        self.assertIn("No CI dist manifest", self.summary.read_text(encoding="utf-8"))

    def test_select_picks_newest_unexpired_artifact_of_this_repository(self):
        def artifact(id, created_at, expired=False, head_repository_id=1):
            run = {"repository_id": 1, "head_repository_id": head_repository_id}
            return {"id": id, "created_at": created_at, "expired": expired, "workflow_run": run}

        listing = self.root / "artifacts.json"
        listing.write_text(json.dumps({"artifacts": [
            artifact(11, "2026-11-01T10:00:00Z"),
            artifact(12, "2026-11-02T10:00:00Z"),
            artifact(13, "2026-11-03T10:00:00Z", expired=True),
            artifact(14, "2026-11-04T10:00:00Z", head_repository_id=2),
            {"id": 15, "created_at": "2026-11-05T10:00:00Z", "expired": False, "workflow_run": None},
        ]}), encoding="utf-8")
        result = self.run_script("select", listing)
        self.assertEqual((result.returncode, result.stdout), (0, "12\n"))

    def test_select_prints_nothing_without_a_trusted_artifact(self):
        listing = self.root / "artifacts.json"
        listing.write_text('{"artifacts": []}', encoding="utf-8")
        self.assertEqual(self.run_script("select", listing).stdout, "")

    def test_rejects_unknown_command_or_wrong_arguments(self):
        self.assertEqual(self.run_script("verify", self.dist, self.ci).returncode, 2)
        self.assertEqual(self.run_script("select", self.dist, self.ci).returncode, 2)


if __name__ == "__main__":
    unittest.main()
