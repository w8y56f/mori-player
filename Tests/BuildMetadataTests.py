"""Exercise the build script in disposable Git repositories, never the app repo."""
import json
import os
from pathlib import Path
import subprocess
import tempfile

SCRIPT = Path(__file__).resolve().parents[1] / "Scripts/GenerateBuildMetadata.sh"
ENV = {k: v for k, v in os.environ.items() if k not in {"GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE"}}
ENV.update(GIT_CONFIG_GLOBAL=os.devnull, GIT_CONFIG_NOSYSTEM="1")


def git(root, *args):
    return subprocess.check_output(["/usr/bin/git", "-C", str(root), *args], env=ENV, text=True).strip()


def stamp(root, output=None):
    output = output or root / ".build" / "BuildMetadata.json"
    subprocess.run(["/bin/sh", str(SCRIPT), str(root), str(output)], env=ENV, check=True)
    return json.loads(output.read_text())


with tempfile.TemporaryDirectory(prefix="mori-build-metadata-") as temporary:
    root = Path(temporary) / "repo with spaces"
    root.mkdir()
    git(root, "init", "--quiet")
    assert stamp(root) == {"commit": "no-commit", "dirty": True}
    (root / ".gitignore").write_text(".build/\n")
    source = root / "source.txt"
    source.write_text("original\n")
    git(root, "add", ".")
    git(root, "-c", "user.name=Build Test", "-c", "user.email=build-test@example.invalid", "-c", "commit.gpgsign=false", "commit", "--quiet", "-m", "initial")
    first = git(root, "rev-parse", "--short=7", "HEAD")
    assert stamp(root) == {"commit": first, "dirty": False}
    output = root / ".build" / "BuildMetadata.json"
    previous_time = output.stat().st_mtime_ns
    assert stamp(root)["dirty"] is False
    assert output.stat().st_mtime_ns == previous_time
    (root / ".build" / "ignored.txt").write_text("ignored")
    assert stamp(root)["dirty"] is False
    source.write_text("changed\n")
    assert stamp(root) == {"commit": first, "dirty": True}
    git(root, "add", "source.txt")
    assert stamp(root)["dirty"] is True
    git(root, "-c", "user.name=Build Test", "-c", "user.email=build-test@example.invalid", "-c", "commit.gpgsign=false", "commit", "--quiet", "-m", "update")
    second = git(root, "rev-parse", "--short=7", "HEAD")
    assert second != first and stamp(root) == {"commit": second, "dirty": False}
    untracked = root / "untracked.txt"
    untracked.write_text("new")
    assert stamp(root)["dirty"] is True
    untracked.unlink()
    assert stamp(root)["dirty"] is False
    exported = root / ".build" / "exported source"
    exported.mkdir()
    assert stamp(exported) == {"commit": "unknown", "dirty": None}
print("PASS: no commit, clean commit, unstaged/staged/untracked changes, ignored outputs, commit refresh, unchanged timestamps, missing Git metadata, quoted paths.")
