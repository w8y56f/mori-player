---
name: mori-release
description: Package Mori Player into a versioned macOS DMG and publish it with bilingual notes and checksums to this repository's GitHub Releases. Use when preparing or publishing a Mori Player release.
---

# Mori Player release

Operate from the repository root. The executable helper is `Scripts/Release.py`.
The destination is `w8y56f/mori-player`; use `v<MARKETING_VERSION>` as the tag.
Creating or editing this skill is not an instruction to publish a release.

## First report Git state

Before building, run `python3 Scripts/Release.py status` and show the user the branch,
commit, whether the worktree is clean, and upstream ahead/behind counts. These counts
are local until refreshed. Run `git fetch origin`, then report the refreshed state.

- With staged, unstaged or untracked changes, summarize them and ask whether to commit
  **and push**. A push cannot save uncommitted files. Do not auto-stage or discard them.
- With only unpushed commits, ask to push those commits. This confirmation is the user's
  requested release workflow. If this invocation already explicitly authorizes the exact
  commits/push, proceed without asking again.
- If behind or diverged, inspect and explain the difference; resolve it within the user's
  authorized scope. Do not force-push or reset branches. Move a release tag only for an explicitly authorized replacement.
- After the authorized commit/push, verify clean HEAD equals the GitHub branch. Stop on
  authentication or permission failures; report the concrete command/error.

## Prepare the release

Read the version from the Xcode project; do not bump it unless requested. Check for an
existing release/tag before building. If the release exists, report its URL and stop;
updates or replacement need an explicit request. The helper refuses existing artifacts
so failed attempts are reviewable rather than silently overwritten.

Run the applicable checks documented in README.md, including build metadata and language
checks and playback/subtitle regressions when the change warrants them. Do not claim the
legacy AVPlayer test suite is fully migrated. Do not commit personal video fixtures.

Use `python3 Scripts/Release.py package` to build the clean, pushed source. It builds a
universal arm64/x86_64 Release in `.build/DerivedData`, checks version/Git metadata,
frameworks, resources and signature, and makes a compressed DMG containing the app,
an Applications shortcut and installation instructions. Artifacts go to
`.build/releases/v<version>/`: DMG, SHA256SUMS.txt and local release.json manifest.

The project currently uses ad hoc signing. By default package a test build, explicitly
reporting that it is **not notarized**. Never describe it as a notarized public build.
To produce a notarized release, use existing authorized Developer ID credentials:

```sh
python3 Scripts/Release.py package \
  --identity 'Developer ID Application: …' --team TEAM_ID \
  --notary-profile KEYCHAIN_PROFILE
```

Do not store certificates, passwords or tokens in the repository. Signing/notarization
failure stops publication; do not silently fall back to ad hoc. The helper signs and
notarizes the DMG and staples the accepted ticket.

## Publish and verify

Prepare a UTF-8 bilingual notes file under the ignored output directory, describing
actual changes, minimum macOS version, supported architectures, drag-to-Applications
installation and any relevant limitations. An ad hoc build must explicitly state
“not notarized / 未公证” and is published as a prerelease. Keep source commit/version in
the notes. Review DMG contents and installation from the mounted image before publishing;
unmount only images mounted by this run. Do not change system security settings.

If the user requested publication, continue without an extra final approval. If only a
package or draft was requested, deliver that result without publishing. For publication:

```sh
python3 Scripts/Release.py publish --notes .build/releases/vVERSION/notes.md
# For an explicitly disclosed ad hoc test release, also pass --allow-unnotarized.
```

The helper verifies current clean/pushed HEAD, version and artifact checksum before
creating a GitHub Release at the exact commit and uploading DMG + SHA256SUMS.txt.
After creation, verify the remote tag resolves to that commit and the release has both
attachments with expected sizes; download the DMG to an ignored verification directory
and compare its SHA-256. On partial upload/failure, inspect the existing release before
retrying. Do not delete/recreate an existing release or use upload clobber implicitly.

Report the release URL, tag/commit, signing/notarization state and checks performed.

## Explicit replacement

When the user explicitly asks to replace an existing release, keep its version and URL.
Use `package --replace-existing`; the previous local package is archived automatically.
After checking the new DMG, upload the two assets with `gh release upload --clobber`,
update `refs/tags/vVERSION` through the GitHub Git refs API to the exact new commit,
and update the existing release's bilingual notes with `gh release edit`.
This path is only for explicit replacement authorization, never the default retry path.
Verify the remote tag and redownloaded checksum just as for a new release. Include any
Bundle Identifier change and its settings/history implications in the notes.
