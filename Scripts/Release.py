#!/usr/bin/env python3
"""Mori Player release helpers. No commit, push or publication occurs implicitly."""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import re
import subprocess
import tempfile
from datetime import datetime, timezone

ROOT = Path(__file__).resolve().parents[1]
REPOSITORY = "w8y56f/mori-player"

def run(*args, capture=True, cwd=ROOT):
    result = subprocess.run(args, cwd=cwd, check=True, text=True,
                            stdout=subprocess.PIPE if capture else None)
    return result.stdout.rstrip("\n") if capture else ""

def git(*args):
    return run("git", *args)

def status():
    dirty = git("status", "--porcelain=v1", "--untracked-files=all")
    branch = git("branch", "--show-current")
    try:
        upstream = git("rev-parse", "--abbrev-ref", "@{upstream}")
        behind, ahead = map(int, git("rev-list", "--left-right", "--count", "@{upstream}...HEAD").split())
    except subprocess.CalledProcessError:
        upstream, behind, ahead = None, None, None
    return dict(branch=branch, commit=git("rev-parse", "HEAD"), clean=not dirty,
                changes=dirty.splitlines(), upstream=upstream, ahead=ahead, behind=behind)

def require_ready():
    state = status()
    print(json.dumps(state, ensure_ascii=False, indent=2), flush=True)
    if not state["clean"]:
        raise SystemExit("Uncommitted changes: review, commit and push before packaging.")
    if not state["branch"] or not state["upstream"]:
        raise SystemExit("A named branch with an upstream is required.")
    if state["ahead"] or state["behind"]:
        raise SystemExit("Local HEAD and upstream differ. Resolve and push before packaging.")
    remote = run("gh", "api", f"repos/{REPOSITORY}/commits/{state['branch']}", "--jq", ".sha")
    if remote != state["commit"]:
        raise SystemExit("GitHub branch does not match HEAD. Fetch and resolve before packaging.")
    return state

def version():
    values = re.findall(r"MARKETING_VERSION\s*=\s*([\d.]+);", (ROOT / "MoriPlayer.xcodeproj/project.pbxproj").read_text())
    if not values or len(set(values)) != 1 or not re.fullmatch(r"\d+\.\d+\.\d+", values[0]):
        raise SystemExit("Debug and Release must have the same semantic version.")
    return values[0]

def create_dmg(app, destination, volume):
    """Build a drag-to-Applications DMG, also usable by local packaging tests."""
    if destination.exists():
        raise SystemExit(f"Refusing to overwrite {destination}")
    with tempfile.TemporaryDirectory(prefix="mori-dmg-") as directory:
        stage = Path(directory)
        run("ditto", str(app), str(stage / app.name))
        (stage / "Applications").symlink_to("/Applications")
        (stage / "INSTALL.txt").write_text(
            "Drag Mori Player.app to Applications, then eject this disk image.\n"
            "将 Mori Player.app 拖入 Applications，然后推出此磁盘映像。\n", encoding="utf-8")
        run("hdiutil", "create", "-volname", volume, "-srcfolder", str(stage),
            "-format", "UDZO", "-ov", str(destination), capture=False)
    run("hdiutil", "verify", str(destination), capture=False)

def package(args):
    state = require_ready()
    v = version()
    if args.version and args.version != v:
        raise SystemExit("Requested version does not match MARKETING_VERSION.")
    if bool(args.identity) != bool(args.team) or bool(args.identity) != bool(args.notary_profile):
        raise SystemExit("Provide --identity, --team and --notary-profile together, or none for ad hoc testing.")
    if args.identity and not args.identity.startswith("Developer ID Application:"):
        raise SystemExit("Use a Developer ID Application identity for notarized releases.")
    tag = "v" + v
    existing = subprocess.run(["gh", "release", "view", tag, "--repo", REPOSITORY], cwd=ROOT,
                              stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    if existing.returncode == 0 and not args.replace_existing:
        raise SystemExit("This version already has a release. Do not overwrite it.")
    out = ROOT / ".build/releases" / tag
    if out.exists():
        if not args.replace_existing:
            raise SystemExit(f"Output already exists; inspect it before retrying: {out}")
        backup = out.parent / "backups" / (tag + "-" + datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ"))
        backup.parent.mkdir(parents=True, exist_ok=True)
        out.rename(backup)
        print(f"Previous local package preserved at {backup}", flush=True)
    run("sh", "Scripts/PrepareDependencies.sh", capture=False)
    command = ["xcodebuild", "-project", "MoriPlayer.xcodeproj", "-scheme", "MoriPlayer",
               "-configuration", "Release", "-derivedDataPath", ".build/DerivedData",
               "ARCHS=arm64 x86_64", "ONLY_ACTIVE_ARCH=NO", "CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO"]
    if args.identity:
        command += [f"CODE_SIGN_IDENTITY={args.identity}", f"DEVELOPMENT_TEAM={args.team}",
                    "CODE_SIGN_STYLE=Manual", "OTHER_CODE_SIGN_FLAGS=--timestamp"]
    run(*command, "build", capture=False)
    app = ROOT / ".build/DerivedData/Build/Products/Release/Mori Player.app"
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    metadata = json.loads((app / "Contents/Resources/BuildMetadata.json").read_text())
    if info["CFBundleShortVersionString"] != v or metadata != {"commit": state["commit"][:7], "dirty": False}:
        raise SystemExit("Build version or clean Git metadata does not match the release source.")
    run("codesign", "--verify", "--deep", "--strict", str(app), capture=False)
    for binary in [app / "Contents/MacOS/Mori Player", app / "Contents/Frameworks/VLCKit.framework/VLCKit"]:
        run("lipo", str(binary), "-verify_arch", "arm64", "x86_64")
    for resource in ["en.lproj/Localizable.strings", "zh-Hans.lproj/Localizable.strings", "VLCKit-LICENSE.txt"]:
        if not (app / "Contents/Resources" / resource).is_file():
            raise SystemExit(f"Missing resource: {resource}")
    if status() != state:
        raise SystemExit("Source changed during build. Stop and rebuild from a clean pushed commit.")
    out.mkdir(parents=True)
    dmg = out / f"MoriPlayer-{v}-macOS.dmg"
    create_dmg(app, dmg, f"Mori Player {v}")
    if args.identity:
        run("codesign", "--force", "--sign", args.identity, "--timestamp", str(dmg))
        run("xcrun", "notarytool", "submit", str(dmg), "--keychain-profile", args.notary_profile, "--wait", capture=False)
        # Stapling fails unless Apple's notarization was accepted.
        run("xcrun", "stapler", "staple", str(dmg), capture=False)
        run("xcrun", "stapler", "validate", str(dmg), capture=False)
    checksum = hashlib.sha256(dmg.read_bytes()).hexdigest()
    (out / "SHA256SUMS.txt").write_text(f"{checksum}  {dmg.name}\n")
    manifest = dict(version=v, tag=tag, commit=state["commit"], dmg=dmg.name,
                    sha256=checksum, notarized=bool(args.identity), repository=REPOSITORY)
    (out / "release.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(json.dumps(manifest, indent=2))

def publish(args):
    state = require_ready()
    v = version()
    out = ROOT / ".build/releases" / ("v" + v)
    manifest = json.loads((out / "release.json").read_text())
    dmg = out / f"MoriPlayer-{v}-macOS.dmg"
    if manifest["commit"] != state["commit"] or manifest["version"] != v or manifest["tag"] != "v" + v or manifest["repository"] != REPOSITORY:
        raise SystemExit("Package source does not match current HEAD/version.")
    digest = hashlib.sha256(dmg.read_bytes()).hexdigest()
    if digest != manifest["sha256"] or (out / "SHA256SUMS.txt").read_text() != f"{digest}  {dmg.name}\n":
        raise SystemExit("Release checksum verification failed.")
    if not manifest["notarized"] and not args.allow_unnotarized:
        raise SystemExit("Ad hoc package: explicitly pass --allow-unnotarized to publish a prerelease.")
    if manifest["notarized"]:
        run("xcrun", "stapler", "validate", str(dmg), capture=False)
        run("codesign", "--verify", "--strict", str(dmg), capture=False)
    notes = args.notes.resolve()
    if not notes.is_file() or not notes.read_text().strip():
        raise SystemExit("Provide a nonempty bilingual release notes file.")
    if not manifest["notarized"] and "not notarized" not in notes.read_text().lower():
        raise SystemExit("Unnotarized prerelease notes must state 'not notarized'.")
    tag = manifest["tag"]
    remote_tag = git("ls-remote", "origin", f"refs/tags/{tag}", f"refs/tags/{tag}^{{}}")
    if remote_tag:
        commits = [line.split()[0] for line in remote_tag.splitlines()]
        if state["commit"] not in commits:
            raise SystemExit("Existing remote tag points to a different commit. Never move it.")
    command = ["gh", "release", "create", tag, str(dmg), str(out / "SHA256SUMS.txt"),
               "--repo", REPOSITORY, "--target", state["commit"], "--title", f"Mori Player {v}",
               "--notes-file", str(notes)]
    if not manifest["notarized"]:
        command += ["--prerelease"]
    run(*command, capture=False)
    run("gh", "release", "view", tag, "--repo", REPOSITORY, "--json", "url,tagName,isPrerelease,assets", capture=False)

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="action", required=True)
    sub.add_parser("status")
    pack = sub.add_parser("package")
    pack.add_argument("--version")
    pack.add_argument("--replace-existing", action="store_true", help="Use only when replacement of this release was explicitly requested; archives previous local output")
    pack.add_argument("--identity")
    pack.add_argument("--team")
    pack.add_argument("--notary-profile")
    pub = sub.add_parser("publish")
    pub.add_argument("--notes", type=Path, required=True)
    pub.add_argument("--allow-unnotarized", action="store_true")
    args = parser.parse_args()
    if args.action == "status": print(json.dumps(status(), ensure_ascii=False, indent=2))
    elif args.action == "package": package(args)
    else: publish(args)
